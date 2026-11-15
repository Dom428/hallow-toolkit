<#
  Hallow Toolkit - quick fixes, driver backup and old driver cleanup. No window code.
  Dot-sourced by HallowCore.ps1.
#>

# ================================================================ QUICK FIXES
function Restart-Svc([string[]]$Names, [string]$Label) {
    foreach ($n in $Names) {
        try { Restart-Service -Name $n -Force -ErrorAction Stop; Log "  restarted $n" } catch { Log "  could not restart $n ($($_.Exception.Message))" }
    }
}

function Repair-Audio {
    if (-not (Need-Admin 'Fixing audio')) { return }
    Log '===== FIX AUDIO ====='
    Restart-Svc 'AudioEndpointBuilder', 'Audiosrv'
    Log 'Audio services restarted. Still silent? Click the speaker icon > pick the right output (headset vs monitor).'
}

function Repair-Bluetooth {
    if (-not (Need-Admin 'Fixing Bluetooth')) { return }
    Log '===== FIX BLUETOOTH ====='
    Restart-Svc 'bthserv'
    Log 'Bluetooth service restarted. Turn the device off and on again to reconnect.'
}

function Repair-Search {
    Log '===== FIX START MENU SEARCH ====='
    Get-Process SearchHost, SearchApp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Log '  restarted the Start menu search app'
    if ($IsAdmin) { Restart-Svc 'WSearch' } else { Log '  Windows Search service - skipped (needs admin)' }
    Log 'Try searching again in a few seconds.'
}

function Repair-Store {
    Log '===== RESET MICROSOFT STORE ====='
    Start-Process wsreset.exe
    Log 'Clearing the Store cache - a blank window appears, then the Store opens by itself. Downloads/installs work again after that.'
}

function Repair-IconCache {
    Log '===== REBUILD ICONS & THUMBNAILS ====='
    $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    $n = 0
    foreach ($pat in 'iconcache_*.db', 'thumbcache_*.db') {
        Get-ChildItem $dir -Filter $pat -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction Stop; $n++ } catch { } }
    }
    $old = Join-Path $env:LOCALAPPDATA 'IconCache.db'; if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue; $n++ }
    Start-Process explorer.exe
    Log "  cleared $n cache file(s) and restarted Explorer. Icons and thumbnails rebuild as you browse."
}

function Sync-Clock {
    if (-not (Need-Admin 'Syncing the clock')) { return }
    Log '===== SYNC CLOCK ====='
    Start-Service W32Time -ErrorAction SilentlyContinue
    $out = (w32tm /resync /force 2>&1 | Out-String).Trim()
    Log "  $($out -replace '\s+', ' ')"
    Log 'A wrong clock breaks game logins, launchers and HTTPS sites - this sets it from the internet time server.'
}

function Reset-WindowsUpdate {
    if (-not (Need-Admin 'Resetting Windows Update')) { return }
    Log '===== RESET WINDOWS UPDATE ====='
    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver'
    foreach ($s in $svcs) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
    foreach ($pair in @(@("$env:WINDIR\SoftwareDistribution", 'download cache'), @("$env:WINDIR\System32\catroot2", 'signature cache'))) {
        $p = $pair[0]; $bak = "$p.old"
        if (Test-Path $bak) { Remove-Item $bak -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $p) {
            try { Rename-Item $p (Split-Path $bak -Leaf) -ErrorAction Stop; Log "  moved the $($pair[1]) aside ($(Split-Path $bak -Leaf))" }
            catch { Log "  could not move the $($pair[1]) ($($_.Exception.Message))" }
        }
    }
    foreach ($s in $svcs) { Start-Service $s -ErrorAction SilentlyContinue }
    Log 'Done. Windows rebuilds both caches on the next check - open Windows Update and click "Check for updates".'
    Log 'The .old folders can be deleted later with Storage > Windows Disk Cleanup.'
}

# ================================================================ DRIVER BACKUP
$DriverBackupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Hallow Driver Backups'

$DriverBackupWork = {
    param($Root)
    $dest = Join-Path $Root ("{0:yyyy-MM-dd_HHmm}" -f (Get-Date))
    New-Item -ItemType Directory -Force $dest | Out-Null
    try {
        $d = @(Export-WindowsDriver -Online -Destination $dest -ErrorAction Stop)
        $mb = [math]::Round(((Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB)
        "Backed up $($d.Count) drivers ($mb MB) to $dest"
        "To restore one later: Device Manager > right-click the device > Update driver > Browse my computer > pick this folder (tick Include subfolders)."
    } catch { "Driver backup failed: $($_.Exception.Message)" }
}

# ================================================================ OLD DRIVER CLEANUP
# Lists third-party driver packages that have a newer version of the same driver installed. Read-only.
function Get-OldDriverPackages {
    $raw = (pnputil /enum-drivers 2>$null | Out-String) -split "\r?\n\r?\n"
    $pk = foreach ($b in $raw) {
        $h = @{}
        foreach ($l in $b -split "\r?\n") { if ($l -match '^\s*([^:]+):\s+(.*)$') { $h[$Matches[1].Trim()] = $Matches[2].Trim() } }
        if (-not $h['Published Name'] -or -not $h['Original Name']) { continue }
        $date = [datetime]::MinValue; $ver = [version]'0.0'
        if ($h['Driver Version'] -match '^(\S+)\s+(\S+)$') {
            [void][datetime]::TryParse($Matches[1], [cultureinfo]'en-US', 'None', [ref]$date)
            try { $ver = [version]$Matches[2] } catch { }
        }
        [pscustomobject]@{ Oem = $h['Published Name']; Inf = $h['Original Name']; Provider = $h['Provider Name']; Class = $h['Class Name']; Date = $date; Version = $ver }
    }
    $repo = "$env:WINDIR\System32\DriverStore\FileRepository"
    foreach ($grp in $pk | Group-Object Inf, Provider | Where-Object Count -gt 1) {
        $sorted = @($grp.Group | Sort-Object Version, Date -Descending)
        $newest = $sorted[0]
        foreach ($old in $sorted | Select-Object -Skip 1) {
            # find this package's folder: the FileRepository copy whose .inf matches the oemNN.inf copy
            $size = 0; $folder = ''
            $oemHash = (Get-FileHash "$env:WINDIR\INF\$($old.Oem)" -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
            foreach ($dir in Get-ChildItem $repo -Directory -Filter "$($old.Inf)_*" -ErrorAction SilentlyContinue) {
                $h = (Get-FileHash (Join-Path $dir.FullName $old.Inf) -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
                if ($h -and $h -eq $oemHash) { $folder = $dir.FullName; $size = (Get-ChildItem $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; break }
            }
            [pscustomobject]@{
                Oem = $old.Oem; Inf = $old.Inf; Provider = $old.Provider; Class = $old.Class
                Version = "$($old.Version)"; Date = $old.Date; Newer = "$($newest.Version)"; Bytes = [double]$size; Folder = $folder
            }
        }
    }
}

function Remove-OldDriverPackages($Items) {
    if (-not (Need-Admin 'Removing old drivers')) { return }
    Log '===== OLD DRIVER CLEANUP ====='
    $ok = 0; $kept = 0; $freed = 0
    foreach ($it in $Items) {
        $out = (pnputil /delete-driver $it.Oem 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $out -match 'deleted') { $ok++; $freed += $it.Bytes; Log "  removed $($it.Inf) $($it.Version) ($($it.Oem))" }
        else { $kept++; Log "  kept $($it.Inf) $($it.Version) - Windows says it is still in use" }
    }
    Log ("Removed {0} old driver package(s), freed about {1}. {2}" -f $ok, (Format-Size $freed), $(if ($kept) { "$kept still in use were left alone." } else { '' }))
}
