<#
  Hallow Toolkit - display check, games on the RTX, windowed-game optimizations, PBO guide. No window code.
  Dot-sourced by HallowCore.ps1.
#>

# ================================================================ DISPLAYS (which GPU drives each monitor, refresh rate)
Import-HallowType 'HallowDisplay' @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class HallowDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE { public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString; public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE { [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency,
        dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE dd, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
    public class Screen { public string Adapter, Monitor; public bool Primary; public int Width, Height, Hz, MaxHz; }
    public static List<Screen> Get() {
        var list = new List<Screen>();
        for (int i = 0; ; i++) {
            var a = new DISPLAY_DEVICE(); a.cb = Marshal.SizeOf(a);
            if (!EnumDisplayDevices(null, i, ref a, 0)) break;
            if ((a.StateFlags & 1) == 0) continue;
            var m = new DISPLAY_DEVICE(); m.cb = Marshal.SizeOf(m);
            string mon = EnumDisplayDevices(a.DeviceName, 0, ref m, 0) ? m.DeviceString : "";
            var cur = new DEVMODE(); cur.dmSize = (short)Marshal.SizeOf(cur);
            if (!EnumDisplaySettings(a.DeviceName, -1, ref cur)) continue;
            int max = cur.dmDisplayFrequency;
            for (int k = 0; ; k++) {
                var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
                if (!EnumDisplaySettings(a.DeviceName, k, ref dm)) break;
                if (dm.dmPelsWidth == cur.dmPelsWidth && dm.dmPelsHeight == cur.dmPelsHeight && dm.dmDisplayFrequency > max) max = dm.dmDisplayFrequency;
            }
            list.Add(new Screen { Adapter = a.DeviceString, Monitor = mon, Primary = (a.StateFlags & 4) != 0,
                Width = cur.dmPelsWidth, Height = cur.dmPelsHeight, Hz = cur.dmDisplayFrequency, MaxHz = max });
        }
        return list;
    }
}
'@

# ================================================================ GAMES ON THE RTX (per-app GPU preference, same as Settings > Display > Graphics)
$GpuPrefKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$SkipExe = 'crash|report|unins|redist|dxsetup|directx|setup|install|helper|easyanticheat|eac_|beservice|battleye|cefsharp|webhelper|prereq|dotnet|start_protected_game|bugsplat|sentry|updater|cleanup'

function Get-GameExes {
    foreach ($root in Get-GameRoots) {
        foreach ($g in Get-ChildItem $root -Directory -ErrorAction SilentlyContinue) {
            $exes = @(Get-ChildItem $g.FullName -Filter *.exe -Recurse -Depth 4 -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $SkipExe })
            $pick = @($exes | Where-Object { $_.Name -match '-Shipping\.exe$' })
            $pick += @($exes | Where-Object { Test-Path (Join-Path $_.DirectoryName 'UnityPlayer.dll') })
            if (-not $pick) { $pick = @($exes | Where-Object { $_.Length -gt 20MB } | Sort-Object Length -Descending | Select-Object -First 2) }
            foreach ($e in $pick | Sort-Object FullName -Unique) {
                $cur = (Get-ItemProperty $GpuPrefKey -Name $e.FullName -ErrorAction SilentlyContinue).($e.FullName)
                [pscustomobject]@{ Game = $g.Name; Exe = $e.Name; Path = $e.FullName; Pinned = ("$cur" -match 'GpuPreference=2') }
            }
        }
    }
}

function Set-GameGpu([string[]]$Paths) {
    if (-not (Test-Path $GpuPrefKey)) { New-Item $GpuPrefKey -Force | Out-Null }
    foreach ($p in $Paths) {
        $cur = "$((Get-ItemProperty $GpuPrefKey -Name $p -ErrorAction SilentlyContinue).$p)"
        $new = if ($cur -match 'GpuPreference=\d;') { $cur -replace 'GpuPreference=\d;', 'GpuPreference=2;' } else { "GpuPreference=2;$cur" }
        Set-ItemProperty $GpuPrefKey -Name $p -Value $new -Type String
    }
    Log "Pinned $(@($Paths).Count) game(s) to the high-performance GPU - takes effect the next time each game starts."
}

# Windowed-game optimizations live inside one shared string, e.g. "SwapEffectUpgradeEnable=1;VRROptimizeEnable=0;"
function Get-DxGlobal { "$((Get-ItemProperty $GpuPrefKey -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue).DirectXUserGlobalSettings)" }
function Set-DxGlobalFlag([string]$Name, [string]$Value) {
    if (-not (Test-Path $GpuPrefKey)) { New-Item $GpuPrefKey -Force | Out-Null }
    $s = (Get-DxGlobal) -replace "$Name=[^;]*;?", ''
    if ($Value) { $s = "$s$Name=$Value;" }
    if ($s) { Set-ItemProperty $GpuPrefKey -Name DirectXUserGlobalSettings -Value $s -Type String }
    else { Remove-ItemProperty $GpuPrefKey -Name DirectXUserGlobalSettings -ErrorAction SilentlyContinue }
}

# ================================================================ PBO / CURVE OPTIMIZER GUIDE
function Show-PboGuide {
    $b = Get-BoardInfo; $cpu = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim()
    Log '===== PBO + CURVE OPTIMIZER ====='
    Log "$cpu on $($b.Maker) $($b.Model), BIOS $($b.Bios)"
    if ($cpu -notmatch 'Ryzen') { Log 'This guide is for AMD Ryzen CPUs - nothing to do on this PC.'; return }
    Log 'What it does: lets the CPU boost higher for longer and, with a negative curve, run cooler at the same speed.'
    Log 'Typical result: a few % more FPS in CPU-heavy games and 5-10 C lower temps. Undo any time by loading BIOS defaults (F5).'
    Log 'AMD counts PBO as overclocking. These settings are common and mild, but they are at your own risk.'
    Log 'In the BIOS, press F7 for Advanced mode, then:'
    switch ($b.Vendor) {
        'ASUS'     { $path = 'Ai Tweaker > Precision Boost Overdrive' }
        'MSI'      { $path = 'OC > Advanced CPU Configuration > AMD Overclocking > Precision Boost Overdrive' }
        'Gigabyte' { $path = 'Tweaker > Advanced CPU Settings > Precision Boost Overdrive' }
        'ASRock'   { $path = 'OC Tweaker > AMD Overclocking > Precision Boost Overdrive' }
        default    { $path = 'the AMD Overclocking / Precision Boost Overdrive menu' }
    }
    Log "  1. $path > Precision Boost Overdrive = Advanced"
    Log '  2. PBO Limits = Motherboard'
    Log '  3. Curve Optimizer = All Cores, Sign = Negative, Magnitude = 10'
    Log '  4. Leave Max CPU Boost Clock Override at 0 for now. F10 to save and exit.'
    Log 'Then play normally for a day and run Health > Run system check: "Hardware errors" must stay at 0.'
    Log '  Stable? Next time try 15, then 20 (most chips are fine at 15-25).'
    Log '  A crash, freeze or hardware error? Go back 5 (e.g. 15 -> 10). Keep EXPO on as it is.'
    Log 'Tools tab > Restart into BIOS takes you straight there.'
}

# ================================================================ NVIDIA SHADER CACHE
function Show-ShaderCacheTip {
    Log 'Bigger shader cache = fewer stutters after driver updates and in big open-world games.'
    Log 'NVIDIA app > Graphics > Global Settings > Shader Cache Size = 10 GB (or Unlimited). Click Apply.'
    $app = Get-ChildItem 'C:\Program Files\NVIDIA Corporation\NVIDIA app' -Recurse -Filter 'NVIDIA app.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($app) { Start-Process $app.FullName; Log 'Opened the NVIDIA app.' }
    else { Log 'NVIDIA app not found - on older drivers: NVIDIA Control Panel > Manage 3D settings > Shader Cache Size.' }
}
