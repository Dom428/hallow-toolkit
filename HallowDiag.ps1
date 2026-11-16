<#
  Hallow Toolkit - boot time tracker and "which part of the game crashed" analysis. No window code.
  Dot-sourced by HallowCore.ps1.
#>

# ================================================================ BOOT TIME
function Get-EventFields($e) {
    $h = @{}; foreach ($n in ([xml]$e.ToXml()).Event.EventData.Data) { $h[$n.Name] = $n.'#text' }; $h
}

function Invoke-BootTime {
    if (-not (Need-Admin 'Reading the boot timing log')) { return }
    Log '===== BOOT TIME ====='
    $log = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    $boots = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 100 } -MaxEvents 12 -ErrorAction SilentlyContinue)
    if (-not $boots) { Log 'Windows has no boot timings yet (the log is empty or turned off). Restart once and try again.'; return }
    Log 'Recent starts (to the desktop, then until Windows settles down):'
    $totals = foreach ($b in $boots) {
        $d = Get-EventFields $b
        $main = [double]$d['MainPathBootTime'] / 1000; $post = [double]$d['BootPostBootTime'] / 1000; $tot = [double]$d['BootTime'] / 1000
        Log ("  {0:ddd yyyy-MM-dd HH:mm}   desktop in {1,5:N1} s   settled after {2,5:N1} s" -f $b.TimeCreated, $main, $tot)
        $tot
    }
    $avg = ($totals | Measure-Object -Average).Average
    $grade = if ($avg -lt 30) { 'fast' } elseif ($avg -lt 60) { 'normal' } elseif ($avg -lt 120) { 'slow' } else { 'very slow' }
    Log ("Average: {0:N0} s - {1}. (A gaming PC on an NVMe SSD usually settles in 20-45 s.)" -f $avg, $grade)
    if ($totals.Count -ge 6) {
        $new = ($totals | Select-Object -First 3 | Measure-Object -Average).Average
        $old = ($totals | Select-Object -Skip 3 | Measure-Object -Average).Average
        if ($new -gt $old * 1.3 -and ($new - $old) -gt 10) { Log ("Getting slower: the last 3 starts average {0:N0} s vs {1:N0} s before. Something new was added to startup." -f $new, $old) }
        elseif ($new -lt $old * 0.8) { Log ("Getting faster: the last 3 starts average {0:N0} s vs {1:N0} s before." -f $new, $old) }
    }
    # 101 = app, 102 = driver, 103 = service, 106 = background task, 109 = device: each slowed a start down
    $slow = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 101, 102, 103, 106, 109; StartTime = (Get-Date).AddDays(-60) } -ErrorAction SilentlyContinue)
    if ($slow) {
        $kind = @{ 101 = 'app'; 102 = 'driver'; 103 = 'service'; 106 = 'task'; 109 = 'device' }
        $rows = foreach ($e in $slow) {
            $d = Get-EventFields $e
            $name = @($d['FriendlyName'], $d['Name'], $d['File']) | Where-Object { $_ } | Select-Object -First 1
            [pscustomobject]@{ Name = "$name ($($kind[$e.Id]))"; Ms = [double]$d['DegradationTime'] }
        }
        Log 'What slowed the starts down (last 60 days, extra seconds each time):'
        foreach ($g in $rows | Group-Object Name | Sort-Object { ($_.Group | Measure-Object Ms -Sum).Sum } -Descending | Select-Object -First 8) {
            Log ("  +{0,4:N1} s  {1}  ({2}x)" -f (($g.Group | Measure-Object Ms -Average).Average / 1000), $g.Name, $g.Count)
        }
        Log 'Apps here can be turned off at startup on the Tweaks tab (Startup apps). Leave drivers and Windows services alone.'
    } else { Log 'Windows did not flag any app, driver or service for slowing the start down.' }
    $fs = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($fs -eq 0) { Log 'Fast Startup is off, so every start is a full cold boot - normal with the Performance tweak, just a few seconds slower.' }
    Log '===== END ====='
}

# ================================================================ GAME / APP CRASH CULPRITS
# Faulting module -> who is to blame and what to do.
$CrashModules = @(
    ,@('^(nvwgf2umx?|nvlddmkm|nvoglv(32|64)|nvd3dumx?|nvapi(64)?|nvgpucomp(64|32)|nvwgf2um_cfg|nvcuda(64)?)\.dll$', 'the NVIDIA driver', 'Update the driver, or do a clean install (NVIDIA app > Drivers > Reinstall > Clean). Check GPU temps on the Monitor tab.')
    ,@('^(amdxx64|atidxx64|aticfx64|amdxc64)\.dll$', 'the AMD graphics driver', 'Update or clean-install the AMD driver.')
    ,@('^(d3d11|d3d12|d3d12core|dxgi|d3d9|dxcore)\.dll$', 'DirectX / the graphics stack', 'Usually the graphics driver or an overlay. Update the GPU driver and turn off overlays you do not need.')
    ,@('^(gameoverlayrenderer(64)?|discordhook(64)?|rtsshooks(64)?|nvspcap(64)?|overlay64|graphics-hook\d*|obs-vulkan\d*)\.dll$', 'an overlay (Steam, Discord, RTSS, NVIDIA or OBS)', 'Turn that overlay off for this game.')
    ,@('^(easyanticheat.*|beclient.*|battleye.*|vgc|vgk|ace-?.*|anticheat.*)\.(dll|sys|exe)$', 'the anti-cheat', 'Verify the game files and restart the PC. Some anti-cheats crash with debug or overclocking tools running.')
    ,@('^(unityplayer|gameassembly|mono-2\.0-bdwgc|coreclr|clr|unrealengine.*|.*-win64-shipping\.exe)\.?(dll|exe)?$', "the game's own code", 'Verify the game files (Steam > Properties > Installed files) and check for a game update.')
    ,@('^(ntdll|kernelbase|ucrtbase|msvcp\d+|vcruntime\d+(_\d)?|kernel32)\.dll$', 'the program itself (Windows only reported it)', 'Verify/reinstall the program. If many different programs crash like this, suspect RAM stability (EXPO).')
    ,@('^qbcore\.dll$', 'the program itself', 'It crashed on purpose after an internal error - update or reinstall it.')
)
function Get-CrashCulprit([string]$Module, [string]$App) {
    $m = $Module.ToLower()
    if ($m -eq $App.ToLower()) { return @("the program's own code", 'Update or reinstall it; for a game, verify its files.') }
    foreach ($r in $CrashModules) { if ($m -match $r[0]) { return @($r[1], $r[2]) } }
    @("$Module", 'Search the module name with the program name to see who makes it.')
}

function Show-AppCrashCulprits([int]$Days = 30) {
    $since = (Get-Date).AddDays(-$Days)
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since } -ErrorAction SilentlyContinue)
    $hangs = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $since } -ErrorAction SilentlyContinue)
    if (-not $ev -and -not $hangs) { Log "Apps/games that crashed or froze ($Days days): none"; return }
    Log "Apps/games that crashed ($Days days) - and which part crashed:"
    $sysWide = @{}
    foreach ($g in $ev | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 8) {
        $byMod = $g.Group | Group-Object { "$($_.Properties[3].Value)" } | Sort-Object Count -Descending
        $top = $byMod[0].Name
        $c = Get-CrashCulprit $top $g.Name
        $last = ($g.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
        Log ("  {0,3}x  {1}  (last {2:MM-dd HH:mm})" -f $g.Count, $g.Name, $last)
        Log ("        crashed in {0} -> {1}" -f $top, $c[0])
        Log ("        fix: {0}" -f $c[1])
        if ($top -match '^(ntdll|kernelbase|ucrtbase)\.dll$') { $sysWide[$g.Name] = 1 }
    }
    if ($sysWide.Count -ge 3) { Log '  ! 3+ different programs crash inside core Windows files - that pattern points at RAM/CPU stability. Run Health > Run memory test and consider EXPO off for a day to compare.' }
    if ($hangs) {
        Log 'Froze (stopped responding):'
        foreach ($g in $hangs | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 5) { Log ("  {0,3}x  {1}" -f $g.Count, $g.Name) }
    }
}
