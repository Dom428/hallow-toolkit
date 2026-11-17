<#
  Hallow Toolkit - Apps tab logic: install a bunch of apps at once with winget (like Ninite, but built in),
  see what's installed or has an update, search all of winget, and "my apps" for a fresh Windows install.
  No window code. Dot-sourced by HallowCore.ps1.
#>
. (Join-Path $HallowRoot 'HallowAppList.ps1')

# One row per catalog app: Category, Name, Id, Ninite, Note, User (installer refuses to run as admin)
function Get-AppCatalogRows {
    foreach ($cat in $AppCatalog.Keys) {
        foreach ($a in $AppCatalog[$cat]) {
            [pscustomobject]@{ Category = $cat; Name = $a[0]; Id = $a[1]; Ninite = $a[2]; Note = $a[3]; User = ("$($a[4])" -match 'user'); Rec = ("$($a[4])" -match 'rec') }
        }
    }
}

# Background: which winget ids are installed and which have updates. Returns @{ Installed; Names; Updates; Error }.
$AppStateWork = {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return @{ Error = 'winget is not installed (get "App Installer" from the Microsoft Store).' } }
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $tmp = Join-Path $env:TEMP ("hallow-apps-{0}.json" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
    $null = winget export -o $tmp --source winget --accept-source-agreements --disable-interactivity 2>&1
    $ids = @()
    if (Test-Path $tmp) {
        try { $ids = @((Get-Content $tmp -Raw | ConvertFrom-Json).Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier }) } catch { }
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    $names = @(foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object { "$($_.DisplayName)" }
    })
    $raw = (winget upgrade --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $lines = @($raw -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1].TrimEnd() })
    $upd = @(); $hi = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*Name\s+Id\s+Version\s+Available') { $hi = $i; break } }
    if ($hi -ge 0) {
        $iId = $lines[$hi].IndexOf('Id ')
        for ($i = $hi + 2; $i -lt $lines.Count; $i++) {
            $l = $lines[$i]
            if (-not $l.Trim() -or $l -match '^\d+ upgrades? available' -or $l -match 'require explicit targeting') { break }
            if ($l.Length -gt $iId) { $upd += @($l.Substring($iId).Trim() -split '\s+')[0] }
        }
    }
    @{ Error = $null; Installed = $ids; Names = $names; Updates = $upd }
}

# Background: install / update the given rows one by one. Yields log lines.
$AppInstallWork = {
    param([object[]]$Items)
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $ok = 0; $n = 0
    foreach ($it in $Items) {
        $n++
        $verb = if ($it.Update) { 'upgrade' } else { 'install' }
        "[$n/$($Items.Count)] $(if ($it.Update) { 'Updating' } else { 'Installing' }) $($it.Name)..."
        $out = winget $verb --id $it.Id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        $hex = '0x{0:X8}' -f $LASTEXITCODE
        if ($LASTEXITCODE -eq 0) { "   done"; $ok++ }
        elseif ($hex -in '0x8A150061', '0x8A15002B') { "   already installed and up to date"; $ok++ }
        elseif ($hex -in '0x8A150056', '0x8A15010C') { "   skipped - $($it.Name) is open. Close it and try again." }
        elseif ($hex -eq '0x8A150011' -or $hex -eq '0x8A150049') { "   cancelled" }
        elseif ($hex -eq '0x8A150109') { "   installed - restart the PC to finish"; $ok++ }
        else {
            $why = @($out -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1].Trim() } | Where-Object { $_ -and $_ -notmatch '^[\-\\|/ ]+$|[^\x00-\x7F]{3}|Downloading|^Found |^This application|^Microsoft is not|^Successfully verified|^Starting package' }) | Select-Object -Last 1
            "   failed ($hex) $why"
        }
    }
    "Finished: $ok of $($Items.Count) app(s) ready."
}

# Background: search all of winget. Returns rows Name, Id, Version.
$AppSearchWork = {
    param([string]$Query)
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $raw = (winget search $Query --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $lines = @($raw -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1].TrimEnd() })
    $hi = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*Name\s+Id\s+Version') { $hi = $i; break } }
    if ($hi -lt 0) { return }
    $h = $lines[$hi]; $iId = $h.IndexOf('Id '); $iVer = $h.IndexOf('Version')
    $iEnd = @(@($h.IndexOf('Match'), $h.IndexOf('Source')) | Where-Object { $_ -gt $iVer } | Sort-Object)[0]
    $n = 0
    for ($i = $hi + 2; $i -lt $lines.Count -and $n -lt 40; $i++) {
        $l = $lines[$i]
        if ($l.Length -le $iVer) { continue }
        $id = @($l.Substring($iId).Trim() -split '\s+')[0]
        $ver = if ($iEnd -and $l.Length -gt $iEnd) { $l.Substring($iVer, $iEnd - $iVer).Trim() } else { $l.Substring($iVer).Trim() -split '\s+' | Select-Object -First 1 }
        [pscustomobject]@{ Name = $l.Substring(0, $iId).Trim(); Id = $id; Version = $ver }; $n++
    }
}

# Apps that refuse to install from an admin window (Spotify): run winget from a normal-user window instead.
function Start-UserAppInstall($Items) {
    $cmd = Join-Path $env:TEMP 'hallow-user-install.cmd'
    $lines = @('@echo off', 'title Hallow Toolkit - installing', 'echo Installing apps that must not run as admin...')
    foreach ($it in $Items) { $lines += "echo. & echo $($it.Name)..."; $lines += "winget install --id $($it.Id) --exact --source winget --accept-package-agreements --accept-source-agreements" }
    $lines += 'echo. & echo Done - this window closes in 10 seconds.', 'timeout /t 10 >nul'
    Set-Content $cmd $lines -Encoding ASCII
    Start-Process explorer.exe "`"$cmd`""   # Explorer runs it as you, not as admin
    Log "$(($Items | ForEach-Object Name) -join ', ') - installing in a separate window (it can't install from an admin window)."
}

function Get-NiniteUrl($Rows) {
    $slugs = @($Rows | Where-Object Ninite | ForEach-Object Ninite | Sort-Object -Unique)
    if (-not $slugs) { return $null }
    "https://ninite.com/$($slugs -join '-')/"
}

function Get-MyApps { @((Get-Settings).MyApps | Where-Object { $_ }) }
function Save-MyApps([string[]]$Ids) {
    $s = Get-Settings; $s | Add-Member -NotePropertyName MyApps -NotePropertyValue @($Ids) -Force; Save-Settings $s
}
