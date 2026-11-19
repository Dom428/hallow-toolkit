<#
  Hallow Toolkit - pre-game check (v5.9) and scheduled clean-up (v5.9). No window code. Dot-sourced by HallowCore.ps1.
  The pre-game check only reads: it changes nothing until you click one of its fixes.
#>

# ================================================================ PRE-GAME CHECK
# Lines: Key, Level (good / warn / bad), Text, Fix (winupdate, updateapps, storage, closehogs, nvidia, taskmgr, start) and Arg.
# Self-contained (runs in a background runspace). $Opt: GameDrives, NvSmi, Hogs, Hallow (installed Hallow app names),
# Local / Roaming (data folders), WingetWork (the toolkit's winget list scriptblock as text; empty = skip app updates).
$PreGameWork = {
    param($Opt)
    $out = New-Object System.Collections.ArrayList
    function Add-Line($Key, $Level, $Text, $Fix, $Arg) { [void]$out.Add([pscustomobject]@{ Key = $Key; Level = $Level; Text = $Text; Fix = $Fix; Arg = $Arg }) }
    # Windows updates waiting for a restart
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    if ($pending) { Add-Line 'restart' 'warn' 'Windows updates are waiting for a restart - restart before a long session, or Windows may do it for you' 'winupdate' $null }
    else { Add-Line 'restart' 'good' 'No restart waiting' $null $null }
    # RAM
    try {
        $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
        $used = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB; $tot = $os.TotalVisibleMemorySize / 1MB; $pct = [int](100 * $used / $tot)
        $txt = 'RAM {0:N1} of {1:N0} GB in use ({2}%)' -f $used, $tot, $pct
        if ($pct -ge 90) { Add-Line 'ram' 'bad' "$txt - close something before you play" 'taskmgr' $null }
        elseif ($pct -ge 75) { Add-Line 'ram' 'warn' "$txt - games may stutter" 'taskmgr' $null }
        else { Add-Line 'ram' 'good' $txt $null $null }
    } catch { }
    # apps known to get in the way of games (the toolkit's Boost list + its known background hogs)
    $hogs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { @($Opt.Hogs) -contains $_.ProcessName } | Select-Object -ExpandProperty ProcessName -Unique)
    if ($hogs.Count) { Add-Line 'hogs' 'warn' "Running in the background: $($hogs -join ', ')" 'closehogs' ($hogs -join ',') }
    else { Add-Line 'hogs' 'good' 'No known background hogs running' $null $null }
    # free space on the game drives
    foreach ($dl in @($Opt.GameDrives)) {
        try {
            $d = New-Object IO.DriveInfo($dl); if (-not $d.IsReady) { continue }
            $gb = $d.TotalFreeSpace / 1GB; $pct = [int](100 * $d.TotalFreeSpace / $d.TotalSize)
            $txt = '{0} {1:N0} GB free ({2}%)' -f $d.Name.TrimEnd('\'), $gb, $pct
            if ($pct -lt 3 -or $gb -lt 5) { Add-Line "drive$dl" 'bad' "$txt - games can fail to update or save" 'storage' $null }
            elseif ($pct -lt 10 -or $gb -lt 20) { Add-Line "drive$dl" 'warn' "$txt - getting full" 'storage' $null }
            else { Add-Line "drive$dl" 'good' $txt $null $null }
        } catch { }
    }
    # CPU / GPU load and temperature (before a game, they should be quiet)
    try {
        $cpu = [int](Get-CimInstance Win32_Processor -Property LoadPercentage | Measure-Object LoadPercentage -Average).Average
        if ($cpu -ge 50) { Add-Line 'cpu' 'warn' "CPU is already $cpu% busy - something is running" 'taskmgr' $null } else { Add-Line 'cpu' 'good' "CPU $cpu% busy" $null $null }
    } catch { }
    if ($Opt.NvSmi -and (Test-Path $Opt.NvSmi)) {
        $q = & $Opt.NvSmi '--query-gpu=utilization.gpu,temperature.gpu,driver_version' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if ($q) {
            $v = @($q -split ',\s*')
            $gu = [int]$v[0]; $gt = [int]$v[1]
            if ($gu -ge 40) { Add-Line 'gpu' 'warn' "GPU is already $gu% busy ($gt C) - something is using it" 'taskmgr' $null }
            elseif ($gt -ge 80) { Add-Line 'gpu' 'warn' "GPU is $gt C before the game starts - check fans and dust" $null $null }
            else { Add-Line 'gpu' 'good' "GPU $gu% busy, $gt C" $null $null }
            # driver age (from Windows' record of the NVIDIA driver date - nothing is looked up online)
            $drv = "$($v[2])".Trim(); $date = $null
            try { $date = (Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -like 'NVIDIA*' } | Select-Object -First 1).DriverDate } catch { }
            if ($date -and ((Get-Date) - $date).TotalDays -gt 92) { Add-Line 'nvidia' 'warn' ('NVIDIA driver {0} is from {1:d MMM yyyy} - older than 3 months, new games may want a newer one' -f $drv, $date) 'nvidia' $null }
            elseif ($date) { Add-Line 'nvidia' 'good' ('NVIDIA driver {0} from {1:d MMM yyyy}' -f $drv, $date) $null $null }
            else { Add-Line 'nvidia' 'good' "NVIDIA driver $drv" $null $null }
        }
    }
    # Hallow apps worth having on while you play
    foreach ($a in @($Opt.Hallow)) {
        $run = [bool](Get-Process "Hallow$a" -ErrorAction SilentlyContinue)
        if ($a -eq 'Clips') {
            $st = $null; try { $st = Get-Content (Join-Path $Opt.Local 'HallowClips\status.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { }
            if (-not $run) { Add-Line 'clips' 'warn' "Hallow Clips isn't running - no instant replay this session" 'start' 'Clips' }
            elseif ($st -and $st.PSObject.Properties.Name -contains 'recording' -and -not $st.recording) { Add-Line 'clips' 'good' 'Hallow Clips is running (its replay buffer starts when the game does)' $null $null }
            else { Add-Line 'clips' 'good' 'Hallow Clips is running - Ctrl+Alt+S saves a clip' $null $null }
        } elseif ($a -eq 'Overlay') {
            if ($run) { Add-Line 'overlay' 'good' 'Hallow Overlay is running' $null $null } else { Add-Line 'overlay' 'warn' "Hallow Overlay isn't running - no FPS / temps over the game" 'start' 'Overlay' }
        }
    }
    # app updates (winget, read-only list) - last because it's the slowest
    if ($Opt.WingetWork) {
        try {
            $rows = @(& ([scriptblock]::Create($Opt.WingetWork)) | Where-Object { $_.Id })
            if ($rows.Count) { Add-Line 'apps' 'warn' ("{0} app update(s) available: {1}{2}" -f $rows.Count, (@($rows | Select-Object -First 4 | ForEach-Object Name) -join ', '), $(if ($rows.Count -gt 4) { '...' })) 'updateapps' $null }
            else { Add-Line 'apps' 'good' 'Apps are up to date (winget)' $null $null }
        } catch { }
    }
    $out
}
# Drives with games: C: plus every Steam library
function Get-GameDrives {
    $d = @('C:\') + @(Get-SteamLibraries | ForEach-Object { try { [IO.Path]::GetPathRoot($_) } catch { } })
    @($d | Where-Object { $_ } | ForEach-Object { $_.ToUpper() } | Select-Object -Unique)
}
function Get-PreGameOptions([switch]$NoWinget) {
    @{
        GameDrives = @(Get-GameDrives); NvSmi = $NvSmi; Local = $env:LOCALAPPDATA
        Hogs = @(@($BackgroundHogs) + @((Get-Settings).BoostApps) | Where-Object { $_ } | Select-Object -Unique)
        Hallow = @('Overlay', 'Clips' | Where-Object { Test-FamilyInstalled $_ })
        WingetWork = $(if ($NoWinget -or -not (Get-Command winget -ErrorAction SilentlyContinue)) { '' } else { $WingetListWork.ToString() })
    }
}

# ================================================================ SCHEDULED CLEAN-UP
# Off unless you turn it on. A daily task at your time runs "-Mode Clean"; it cleans only when the weekly / monthly
# slot has come round since the last run (so a missed slot runs the next time the PC is on), with the Quick Clean-up
# items you ticked, and writes a report to <toolkit>\reports (the tray shows it).
$CleanItems = [ordered]@{
    Temp       = 'Your temp files'
    CrashDumps = 'Crash dumps'
    WinTemp    = 'Windows temp files (admin)'
    DeliveryOpt = 'Windows Update download cache (admin)'
    RecycleBin = 'Recycle Bin (permanent)'
    Dns        = 'DNS cache'
    Trim       = 'SSD TRIM (admin)'
}
$CleanTaskName = 'Hallow Toolkit Scheduled Clean-up'
$ReportDir = Join-Path $HallowRoot 'reports'
function Get-CleanSchedule {
    $s = Get-Settings; $c = $s.CleanSchedule
    $o = [ordered]@{ On = $false; Freq = 'Weekly'; Day = 'Sunday'; DayOfMonth = 1; Time = '04:00'; Items = @('Temp', 'CrashDumps', 'WinTemp', 'DeliveryOpt', 'Dns') }
    if ($c) { foreach ($k in @($o.Keys)) { if ($c.PSObject.Properties.Name -contains $k -and $null -ne $c.$k) { $o[$k] = $c.$k } } }
    $o.Items = @($o.Items | Where-Object { $CleanItems.Contains("$_") })
    [pscustomobject]$o
}
function Save-CleanSchedule($Sched) { $s = Get-Settings; $s | Add-Member CleanSchedule ([pscustomobject]@{ On = [bool]$Sched.On; Freq = "$($Sched.Freq)"; Day = "$($Sched.Day)"; DayOfMonth = [int]$Sched.DayOfMonth; Time = "$($Sched.Time)"; Items = @($Sched.Items) }) -Force; Save-Settings $s }
# the most recent weekly / monthly slot at or before $Now
function Get-LastCleanSlot($Sched, [datetime]$Now = (Get-Date)) {
    $t = [timespan]::Parse("$($Sched.Time)")
    if ($Sched.Freq -eq 'Monthly') {
        $dom = [math]::Max(1, [math]::Min(28, [int]$Sched.DayOfMonth))
        $slot = (Get-Date -Year $Now.Year -Month $Now.Month -Day $dom).Date + $t
        if ($slot -gt $Now) { $slot = $slot.AddMonths(-1) }
    } else {
        $want = [int][DayOfWeek]"$($Sched.Day)"
        $slot = $Now.Date.AddDays(-((([int]$Now.DayOfWeek) - $want + 7) % 7)) + $t
        if ($slot -gt $Now) { $slot = $slot.AddDays(-7) }
    }
    $slot
}
function Test-CleanDue($Sched, [datetime]$Now = (Get-Date)) {
    $last = [datetime]::MinValue; [void][datetime]::TryParse("$((Get-Settings).LastScheduledClean)", [ref]$last)
    $last -lt (Get-LastCleanSlot $Sched $Now)
}
# Runs (or with -DryRun only measures) the chosen items. Returns the report object; also saved to reports\ unless -NoSave.
function Invoke-CleanItems([string[]]$Items, [switch]$DryRun, [switch]$NoSave, [string]$Trigger = 'Scheduled') {
    $rows = New-Object System.Collections.ArrayList
    function Add-Row($Item, [double]$Bytes, [string]$Note) { [void]$rows.Add([pscustomobject]@{ Item = $CleanItems[$Item]; Bytes = [double]$Bytes; Note = $Note }) }
    function Clean-Folder($Item, [string]$Path, [string[]]$Keep = @()) {
        if (-not (Test-Path -LiteralPath $Path)) { Add-Row $Item 0 'nothing there'; return }
        $kids = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Where-Object { $Keep -notcontains $_.Name })
        $before = 0; foreach ($k in $kids) { $before += $(if ($k.PSIsContainer) { Get-FolderBytes $k.FullName } else { $k.Length }) }
        if ($DryRun) { Add-Row $Item $before 'would be freed (some may be in use)'; return }
        foreach ($k in $kids) { try { Remove-Item -LiteralPath $k.FullName -Recurse -Force -ErrorAction Stop } catch { } }
        $after = 0; foreach ($k in $kids) { if (Test-Path -LiteralPath $k.FullName) { $after += $(if ((Get-Item -LiteralPath $k.FullName -Force).PSIsContainer) { Get-FolderBytes $k.FullName } else { (Get-Item -LiteralPath $k.FullName -Force).Length }) } }
        Add-Row $Item ([math]::Max(0, $before - $after)) $(if ($after -gt 0) { "$(Format-Size $after) in use, left" } else { '' })
    }
    foreach ($i in $Items) {
        switch ($i) {
            'Temp' { Clean-Folder $i $env:TEMP @('claude') }
            'CrashDumps' { Clean-Folder $i (Join-Path $env:LOCALAPPDATA 'CrashDumps') }
            'WinTemp' { if ($IsAdmin) { Clean-Folder $i (Join-Path $env:WINDIR 'Temp') } else { Add-Row $i 0 'skipped - needs admin' } }
            'DeliveryOpt' {
                if (-not $IsAdmin) { Add-Row $i 0 'skipped - needs admin' }
                elseif ($DryRun) { Add-Row $i 0 'would be cleared' }
                else { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Add-Row $i 0 'cleared' } catch { Add-Row $i 0 'skipped' } }
            }
            'RecycleBin' {
                $b = 0; try { $sh = New-Object -ComObject Shell.Application; foreach ($it in @($sh.Namespace(10).Items())) { $b += [double]$it.Size } } catch { }
                if ($DryRun) { Add-Row $i $b 'would be emptied' } else { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Add-Row $i $b 'emptied' }
            }
            'Dns' { if ($DryRun) { Add-Row $i 0 'would be flushed' } else { try { Clear-DnsClientCache -ErrorAction Stop; Add-Row $i 0 'flushed' } catch { Add-Row $i 0 'skipped' } } }
            'Trim' {
                if (-not $IsAdmin) { Add-Row $i 0 'skipped - needs admin' }
                elseif ($DryRun) { Add-Row $i 0 'would run' }
                else {
                    $n = 0; Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' } | ForEach-Object { try { Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction Stop; $n++ } catch { } }
                    Add-Row $i 0 "done on $n drive(s)"
                }
            }
        }
    }
    $total = ($rows | Measure-Object Bytes -Sum).Sum
    $rep = [pscustomobject]@{ Time = (Get-Date).ToString('s'); Trigger = $Trigger; DryRun = [bool]$DryRun; TotalBytes = [double]$total; Items = @($rows) }
    if (-not $NoSave) {
        New-Item -ItemType Directory -Force $ReportDir | Out-Null
        $rep | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ReportDir ("clean-{0:yyyy-MM-dd_HHmmss}{1}.json" -f (Get-Date), $(if ($DryRun) { '-preview' } else { '' }))) -Encoding UTF8
        Get-ChildItem $ReportDir -Filter 'clean-*.json' | Sort-Object Name -Descending | Select-Object -Skip 30 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $rep
}
function Get-CleanReports { Get-ChildItem $ReportDir -Filter 'clean-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object { try { $r = Get-Content $_.FullName -Raw | ConvertFrom-Json; $r | Add-Member File $_.FullName -Force; $r } catch { } } }
function Format-CleanReport($Rep) {
    $parts = @($Rep.Items | Where-Object { $_.Bytes -gt 0 } | ForEach-Object { "$($_.Item) $(Format-Size $_.Bytes)" })
    "{0} {1}{2}" -f $(if ($Rep.DryRun) { 'Would free' } else { 'Freed' }), (Format-Size $Rep.TotalBytes), $(if ($parts) { " ($($parts -join ', '))" } else { '' })
}
# -Mode Clean (the scheduled task): clean when the slot is due, then remember it
function Invoke-ScheduledClean([switch]$DryRun, [switch]$Force) {
    $sc = Get-CleanSchedule
    if (-not $sc.On -and -not $Force) { Log 'Scheduled clean-up is off.'; return }
    if (-not $Force -and -not (Test-CleanDue $sc)) { return }
    $rep = Invoke-CleanItems $sc.Items -DryRun:$DryRun
    if (-not $DryRun) { $s = Get-Settings; $s | Add-Member LastScheduledClean ((Get-Date).ToString('s')) -Force; Save-Settings $s }
    Log "Scheduled clean-up: $(Format-CleanReport $rep)"
    $rep
}
# The task: every day at your time (it decides whether today's the day); runs when the PC is next on if it was off.
function Register-CleanTask($Sched, [string]$TaskName = $CleanTaskName) {
    $main = Join-Path $HallowRoot 'HallowToolkit.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$main`" -Mode Clean"
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today + [timespan]::Parse("$($Sched.Time)"))
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    $p = @{ TaskName = $TaskName; Action = $action; Trigger = $trigger; Settings = $set; Force = $true }
    if ($IsAdmin) { $p.Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest }   # admin items (Windows temp, TRIM) need it
    Register-ScheduledTask @p | Out-Null
}
function Unregister-CleanTask([string]$TaskName = $CleanTaskName) { if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false } }
