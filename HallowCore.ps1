<#
  Hallow Toolkit - shared tools (no window code). Dot-sourced by HallowToolkit.ps1 and HallowTray.ps1.
#>

$AppName = 'Hallow Toolkit'
$AppVersion = '3.4'
$HallowRoot = $PSScriptRoot
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

$LogDir = Join-Path $HallowRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("hallow-{0:yyyy-MM-dd}.log" -f (Get-Date))
if (-not (Get-Variable -Name LogBox -Scope Script -ErrorAction SilentlyContinue)) { $script:LogBox = $null }

function Log([string]$Message) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    if ($script:LogBox) {
        $script:LogBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    } else { Write-Host $line }
}

# Compiles a small C# helper once into bin\, then loads the ready-made DLL on every later start (much faster).
function Import-HallowType([string]$TypeName, [string]$Source, [string[]]$Refs) {
    if ($TypeName -as [type]) { return }
    $refArgs = @{}; if ($Refs) { $refArgs.ReferencedAssemblies = $Refs }
    $bin = Join-Path $HallowRoot 'bin'
    $sha = [Security.Cryptography.SHA1]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Source + ($Refs -join ','))))).Replace('-', '').Substring(0, 10)
    $dll = Join-Path $bin "$TypeName-$hash.dll"
    if (Test-Path $dll) { try { Add-Type -Path $dll -ErrorAction Stop; if ($TypeName -as [type]) { return } } catch { } }
    try {
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        Add-Type -TypeDefinition $Source -OutputAssembly $dll -OutputType Library -ErrorAction Stop @refArgs
        if (-not ($TypeName -as [type])) { Add-Type -Path $dll -ErrorAction Stop }
        Get-ChildItem $bin -Filter "$TypeName-*.dll" | Where-Object FullName -ne $dll | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {
        if (-not ($TypeName -as [type])) { Add-Type -TypeDefinition $Source @refArgs }
    }
}

function Need-Admin([string]$What) {
    if ($IsAdmin) { return $true }
    Log "$What needs admin. Close the toolkit, open it again and click Yes on the prompt."
    return $false
}

function Confirm-Action([string]$Message) {
    if (-not $script:LogBox) { return $true }
    [System.Windows.Forms.MessageBox]::Show($Message, $AppName, 'YesNo', 'Warning') -eq 'Yes'
}

function Get-FolderBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($sum) { [double]$sum } else { 0 }
}

function Format-GB([double]$Bytes) { '{0:N2} GB' -f ($Bytes / 1GB) }
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) } elseif ($Bytes -ge 1MB) { '{0:N0} MB' -f ($Bytes / 1MB) } else { '{0:N0} KB' -f ($Bytes / 1KB) }
}

function Get-DriveSpace {
    # .NET DriveInfo is instant (WMI takes ~0.1-0.2 s on first use)
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady -or $d.TotalSize -le 0) { continue }
        [pscustomobject]@{
            Drive = $d.Name.TrimEnd('\'); Label = $d.VolumeLabel
            FreeGB = [math]::Round($d.TotalFreeSpace / 1GB, 1); SizeGB = [math]::Round($d.TotalSize / 1GB, 1)
            FreePct = [math]::Round(100 * $d.TotalFreeSpace / $d.TotalSize)
        }
    }
}

function Clear-FolderContents([string]$Path, [string]$Label, [string[]]$Keep = @()) {
    if (-not (Test-Path -LiteralPath $Path)) { Log "$Label - nothing to clean"; return }
    $before = Get-FolderBytes $Path
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Where-Object { $Keep -notcontains $_.Name } |
        ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { } }
    $after = Get-FolderBytes $Path
    Log ("{0} - freed {1} ({2} left - in use or skipped)" -f $Label, (Format-GB ($before - $after)), (Format-GB $after))
}

function Test-PendingReboot {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}

function Start-InNewWindow([string]$Title, [string]$Command) {
    $full = "`$host.UI.RawUI.WindowTitle = '$Title'; $Command; Write-Host ''; Write-Host 'Finished. You can close this window.' -ForegroundColor Green"
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-Command', $full)
}

# ---------------------------------------------------------------- settings
$SettingsFile = Join-Path $HallowRoot 'settings.json'
function Get-Settings {
    $s = [pscustomobject]@{
        BoostApps       = @('OneDrive', 'ms-teams', 'PhoneExperienceHost', 'ChatGPT')
        ReopenAfterGame = $true
        AutoBoost       = $true
        PanicHotkey     = $true
        AutoUpdate      = $true
        LastUpdateCheck = ''
        GameSession     = $null
        LastBios        = ''
    }
    if (Test-Path $SettingsFile) {
        try {
            $f = Get-Content $SettingsFile -Raw | ConvertFrom-Json
            foreach ($p in $f.PSObject.Properties) { $s | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
        } catch { }
    }
    $s.BoostApps = @($s.BoostApps)
    $s
}
function Save-Settings($Settings) { $Settings | ConvertTo-Json -Depth 5 | Set-Content $SettingsFile -Encoding UTF8 }

# ================================================================ TUNE-UP

function Invoke-HealthReport {
    Log '===== HEALTH REPORT ====='
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    Log "Windows 11 $($cv.DisplayVersion) (build $($cv.CurrentBuild).$($cv.UBR))"
    $wu = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    if ($wu -and $wu.TargetReleaseVersion -eq 1) {
        Log "  PROBLEM: Windows Update is pinned to '$($wu.TargetReleaseVersionInfo)'. Click 'Unblock Windows updates'."
    } else { Log '  Windows Update version pin: none (good)' }
    $dates = foreach ($q in (Get-CimInstance Win32_QuickFixEngineering -ErrorAction SilentlyContinue)) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParse([string]$q.InstalledOn, [cultureinfo]::InvariantCulture, 'None', [ref]$d)) { $d }
    }
    $last = $dates | Sort-Object -Descending | Select-Object -First 1
    if ($last) {
        $days = ((Get-Date) - $last).Days
        Log ("  Last Windows update: {0:yyyy-MM-dd} ({1} days ago){2}" -f $last, $days, $(if ($days -gt 60) { '  <- too long' } else { '' }))
    }
    if (Test-PendingReboot) { Log '  A restart is pending to finish updates.' }
    $up = (Get-Date) - $os.LastBootUpTime
    Log ("Uptime: {0}d {1}h{2}" -f $up.Days, $up.Hours, $(if ($up.TotalDays -gt 3) { '  <- restart soon' } else { '' }))
    $totalGB = $os.TotalVisibleMemorySize / 1MB; $freeGB = $os.FreePhysicalMemory / 1MB
    Log ('RAM: {0:N1} GB used of {1:N1} GB' -f ($totalGB - $freeGB), $totalGB)
    Get-Process | Group-Object ProcessName | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; MB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB) }
    } | Sort-Object MB -Descending | Select-Object -First 6 | ForEach-Object { Log ("  {0,-28} {1,6} MB" -f $_.Name, $_.MB) }
    Log 'Drives:'
    foreach ($d in Get-DriveSpace) {
        $warn = if ($d.FreePct -lt 15) { '  <- low, free up space' } else { '' }
        Log ("  {0} {1,-8} {2,7} GB free of {3} GB ({4}%){5}" -f $d.Drive, $d.Label, $d.FreeGB, $d.SizeGB, $d.FreePct, $warn)
    }
    Log ("Temp folder: {0}" -f (Format-GB (Get-FolderBytes $env:TEMP)))
    $gm = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue).AutoGameModeEnabled
    Log ("Game Mode: {0}" -f $(if ($gm -eq 0) { 'OFF  <- Gaming > Gaming tweaks' } else { 'on' }))
    Log ("Mouse acceleration: {0}" -f $(if ((Get-MouseAccel)) { 'ON  <- Gaming > Mouse acceleration' } else { 'off (good for aim)' }))
    Log ("Power plan: {0}" -f ((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1'))
    Log ("Startup entries: {0}" -f @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue).Count)
    $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue)
    Log ("Unexpected shutdowns (30 days): {0}{1}" -f $crashes.Count, $(if ($crashes.Count -gt 1) { '  <- Health > Crash detective' } else { '' }))
    Log '===== END REPORT ====='
}

function Invoke-QuickClean([bool]$EmptyRecycleBin = $true) {
    Log '===== QUICK CLEAN-UP ====='
    $before = Get-DriveSpace
    Clear-FolderContents $env:TEMP 'Your temp files' -Keep @('claude')
    Clear-FolderContents (Join-Path $env:LOCALAPPDATA 'CrashDumps') 'Crash dumps'
    if ($IsAdmin) {
        Clear-FolderContents (Join-Path $env:WINDIR 'Temp') 'Windows temp files'
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Log 'Delivery Optimization cache - cleared' } catch { Log 'Delivery Optimization cache - skipped' }
    } else { Log 'Windows temp + update caches - skipped (needs admin)' }
    if ($EmptyRecycleBin) { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Log 'Recycle Bin - emptied' }
    try { Clear-DnsClientCache -ErrorAction Stop; Log 'DNS cache - flushed' } catch { Log 'DNS cache - skipped' }
    if ($IsAdmin) {
        Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' } | ForEach-Object {
            try { Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction Stop; Log "SSD TRIM on $($_.DriveLetter): - done" }
            catch { Log "SSD TRIM on $($_.DriveLetter): - skipped" }
        }
    } else { Log 'SSD TRIM - skipped (needs admin)' }
    foreach ($a in Get-DriveSpace) {
        $b = $before | Where-Object Drive -eq $a.Drive
        Log ("{0} now {1} GB free (+{2:N1} GB)" -f $a.Drive, $a.FreeGB, ($a.FreeGB - $b.FreeGB))
    }
    Log '===== DONE ====='
}

function Invoke-UnblockWindowsUpdates {
    if (-not (Need-Admin 'Unblocking Windows updates')) { return }
    $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; $removed = 0
    foreach ($name in 'TargetReleaseVersion', 'TargetReleaseVersionInfo', 'ProductVersion') {
        if ((Get-ItemProperty $key -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains $name) {
            Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue; Log "Removed policy: $name"; $removed++
        }
    }
    if ($removed -eq 0) { Log 'No version pin found - Windows Update is not blocked.' }
    try { Start-Process UsoClient.exe -ArgumentList 'StartInteractiveScan' -ErrorAction Stop } catch { }
    Start-Process 'ms-settings:windowsupdate'
    Log 'Opened Windows Update - click "Check for updates".'
}

function Invoke-UpdateApps {
    Log 'Updating all apps with winget in a new window (installers may pop up)...'
    Start-InNewWindow 'Updating apps' 'winget upgrade --all --accept-package-agreements --accept-source-agreements --disable-interactivity'
}

function Invoke-RepairWindows {
    if (-not (Need-Admin 'Repairing Windows')) { return }
    Log 'Repairing Windows system files in a new window (10-30 minutes)...'
    Start-InNewWindow 'Repairing Windows' 'DISM /Online /Cleanup-Image /RestoreHealth; sfc /scannow'
}

$TaskName = 'Hallow Toolkit Weekly Clean-up'
function Invoke-ToggleWeeklyClean {
    if (-not (Need-Admin 'Scheduling the weekly clean-up')) { return }
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Log 'Weekly auto clean-up - turned OFF'; return
    }
    $main = Join-Path $HallowRoot 'HallowToolkit.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$main`" -Mode Quick -NoRecycleBin"
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '3:00 AM'
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    Log 'Weekly auto clean-up - turned ON (Sundays 3 AM, or next time the PC is on; Recycle Bin is left alone)'
}

# ================================================================ HEALTH

$BugChecks = @{
    0x0A  = @('IRQL_NOT_LESS_OR_EQUAL', 'a driver or unstable RAM')
    0x19  = @('BAD_POOL_HEADER', 'a driver or unstable RAM')
    0x1A  = @('MEMORY_MANAGEMENT', 'unstable RAM - try turning EXPO off or lowering RAM speed')
    0x1E  = @('KMODE_EXCEPTION_NOT_HANDLED', 'a faulty driver')
    0x3B  = @('SYSTEM_SERVICE_EXCEPTION', 'a faulty driver (often GPU or anti-cheat)')
    0x50  = @('PAGE_FAULT_IN_NONPAGED_AREA', 'unstable RAM or a faulty driver')
    0x7E  = @('SYSTEM_THREAD_EXCEPTION_NOT_HANDLED', 'a faulty driver')
    0x9F  = @('DRIVER_POWER_STATE_FAILURE', 'a driver failing on sleep/wake')
    0xC2  = @('BAD_POOL_CALLER', 'a faulty driver')
    0xD1  = @('DRIVER_IRQL_NOT_LESS_OR_EQUAL', 'a faulty driver (often network or GPU)')
    0xEF  = @('CRITICAL_PROCESS_DIED', 'corrupted Windows files or a failing drive - run Repair Windows files')
    0x101 = @('CLOCK_WATCHDOG_TIMEOUT', 'CPU instability - overclock/PBO/undervolt or BIOS')
    0x116 = @('VIDEO_TDR_FAILURE', 'the graphics driver or GPU')
    0x124 = @('WHEA_UNCORRECTABLE_ERROR', 'hardware instability - RAM EXPO, CPU overclock or BIOS')
    0x133 = @('DPC_WATCHDOG_VIOLATION', 'a driver or SSD firmware')
    0x139 = @('KERNEL_SECURITY_CHECK_FAILURE', 'a driver or unstable RAM')
}

function Invoke-CrashDetective {
    Log '===== CRASH DETECTIVE (last 60 days) ====='
    $since = (Get-Date).AddDays(-60)
    $logStart = (Get-WinEvent -LogName System -MaxEvents 1 -Oldest -ErrorAction SilentlyContinue).TimeCreated
    if ($logStart -and $logStart -gt $since) { Log ("(Windows' crash history only goes back to {0:yyyy-MM-dd} - older logs were cleared, e.g. by a Windows upgrade)" -f $logStart) }
    $clues = @{ Power = 0; BSOD = 0; RAM = 0; Driver = 0; GPU = 0; Hardware = 0 }

    $kp = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue)
    Log ("Unexpected shutdowns: {0}" -f $kp.Count)
    foreach ($e in $kp) {
        $x = [xml]$e.ToXml(); $d = @{}
        foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
        $code = [int64]$d['BugcheckCode']
        if ($code -ne 0) {
            $info = $BugChecks[[int]$code]
            if ($info) { Log ("  {0:yyyy-MM-dd HH:mm}  BLUE SCREEN {1} (0x{2:X}) - usually {3}" -f $e.TimeCreated, $info[0], $code, $info[1]) }
            else { Log ("  {0:yyyy-MM-dd HH:mm}  BLUE SCREEN code 0x{1:X}" -f $e.TimeCreated, $code) }
            $clues.BSOD++
            if ($info -and $info[1] -match 'RAM') { $clues.RAM++ }
            if ($info -and $info[1] -match 'driver') { $clues.Driver++ }
            if ($info -and $info[1] -match 'hardware|CPU') { $clues.Hardware++ }
        } elseif ([int64]$d['PowerButtonTimestamp'] -ne 0) {
            Log ("  {0:yyyy-MM-dd HH:mm}  Power button held - the PC was frozen and forced off" -f $e.TimeCreated); $clues.Hardware++
        } else {
            Log ("  {0:yyyy-MM-dd HH:mm}  Sudden power-off with no blue screen (power cut, PSU, or a hard freeze)" -f $e.TimeCreated); $clues.Power++
        }
    }

    $whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } -ErrorAction SilentlyContinue)
    Log ("Hardware error reports (WHEA): {0}{1}" -f $whea.Count, $(if ($whea.Count) { '  <- CPU/RAM/PCIe errors, often from EXPO or overclocks' } else { '' }))
    $clues.Hardware += [math]::Min($whea.Count, 3)
    foreach ($w in $whea | Select-Object -First 3) { Log ("  {0:yyyy-MM-dd HH:mm}  {1}" -f $w.TimeCreated, (($w.Message -split "`n")[0]).Trim()) }

    $tdr = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $since } -ErrorAction SilentlyContinue)
    Log ("Graphics driver resets: {0}{1}" -f $tdr.Count, $(if ($tdr.Count) { '  <- GPU driver crashed and recovered' } else { '' }))
    $clues.GPU += $tdr.Count

    if ($IsAdmin) {
        $dumps = @(Get-ChildItem "$env:WINDIR\Minidump" -Filter *.dmp -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        Log ("Crash dump files: {0}" -f $dumps.Count)
        foreach ($m in $dumps | Select-Object -First 5) { Log ("  {0:yyyy-MM-dd HH:mm}  {1}" -f $m.LastWriteTime, $m.Name) }
    }

    $apps = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Properties[0].Value } | Group-Object | Sort-Object Count -Descending | Select-Object -First 6
    if ($apps) { Log 'Apps/games that crashed (30 days):'; foreach ($a in $apps) { Log ("  {0,3}x  {1}" -f $a.Count, $a.Name) } }
    else { Log 'Apps/games that crashed (30 days): none' }

    Log '--- Verdict ---'
    if (($kp.Count + $whea.Count + $tdr.Count) -eq 0) { Log 'No system crashes found. Nice and stable.' }
    else {
        if ($clues.RAM -gt 0 -or $clues.Hardware -gt 0) { Log '* Most likely hardware stability: run Health > Memory check, and if it keeps happening turn EXPO off (or set RAM to 5600) in the BIOS and update the BIOS.' }
        if ($clues.Driver -gt 0) { Log '* A driver is involved: update GPU, chipset and network drivers (Health > Driver check).' }
        if ($clues.GPU -gt 0) { Log '* Graphics driver crashes: update or clean-reinstall the NVIDIA driver; check GPU temps on the Monitor tab.' }
        if ($clues.Power -gt 0) { Log '* Sudden power-offs with no blue screen point at power: PSU, power strip/outlet, or a hard freeze. Update the BIOS too.' }
    }
    Log '===== END ====='
}

function Get-RamInfo {
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    [pscustomobject]@{
        Sticks = $ram.Count; TotalGB = ($ram | Measure-Object Capacity -Sum).Sum / 1GB
        Rated = ($ram | Select-Object -First 1).Speed; Running = ($ram | Select-Object -First 1).ConfiguredClockSpeed
        Part = (($ram | Select-Object -First 1).PartNumber).Trim()
    }
}

function Invoke-MemoryInfo {
    Log '===== MEMORY ====='
    $r = Get-RamInfo
    Log ("{0} x {1:N0} GB = {2:N0} GB  ({3})" -f $r.Sticks, ($r.TotalGB / $r.Sticks), $r.TotalGB, $r.Part)
    Log ("Running at {0} MT/s (standard speed {1} MT/s)" -f $r.Running, $r.Rated)
    if ($r.Running -gt $r.Rated) { Log '  EXPO/XMP is ON - faster, but if the PC crashes randomly this is suspect #1.' }
    $res = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 3 -ErrorAction SilentlyContinue
    if ($res) { foreach ($e in $res) { Log ("Last memory test {0:yyyy-MM-dd}: {1}" -f $e.TimeCreated, (($e.Message -split "`n")[0]).Trim()) } }
    else { Log 'No memory test has been run yet (or the logs were cleared).' }
}

function Invoke-MemoryTest {
    if (-not (Need-Admin 'The memory test')) { return }
    Log 'Opening Windows Memory Diagnostic. Choose "Restart now" or "Check next time I start my computer".'
    Log 'The test takes 10-20 minutes during restart. Afterwards, click "Memory info" here to see the result.'
    Start-Process mdsched.exe
}

function Invoke-SsdHealth {
    Log '===== DRIVE HEALTH ====='
    foreach ($d in Get-PhysicalDisk) {
        Log ("{0} ({1:N0} GB, {2} {3}) - {4}" -f $d.FriendlyName, ($d.Size / 1GB), $d.BusType, $d.MediaType, $d.HealthStatus)
        if ($IsAdmin) {
            $c = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($c) {
                if ($null -ne $c.Wear) { Log ("  Wear used: {0}%{1}" -f $c.Wear, $(if ($c.Wear -ge 80) { '  <- plan a replacement' } else { '' })) }
                if ($c.Temperature) { Log ("  Temperature: {0} C (max seen {1} C)" -f $c.Temperature, $c.TemperatureMax) }
                if ($null -ne $c.PowerOnHours) { Log ("  Powered on: {0:N0} hours" -f $c.PowerOnHours) }
                $errs = [int64]$c.ReadErrorsUncorrected + [int64]$c.WriteErrorsUncorrected
                Log ("  Uncorrected errors: {0}{1}" -f $errs, $(if ($errs -gt 0) { '  <- back up important files!' } else { '' }))
            }
        }
    }
    if (-not $IsAdmin) { Log '(Open the toolkit as admin to see wear, temperature and error counts.)' }
}

function Invoke-DriverCheck {
    Log '===== DRIVERS ====='
    $drv = Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY' OR DeviceClass='NET' OR DeviceClass='MEDIA'" -ErrorAction SilentlyContinue |
        Where-Object { $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' -and $_.DeviceName -notmatch 'Virtual|Tailscale|Nord|WAN Miniport|TAP|OpenVPN|WireGuard' }
    foreach ($d in $drv | Sort-Object DeviceClass, DeviceName -Unique) {
        $date = $d.DriverDate
        $age = if ($date) { ((Get-Date) - $date).Days } else { 0 }
        $ver = $d.DriverVersion
        if ($d.DeviceClass -eq 'DISPLAY' -and $d.DeviceName -match 'NVIDIA' -and ($ver -replace '\.', '').Length -ge 5) {
            $digits = ($ver -replace '\.', ''); $n = $digits.Substring($digits.Length - 5)
            $ver = "{0}.{1}  ({2})" -f $n.Substring(0, 3), $n.Substring(3), $d.DriverVersion
        }
        Log ("{0,-8} {1}" -f $d.DeviceClass, $d.DeviceName)
        Log ("         version {0}, dated {1:yyyy-MM-dd}{2}" -f $ver, $date, $(if ($age -gt 180) { "  <- $age days old, check for an update" } else { '' }))
    }
    Log 'Get updates: NVIDIA app (GPU), or the Drivers tab (motherboard drivers, BIOS and Windows Update drivers).'
}

# ================================================================ GAMING

function Invoke-GamingTweaks {
    $gb = 'HKCU:\Software\Microsoft\GameBar'
    if (-not (Test-Path $gb)) { New-Item $gb -Force | Out-Null }
    Set-ItemProperty $gb -Name AutoGameModeEnabled -Value 1 -Type DWord
    Set-ItemProperty $gb -Name AllowAutoGameMode -Value 1 -Type DWord
    Log 'Game Mode - ON'
    if ($IsAdmin) {
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -Value 2 -Type DWord
        Log 'Hardware-accelerated GPU scheduling - ON (after restart)'
    } else { Log 'GPU scheduling - skipped (needs admin)' }
}

function Set-PowerPlan([string]$Scheme) {
    powercfg /setactive $Scheme
    Log ("Power plan set to {0}" -f ((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1'))
}

Import-HallowType 'HallowNative' @'
using System; using System.Runtime.InteropServices;
public static class HallowNative {
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SystemParametersInfo(uint action, uint param, int[] vparam, uint winIni);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
'@

function Get-MouseAccel { (Get-ItemProperty 'HKCU:\Control Panel\Mouse' -ErrorAction SilentlyContinue).MouseSpeed -ne '0' }
function Set-MouseAccel([bool]$On) {
    $vals = if ($On) { @(6, 10, 1) } else { @(0, 0, 0) }
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold1 -Value ([string]$vals[0])
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold2 -Value ([string]$vals[1])
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed -Value ([string]$vals[2])
    [void][HallowNative]::SystemParametersInfo(0x0004, 0, [int[]]$vals, 3)   # SPI_SETMOUSE, apply now
    Log ("Mouse acceleration (Enhance pointer precision) - {0}" -f $(if ($On) { 'ON (Windows default)' } else { 'OFF - 1:1 aim, better for shooters' }))
}

function Clear-ShaderCache {
    Log '===== SHADER CACHE ====='
    $paths = @(
        @("$env:LOCALAPPDATA\NVIDIA\DXCache", 'NVIDIA DirectX cache'),
        @("$env:LOCALAPPDATA\NVIDIA\GLCache", 'NVIDIA OpenGL cache'),
        @("$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache", 'NVIDIA cache'),
        @("$env:LOCALAPPDATA\D3DSCache", 'DirectX shader cache'),
        @("$env:LOCALAPPDATA\AMD\DxCache", 'AMD DirectX cache'))
    foreach ($p in $paths) { if (Test-Path $p[0]) { Clear-FolderContents $p[0] $p[1] } }
    Log 'Games rebuild shaders the first time you play - expect a short loading/stutter once.'
}

$BackgroundHogs = @('OneDrive', 'ms-teams', 'Teams', 'PhoneExperienceHost', 'ChatGPT', 'Medal', 'Spotify', 'msedge',
    'Radarr.Console', 'EpicGamesLauncher', 'UbisoftConnect', 'upc', 'Battle.net', 'EADesktop', 'Grok Bot', 'Codex', 'CrossDeviceService')
$NeverClose = @('explorer', 'powershell', 'pwsh', 'conhost', 'dwm', 'csrss', 'winlogon', 'svchost', 'ApplicationFrameHost',
    'TextInputHost', 'SystemSettings', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'Idle', 'System', 'lsass', 'services', 'smss', 'wininit')

function Get-ClosableApps {
    Get-Process | Where-Object { $NeverClose -notcontains $_.ProcessName -and $_.Id -ne $PID } |
        Where-Object { $_.MainWindowTitle -or $BackgroundHogs -contains $_.ProcessName } |
        Group-Object ProcessName | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; MB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB) }
        } | Sort-Object MB -Descending
}

# Closes apps by process name. Returns the exe paths that were running (so they can be reopened later).
function Close-Apps([string[]]$Names, [switch]$Quiet) {
    $freed = 0; $paths = @()
    foreach ($n in $Names) {
        $ps = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        if (-not $ps) { continue }
        $mb = ($ps | Measure-Object WorkingSet64 -Sum).Sum / 1MB
        $p0 = $ps | Where-Object { $_.Path } | Select-Object -First 1
        if ($p0) { $paths += $p0.Path }
        foreach ($p in $ps) { try { [void]$p.CloseMainWindow() } catch { } }
        Start-Sleep -Milliseconds 1200
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $freed += $mb
        if (-not $Quiet) { Log ("Closed {0} ({1:N0} MB)" -f $n, $mb) }
    }
    if (-not $Quiet) { Log ("Freed about {0:N1} GB of RAM" -f ($freed / 1024)) }
    , $paths
}

function Get-UniquePaths([string[]]$Paths) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $Paths) { if ($p) { $q = $p.TrimEnd('\'); if ($set.Add($q)) { $q } } }
}

function Get-SteamLibraries {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { return }
    $steam = $steam -replace '/', '\'
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    $libs = @($steam)
    if (Test-Path $vdf) { $libs += (Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }) }
    Get-UniquePaths $libs
}

# Folders where installed games live (Steam libraries, Xbox, Epic, etc.)
function Get-GameRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($l in Get-SteamLibraries) { $c = Join-Path $l 'steamapps\common'; if (Test-Path $c) { $roots.Add($c) } }
    foreach ($d in Get-PSDrive -PSProvider FileSystem) {
        foreach ($x in 'Xbox', 'XboxGames', 'Program Files\Epic Games', 'Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games', 'Program Files\EA Games', 'Riot Games', 'Games') {
            $p = Join-Path $d.Root $x
            if (Test-Path $p) { $roots.Add($p) }
        }
    }
    @(Get-UniquePaths $roots)
}

function Get-SteamGames {
    foreach ($l in Get-SteamLibraries) {
        foreach ($acf in Get-ChildItem (Join-Path $l 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
            $t = Get-Content $acf.FullName -Raw -Encoding UTF8
            $get = { param($k) if ($t -match ('"' + $k + '"\s+"([^"]*)"')) { $Matches[1] } }
            $id = & $get 'appid'; $name = & $get 'name'; $dir = & $get 'installdir'
            if ($name -match 'Steamworks Common|Redistributables|Proton|Steam Linux Runtime') { continue }
            $lp = [int64](& $get 'LastPlayed')
            [pscustomobject]@{
                Name = $name; Store = 'Steam'; Id = $id; Bytes = [double](& $get 'SizeOnDisk')
                LastPlayed = $(if ($lp -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($lp).LocalDateTime } else { $null })
                Path = (Join-Path $l "steamapps\common\$dir")
            }
        }
    }
}

# ================================================================ NETWORK

function Get-MainAdapter {
    $phys = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    foreach ($r in (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric)) {
        $a = $phys | Where-Object ifIndex -eq $r.ifIndex
        if ($a) { return $a }
    }
    $phys | Select-Object -First 1
}

function Invoke-NetworkInfo {
    $a = Get-MainAdapter
    if (-not $a) { Log 'No connected network adapter found.'; return }
    $ip = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex
    Log '===== NETWORK ====='
    Log "Adapter:  $($a.Name) - $($a.InterfaceDescription)"
    Log "Speed:    $($a.LinkSpeed)"
    Log "IP:       $(($ip.IPv4Address | Select-Object -First 1).IPAddress)"
    Log "Router:   $(($ip.IPv4DefaultGateway | Select-Object -First 1).NextHop)"
    Log "DNS:      $((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses -join ', ')"
    $vpn = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'Nord|Tailscale|WireGuard|TAP|VPN' }
    if ($vpn) { Log "VPN/tunnels up: $(($vpn.Name) -join ', ')  (VPNs can add ping in games)" }
}

function Set-GamingDns([bool]$Cloudflare) {
    if (-not (Need-Admin 'Changing DNS')) { return }
    $a = Get-MainAdapter
    if (-not $a) { Log 'No connected network adapter found.'; return }
    if ($Cloudflare) {
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @('1.1.1.1', '1.0.0.1')
        Log "DNS on $($a.Name) set to Cloudflare (1.1.1.1, 1.0.0.1)"
    } else {
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses
        Log "DNS on $($a.Name) reset to automatic (from your router)"
    }
    Clear-DnsClientCache
}

function Invoke-NetworkReset {
    if (-not (Need-Admin 'Network reset')) { return }
    if (-not (Confirm-Action "Reset Windows networking (Winsock + TCP/IP)?`n`nUse this when the internet is acting up. You must restart afterwards.")) { return }
    netsh winsock reset | Out-Null; netsh int ip reset | Out-Null; ipconfig /flushdns | Out-Null
    Log 'Network stack reset. Restart the PC to finish.'
}

function Invoke-WhoIsOnline {
    Log '===== APPS USING THE INTERNET RIGHT NOW ====='
    $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|fe80)' }
    $groups = $conns | Group-Object OwningProcess | ForEach-Object {
        $p = Get-Process -Id ([int]$_.Name) -ErrorAction SilentlyContinue
        [pscustomobject]@{ Name = $(if ($p) { $p.ProcessName } else { "PID $($_.Name)" }); Count = $_.Count }
    } | Group-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = ($_.Group | Measure-Object Count -Sum).Sum } } |
        Sort-Object Count -Descending
    foreach ($g in $groups | Select-Object -First 15) { Log ("  {0,-30} {1,3} connection(s)" -f $g.Name, $g.Count) }
    Log 'For live upload/download per app, open Resource Monitor > Network (Tools tab).'
}

$PingWork = {
    param($Targets)
    foreach ($t in $Targets) {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $times = New-Object System.Collections.Generic.List[double]; $lost = 0
        for ($i = 0; $i -lt 20; $i++) {
            try { $r = $ping.Send($t.Host, 1000); if ($r.Status -eq 'Success') { $times.Add($r.RoundtripTime) } else { $lost++ } } catch { $lost++ }
            Start-Sleep -Milliseconds 100
        }
        if ($times.Count -gt 0) {
            $jit = 0; for ($i = 1; $i -lt $times.Count; $i++) { $jit += [math]::Abs($times[$i] - $times[$i - 1]) }
            if ($times.Count -gt 1) { $jit = $jit / ($times.Count - 1) }
            $avg = ($times | Measure-Object -Average).Average
            "{0,-22} avg {1,4:N0} ms   min {2,3}   max {3,4}   jitter {4,4:N1} ms   loss {5}%" -f $t.Name, $avg,
                ($times | Measure-Object -Minimum).Minimum, ($times | Measure-Object -Maximum).Maximum, $jit, ($lost * 5)
        } else { "{0,-22} no reply" -f $t.Name }
    }
    'Under 30 ms with low jitter and 0% loss is great for gaming.'
}

$SpeedTestWork = {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::DefaultConnectionLimit = 16
    $streams = 6
    # download: 6 parallel streams of 50 MB
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tasks = for ($i = 0; $i -lt $streams; $i++) { (New-Object Net.WebClient).DownloadDataTaskAsync("https://speed.cloudflare.com/__down?bytes=50000000&r=$i") }
    try { [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks, 60000) } catch { }
    $sw.Stop()
    $bytes = 0; foreach ($t in $tasks) { if ($t.Status -eq 'RanToCompletion') { $bytes += $t.Result.Length } }
    if ($bytes -gt 0) { "Download:  {0,7:N0} Mbit/s   ({1:N0} MB in {2:N1}s)" -f ($bytes * 8 / 1e6 / $sw.Elapsed.TotalSeconds), ($bytes / 1MB), $sw.Elapsed.TotalSeconds }
    else { 'Download: failed (no internet, or the test server was blocked)' }
    # upload: 4 parallel streams of 10 MB
    $data = New-Object byte[] (10MB); (New-Object Random).NextBytes($data)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tasks = for ($i = 0; $i -lt 4; $i++) { (New-Object Net.WebClient).UploadDataTaskAsync('https://speed.cloudflare.com/__up', 'POST', $data) }
    try { [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks, 60000) } catch { }
    $sw.Stop()
    $ok = @($tasks | Where-Object Status -eq 'RanToCompletion').Count
    if ($ok -gt 0) { "Upload:    {0,7:N0} Mbit/s   ({1:N0} MB in {2:N1}s)" -f ($ok * $data.Length * 8 / 1e6 / $sw.Elapsed.TotalSeconds), ($ok * $data.Length / 1MB), $sw.Elapsed.TotalSeconds }
    else { 'Upload: failed' }
    'Speed test server: Cloudflare (speed.cloudflare.com). A VPN, if on, slows this down.'
}

# ================================================================ STORAGE (background scans return objects)

$TreeSizeFn = @'
function Get-TreeSize([string]$Path) {
    $total = [double]0; $stack = New-Object System.Collections.Stack; $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $p = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo $p
            foreach ($f in $di.EnumerateFiles()) { $total += $f.Length }
            foreach ($s in $di.EnumerateDirectories()) {
                if (-not ($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { $stack.Push($s.FullName) }
            }
        } catch { }
    }
    $total
}
'@

$SizeScanWork = [scriptblock]::Create('param($Root, $Mode)' + "`n" + $TreeSizeFn + @'
if ($Mode -eq 'folders') {
    $dirs = (New-Object System.IO.DirectoryInfo $Root).EnumerateDirectories() |
        Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }
    foreach ($d in $dirs) { [pscustomobject]@{ Path = $d.FullName; Bytes = (Get-TreeSize $d.FullName); Info = 'folder' } }
} else {
    $stack = New-Object System.Collections.Stack; $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $p = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo $p
            foreach ($f in $di.EnumerateFiles()) { if ($f.Length -ge 1GB) { [pscustomobject]@{ Path = $f.FullName; Bytes = [double]$f.Length; Info = ('modified {0:yyyy-MM-dd}' -f $f.LastWriteTime) } } }
            foreach ($s in $di.EnumerateDirectories()) {
                if (-not ($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { $stack.Push($s.FullName) }
            }
        } catch { }
    }
}
'@)

# Finds rebuildable junk inside coding/game-dev projects.
$ProjectScanWork = [scriptblock]::Create('param($Root)' + "`n" + $TreeSizeFn + @'
$skip = @('AppData', '.git', '.vs', 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', '$Recycle.Bin', 'OneDrive')
$stack = New-Object System.Collections.Stack; $stack.Push(@($Root, 0))
while ($stack.Count -gt 0) {
    $item = $stack.Pop(); $p = $item[0]; $depth = $item[1]
    try { $di = New-Object System.IO.DirectoryInfo $p; $subs = @($di.EnumerateDirectories()); $files = @($di.EnumerateFiles() | ForEach-Object Name) } catch { continue }
    $names = @($subs | ForEach-Object Name)
    $isUnity = ($names -contains 'Assets') -and ($names -contains 'ProjectSettings')
    $hits = @{}
    if ($isUnity) { foreach ($n in 'Library', 'Temp', 'obj', 'Logs') { if ($names -contains $n) { $hits[$n] = 'Unity cache (Unity re-imports it when you open the project)' } } }
    if ($files -contains 'package.json' -and $names -contains 'node_modules') { $hits['node_modules'] = 'Node packages (npm install brings them back)' }
    if ($files -contains 'Cargo.toml' -and $names -contains 'target') { $hits['target'] = 'Rust build output (cargo build recreates it)' }
    if ($files -contains 'project.godot' -and $names -contains '.godot') { $hits['.godot'] = 'Godot import cache (rebuilt on open)' }
    if (-not $isUnity -and ($files | Where-Object { $_ -like '*.csproj' -or $_ -like '*.sln' })) {
        foreach ($n in 'bin', 'obj') { if ($names -contains $n) { $hits[$n] = '.NET build output (rebuild recreates it)' } }
    }
    if ($names -contains '.next' -and $files -contains 'package.json') { $hits['.next'] = 'Next.js build cache' }
    if ($names -contains '__pycache__') { $hits['__pycache__'] = 'Python bytecode cache' }
    foreach ($s in $subs) {
        if ($hits.ContainsKey($s.Name)) {
            $size = Get-TreeSize $s.FullName
            if ($size -ge 20MB) { [pscustomobject]@{ Path = $s.FullName; Bytes = $size; Info = $hits[$s.Name] } }
        } elseif ($depth -lt 6 -and $skip -notcontains $s.Name -and -not ($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $s.Name -ne 'node_modules') {
            $stack.Push(@($s.FullName, ($depth + 1)))
        }
    }
}
'@)

$DownloadsScanWork = {
    param($Root)
    $kinds = @{ '.exe' = 'installer'; '.msi' = 'installer'; '.msix' = 'installer'; '.zip' = 'archive'; '.rar' = 'archive'; '.7z' = 'archive'
        '.iso' = 'disk image'; '.img' = 'disk image'; '.mp4' = 'video'; '.mkv' = 'video'; '.mov' = 'video'; '.avi' = 'video'; '.tar' = 'archive'; '.gz' = 'archive' }
    Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $age = ((Get-Date) - $_.LastWriteTime).Days
        $k = $kinds[$_.Extension.ToLower()]
        if ($k -or $_.Length -ge 500MB -or $age -ge 180) {
            if (-not $k) { $k = 'file' }
            [pscustomobject]@{ Path = $_.FullName; Bytes = [double]$_.Length; Info = ('{0}, {1} days old' -f $k, $age) }
        }
    }
}

$DuplicateScanWork = {
    param($Root)
    $skip = @('AppData', '.git', 'node_modules', 'Library', '$Recycle.Bin', 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'steamapps')
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $stack = New-Object System.Collections.Stack; $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $p = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo $p
            foreach ($f in $di.EnumerateFiles()) { if ($f.Length -ge 1MB) { $files.Add($f) } }
            foreach ($s in $di.EnumerateDirectories()) {
                if ($skip -notcontains $s.Name -and -not ($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { $stack.Push($s.FullName) }
            }
        } catch { }
    }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    foreach ($g in ($files | Group-Object Length | Where-Object Count -gt 1)) {
        $byHash = @{}
        foreach ($f in $g.Group) {
            try {
                $s = [System.IO.File]::OpenRead($f.FullName)
                try { $h = [BitConverter]::ToString($md5.ComputeHash($s)) } finally { $s.Close() }
                if (-not $byHash.ContainsKey($h)) { $byHash[$h] = New-Object System.Collections.Generic.List[System.IO.FileInfo] }
                $byHash[$h].Add($f)
            } catch { }
        }
        foreach ($set in $byHash.Values) {
            if ($set.Count -lt 2) { continue }
            $keep = $set | Sort-Object LastWriteTime | Select-Object -First 1
            foreach ($f in $set) {
                if ($f.FullName -ne $keep.FullName) { [pscustomobject]@{ Path = $f.FullName; Bytes = [double]$f.Length; Info = "copy of $($keep.FullName)" } }
            }
        }
    }
}

$XboxSizeWork = [scriptblock]::Create('param($Folders)' + "`n" + $TreeSizeFn + @'
foreach ($f in $Folders) { [pscustomobject]@{ Path = $f; Bytes = (Get-TreeSize $f) } }
'@)

# Recycle (safe) or delete (permanent) a list of paths.
function Remove-Paths([string[]]$Paths, [bool]$Recycle) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ok = 0; $fail = 0
    foreach ($p in $Paths) {
        try {
            if ($Recycle) {
                if (Test-Path -LiteralPath $p -PathType Container) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                } else {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
            } else {
                if (Test-Path -LiteralPath $p -PathType Container) { cmd.exe /c "rd /s /q `"\\?\$p`"" 2>$null | Out-Null }
                else { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
            }
            if (Test-Path -LiteralPath $p) { $fail++; Log "Could not fully remove: $p" } else { $ok++ }
        } catch { $fail++; Log "Could not remove: $p ($($_.Exception.Message))" }
    }
    Log ("Removed {0} item(s){1}{2}" -f $ok, $(if ($fail) { ", $fail failed" } else { '' }), $(if ($Recycle) { ' - sent to the Recycle Bin' } else { ' - deleted permanently' }))
}

# ================================================================ TOOLS

function Copy-Specs {
    $cs = Get-CimInstance Win32_ComputerSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $r = Get-RamInfo
    $lines = @(
        "CPU:   $($cpu.Name.Trim())"
        "GPU:   $((Get-CimInstance Win32_VideoController | Where-Object Name -notmatch 'Radeon\(TM\) Graphics|Basic' | Select-Object -ExpandProperty Name) -join ', ')"
        ("RAM:   {0:N0} GB ({1}x{2:N0} GB @ {3} MT/s)" -f $r.TotalGB, $r.Sticks, ($r.TotalGB / $r.Sticks), $r.Running)
        "Board: $((Get-CimInstance Win32_BaseBoard).Product) (BIOS $((Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion))"
        "Disks: $((Get-PhysicalDisk | ForEach-Object { '{0} ({1:N0} GB)' -f $_.FriendlyName, ($_.Size / 1GB) }) -join ', ')"
        "OS:    Windows 11 $($cv.DisplayVersion) build $($cv.CurrentBuild).$($cv.UBR)"
    )
    [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n"))
    $lines | ForEach-Object { Log $_ }
    Log 'Specs copied to clipboard - paste them anywhere (Discord, forums...).'
}

function New-RestorePoint {
    if (-not (Need-Admin 'Creating a restore point')) { return }
    try {
        Checkpoint-Computer -Description "$AppName $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Log 'Restore point created (Windows allows one per 24 hours).'
    } catch {
        Log "Restore point failed: $($_.Exception.Message)"
        Log 'If System Protection is off: Tools > System Properties > System Protection tab > Configure > Turn on.'
    }
}

function Restart-Explorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Log 'Explorer restarted (fixes a stuck taskbar / Start menu).'
}

function Restart-ToBios {
    if (-not (Need-Admin 'Restarting into BIOS')) { return }
    if (-not (Confirm-Action "Restart into the BIOS now?`n`nSave your work first. The PC restarts in 5 seconds.")) { return }
    shutdown.exe /r /fw /t 5
    Log 'Restarting into BIOS...'
}

# ---- tray app at startup
$TrayRunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$TrayRunName = 'HallowToolkitTray'
function Get-TrayCommand { "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $HallowRoot 'HallowTray.ps1')`"" }
function Test-TrayAtStartup { [bool](Get-ItemProperty $TrayRunKey -Name $TrayRunName -ErrorAction SilentlyContinue) }
function Set-TrayAtStartup([bool]$On) {
    if ($On) { Set-ItemProperty $TrayRunKey -Name $TrayRunName -Value (Get-TrayCommand); Log 'Hallow tray app will start with Windows.' }
    else { Remove-ItemProperty $TrayRunKey -Name $TrayRunName -ErrorAction SilentlyContinue; Log 'Hallow tray app will no longer start with Windows.' }
}
function Start-TrayApp {
    $running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object CommandLine -match 'HallowTray\.ps1'
    if ($running) { Log 'The Hallow tray app is already running (look for the orange H by the clock).'; return }
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowTray.ps1')`"")
    Log 'Started the Hallow tray app - orange H by the clock. Auto Game Boost + panic key (Ctrl+Alt+End) are active.'
}

# ---- CPU temperature via LibreHardwareMonitor (optional, free)
function Get-LhmCpuTemp {
    # quick exit when LibreHardwareMonitor isn't running (the sensor lookups below are slow when it's missing)
    if (-not (Get-Process -Name 'LibreHardwareMonitor' -ErrorAction SilentlyContinue)) { return $null }
    try {
        $s = Get-CimInstance -Namespace 'root/LibreHardwareMonitor' -ClassName Sensor -Filter "SensorType='Temperature'" -ErrorAction Stop |
            Where-Object { $_.Name -match 'Tctl|Tdie|CPU Package|Core \(Tctl' } | Select-Object -First 1
        if ($s) { return [double]$s.Value }
    } catch { }
    try {
        $j = Invoke-RestMethod -Uri 'http://localhost:8085/data.json' -TimeoutSec 1 -ErrorAction Stop
        $stack = New-Object System.Collections.Stack; $stack.Push($j)
        while ($stack.Count -gt 0) {
            $n = $stack.Pop()
            if ($n.Text -match 'Tctl|Tdie|CPU Package' -and $n.Value -match '([\d\.,]+)') { return [double]($Matches[1] -replace ',', '.') }
            foreach ($c in @($n.Children)) { if ($c) { $stack.Push($c) } }
        }
    } catch { }
    $null
}
function Install-Lhm {
    Log 'Installing LibreHardwareMonitor (free, open source) with winget in a new window...'
    Log 'After it installs: open it once as admin, then Options > tick "Run On Windows Startup" and "Remote Web Server > Run". The Monitor tab will then show CPU temperature.'
    Start-InNewWindow 'Installing LibreHardwareMonitor' 'winget install --id LibreHardwareMonitor.LibreHardwareMonitor -e --accept-package-agreements --accept-source-agreements'
}

# ================================================================ DEEP UNINSTALL

# Reads every installed program (registry), Steam game and Store/Xbox app.
$ProgramListWork = {
    $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    $seen = @{}
    # Steam game folders by app id (Steam's uninstall entries have no install location)
    $steamDirs = @{}
    $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($sp) {
        $sp = $sp -replace '/', '\'; $libs = @($sp)
        $vdf = Join-Path $sp 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) { $libs += (Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }) }
        foreach ($l in $libs) {
            foreach ($acf in Get-ChildItem (Join-Path $l 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
                $t = Get-Content $acf.FullName -Raw -Encoding UTF8
                if ($t -match '"appid"\s+"(\d+)"') { $aid = $Matches[1]; if ($t -match '"installdir"\s+"([^"]+)"') { $steamDirs[$aid] = Join-Path $l "steamapps\common\$($Matches[1])" } }
            }
        }
    }
    foreach ($k in $keys) {
        foreach ($sk in Get-ChildItem $k -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty $sk.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName -or $p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.ReleaseType -match 'Update|Hotfix') { continue }
            if (-not $p.UninstallString) { continue }
            $id = "$($p.DisplayName)|$($p.DisplayVersion)"
            if ($seen.ContainsKey($id)) { continue }; $seen[$id] = 1
            $loc = [string]$p.InstallLocation
            if ($loc) { $loc = $loc.Trim().Trim('"').TrimEnd('\') }
            if ($p.UninstallString -match 'steam://uninstall/(\d+)' -and $steamDirs.ContainsKey($Matches[1])) { $loc = $steamDirs[$Matches[1]] }
            if (-not $loc -and $p.UninstallString -match '^"?([A-Za-z]:\\[^"]+?\.exe)' -and $Matches[1] -notmatch '(?i)\\(Windows|Package Cache)\\') {
                $ud = Split-Path $Matches[1]
                if ((Split-Path $ud -Leaf) -notmatch '^(?i)(uninstall|uninst|_uninst|bin)$') { $loc = $ud } else { $loc = Split-Path $ud }
            }
            $date = $null
            if ([string]$p.InstallDate -match '^\d{8}$') { try { $date = [datetime]::ParseExact($p.InstallDate, 'yyyyMMdd', $null) } catch { } }
            [pscustomobject]@{
                Name = ([string]$p.DisplayName).Trim(); Publisher = ([string]$p.Publisher).Trim(); Version = [string]$p.DisplayVersion
                Type = $(if ($p.UninstallString -match 'steam://uninstall') { 'Steam' } else { 'Program' })
                Bytes = $(if ($p.EstimatedSize) { [double]$p.EstimatedSize * 1KB } else { -1 })
                Installed = $date; InstallLocation = $loc; Uninstall = [string]$p.UninstallString; Icon = [string]$p.DisplayIcon
                Key = ($sk.Name -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' -replace '^HKEY_CURRENT_USER', 'HKCU:'); Package = $null
            }
        }
    }
    foreach ($a in Get-AppxPackage -ErrorAction SilentlyContinue) {
        if ($a.IsFramework -or $a.NonRemovable -or $a.IsResourcePackage -or $a.SignatureKind -ne 'Store') { continue }
        $dn = $null; $pub = $null
        try {
            $m = [xml](Get-Content (Join-Path $a.InstallLocation 'AppxManifest.xml') -Raw -ErrorAction Stop)
            $dn = $m.Package.Properties.DisplayName; $pub = $m.Package.Properties.PublisherDisplayName
        } catch { }
        if (-not $dn -or $dn -like 'ms-resource:*') { $dn = $a.Name }
        if ($pub -like 'ms-resource:*') { $pub = '' }
        [pscustomobject]@{
            Name = [string]$dn; Publisher = [string]$pub; Version = [string]$a.Version; Type = 'Store'; Bytes = -1; Installed = $null
            InstallLocation = $a.InstallLocation; Uninstall = $null; Icon = $null; Key = $null; Package = $a.PackageFullName
        }
    }
}

function Invoke-ProgramUninstall($P) {
    if ($P.Type -eq 'Steam') {
        if ($P.Uninstall -match 'steam://uninstall/(\d+)') { Start-Process "steam://uninstall/$($Matches[1])"; Log "Steam will ask you to confirm uninstalling $($P.Name)." }
    } elseif ($P.Type -eq 'Store') {
        try { Remove-AppxPackage -Package $P.Package -ErrorAction Stop; Log "Removed the Store app $($P.Name)." }
        catch { Log "Could not remove $($P.Name): $($_.Exception.Message)" }
    } else {
        if ($IsAdmin) {
            Log 'Creating a restore point first (Windows allows one per 24 hours)...'
            try { Checkpoint-Computer -Description "Before uninstalling $($P.Name)" -RestorePointType APPLICATION_UNINSTALL -WarningAction SilentlyContinue -ErrorAction Stop } catch { Log "  (restore point skipped: $($_.Exception.Message))" }
        }
        $u = $P.Uninstall
        if ($u -match '(?i)msiexec' -and $u -match '(\{[0-9A-Fa-f\-]{36}\})') { Start-Process msiexec.exe -ArgumentList "/x $($Matches[1])" }
        else { Start-Process cmd.exe -ArgumentList '/c', "`"$u`"" -WindowStyle Hidden }
        Log "Started the uninstaller for $($P.Name)."
    }
    Log 'When the uninstaller has finished, click "Scan leftovers".'
}

$LeftoverCommon = @'
function Norm([string]$s) { ([string]$s).ToLower() -replace '[^a-z0-9]', '' }
function Clean-Name([string]$n) {
    $n = $n -replace '\(.*?\)', '' -replace '\[.*?\]', '' -replace '\s+-\s+.*$', '' -replace '\bv?\d+(\.\d+)+\b', ''
    $n = $n -replace '(?i)\b(x64|x86|64-bit|32-bit|amd64|arm64)\b', '' -replace '[^\w\s\.\-&+]', ''
    ($n -replace '\s+', ' ').Trim()
}
function Clean-Pub([string]$n) {
    $n = $n -replace '(?i),?\s*\b(Inc|LLC|Ltd|Limited|Corp|Corporation|Co|GmbH|S\.A|SA|AB|Software|Technologies|Studios|Entertainment)\b\.?', ''
    ($n -replace '\s+', ' ').Trim(' ', ',', '.')
}
function Get-TreeInfo([string]$Path) {
    $total = [double]0; $newest = [datetime]::MinValue; $stack = New-Object System.Collections.Stack; $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $p = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo $p
            foreach ($f in $di.EnumerateFiles()) { $total += $f.Length; if ($f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime } }
            foreach ($s in $di.EnumerateDirectories()) { if (-not ($s.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { $stack.Push($s.FullName) } }
        } catch { }
    }
    [pscustomobject]@{ Bytes = $total; Newest = $newest }
}
'@

# Leftover scan for one program. Level: Safe / Moderate / Advanced. $Others = all other installed programs (protected).
$LeftoverScanWork = [scriptblock]::Create('param($T, $Level, $Others)' + "`n" + $LeftoverCommon + @'
$lvl = @{ Safe = 1; Moderate = 2; Advanced = 3 }[$Level]
$name = Clean-Name $T.Name; $nName = Norm $name
$pub = Clean-Pub $T.Publisher; $nPub = Norm $pub
$loc = [string]$T.InstallLocation
$generic = @('microsoft','windows','common','update','updater','setup','driver','drivers','intel','nvidia','google','system','program',
    'programs','files','temp','cache','packages','local','roaming','tools','games','steam','launcher','client','service','services',
    'helper','runtime','redistributable','visual','studio','plugin','plugins','desktop','manager','edition','software','online',
    'player','media','audio','video','network','security','browser','office','support','installer','uninstall','users','settings',
    'config','assets','server','windows')
$words = @(($name -split '[\s\-_\.]+') | Where-Object { $_.Length -ge 5 -and $generic -notcontains $_.ToLower() } | ForEach-Object { Norm $_ })
$otherLocs = @($Others | Where-Object { $_.InstallLocation -and $_.InstallLocation.Length -gt 3 } | ForEach-Object { ([string]$_.InstallLocation).TrimEnd('\') })
$otherNames = @($Others | ForEach-Object { Norm (Clean-Name $_.Name) } | Where-Object { $_.Length -ge 3 })
$otherPubs = @($Others | ForEach-Object { Norm (Clean-Pub $_.Publisher) } | Where-Object { $_ })
$pubShared = [bool]($nPub -and ($otherPubs -contains $nPub))
$docs = [Environment]::GetFolderPath('MyDocuments'); $desk = [Environment]::GetFolderPath('Desktop')
$forbidden = @("$env:SystemDrive\", $env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA,
    "$env:USERPROFILE\AppData\LocalLow", "$env:USERPROFILE\AppData", $env:USERPROFILE, "$env:LOCALAPPDATA\Programs", $env:TEMP, $docs, $desk,
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:USERPROFILE\Saved Games",
    "$env:USERPROFILE\Downloads", "$env:PUBLIC\Desktop", "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files",
    "${env:ProgramFiles(x86)}\InstallShield Installation Information", "$env:ProgramData\Package Cache", "$env:LOCALAPPDATA\Package Cache",
    "$env:ProgramFiles\WindowsApps", "$env:LOCALAPPDATA\Packages") | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
$results = New-Object System.Collections.ArrayList
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

function Test-SafePath([string]$p) {
    $p = $p.TrimEnd('\')
    if ($p.Length -le 3) { return $false }
    foreach ($f in $forbidden) { if ($p -ieq $f) { return $false } }
    if ($p.StartsWith($env:WINDIR + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ($p -match '(?i)\\WindowsApps(\\|$)|\\AppData\\Local\\Packages\\') { return $false }   # Store app files: Windows removes these itself
    $inOwn = $loc -and $loc.Length -gt 3 -and ($p -ieq $loc.TrimEnd('\') -or $p.StartsWith($loc.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))
    foreach ($o in $otherLocs) {
        if ($loc -and $o -ieq $loc.TrimEnd('\')) { continue }
        # never touch a folder that holds another installed program...
        if ($o.StartsWith($p + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
        # ...or sits inside one (unless it is this program's own folder, e.g. a Steam game inside the Steam folder)
        if (-not $inOwn -and ($p -ieq $o -or $p.StartsWith($o + '\', [StringComparison]::OrdinalIgnoreCase))) { return $false }
    }
    $leaf = Norm (Split-Path $p -Leaf)
    if ($leaf -ne $nName -and $otherNames -contains $leaf) { return $false }
    if ($leaf -eq $nPub -and $pubShared) { return $false }
    $true
}
function Add-Hit($Type, [string]$Path, [int]$L, [string]$Why, [bool]$Tick = $true) {
    if ($L -gt $lvl) { return }
    if ($seen.Contains("$Type|$Path")) { return }
    $bytes = 0
    if ($Type -eq 'Folder' -or $Type -eq 'File') {
        if (-not (Test-SafePath $Path)) { return }
        if ($Type -eq 'Folder') { $bytes = (Get-TreeInfo $Path).Bytes } else { $bytes = (Get-Item -LiteralPath $Path -Force).Length }
        if ($Path -match '(?i)\\AppData\\LocalLow\\|\\Saved Games\\|\\Documents\\') { $Tick = $false; $Why += ' - may contain saves/your files' }
    }
    [void]$seen.Add("$Type|$Path")
    [void]$results.Add([pscustomobject]@{ Type = $Type; Path = $Path; Bytes = [double]$bytes; Level = $L; Why = $Why; Tick = ($Tick -and $L -lt 3) })
}
function Is-Like([string]$n) { ($nName.Length -ge 5 -and $n.Contains($nName)) -or ($words -contains $n) }

# ---- SAFE: install folder + exact-name folders
if ($loc -and (Test-Path -LiteralPath $loc)) { Add-Hit 'Folder' $loc 1 'Install folder' }
foreach ($x in @($T.Icon, $T.Uninstall)) {
    if ([string]$x -match '^"?([A-Za-z]:\\[^"]+?\.exe)') {
        $d = Split-Path $Matches[1]
        if ((Test-Path -LiteralPath $d) -and $nName.Length -ge 4 -and (Norm (Split-Path $d -Leaf)).Contains($nName)) { Add-Hit 'Folder' $d 1 'Program folder' }
    }
}
$bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, "$env:LOCALAPPDATA\Programs", "$env:USERPROFILE\AppData\LocalLow") |
    Where-Object { $_ -and (Test-Path $_) }
if ($nName.Length -ge 4) {
    foreach ($b in $bases) {
        foreach ($d in Get-ChildItem -LiteralPath $b -Directory -Force -ErrorAction SilentlyContinue) {
            $n = Norm $d.Name
            if ($n -eq $nName) { Add-Hit 'Folder' $d.FullName 1 'Same name as the program' }
            elseif ($nPub.Length -ge 3 -and $n -eq $nPub) {
                foreach ($s in Get-ChildItem -LiteralPath $d.FullName -Directory -Force -ErrorAction SilentlyContinue) {
                    $sn = Norm $s.Name
                    if ($sn -eq $nName) { Add-Hit 'Folder' $s.FullName 1 "Program folder inside $($d.Name)" }
                    elseif (Is-Like $sn) { Add-Hit 'Folder' $s.FullName 3 'Similar name' $false }
                }
                if (-not $pubShared) { Add-Hit 'Folder' $d.FullName 2 "Publisher folder - only if you use no other $($d.Name) apps" $false }
            }
            elseif (Is-Like $n) { Add-Hit 'Folder' $d.FullName 3 'Similar name' $false }
        }
    }
}

# ---- MODERATE: registry, shortcuts, temp, leftover uninstall entry
if ($lvl -ge 2) {
    # an uninstall entry is only "left behind" when both its folder and its uninstaller are gone
    $unExe = if ([string]$T.Uninstall -match '^"?([A-Za-z]:\\[^"]+?\.exe)') { $Matches[1] } else { $null }
    $unGone = $unExe -and $unExe -notmatch '(?i)\\(msiexec|rundll32|cmd)\.exe$' -and -not (Test-Path -LiteralPath $unExe)
    $msiGone = ([string]$T.Uninstall -match '(?i)msiexec') -and $loc -and -not (Test-Path -LiteralPath $loc)
    if ($T.Type -eq 'Program' -and $T.Key -and (Test-Path $T.Key) -and ($unGone -or $msiGone) -and -not ($loc -and (Test-Path -LiteralPath $loc))) {
        Add-Hit 'RegKey' $T.Key 2 'Uninstall entry left behind'
    }
    $skipKeys = @('microsoft', 'classes', 'policies', 'wow6432node', 'clients', 'registeredapplications', 'intel', 'nvidiacorporation', 'google', 'mozilla', 'valve')
    foreach ($h in 'HKCU:\Software', 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node') {
        foreach ($k in Get-ChildItem $h -ErrorAction SilentlyContinue) {
            $n = Norm $k.PSChildName
            if ($skipKeys -contains $n) { continue }
            $kp = $k.Name -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' -replace '^HKEY_CURRENT_USER', 'HKCU:'
            if ($nName.Length -ge 4 -and $n -eq $nName) { Add-Hit 'RegKey' $kp 2 'Program settings' }
            elseif ($nPub.Length -ge 3 -and $n -eq $nPub) {
                foreach ($s in Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue) {
                    $sn = Norm $s.PSChildName
                    $sp = $s.Name -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' -replace '^HKEY_CURRENT_USER', 'HKCU:'
                    if ($sn -eq $nName) { Add-Hit 'RegKey' $sp 2 "Program settings under $($k.PSChildName)" }
                    elseif (Is-Like $sn) { Add-Hit 'RegKey' $sp 3 'Similar name' $false }
                }
                if (-not $pubShared -and $otherNames -notcontains $n) { Add-Hit 'RegKey' $kp 2 "Publisher key - only if you use no other $($k.PSChildName) apps" $false }
            }
            elseif ((Is-Like $n) -and $otherNames -notcontains $n) { Add-Hit 'RegKey' $kp 3 'Similar name' $false }
        }
    }
    $sh = New-Object -ComObject WScript.Shell
    foreach ($r in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", $desk, "$env:PUBLIC\Desktop")) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue) {
            $n = Norm $d.Name
            if ($nName.Length -ge 4 -and ($n -eq $nName -or ($nPub.Length -ge 3 -and $n -eq $nPub -and -not $pubShared))) { Add-Hit 'Folder' $d.FullName 2 'Start menu folder' }
        }
        foreach ($l in Get-ChildItem -LiteralPath $r -Filter *.lnk -Recurse -Depth 2 -ErrorAction SilentlyContinue) {
            $tgt = ''; try { $tgt = $sh.CreateShortcut($l.FullName).TargetPath } catch { }
            $byLoc = $loc -and $tgt -and $tgt.StartsWith($loc + '\', [StringComparison]::OrdinalIgnoreCase)
            $broken = $tgt -and -not (Test-Path -LiteralPath $tgt)
            if ($byLoc -or ($nName.Length -ge 4 -and (Norm $l.BaseName).Contains($nName) -and ($broken -or -not $tgt))) {
                Add-Hit 'File' $l.FullName 2 $(if ($broken) { 'Shortcut to the removed program' } else { 'Shortcut' })
            }
        }
    }
    if ($nName.Length -ge 4) {
        foreach ($d in Get-ChildItem -LiteralPath $env:TEMP -Directory -ErrorAction SilentlyContinue) { if ((Norm $d.Name) -eq $nName) { Add-Hit 'Folder' $d.FullName 2 'Temp files' } }
    }
}

# ---- ADVANCED: similar names everywhere, services, tasks, startup entries (nothing pre-ticked)
if ($lvl -ge 3) {
    $extra = @($docs, "$env:USERPROFILE\Saved Games")
    foreach ($dr in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        if (-not $dr.Used -or $dr.Root -ieq "$env:SystemDrive\") { continue }
        $extra += $dr.Root
        foreach ($x in 'Program Files', 'Program Files (x86)', 'Games') { $extra += (Join-Path $dr.Root $x) }
    }
    if ($nName.Length -ge 4) {
        foreach ($b in $extra | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) {
            foreach ($d in Get-ChildItem -LiteralPath $b -Directory -Force -ErrorAction SilentlyContinue) {
                $n = Norm $d.Name
                if ($n -eq $nName -or (Is-Like $n)) { Add-Hit 'Folder' $d.FullName 3 'Similar name' $false }
            }
        }
    }
    foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
        $pth = [string]$s.PathName
        if ($pth -match '(?i)\\Windows\\') { continue }
        $hit = ($loc -and $loc.Length -gt 3 -and $pth.IndexOf($loc, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or
               ($nName.Length -ge 5 -and ((Norm $s.Name).Contains($nName) -or (Norm $s.DisplayName).Contains($nName)))
        if ($hit) { Add-Hit 'Service' $s.Name 3 "Background service: $($s.DisplayName)" $false }
    }
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) {
        $exe = (@($t.Actions) | ForEach-Object { [string]$_.Execute }) -join ' '
        $hit = ($loc -and $loc.Length -gt 3 -and $exe.IndexOf($loc, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or
               ($nName.Length -ge 5 -and (Norm ($t.TaskPath + $t.TaskName)).Contains($nName))
        if ($hit) { Add-Hit 'Task' ($t.TaskPath + $t.TaskName) 3 'Scheduled task' $false }
    }
    foreach ($rk in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
        $props = Get-ItemProperty $rk -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($pp in $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            $v = [string]$pp.Value
            $hit = ($loc -and $loc.Length -gt 3 -and $v.IndexOf($loc, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($nName.Length -ge 5 -and (Norm $pp.Name).Contains($nName))
            if ($hit) { Add-Hit 'RegValue' "$rk|$($pp.Name)" 3 'Starts with Windows' $false }
        }
    }
}
$results
'@)

# Leftover finder: folders in AppData / ProgramData / Program Files that no installed app owns and that haven't been used in 30+ days.
$OrphanScanWork = [scriptblock]::Create('param($Installed, $Running)' + "`n" + $LeftoverCommon + @'
$tokens = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($p in $Installed) {
    foreach ($t in @((Norm (Clean-Name $p.Name)), (Norm (Clean-Pub $p.Publisher)), $(if ($p.InstallLocation) { Norm (Split-Path ([string]$p.InstallLocation).TrimEnd('\') -Leaf) }))) {
        if ($t -and $t.Length -ge 3) { [void]$tokens.Add($t) }
    }
    foreach ($w in ((Clean-Name $p.Name) -split '\s+')) { $nw = Norm $w; if ($nw.Length -ge 5) { [void]$tokens.Add($nw) } }
}
$known = @('microsoft','windows','packages','temp','comms','connecteddevicesplatform','crashdumps','d3dscache','peerdistrepub','programs','publishers',
    'nvidia','intel','amd','realtek','commonfiles','modifiablewindowsapps','windowsapps','windowspowershell','internetexplorer','msbuild',
    'referenceassemblies','dotnet','uninstallinformation','packagecache','ssh','usoshared','usoprivate','virtualstore','placeholdertilelogofolder',
    'claude','anthropic','npm','npmcache','pip','nuget','yarn','pnpm','nodegyp','squirreltemp','github','git','code','cursor','unity','jetbrains',
    'docker','python','uv','cargo','rustup','gradle','android','google','mozilla','chrome','brave','discord','steam','epicgames','riotgames','xbox',
    'electron','webview','msedge','edge','onedrive','openai','chatgpt','codex','msplaywright','puppeteer','fontconfig','history','inetcache',
    'iconcache','fonts','regid','oem','sentry','crashpad','powershell','terminal','vscode','ollama','huggingface','nodejs','node','java','oracle',
    'apple','logitech','lghub','steelseries','asus','armourycrate','nordvpn','nordsecurity','nordlocker','tailscale','medal','spotify',
    'wallpaperengine','packagemanagement','desktop','downloads','documents','games','gameanalytics','unitytechnologies','unity3d','application',
    'systemprofile','ssl','tor','gnupg','mesa','vulkan','cache','caches','logs','updater','setup','installer','uninstall','defender','security',
    'mpcmdrun','ms','dbg','symbols','sym','wer','diagnosis','servicing','tempdir','localstate','roamingstate','sxs','assembly','bluetooth',
    'mediatek','killer','qualcomm','dell','hp','lenovo','msi','gigabyte','asrock','corsair','razer','hyperx','elgato','installshield')
$isKnown = { param($n) foreach ($k in $known) { if ($n -eq $k -or ($k.Length -ge 5 -and $n.Contains($k)) -or ($n.Length -ge 4 -and $n.StartsWith($k) -and $k.Length -ge 3)) { return $true } }; $false }
$runningDirs = @($Running | Where-Object { $_ } | ForEach-Object { Split-Path $_ })
$bases = @($env:APPDATA, $env:LOCALAPPDATA, "$env:USERPROFILE\AppData\LocalLow", $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") |
    Where-Object { $_ -and (Test-Path $_) }
foreach ($b in $bases) {
    foreach ($d in Get-ChildItem -LiteralPath $b -Directory -Force -ErrorAction SilentlyContinue) {
        if ($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
        $n = Norm $d.Name
        if ($n.Length -lt 3 -or (& $isKnown $n)) { continue }
        $owned = $false
        foreach ($t in $tokens) { if ($n -eq $t -or ($t.Length -ge 4 -and $n.Contains($t)) -or ($n.Length -ge 4 -and $t.Contains($n))) { $owned = $true; break } }
        if ($owned) { continue }
        if ($runningDirs | Where-Object { $_.StartsWith($d.FullName, [StringComparison]::OrdinalIgnoreCase) }) { continue }
        $info = Get-TreeInfo $d.FullName
        if ($info.Bytes -lt 1MB) { continue }
        $days = if ($info.Newest -gt [datetime]::MinValue) { [int]((Get-Date) - $info.Newest).TotalDays } else { 9999 }
        if ($days -lt 30) { continue }
        $why = "No installed app owns it - last changed $days days ago"
        if ($b -match 'LocalLow') { $why += ' (may contain game saves)' }
        [pscustomobject]@{ Type = 'Folder'; Path = $d.FullName; Bytes = $info.Bytes; Level = 3; Why = $why; Tick = $false }
    }
}
'@)

function Test-LeftoverExists($I) {
    switch ($I.Type) {
        'RegValue' { $k, $v = $I.Path -split '\|', 2; return [bool](Get-ItemProperty -LiteralPath $k -Name $v -ErrorAction SilentlyContinue) }
        'Service' { return [bool](Get-Service -Name $I.Path -ErrorAction SilentlyContinue) }
        'Task' { $i2 = $I.Path.LastIndexOf('\'); return [bool](Get-ScheduledTask -TaskPath $I.Path.Substring(0, $i2 + 1) -TaskName $I.Path.Substring($i2 + 1) -ErrorAction SilentlyContinue) }
        default { return (Test-Path -LiteralPath $I.Path) }
    }
}

# Removes leftovers: files/folders go to the Recycle Bin; registry keys, startup entries, services and tasks are backed up first.
function Remove-LeftoverItems($Items) {
    $bk = Join-Path $HallowRoot ('backups\' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    New-Item -ItemType Directory -Force -Path $bk | Out-Null
    $files = @(); $n = 0
    foreach ($i in $Items) {
        try {
            if ($i.Type -eq 'Folder' -or $i.Type -eq 'File') { $files += $i.Path }
            elseif (($i.Path -like 'HKLM:*' -or $i.Type -in 'Service', 'Task') -and -not $IsAdmin) { Log "Skipped (needs admin): $($i.Path)" }
            elseif ($i.Type -eq 'RegKey') {
                $n++; reg.exe export ($i.Path -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU') (Join-Path $bk "registry-$n.reg") /y | Out-Null
                Remove-Item -LiteralPath $i.Path -Recurse -Force -ErrorAction Stop
                Log "Removed registry key $($i.Path)"
            } elseif ($i.Type -eq 'RegValue') {
                $k, $v = $i.Path -split '\|', 2
                $n++; reg.exe export ($k -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU') (Join-Path $bk "startup-$n.reg") /y | Out-Null
                Remove-ItemProperty -LiteralPath $k -Name $v -ErrorAction Stop
                Log "Removed startup entry $v"
            } elseif ($i.Type -eq 'Service') {
                sc.exe qc $i.Path | Set-Content (Join-Path $bk "service-$($i.Path).txt")
                Stop-Service -Name $i.Path -Force -ErrorAction SilentlyContinue
                sc.exe delete $i.Path | Out-Null
                Log "Removed service $($i.Path)"
            } elseif ($i.Type -eq 'Task') {
                $ix = $i.Path.LastIndexOf('\'); $tp = $i.Path.Substring(0, $ix + 1); $tn = $i.Path.Substring($ix + 1)
                Export-ScheduledTask -TaskPath $tp -TaskName $tn | Set-Content (Join-Path $bk ("task-" + ($tn -replace '[^\w\-]', '_') + '.xml'))
                Unregister-ScheduledTask -TaskPath $tp -TaskName $tn -Confirm:$false -ErrorAction Stop
                Log "Removed scheduled task $($i.Path)"
            }
        } catch { Log "Could not remove $($i.Path): $($_.Exception.Message)" }
    }
    if ($files) { Remove-Paths $files $true }
    if (Get-ChildItem $bk -ErrorAction SilentlyContinue) { Log "Backups saved in $bk (double-click a .reg file to restore it)" }
    else { Remove-Item $bk -Force -ErrorAction SilentlyContinue }
}

# v3 extras
. (Join-Path $HallowRoot 'HallowExtras.ps1')
. (Join-Path $HallowRoot 'HallowUpdates.ps1')

. (Join-Path $HallowRoot 'HallowSystem.ps1')
. (Join-Path $HallowRoot 'HallowPerf.ps1')
