<#
  Hallow Toolkit - game-ready check, driver check and disk health (v5.15). No window code. Dot-sourced by HallowCore.ps1.
  Every check here only reads. The only things that change a setting are the Set-GameReadySetting fixes, and those run
  only when you click their button (and say yes).
  Check lines use the pre-game check's shape: Key, Level (good / warn / bad), Text, Fix, Arg.
#>

# ================================================================ GAME-READY CHECK
# Game Mode, GPU scheduling (HAGS), power plan, Xbox Game Bar captures (they fight Hallow Clips for the video encoder),
# apps already using the CPU / GPU, Discord's hardware acceleration and full-screen optimizations.
# Self-contained (runs inside the pre-game check's runspace). $Opt (tests): Reg (hashtable 'path|name' -> value; when
# given, the registry is not read at all), Scheme (@{ Guid; Name }), Cpu / Gpu (fake samples: Name, Pct), Roaming,
# Clips (Hallow Clips installed), DiscordRunning, SampleMs. GameProcs: process names of a game running now - their own
# CPU / GPU use is not "background".
$GameReadyWork = {
    param($Opt)
    if (-not $Opt) { $Opt = @{} }
    $out = New-Object System.Collections.ArrayList
    function Add-Line($Key, $Level, $Text, $Fix, $Arg) { [void]$out.Add([pscustomobject]@{ Key = $Key; Level = $Level; Text = $Text; Fix = $Fix; Arg = $Arg }) }
    function Read-RegVal([string]$Path, [string]$Name) {
        if ($Opt.Reg) { return $Opt.Reg["$Path|$Name"] }
        try { (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
    }
    # Game Mode (on unless it was turned off)
    if ((Read-RegVal 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -eq 0) { Add-Line 'gamemode' 'warn' 'Game Mode is off - on, Windows gives the game priority and holds back updates and restarts while you play' 'gamemode' $null }
    else { Add-Line 'gamemode' 'good' 'Game Mode is on' $null $null }
    # Hardware-accelerated GPU scheduling (admin + restart to change, so it's a link to Settings)
    switch (Read-RegVal 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') {
        2 { Add-Line 'hags' 'good' 'GPU scheduling (HAGS) is on' $null $null }
        1 { Add-Line 'hags' 'warn' 'GPU scheduling (HAGS) is off - on is better for most recent graphics cards and needed for DLSS Frame Generation (Settings, then a restart)' 'hags' $null }
        default { Add-Line 'hags' 'good' 'GPU scheduling (HAGS): Windows default for your graphics card' $null $null }
    }
    # power plan
    $sch = $Opt.Scheme
    if (-not $sch) {
        $t = "$(powercfg /getactivescheme 2>$null)"
        $g = [regex]::Match($t, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
        $sch = @{ Guid = $g; Name = $(if ($t -match '\((.*)\)') { $Matches[1] } else { '' }) }
    }
    if ("$($sch.Guid)" -eq 'a1841308-3542-41e9-8f9b-bc7d2f0ad7bd' -or "$($sch.Name)" -match 'saver') { Add-Line 'power' 'warn' "Power plan is $($sch.Name) - it holds the CPU back in games" 'power' $null }
    elseif ($sch.Name) { Add-Line 'power' 'good' "Power plan: $($sch.Name)" $null $null }
    # Xbox Game Bar captures: background recording always costs FPS; with Hallow Clips installed they also fight it for the video encoder
    $dvr = Read-RegVal 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    $cap = Read-RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
    $hist = Read-RegVal 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled'
    $capOn = -not ($dvr -eq 0 -or $cap -eq 0)
    if ($capOn -and $hist -eq 1) { Add-Line 'gamebar' 'warn' ("Xbox Game Bar records in the background all the time - it costs FPS{0}" -f $(if ($Opt.Clips) { ' and fights Hallow Clips for the video encoder' } else { '' })) 'gamebar' $null }
    elseif ($capOn -and $Opt.Clips) { Add-Line 'gamebar' 'warn' 'Xbox Game Bar captures are on next to Hallow Clips - two recorders on one video encoder can stutter or fail to save; Clips does the job' 'gamebar' $null }
    elseif ($capOn) { Add-Line 'gamebar' 'good' 'Xbox Game Bar captures are ready but only record when you ask (Win+Alt+R)' $null $null }
    else { Add-Line 'gamebar' 'good' 'Xbox Game Bar captures are off' $null $null }
    # apps already using the CPU (a short sample of every process's CPU time)
    $skip = @('Idle', 'System', 'Registry', 'Memory Compression', 'dwm', 'csrss', 'audiodg', 'Interrupts', 'smss', 'wininit', 'services', 'lsass') + @($Opt.GameProcs | Where-Object { $_ })
    $cpu = $Opt.Cpu
    if ($null -eq $cpu) {
        $cpu = @()
        try {
            $ms = $(if ($Opt.SampleMs) { [int]$Opt.SampleMs } else { 1500 })
            $a = @{}; foreach ($p in Get-Process -ErrorAction SilentlyContinue) { try { $a[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { } }
            $sw = [Diagnostics.Stopwatch]::StartNew(); Start-Sleep -Milliseconds $ms
            $el = $sw.Elapsed.TotalMilliseconds * [Environment]::ProcessorCount
            $per = @{}
            foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
                if ($p.Id -eq $PID -or -not $a.ContainsKey($p.Id)) { continue }
                try { $d = $p.TotalProcessorTime.TotalMilliseconds - $a[$p.Id] } catch { continue }
                if ($d -le 0) { continue }
                $per[$p.ProcessName] = [double]$per[$p.ProcessName] + 100.0 * $d / $el
            }
            $cpu = @($per.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Pct = $per[$_] } })
        } catch { }
    }
    $busy = @($cpu | Where-Object { $_.Pct -ge 8 -and $skip -notcontains $_.Name -and $_.Name -notlike 'Hallow*' } | Sort-Object Pct -Descending | Select-Object -First 3)
    if ($busy.Count) { Add-Line 'bgcpu' 'warn' ('Already using the CPU: {0}' -f (@($busy | ForEach-Object { '{0} {1:N0}%' -f $_.Name, $_.Pct }) -join ', ')) 'taskmgr' $null }
    else { Add-Line 'bgcpu' 'good' 'No background app is using much CPU' $null $null }
    # apps already using the GPU (3D engine, from Windows' GPU counters)
    $gpu = $Opt.Gpu
    if ($null -eq $gpu) {
        $gpu = @()
        try {
            $per = @{}
            foreach ($s in (Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop).CounterSamples) {
                $m = [regex]::Match($s.InstanceName, 'pid_(\d+)_'); if (-not $m.Success) { continue }
                $id = [int]$m.Groups[1].Value; $per[$id] = [double]$per[$id] + $s.CookedValue
            }
            $gpu = @(foreach ($id in $per.Keys) { $n = $null; try { $n = (Get-Process -Id $id -ErrorAction Stop).ProcessName } catch { }; if ($n) { [pscustomobject]@{ Name = $n; Pct = $per[$id] } } })
        } catch { }
    }
    $gbusy = @($gpu | Where-Object { $_.Pct -ge 10 -and $skip -notcontains $_.Name -and $_.Name -notlike 'Hallow*' } | Group-Object Name | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Pct = ($_.Group | Measure-Object Pct -Sum).Sum } } | Sort-Object Pct -Descending | Select-Object -First 3)
    if ($gbusy.Count) { Add-Line 'bggpu' 'warn' ('Already using the GPU: {0}' -f (@($gbusy | ForEach-Object { '{0} {1:N0}%' -f $_.Name, [math]::Min(100, $_.Pct) }) -join ', ')) 'taskmgr' $null }
    else { Add-Line 'bggpu' 'good' 'No background app is using much GPU' $null $null }
    # Discord: hardware acceleration shares the GPU with the game (its own setting; the toolkit never edits Discord's files)
    $roam = $(if ($Opt.Roaming) { $Opt.Roaming } else { $env:APPDATA })
    $dsf = Join-Path $roam 'discord\settings.json'
    if (Test-Path -LiteralPath $dsf) {
        $ds = $null; try { $ds = [IO.File]::ReadAllText($dsf) | ConvertFrom-Json } catch { }
        $hw = $true; if ($ds -and $ds.PSObject.Properties.Name -contains 'enableHardwareAcceleration') { $hw = [bool]$ds.enableHardwareAcceleration }
        $drun = $(if ($null -ne $Opt.DiscordRunning) { [bool]$Opt.DiscordRunning } else { [bool](Get-Process Discord -ErrorAction SilentlyContinue) })
        if ($hw) { Add-Line 'discord' 'warn' ("Discord's hardware acceleration is on{0} - it shares the GPU with the game; if games stutter with Discord open, turn it off (its in-game overlay too, if you don't use it)" -f $(if ($drun) { ' and Discord is running' } else { '' })) 'discord' $null }
        else { Add-Line 'discord' 'good' "Discord's hardware acceleration is off" $null $null }
    }
    # full-screen optimizations: Windows' default is on; some tweak tools turn them off for every game
    $fse = Read-RegVal 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode'
    $layers = @()
    if ($Opt.Reg) { $layers = @($Opt.Reg['Layers'] | Where-Object { $_ }) }
    else { try { $k = Get-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -ErrorAction Stop; $layers = @($k.GetValueNames() | Where-Object { "$($k.GetValue($_))" -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE' } | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) } catch { } }
    $per = $(if ($layers.Count) { " ({0} game(s) have them off in Properties > Compatibility: {1})" -f $layers.Count, (@($layers | Select-Object -First 3) -join ', ') } else { '' })
    if (@($Opt.GameProcs | Where-Object { $_ }).Count) { Add-Line 'gamenow' 'good' "A game is running now ($(@($Opt.GameProcs | Where-Object { $_ } | Select-Object -First 2) -join ', ')) - its own CPU and GPU use is left out above" $null $null }
    if ($fse -eq 2) { Add-Line 'fso' 'warn' "Full-screen optimizations are off for every game (a tweak) - Windows' default (on) gives faster Alt+Tab, HDR and VRR in most games$per" $null $null }
    else { Add-Line 'fso' 'good' "Full-screen optimizations: Windows default$per" $null $null }
    $out
}

# process names running from a game folder (Steam / Epic / ... libraries) - what the game-ready check leaves out
function Get-GameProcessNames {
    $skipProcs = @('crashpad_handler', 'UnityCrashHandler64', 'UnityCrashHandler32', 'CrashReportClient', 'wallpaper32', 'wallpaper64', 'webwallpaper32')
    $roots = @(); try { $roots = @(Get-GameRoots) } catch { }
    @(foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        if ($skipProcs -contains $p.ProcessName) { continue }
        if ($p.ProcessName -match '-(Win64|Win32|WinGDK)-Shipping$') { $p.ProcessName; continue }   # Unreal Engine games (path often hidden by anti-cheat)
        $path = $null; try { $path = $p.Path } catch { }
        if (-not $path) { continue }
        foreach ($r in $roots) { if ($path.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase) -and $path -notmatch '\\(wallpaper_engine|Steamworks Shared|SteamVR)\\') { $p.ProcessName; break } }
    }) | Select-Object -Unique
}

# The fixes behind the game-ready check's buttons. Each changes one setting, only when its button is clicked.
# -WhatIf: says what it would do and changes nothing. -RegRoot (tests): HKCU:\ paths go under this key instead.
function Set-GameReadySetting([string]$What, [switch]$WhatIf, [string]$RegRoot) {
    function Map([string]$p) { if ($RegRoot) { $p -replace '^HKCU:\\', ($RegRoot.TrimEnd('\') + '\') } else { $p } }
    function Put([string]$Path, [string]$Name, [int]$Value) {
        $p = Map $Path
        if ($WhatIf) { return "would set $p\$Name = $Value" }
        if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null }
        Set-ItemProperty -Path $p -Name $Name -Value $Value -Type DWord
        "set $p\$Name = $Value"
    }
    switch ($What) {
        'gamemode' {
            $r = @(Put 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1)
            if ($WhatIf) { return "What if: $($r -join '; ')" }
            'Game Mode is on.'
        }
        'gamebar' {
            $r = @((Put 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0),
                   (Put 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0),
                   (Put 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0))
            if ($WhatIf) { return "What if: $($r -join '; ')" }
            'Xbox Game Bar captures are off (the Game Bar itself still opens with Win+G). Turn them back on any time in Settings > Gaming > Captures.'
        }
        'power' {
            if ($WhatIf) { return 'What if: powercfg /setactive SCHEME_BALANCED' }
            $null = & powercfg.exe /setactive SCHEME_BALANCED 2>&1
            "Power plan is now $(((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1'))."
        }
        default { throw "Unknown setting: $What" }
    }
}

# ================================================================ DRIVER CHECK (read only)
# Graphics, chipset, audio and network drivers: version, date and age, and the maker's driver page. Nothing is
# downloaded or installed from here (the Drivers tab and Windows Update do that). Self-contained (background runspace).
# $Opt (tests): Drivers (fake Win32_PnPSignedDriver rows: DeviceClass, DeviceName, DriverVersion, DriverDate,
# DriverProviderName, Manufacturer), Now, BoardUrl (the motherboard maker's support page).
$DriverAgeWork = {
    param($Opt)
    if (-not $Opt) { $Opt = @{} }
    $now = $(if ($Opt.Now) { [datetime]$Opt.Now } else { Get-Date })
    $out = New-Object System.Collections.ArrayList
    function Add-Line($Key, $Level, $Text, $Fix, $Arg) { [void]$out.Add([pscustomobject]@{ Key = $Key; Level = $Level; Text = $Text; Fix = $Fix; Arg = $Arg }) }
    $pages = @{ NVIDIA = 'https://www.nvidia.com/en-us/drivers/'; AMD = 'https://www.amd.com/en/support/download/drivers.html'; Intel = 'https://www.intel.com/content/www/us/en/support/detect.html' }
    $board = "$($Opt.BoardUrl)"
    function Vendor([string]$s) { if ($s -match 'NVIDIA') { 'NVIDIA' } elseif ($s -match 'AMD|Advanced Micro|Radeon|ATI ') { 'AMD' } elseif ($s -match 'Intel') { 'Intel' } elseif ($s -match 'Realtek') { 'Realtek' } elseif ($s -match 'Killer|Rivet') { 'Killer' } elseif ($s -match 'MediaTek') { 'MediaTek' } else { '' } }
    function Page([string]$v) { if ($pages[$v]) { $pages[$v] } elseif ($board) { $board } else { '' } }
    function Age($d) { if ($d) { [int]($now - [datetime]$d).TotalDays } else { -1 } }
    function When($d) { if ($d) { '{0:d MMM yyyy}' -f [datetime]$d } else { 'unknown date' } }
    function AgeText([int]$days) { if ($days -lt 0) { '' } elseif ($days -lt 60) { "$days days old" } elseif ($days -lt 730) { '{0} months old' -f [int]($days / 30.4) } else { '{0:N1} years old' -f ($days / 365.25) } }
    $rows = $Opt.Drivers
    if ($null -eq $rows) {
        $rows = @()
        try { $rows = @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY' OR DeviceClass='NET' OR DeviceClass='MEDIA' OR DeviceClass='SYSTEM'" -ErrorAction Stop) } catch { }
    }
    $rows = @($rows | Where-Object { $_.DeviceName -and $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' })
    # graphics: every real GPU
    $gpus = @($rows | Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceName -notmatch 'Basic Display|Virtual|Parsec|Remote|Idd|spacedesk|Meta |Oculus|Hyper-V|Citrix' } | Sort-Object DeviceName -Unique)
    foreach ($g in $gpus) {
        $v = Vendor "$($g.DeviceName) $($g.DriverProviderName)"; $ver = "$($g.DriverVersion)"
        if ($v -eq 'NVIDIA') { $dg = $ver -replace '\.', ''; if ($dg.Length -ge 5) { $n = $dg.Substring($dg.Length - 5); $ver = '{0}.{1}' -f $n.Substring(0, 3), $n.Substring(3) } }
        $age = Age $g.DriverDate
        $txt = 'Graphics: {0} - driver {1} from {2}' -f $g.DeviceName, $ver, (When $g.DriverDate)
        if ($age -gt 120) { Add-Line "gpu$($g.DeviceName)" 'warn' "$txt ($(AgeText $age)) - new games often need a newer one; get it from $(if ($v) { $v } else { 'the maker' })" 'open' (Page $v) }
        else { Add-Line "gpu$($g.DeviceName)" 'good' "$txt$(if ($age -ge 0) { " ($(AgeText $age))" })" 'open' (Page $v) }
    }
    if (-not $gpus.Count) { Add-Line 'gpu' 'warn' 'Graphics: no maker driver found - Windows may be using its basic display driver; install the one from NVIDIA, AMD or Intel' $null $null }
    # chipset: AMD / Intel platform drivers (the newest date among them = when the chipset package was last installed)
    $chip = @($rows | Where-Object { $_.DeviceClass -eq 'SYSTEM' -and (Vendor "$($_.DriverProviderName) $($_.Manufacturer)") -in 'AMD', 'Intel' -and
        $_.DeviceName -match 'Chipset|SMBus|GPIO|PSP|I2C|PCI Express|PCI Bridge|Ryzen Power|Management Engine|Serial IO|LPC|SFH|USB4|Platform|Power Management|Dynamic Tuning|Host Bridge|PCI Device' })
    if ($chip.Count) {
        $new = @($chip | Where-Object { $_.DriverDate } | Sort-Object DriverDate -Descending)[0]; if (-not $new) { $new = $chip[0] }
        $v = Vendor "$($new.DriverProviderName) $($new.Manufacturer)"; $age = Age $new.DriverDate
        $txt = 'Chipset: {0} platform drivers ({1} parts), newest from {2}' -f $v, $chip.Count, (When $new.DriverDate)
        $url = $(if ($v -eq 'AMD') { 'https://www.amd.com/en/support/download/drivers.html' } else { $pages.Intel })
        if ($age -gt 730) { Add-Line 'chipset' 'warn' "$txt ($(AgeText $age)) - the $v chipset package (or your board maker's page) has newer ones" 'open' $url }
        else { Add-Line 'chipset' 'good' "$txt$(if ($age -ge 0) { " ($(AgeText $age))" })" 'open' $url }
    }
    # audio and network: the maker's drivers for real devices (virtual cables, VPNs and GPU HDMI audio left out)
    foreach ($kind in @(@('MEDIA', 'Audio', 'Virtual|Steam Streaming|VB-Audio|Voicemeeter|NVIDIA High Definition|NVIDIA Virtual|Broadcast|Oculus|Sonar|AMD High Definition Audio|Intel\(R\) Display Audio|Camo|OBS'),
                        @('NET', 'Network', 'Virtual|Tailscale|Nord|WAN Miniport|TAP|OpenVPN|WireGuard|Hyper-V|Kernel Debug|Npcap|Loopback|VirtualBox|VMware|ZeroTier|Hamachi|Radmin|Bluetooth Device|Wi-Fi Direct|Mullvad|Proton|Surfshark|ExpressVPN|Cisco|Fortinet'))) {
        $list = @($rows | Where-Object { $_.DeviceClass -eq $kind[0] -and $_.DeviceName -notmatch $kind[2] } | Sort-Object DeviceName -Unique)
        foreach ($d in $list) {
            $v = Vendor "$($d.DeviceName) $($d.DriverProviderName) $($d.Manufacturer)"; $age = Age $d.DriverDate
            $txt = '{0}: {1} - driver {2} from {3}' -f $kind[1], $d.DeviceName, $d.DriverVersion, (When $d.DriverDate)
            $url = $(if ($v -in 'Intel', 'AMD', 'NVIDIA') { Page $v } elseif ($v -eq 'Killer') { 'https://www.intel.com/content/www/us/en/products/details/wireless/killer.html' } elseif ($board) { $board } else { '' })
            if ($age -gt 1095) { Add-Line "$kind$($d.DeviceName)" 'warn' "$txt ($(AgeText $age)) - check your board maker's page for a newer one" 'open' $url }
            else { Add-Line "$kind$($d.DeviceName)" 'good' "$txt$(if ($age -ge 0) { " ($(AgeText $age))" })" 'open' $url }
        }
    }
    $out
}

# ================================================================ DISK HEALTH (SMART counters + space trends)
# Health, wear, temperature and error counters from Windows' storage reliability counters (Get-StorageReliabilityCounter -
# the toolkit runs as admin, which Windows needs for these) and how fast each drive is filling up, from a small history
# of free space the toolkit keeps (disk-history.json: one reading per drive per day, 120 days; free space only).
# $Opt (tests): Disks (fake rows: Name, Bus, Media, SizeGB, Health, HasCounters, Wear, Temp, TempMax, Hours, ReadErr, WriteErr)
$DiskHealthWork = {
    param($Opt)
    if (-not $Opt) { $Opt = @{} }
    $out = New-Object System.Collections.ArrayList
    function Add-Line($Key, $Level, $Text, $Fix, $Arg) { [void]$out.Add([pscustomobject]@{ Key = $Key; Level = $Level; Text = $Text; Fix = $Fix; Arg = $Arg }) }
    $disks = $Opt.Disks
    if ($null -eq $disks) {
        $disks = @(foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object DeviceId)) {
            $rc = $null; try { $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            [pscustomobject]@{ Name = "$($d.FriendlyName)"; Bus = "$($d.BusType)"; Media = "$($d.MediaType)"; SizeGB = [math]::Round($d.Size / 1GB); Health = "$($d.HealthStatus)"
                HasCounters = [bool]$rc; Wear = $(if ($rc) { $rc.Wear }); Temp = $(if ($rc) { $rc.Temperature }); TempMax = $(if ($rc) { $rc.TemperatureMax }); Hours = $(if ($rc) { $rc.PowerOnHours })
                ReadErr = $(if ($rc) { [int64]$rc.ReadErrorsUncorrected } else { 0 }); WriteErr = $(if ($rc) { [int64]$rc.WriteErrorsUncorrected } else { 0 }) }
        })
    }
    foreach ($d in $disks) {
        $lvl = 'good'; $bits = @(); $why = @()
        switch -regex ("$($d.Health)") {
            '^Healthy$' { }
            '^Warning$' { $lvl = 'warn'; $why += 'Windows marks it Warning - back up and check it' }
            '^Unhealthy$' { $lvl = 'bad'; $why += 'Windows marks it Unhealthy - back up now' }
        }
        if ($d.HasCounters) {
            if ($null -ne $d.Wear -and "$($d.Wear)" -ne '') {
                $w = [int]$d.Wear; $bits += "$w% worn"
                if ($w -ge 90) { $lvl = 'bad'; $why += 'nearly worn out - plan a replacement' } elseif ($w -ge 70) { if ($lvl -ne 'bad') { $lvl = 'warn' }; $why += 'well worn - keep backups' }
            }
            if ($d.Temp) {
                $t = [int]$d.Temp; $hot = $(if ($d.Media -match 'HDD') { 55 } else { 70 }); $warm = $(if ($d.Media -match 'HDD') { 48 } else { 60 })
                $bits += "$t C$(if ($d.TempMax) { " (hottest $($d.TempMax) C)" })"
                if ($t -ge $hot) { $lvl = 'bad'; $why += 'running hot - check airflow / a heatsink' } elseif ($t -ge $warm) { if ($lvl -ne 'bad') { $lvl = 'warn' }; $why += 'warm' }
            }
            if ($d.Hours) { $bits += '{0:N0} h on' -f [int64]$d.Hours }
            $err = [int64]$d.ReadErr + [int64]$d.WriteErr
            if ($err -gt 0) { $lvl = 'bad'; $bits += "$err uncorrected errors"; $why += 'errors it could not fix - back up important files now' } else { $bits += 'no uncorrected errors' }
        } else { $bits += 'wear, temperature and errors not shown (Windows needs admin, or the drive does not report them)' }
        $txt = '{0} ({1} GB {2} {3}) - {4}: {5}' -f $d.Name, $d.SizeGB, $d.Bus, $d.Media, $(if ($d.Health) { $d.Health } else { 'unknown' }), ($bits -join ', ')
        if ($why.Count) { $txt += " - $($why -join '; ')" }
        Add-Line "disk$($d.Name)" $lvl $txt $null $null
    }
    if (-not @($disks).Count) { Add-Line 'disk' 'warn' 'No drives reported - Windows storage information is not available' $null $null }
    $out
}

$DiskHistoryFile = Join-Path $HallowRoot 'disk-history.json'
# free space on every fixed drive now: @{ 'C:' = @{ Free; Size } }
function Get-DiskSpaceNow {
    $h = [ordered]@{}
    foreach ($d in [IO.DriveInfo]::GetDrives()) { try { if ($d.DriveType -eq 'Fixed' -and $d.IsReady) { $h[$d.Name.TrimEnd('\')] = @{ Free = [double]$d.TotalFreeSpace; Size = [double]$d.TotalSize } } } catch { } }
    $h
}
function Read-DiskHistory([string]$File = $DiskHistoryFile) {
    $h = @{}
    if (Test-Path -LiteralPath $File) { try { $j = [IO.File]::ReadAllText($File) | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = @($p.Value | ForEach-Object { [pscustomobject]@{ d = "$($_.d)"; free = [double]$_.free; size = [double]$_.size } }) } } catch { } }
    $h
}
# adds today's reading (replacing an earlier one from today), keeps 120 days, writes the file atomically
function Update-DiskHistory([string]$File = $DiskHistoryFile, $Now = $null, [datetime]$Today = (Get-Date)) {
    if (-not $Now) { $Now = Get-DiskSpaceNow }
    $h = Read-DiskHistory $File; $day = $Today.ToString('yyyy-MM-dd'); $cut = $Today.AddDays(-120).ToString('yyyy-MM-dd')
    foreach ($k in @($Now.Keys)) {
        $l = @(@($h[$k]) | Where-Object { $_ -and $_.d -ne $day -and $_.d -ge $cut })
        $l += [pscustomobject]@{ d = $day; free = [double]$Now[$k].Free; size = [double]$Now[$k].Size }
        $h[$k] = @($l | Sort-Object d)
    }
    try {
        $o = [ordered]@{}; foreach ($k in @($h.Keys | Sort-Object)) { $o[$k] = @($h[$k]) }
        $tmp = "$File.tmp"; [IO.File]::WriteAllText($tmp, ($o | ConvertTo-Json -Depth 4 -Compress), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $File) { [IO.File]::Replace($tmp, $File, [NullString]::Value) } else { [IO.File]::Move($tmp, $File) }
    } catch { }
    $h
}
# one line per drive: free now, change over the last week / month, and when it fills up at that rate
function Get-DiskTrendLines($History, $Now, [datetime]$Today = (Get-Date)) {
    function GB([double]$b) { if ([math]::Abs($b) -ge 1TB) { '{0:N2} TB' -f ($b / 1TB) } else { '{0:N1} GB' -f ($b / 1GB) } }
    foreach ($k in @($Now.Keys | Sort-Object)) {
        $free = [double]$Now[$k].Free; $size = [double]$Now[$k].Size; if ($size -le 0) { continue }
        $pct = 100 * $free / $size
        $l = @(@($History[$k]) | Where-Object { $_ } | Sort-Object d)
        $txt = '{0} {1} free of {2} ({3:N0}%)' -f $k, (GB $free), (GB $size), $pct
        $lvl = $(if ($pct -lt 5 -or $free -lt 5GB) { 'bad' } elseif ($pct -lt 10 -or $free -lt 20GB) { 'warn' } else { 'good' })
        $old = $null; $span = 0
        foreach ($s in $l) { $age = ($Today.Date - [datetime]::ParseExact($s.d, 'yyyy-MM-dd', $null)).TotalDays; if ($age -ge 3) { $old = $s; $span = $age; break } }
        if ($old) {
            $wk = @($l | Where-Object { ($Today.Date - [datetime]::ParseExact($_.d, 'yyyy-MM-dd', $null)).TotalDays -ge 6 } | Select-Object -Last 1)[0]
            if ($wk) { $dw = $free - $wk.free; $txt += '; {0} {1} in the last {2} days' -f $(if ($dw -lt 0) { 'down' } else { 'up' }), (GB ([math]::Abs($dw))), [int]($Today.Date - [datetime]::ParseExact($wk.d, 'yyyy-MM-dd', $null)).TotalDays }
            $rate = ($old.free - $free) / $span   # bytes used per day (positive = filling up)
            if ($rate -gt 50MB) {
                $days = [int]($free / $rate)
                $txt += '; filling about {0}/day - full in about {1} days at this rate' -f (GB $rate), $days
                if ($days -lt 14) { $lvl = 'bad' } elseif ($days -lt 45 -and $lvl -eq 'good') { $lvl = 'warn' }
            } elseif (-not $wk) { $txt += '; steady over the last {0} days' -f [int]$span }
            else { $txt += ' - steady' }
        } else { $txt += ' (the trend shows after a few days of readings)' }
        [pscustomobject]@{ Key = "space$k"; Level = $lvl; Text = $txt; Fix = $(if ($lvl -ne 'good') { 'storage' }); Arg = $null }
    }
}
