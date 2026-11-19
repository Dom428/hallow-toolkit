<#
  Hallow Toolkit - system info (v5.12), Tweaks presets and browser clean-up (v5.12). No window code. Dot-sourced by HallowCore.ps1.
#>

# ================================================================ SYSTEM INFO (read-only)
# Rows: Group, Item, Value. Drive health needs admin for the detailed counters (temperature, wear, errors, hours).
function Get-SystemInfoRows {
    function Row($G, $I, $V) { [pscustomobject]@{ Group = $G; Item = $I; Value = "$V" } }
    try {
        foreach ($c in @(Get-CimInstance Win32_Processor)) {
            Row 'CPU' 'Processor' "$($c.Name)".Trim()
            Row 'CPU' 'Cores / threads' "$($c.NumberOfCores) cores, $($c.NumberOfLogicalProcessors) threads"
            Row 'CPU' 'Base clock' ('{0:N2} GHz' -f ($c.MaxClockSpeed / 1000))
            if ($c.L3CacheSize) { Row 'CPU' 'L3 cache' ('{0:N0} MB' -f ($c.L3CacheSize / 1024)) }
        }
    } catch { }
    try {
        $vram = @{}
        foreach ($k in Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc -and $p.'HardwareInformation.qwMemorySize') { $vram["$($p.DriverDesc)"] = [double]$p.'HardwareInformation.qwMemorySize' }
        }
        foreach ($g in @(Get-CimInstance Win32_VideoController)) {
            $mem = if ($vram.ContainsKey("$($g.Name)")) { $vram["$($g.Name)"] } else { [double]$g.AdapterRAM }
            Row 'Graphics' "$($g.Name)" ('{0}driver {1} ({2:d MMM yyyy}){3}' -f $(if ($mem -gt 0) { '{0:N0} GB, ' -f ($mem / 1GB) } else { '' }), $g.DriverVersion, $g.DriverDate, $(if ($g.CurrentHorizontalResolution) { ", $($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution) at $($g.CurrentRefreshRate) Hz" } else { '' }))
        }
    } catch { }
    try {
        $sticks = @(Get-CimInstance Win32_PhysicalMemory)
        Row 'Memory' 'Total' ('{0:N0} GB in {1} stick(s)' -f (($sticks | Measure-Object Capacity -Sum).Sum / 1GB), $sticks.Count)
        foreach ($m in $sticks) {
            $speed = if ($m.ConfiguredClockSpeed -and $m.ConfiguredClockSpeed -ne $m.Speed) { "running at $($m.ConfiguredClockSpeed) MT/s (rated $($m.Speed))" } else { "$($m.Speed) MT/s" }
            Row 'Memory' "$($m.DeviceLocator) $($m.BankLabel)".Trim() ('{0:N0} GB, {1}, {2} {3}' -f ($m.Capacity / 1GB), $speed, "$($m.Manufacturer)".Trim(), "$($m.PartNumber)".Trim())
        }
    } catch { }
    try {
        $b = Get-CimInstance Win32_BaseBoard; Row 'Motherboard' 'Board' "$($b.Manufacturer) $($b.Product)".Trim()
        $bi = Get-CimInstance Win32_BIOS; Row 'Motherboard' 'BIOS' ('{0} ({1:d MMM yyyy})' -f "$($bi.SMBIOSBIOSVersion)".Trim(), $bi.ReleaseDate)
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem; $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        Row 'Windows' 'Edition' ("$($os.Caption) $($cv.DisplayVersion)").Trim()
        Row 'Windows' 'Build' "$($os.BuildNumber).$($cv.UBR)"
        Row 'Windows' 'Installed' ('{0:d MMM yyyy}' -f $os.InstallDate)
        Row 'Windows' 'Up since' ('{0:ddd d MMM h:mm tt}' -f $os.LastBootUpTime)
    } catch { }
    try {
        foreach ($d in @(Get-PhysicalDisk | Sort-Object DeviceId)) {
            $txt = '{0:N0} GB {1} {2}, health: {3}' -f ($d.Size / 1GB), $d.BusType, $d.MediaType, $d.HealthStatus
            $rc = $null; try { $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            if ($rc) {
                $bits = @()
                if ($rc.Temperature) { $bits += "$($rc.Temperature) C" }
                if ($null -ne $rc.Wear) { $bits += "$($rc.Wear)% worn" }
                if ($rc.PowerOnHours) { $bits += "$($rc.PowerOnHours) h on" }
                $err = [int64]$rc.ReadErrorsUncorrected + [int64]$rc.WriteErrorsUncorrected
                $bits += $(if ($err) { "$err uncorrected errors" } else { 'no uncorrected errors' })
                $txt += ' - ' + ($bits -join ', ')
            } else { $txt += ' (temperature, wear and errors need admin)' }
            Row 'Drives' "$($d.FriendlyName)" $txt
        }
    } catch { }
}

# ================================================================ TWEAKS PRESETS (WinUtil style)
# A preset only flips switches on the Tweaks page - you see them (yellow = not applied yet), Apply makes them real,
# Undo all puts every switch back to the Windows default.
$TweakPresets = [ordered]@{
    'Minimal' = @('ext', 'endtask', 'tips', 'startrec', 'adid', 'sticky')
    'Gamer'   = @('windowed', 'gamedvr', 'sticky', 'tips', 'startrec', 'bing', 'copilot', 'edgebg', 'doupload')
    'Privacy' = @('adid', 'tips', 'startrec', 'bing', 'tailored', 'copilot', 'recall', 'activity', 'telemetry', 'speech', 'inking', 'location')
}

# ================================================================ BROWSER CLEAN-UP
# Per browser: cache and/or history (opt-in), only when that browser is closed. Cookies and passwords are never touched.
# Firefox keeps history and bookmarks in one file, so only its cache is cleaned.
$BrowserDefs = @(
    @{ Name = 'Chrome'; Proc = 'chrome'; Data = 'Google\Chrome\User Data' }
    @{ Name = 'Edge'; Proc = 'msedge'; Data = 'Microsoft\Edge\User Data' }
    @{ Name = 'Brave'; Proc = 'brave'; Data = 'BraveSoftware\Brave-Browser\User Data' }
    @{ Name = 'Vivaldi'; Proc = 'vivaldi'; Data = 'Vivaldi\User Data' }
    @{ Name = 'Opera'; Proc = 'opera'; Data = 'Opera Software\Opera Stable'; Opera = $true }
    @{ Name = 'Firefox'; Proc = 'firefox'; Firefox = $true }
)
# $Local / $Roaming: data folders (tests point them somewhere else)
function Get-BrowserTargets([string]$Local = $env:LOCALAPPDATA, [string]$Roaming = $env:APPDATA) {
    foreach ($b in $BrowserDefs) {
        $cache = @(); $hist = @()
        if ($b.Firefox) {
            $pr = Join-Path $Local 'Mozilla\Firefox\Profiles'
            if (-not (Test-Path $pr)) { continue }
            foreach ($p in Get-ChildItem $pr -Directory -ErrorAction SilentlyContinue) { foreach ($c in 'cache2', 'startupCache', 'thumbnails') { $cache += Join-Path $p.FullName $c } }
        } else {
            $root = if ($b.Opera) { Join-Path $Roaming $b.Data } else { Join-Path $Local $b.Data }
            if (-not (Test-Path $root)) { continue }
            $profiles = if ($b.Opera) { @(Get-Item $root) } else { @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) }
            $cacheRoot = if ($b.Opera) { Join-Path $Local $b.Data } else { $null }
            foreach ($p in $profiles) {
                foreach ($c in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') { $cache += Join-Path $(if ($cacheRoot) { $cacheRoot } else { $p.FullName }) $c }
                foreach ($h in 'History', 'History-journal', 'Visited Links', 'Top Sites', 'Top Sites-journal') { $hist += Join-Path $p.FullName $h }
            }
            if (-not $b.Opera) { foreach ($c in 'ShaderCache', 'GrShaderCache') { $cache += Join-Path $root $c } }
        }
        [pscustomobject]@{ Name = $b.Name; Proc = $b.Proc; Running = [bool](Get-Process $b.Proc -ErrorAction SilentlyContinue)
            Cache = @($cache | Where-Object { Test-Path -LiteralPath $_ }); History = @($hist | Where-Object { Test-Path -LiteralPath $_ }); HistorySupported = -not $b.Firefox }
    }
}
function Get-PathBytes([string]$Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-Item -LiteralPath $Path -Force).Length } else { Get-FolderBytes $Path } }
# Returns one row per browser: Name, Bytes, Note. -DryRun only measures.
function Invoke-BrowserClean($Targets, [bool]$Cache, [bool]$History, [switch]$DryRun) {
    foreach ($t in @($Targets)) {
        if ($t.Running -or (Get-Process $t.Proc -ErrorAction SilentlyContinue)) { [pscustomobject]@{ Name = $t.Name; Bytes = 0; Note = 'skipped - close it first' }; continue }
        $paths = @(); if ($Cache) { $paths += $t.Cache }; if ($History -and $t.HistorySupported) { $paths += $t.History }
        $bytes = 0
        foreach ($p in $paths) {
            $b = Get-PathBytes $p
            if (-not $DryRun) {
                try {
                    if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
                    else { Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
                    $b -= (Get-PathBytes $p)
                } catch { $b = 0 }
            }
            $bytes += [math]::Max(0, $b)
        }
        $note = @(); if ($Cache) { $note += 'cache' }; if ($History) { $note += $(if ($t.HistorySupported) { 'history' } else { 'history (not for Firefox - use its own Clear history)' }) }
        [pscustomobject]@{ Name = $t.Name; Bytes = [double]$bytes; Note = "$(if ($DryRun) { 'would clear' } else { 'cleared' }) $($note -join ' + ')" }
    }
}
