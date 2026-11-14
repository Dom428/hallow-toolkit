<#
  Hallow Toolkit - System check, app updates (winget) and game sessions. No window code.
  Dot-sourced by HallowCore.ps1, so the main window and the tray app can both use it.
#>

# ================================================================ SYSTEM CHECK
# Runs in a background runspace (self-contained). Returns rows: Check, Value, Verdict (Good/Warn/Bad/Info), Advice.
$SystemCheckWork = {
    $rows = New-Object System.Collections.Generic.List[object]
    function Row($Check, $Value, $Verdict, $Advice = '') { $rows.Add([pscustomobject]@{ Check = $Check; Value = "$Value"; Verdict = $Verdict; Advice = $Advice }) }

    # --- BIOS
    $bi = Get-CimInstance Win32_BIOS; $bb = Get-CimInstance Win32_BaseBoard
    $age = if ($bi.ReleaseDate) { ((Get-Date) - $bi.ReleaseDate).Days } else { 0 }
    Row 'BIOS' ("{0}  ({1:yyyy-MM-dd})  {2}" -f "$($bi.SMBIOSBIOSVersion)".Trim(), $bi.ReleaseDate, "$($bb.Product)".Trim()) $(if ($age -gt 365) { 'Warn' } else { 'Good' }) `
        $(if ($age -gt 365) { "Over a year old - Drivers tab > Check for updates" } else { 'Recent' })

    # --- RAM / EXPO
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $r0 = $ram | Select-Object -First 1
    $gb = ($ram | Measure-Object Capacity -Sum).Sum / 1GB
    $kit = 0; if ("$($r0.PartNumber)" -match '(?<!\d)([4-9]\d00)(?!\d)') { $kit = [int]$Matches[1] }
    $run = [int]$r0.ConfiguredClockSpeed; $std = [int]$r0.Speed
    $val = "{0} MT/s  ({1} x {2:N0} GB{3})" -f $run, $ram.Count, ($gb / [math]::Max(1, $ram.Count)), $(if ($kit) { ", kit rated $kit" } else { '' })
    if ($kit -and $run -ge $kit) { Row 'RAM speed (EXPO)' $val 'Good' 'EXPO is on - running at full speed' }
    elseif ($kit -and $run -lt $kit) { Row 'RAM speed (EXPO)' $val 'Bad' "EXPO is OFF - BIOS: Ai Tweaker > Ai Overclock Tuner > EXPO I (back to $kit)" }
    elseif ($run -gt $std) { Row 'RAM speed (EXPO)' $val 'Good' 'Running above standard speed (EXPO/XMP on)' }
    else { Row 'RAM speed (EXPO)' $val 'Warn' 'Standard speed - turn on EXPO/XMP in the BIOS if your kit supports more' }

    # --- GPU, Resizable BAR
    $vc = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Virtual|Parsec|Remote|Meta' } |
        Sort-Object { [int64]$_.AdapterRAM } -Descending | Select-Object -First 1
    $smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
    if ($smi) {
        $q = (& $smi --query-gpu=name,memory.total,driver_version,temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1) -split ',\s*'
        $vram = [double]$q[1]; $temp = [double]$q[3]
        $drvAge = if ($vc.DriverDate) { ((Get-Date) - $vc.DriverDate).Days } else { 0 }
        Row 'Graphics card' ("{0}  (driver {1})" -f $q[0], $q[2]) $(if ($drvAge -gt 120) { 'Warn' } else { 'Good' }) `
            $(if ($drvAge -gt 120) { "Driver is $drvAge days old - Health > Get NVIDIA driver" } else { 'Driver is recent' })
        Row 'GPU temperature' ("{0:N0} C" -f $temp) $(if ($temp -ge 85) { 'Bad' } elseif ($temp -ge 78) { 'Warn' } else { 'Good' }) `
            $(if ($temp -ge 78) { 'Hot - check case airflow and fan curve' } else { 'Fine' })
        $bar = 0; $mem = (& $smi -q -d MEMORY 2>$null) -join "`n"
        if ($mem -match 'BAR1 Memory Usage\s+Total\s+:\s+(\d+)') { $bar = [double]$Matches[1] }
        if ($bar -and $vram) {
            if ($bar -ge $vram * 0.9) { Row 'Resizable BAR' 'On' 'Good' 'Full GPU memory access - a few % more FPS in some games' }
            else { Row 'Resizable BAR' ("Off (window {0:N0} MB)" -f $bar) 'Warn' 'BIOS: Advanced > PCI Subsystem > Above 4G Decoding + Re-Size BAR = Enabled' }
        }
    } elseif ($vc) {
        Row 'Graphics card' ("{0}  (driver {1})" -f $vc.Name, $vc.DriverVersion) 'Info' 'Resizable BAR and GPU temp need an NVIDIA card to check here'
    }

    # --- CPU
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ct = $null
    if (Get-Process -Name LibreHardwareMonitor -ErrorAction SilentlyContinue) {
        try {
            $s = Get-CimInstance -Namespace 'root/LibreHardwareMonitor' -ClassName Sensor -Filter "SensorType='Temperature'" -ErrorAction Stop |
                Where-Object { $_.Name -match 'Tctl|Tdie|CPU Package' } | Select-Object -First 1
            if ($s) { $ct = [double]$s.Value }
        } catch { }
    }
    if ($null -ne $ct) {
        Row 'CPU temperature' ("{0:N0} C  ({1})" -f $ct, "$($cpu.Name)".Trim()) $(if ($ct -ge 90) { 'Bad' } elseif ($ct -ge 80) { 'Warn' } else { 'Good' }) `
            $(if ($ct -ge 80) { 'High for light use - check the cooler is seated and fans run' } else { 'Fine' })
    } else { Row 'CPU' "$($cpu.Name)".Trim() 'Info' 'For CPU temperature: Monitor tab > install LibreHardwareMonitor' }

    # --- Firmware security (anti-cheat cares about these)
    $sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
    if ($sb -eq 1) { Row 'Secure Boot' 'On' 'Good' 'Needed by some anti-cheat (Call of Duty, Valorant)' }
    else { Row 'Secure Boot' 'Off' 'Warn' 'Some anti-cheat needs it. BIOS: Boot > Secure Boot > OS Type = Windows UEFI mode' }
    $tpm = Get-PnpDevice -Class SecurityDevices -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Trusted Platform Module' }
    if ($tpm -and $tpm.Status -eq 'OK') { Row 'TPM' ($tpm.FriendlyName -replace 'Trusted Platform Module', 'TPM') 'Good' 'Needed by Windows 11 and some anti-cheat' }
    else { Row 'TPM' 'Not found' 'Warn' 'BIOS: Advanced > AMD fTPM configuration > Firmware TPM' }
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cpu.VirtualizationFirmwareEnabled -or $cs.HypervisorPresent) { Row 'Virtualization (SVM)' 'On' 'Good' 'WSL, Docker and emulators can run' }
    else { Row 'Virtualization (SVM)' 'Off' 'Info' 'Only needed for WSL, Docker or Android emulators. BIOS: Advanced > CPU Configuration > SVM Mode' }
    $vbs = (Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue).VirtualizationBasedSecurityStatus
    Row 'Memory integrity (VBS)' $(if ($vbs -eq 2) { 'On' } else { 'Off' }) 'Info' $(if ($vbs -eq 2) { 'More secure; can cost a few % FPS in some games' } else { 'Off - no FPS cost' })

    # --- Windows gaming settings
    $hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue).HwSchMode
    switch ($hags) {
        2 { Row 'GPU scheduling (HAGS)' 'On' 'Good' 'Lower latency on RTX cards' }
        1 { Row 'GPU scheduling (HAGS)' 'Off' 'Warn' 'Gaming tab > Gaming tweaks turns it on' }
        default { Row 'GPU scheduling (HAGS)' 'Windows default' 'Info' 'Gaming tab > Gaming tweaks turns it on for sure' }
    }
    $gm = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue).AutoGameModeEnabled
    Row 'Game Mode' $(if ($gm -eq 0) { 'Off' } else { 'On' }) $(if ($gm -eq 0) { 'Warn' } else { 'Good' }) $(if ($gm -eq 0) { 'Gaming tab > Gaming tweaks' } else { '' })
    Row 'Power plan' ((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1') 'Info' 'Balanced is right for Ryzen 7000; Game session switches to High performance while you play'

    # --- Stability (great right after a BIOS flash or EXPO change)
    $since = (Get-Date).AddDays(-7)
    $kp = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue).Count
    Row 'Unexpected shutdowns (7 days)' $kp $(if ($kp -eq 0) { 'Good' } elseif ($kp -eq 1) { 'Warn' } else { 'Bad' }) $(if ($kp) { 'Health > Crash detective explains each one' } else { 'None' })
    $whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } -ErrorAction SilentlyContinue).Count
    Row 'Hardware errors (7 days)' $whea $(if ($whea -eq 0) { 'Good' } else { 'Bad' }) $(if ($whea) { 'Often RAM/EXPO instability - run Health > Run memory test; if it continues, try EXPO II or 5600' } else { 'None' })

    # --- Drives
    foreach ($d in Get-PhysicalDisk) {
        Row ("Drive: {0}" -f $d.FriendlyName) $d.HealthStatus $(if ($d.HealthStatus -eq 'Healthy') { 'Good' } else { 'Bad' }) $(if ($d.HealthStatus -ne 'Healthy') { 'Back up now - Health > Drive health' } else { '' })
    }
    foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 20GB }) {
        $pct = [math]::Round($v.SizeRemaining / $v.Size * 100)
        Row ("Free space {0}:" -f $v.DriveLetter) ("{0:N0} GB free ({1}%)" -f ($v.SizeRemaining / 1GB), $pct) $(if ($pct -lt 10) { 'Bad' } elseif ($pct -lt 15) { 'Warn' } else { 'Good' }) `
            $(if ($pct -lt 15) { 'Storage tab finds what to remove' } else { '' })
    }

    # --- Windows
    $os = Get-CimInstance Win32_OperatingSystem
    $up = (Get-Date) - $os.LastBootUpTime
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    Row 'Restart' $(if ($pending) { 'Pending' } else { "Up {0}d {1}h" -f $up.Days, $up.Hours }) $(if ($pending -or $up.TotalDays -gt 7) { 'Warn' } else { 'Good' }) `
        $(if ($pending) { 'Restart to finish updates or driver installs' } elseif ($up.TotalDays -gt 7) { 'Restart soon - clears leaks and applies updates' } else { '' })
    $rows
}

# ================================================================ APP UPDATES (winget)
$WingetListWork = {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return @{ Error = 'winget is not installed (get "App Installer" from the Microsoft Store).' } }
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $raw = (winget upgrade --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $lines = @($raw -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1].TrimEnd() })
    $hi = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*Name\s+Id\s+Version\s+Available') { $hi = $i; break } }
    if ($hi -lt 0) { return @() }
    $iId = $lines[$hi].IndexOf('Id ')
    for ($i = $hi + 2; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if (-not $l.Trim() -or $l -match '^\d+ upgrades? available' -or $l -match 'require explicit targeting') { break }
        if ($l.Length -le $iId) { continue }
        $t = @($l.Substring($iId).Trim() -split '\s+')
        if ($t[1] -in '<', '>') { $t = @($t[0], "$($t[1]) $($t[2])") + $t[3..($t.Count - 1)] }
        if ($t.Count -lt 3) { continue }
        [pscustomobject]@{ Name = $l.Substring(0, $iId).Trim(); Id = $t[0]; Version = $t[1]; Available = $t[2] }
    }
}

$WingetUpgradeWork = {
    param([object[]]$Items)
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $ok = 0
    foreach ($it in $Items) {
        "Updating $($it.Name) ($($it.Version) > $($it.Available))..."
        $out = winget upgrade --id $it.Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        $code = $LASTEXITCODE
        $hex = '0x{0:X8}' -f $code
        if ($code -eq 0) { "   done"; $ok++ }
        elseif ($hex -eq '0x8A15002B') { "   already up to date" }
        elseif ($hex -in '0x8A150056', '0x8A15010C') { "   skipped - the app is open. Close it and try again." }
        elseif ($hex -eq '0x8A150011' -or $hex -eq '0x8A150049') { "   you cancelled the install prompt" }
        else {
            $why = @($out -split "`n" | ForEach-Object { ($_.TrimEnd("`r") -split "`r")[-1].Trim() } | Where-Object { $_ -and $_ -notmatch '^[\-\\|/ ]+$|[^\x00-\x7F]{3}|Downloading|^Found ' }) | Select-Object -Last 1
            "   failed ($hex) $why"
        }
    }
    "Updated $ok of $($Items.Count) app(s)."
}

# ================================================================ GAME SESSION
$WuPauseKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$WuPauseNames = 'PauseUpdatesStartTime', 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime',
    'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime'

function Get-ActiveSchemeGuid { if ((powercfg /getactivescheme | Out-String) -match '([0-9a-fA-F]{8}-[0-9a-fA-F\-]{27})') { $Matches[1] } }
function Get-SchemeName { (powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1' }

function Test-UpdatesPaused {
    $v = (Get-ItemProperty $WuPauseKey -ErrorAction SilentlyContinue).PauseUpdatesExpiryTime
    $d = [datetime]::MinValue
    [bool]($v -and [datetime]::TryParse("$v", [ref]$d) -and $d.ToUniversalTime() -gt [datetime]::UtcNow)
}

function Get-GameSession { $g = (Get-Settings).GameSession; if ($g -and $g.Started) { $g } else { $null } }

function Start-GameSession {
    $s = Get-Settings
    if ($s.GameSession -and $s.GameSession.Started) { Log 'A game session is already on - click End game session when you are done.'; return }
    Log '===== GAME SESSION ON ====='
    $state = [ordered]@{ Started = (Get-Date).ToString('o'); Scheme = (Get-ActiveSchemeGuid); SchemeName = (Get-SchemeName); Reopen = @(); PausedWU = $false }

    $running = @($s.BoostApps | Where-Object { $_ -and (Get-Process -Name $_ -ErrorAction SilentlyContinue) })
    if ($running) { $state.Reopen = @(Close-Apps $running -Quiet | ForEach-Object { $_ }); Log ("Closed: {0}" -f ($running -join ', ')) }
    else { Log 'None of your Boost-list apps are running (Gaming tab > tick apps > Save as Auto Boost list).' }

    powercfg /setactive SCHEME_MIN
    Log "Power plan: High performance while you play (was $($state.SchemeName))"

    if ($IsAdmin) {
        if (Test-UpdatesPaused) { Log 'Windows Update was already paused - leaving it as is.' }
        else {
            if (-not (Test-Path $WuPauseKey)) { New-Item $WuPauseKey -Force | Out-Null }
            $now = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); $end = [datetime]::UtcNow.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
            foreach ($n in $WuPauseNames) { Set-ItemProperty $WuPauseKey -Name $n -Value $(if ($n -match 'Start') { $now } else { $end }) -Type String }
            $state.PausedWU = $true
            Log 'Windows Update paused - no downloads or restarts mid-game (resumes by itself after 24 h if you forget).'
        }
    } else { Log 'Windows Update pause - skipped (open the toolkit as admin for this part).' }

    try { Clear-DnsClientCache -ErrorAction Stop } catch { }
    $s.GameSession = [pscustomobject]$state; Save-Settings $s
    Log 'Have fun. Click End game session (or the tray menu) when you are done - everything goes back.'
}

function Stop-GameSession {
    $s = Get-Settings; $g = $s.GameSession
    if (-not ($g -and $g.Started)) { Log 'No game session is on.'; return }
    Log '===== GAME SESSION OFF ====='
    if ($g.Scheme) { powercfg /setactive $g.Scheme; Log "Power plan back to $(Get-SchemeName)" }
    if ($g.PausedWU) {
        if ($IsAdmin) {
            foreach ($n in $WuPauseNames) { Remove-ItemProperty $WuPauseKey -Name $n -ErrorAction SilentlyContinue }
            Log 'Windows Update resumed'
        } else { Log 'Windows Update stays paused until the 24 h limit (open the toolkit as admin and end again to resume now).' }
    }
    $back = @()
    foreach ($p in @($g.Reopen | ForEach-Object { $_ })) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        $n = [IO.Path]::GetFileNameWithoutExtension($p)
        if (Get-Process -Name $n -ErrorAction SilentlyContinue) { continue }
        try { Start-Process -FilePath $p -WindowStyle Minimized -ErrorAction Stop; $back += $n } catch { Log "Could not reopen $n" }
    }
    if ($back) { Log ("Reopened: {0}" -f ($back -join ', ')) }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse("$($g.Started)", [ref]$d)) { $m = [int]((Get-Date) - $d).TotalMinutes; Log ("Session length: {0}h {1:D2}m" -f [int][math]::Floor($m / 60), ($m % 60)) }
    $s.GameSession = $null; Save-Settings $s
}

# ================================================================ PRIVACY: camera / mic / location history
# Windows records when each app last used these in the CapabilityAccessManager consent store (per user). Read-only.
function Get-DeviceAccessHistory {
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
    $caps = [ordered]@{ webcam = 'Camera'; microphone = 'Microphone'; location = 'Location' }
    foreach ($cap in $caps.Keys) {
        $base = Join-Path $root $cap
        if (-not (Test-Path $base)) { continue }
        $keys = @(Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object PSChildName -ne 'NonPackaged')
        if (Test-Path "$base\NonPackaged") { $keys += @(Get-ChildItem "$base\NonPackaged" -ErrorAction SilentlyContinue) }
        foreach ($k in $keys) {
            $start = [int64]($k.GetValue('LastUsedTimeStart', 0)); $stop = [int64]($k.GetValue('LastUsedTimeStop', 0))
            if ($start -le 0) { continue }
            $id = $k.PSChildName
            if ($k.PSParentPath -match 'NonPackaged$') { $path = $id -replace '#', '\'; $name = [IO.Path]::GetFileNameWithoutExtension($path) }
            else { $path = $id; $name = ($id -split '_')[0] -replace '^Microsoft\.(Windows)?', '' }
            [pscustomobject]@{
                Device = $caps[$cap]; App = $name; Path = $path
                Last = [datetime]::FromFileTime($start); InUse = ($stop -eq 0 -or $stop -lt $start)
                Seconds = $(if ($stop -gt $start) { [int](($stop - $start) / 1e7) } else { 0 })
            }
        }
    }
}

# ================================================================ PRIVACY CLEAN
function Invoke-PrivacyClean {
    Log '===== PRIVACY CLEAN ====='
    $recent = [Environment]::GetFolderPath('Recent')
    $n = @(Get-ChildItem $recent -File -Force -ErrorAction SilentlyContinue).Count
    Get-ChildItem $recent -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Log "Recent files list - cleared $n entries (the files themselves are untouched)"
    $j = 0
    foreach ($sub in 'AutomaticDestinations', 'CustomDestinations') {
        $p = Join-Path $recent $sub
        $items = @(Get-ChildItem $p -File -Force -ErrorAction SilentlyContinue); $j += $items.Count
        $items | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Log "Jump lists (taskbar right-click history) - cleared $j"
    $exp = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    foreach ($k in 'WordWheelQuery', 'TypedPaths', 'RunMRU') {
        if (Test-Path "$exp\$k") {
            $props = (Get-Item "$exp\$k").Property
            foreach ($v in $props) { Remove-ItemProperty "$exp\$k" -Name $v -ErrorAction SilentlyContinue }
        }
    }
    Log 'File Explorer search box, address bar and Run box history - cleared'
    try {
        $ok = [Windows.ApplicationModel.DataTransfer.Clipboard, Windows.ApplicationModel.DataTransfer, ContentType = WindowsRuntime]::ClearHistory()
        Log ("Clipboard history - {0}" -f $(if ($ok) { 'cleared (pinned clips are kept)' } else { 'could not clear' }))
    } catch { try { [System.Windows.Forms.Clipboard]::Clear(); Log 'Clipboard - cleared' } catch { Log 'Clipboard - skipped' } }
    Log 'Done. Quick Access in File Explorer refreshes after the next Explorer restart.'
}

# ================================================================ SHARE YOUR SETUP (export / import)
$ShareableSettings = 'BoostApps', 'AutoBoost', 'ReopenAfterGame', 'PanicHotkey', 'AutoUpdate', 'RecordSessions'

function Export-HallowSetup([string]$File) {
    $s = Get-Settings
    $out = [ordered]@{ HallowSetup = 1; From = "Hallow Toolkit v$AppVersion"; Created = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Settings = [ordered]@{}; TweaksOn = @() }
    foreach ($n in $ShareableSettings) { if ($s.PSObject.Properties.Name -contains $n) { $out.Settings[$n] = $s.$n } }
    $out.TweaksOn = @($Tweaks | Where-Object { Test-Tweak $_ } | ForEach-Object { $_.Id })
    $out | ConvertTo-Json -Depth 5 | Set-Content $File -Encoding UTF8
    Log ("Saved your setup to {0}: {1} tweaks on, Boost list: {2}" -f $File, $out.TweaksOn.Count, (@($s.BoostApps) -join ', '))
}

# Returns a plan (what would change) without changing anything.
function Read-HallowSetup([string]$File) {
    $j = Get-Content $File -Raw | ConvertFrom-Json
    if (-not $j.HallowSetup) { throw 'That file is not a Hallow Toolkit setup file.' }
    $turnOn = @(); $turnOff = @()
    foreach ($t in $Tweaks) {
        $want = @($j.TweaksOn) -contains $t.Id; $now = Test-Tweak $t
        if ($want -and -not $now) { $turnOn += $t } elseif ($now -and -not $want) { $turnOff += $t }
    }
    [pscustomobject]@{ Source = $j; TurnOn = $turnOn; TurnOff = $turnOff }
}

function Import-HallowSetup($Plan, [bool]$AlsoTurnOff) {
    $s = Get-Settings
    foreach ($p in $Plan.Source.Settings.PSObject.Properties) {
        if ($ShareableSettings -contains $p.Name) { $s | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
    Save-Settings $s
    Log ("Toolkit settings imported (Boost list: {0})" -f (@($s.BoostApps) -join ', '))
    foreach ($t in $Plan.TurnOn) { Set-Tweak $t $true }
    if ($AlsoTurnOff) { foreach ($t in $Plan.TurnOff) { Set-Tweak $t $false } }
}
