<#
  Hallow Toolkit - v5.14 gamer tools (no window code): shader caches with sizes, Windows gaming settings status,
  display modes (max refresh rate with a timed revert), raw mouse / keyboard input, the motion test renderer,
  route to a server, DNS undo and "verify game files". Dot-sourced by HallowCore.ps1.
  Nothing here changes anything until a button calls it.
#>

# ================================================================ is a game running right now?
# Hallow Hub's list, or any process running from a game folder (same rule as the tray's game finder).
function Get-RunningGameNow {
    if (Test-HubPlaying) {
        try { $n = @((Get-Content (Join-Path $env:APPDATA 'HallowHub\status.json') -Raw -Encoding UTF8 | ConvertFrom-Json).playing | Where-Object { $_ })[0]; if ("$n") { return "$n" } } catch { }
        return 'your game'
    }
    $skipDirs = @('wallpaper_engine', 'Steamworks Shared', 'Steam Controller Configs', 'SteamVR', 'Steam Linux Runtime')
    $skipProcs = @('crashpad_handler', 'UnityCrashHandler64', 'UnityCrashHandler32', 'CrashReportClient', 'wallpaper32', 'wallpaper64', 'webwallpaper32')
    $roots = @(Get-GameRoots)
    foreach ($p in Get-Process) {
        if ($skipProcs -contains $p.ProcessName) { continue }
        $path = $null; try { $path = $p.Path } catch { }
        if (-not $path) { continue }
        foreach ($r in $roots) {
            if ($path.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $folder = ($path.Substring($r.Length + 1) -split '\\')[0]
                if ($skipDirs -notcontains $folder) { return $folder }
            }
        }
    }
    $null
}

# ================================================================ SHADER CACHES (GPU driver, DirectX, Steam per game)
# Every place games and drivers keep compiled shaders. All of it is rebuilt by the driver / game when needed.
function Get-ShaderCacheSpots {
    $la = $env:LOCALAPPDATA; $low = Join-Path $env:USERPROFILE 'AppData\LocalLow'
    $spots = @(
        @('NVIDIA', 'DirectX shader cache', @("$la\NVIDIA\DXCache", "$low\NVIDIA\PerDriverVersion\DXCache")),
        @('NVIDIA', 'OpenGL / Vulkan shader cache', @("$la\NVIDIA\GLCache", "$low\NVIDIA\PerDriverVersion\GLCache")),
        @('NVIDIA', 'Old driver cache (NV_Cache)', @("$la\NVIDIA Corporation\NV_Cache")),
        @('AMD', 'DirectX shader cache', @("$la\AMD\DxCache", "$la\AMD\DxcCache", "$la\AMD\Dx9Cache")),
        @('AMD', 'Vulkan / OpenGL shader cache', @("$la\AMD\VkCache", "$la\AMD\GLCache")),
        @('Intel', 'Shader cache', @("$low\Intel\ShaderCache", "$la\Intel\ShaderCache")),
        @('Windows', 'DirectX shader cache (all GPUs)', @("$la\D3DSCache")))
    foreach ($s in $spots) {
        $dirs = @($s[2] | Where-Object { Test-Path -LiteralPath $_ })
        if ($dirs) { [pscustomobject]@{ Who = $s[0]; What = $s[1]; Dirs = $dirs; Bytes = 0.0; Game = '' } }
    }
    # Steam keeps one shader folder per game: <library>\steamapps\shadercache\<appid>
    $names = @{}; foreach ($g in @(Get-SteamGames)) { if ($g.Id) { $names["$($g.Id)"] = $g.Name } }
    foreach ($lib in @(Get-SteamLibraries)) {
        foreach ($d in Get-ChildItem (Join-Path $lib 'steamapps\shadercache') -Directory -ErrorAction SilentlyContinue) {
            $n = if ($names.ContainsKey($d.Name)) { $names[$d.Name] } else { "Steam app $($d.Name) (not installed)" }
            [pscustomobject]@{ Who = 'Steam'; What = $n; Dirs = @($d.FullName); Bytes = 0.0; Game = $n }
        }
    }
}

# Background runspace: measures each spot (self-contained).
$ShaderSizeWork = {
    param($spots)
    foreach ($s in $spots) {
        $sum = 0.0
        foreach ($d in $s.Dirs) { $m = (Get-ChildItem -LiteralPath $d -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; if ($m) { $sum += $m } }
        $s.Bytes = $sum; $s
    }
}

# Clears the contents of the given spots (files in use are skipped). Refuses while a game runs.
function Clear-ShaderCacheSpots($Spots, [scriptblock]$GameCheck = { Get-RunningGameNow }) {
    $g = & $GameCheck
    if ($g) { Log "Shader caches not cleared - $g is running. Close the game first (its cache is in use)."; return $null }
    $freed = 0.0; $left = 0.0
    foreach ($s in $Spots) {
        foreach ($d in $s.Dirs) {
            if (-not (Test-Path -LiteralPath $d)) { continue }
            $before = Get-FolderBytes $d
            Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch { } }
            $after = Get-FolderBytes $d
            $freed += ($before - $after); $left += $after
        }
        Log ("Shader cache cleared: {0} - {1}" -f $s.Who, $s.What)
    }
    Log ("Freed {0}{1}. Games and the driver rebuild shaders the next time they need them - the first match or level can load a little slower or stutter once." -f (Format-Size $freed), $(if ($left -gt 1MB) { " ($(Format-Size $left) in use was skipped)" } else { '' }))
    $freed
}

# ================================================================ WINDOWS GAMING SETTINGS (read-only status + links)
# (Get-RegValue comes from HallowExtras.ps1)

# Each row: Setting, Now, Level (good / warn / info), Advice, Link (ms-settings: or other URI).
function Get-GamingSettingsStatus {
    $rows = New-Object System.Collections.Generic.List[object]
    function Add-Row($Setting, $Now, $Level, $Advice, $Link) { $rows.Add([pscustomobject]@{ Setting = $Setting; Now = $Now; Level = $Level; Advice = $Advice; Link = $Link }) }

    $gm = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
    if ($gm -eq 0) { Add-Row 'Game Mode' 'Off' 'warn' 'Turn it on: Windows gives the game priority and holds back updates while you play' 'ms-settings:gaming-gamemode' }
    else { Add-Row 'Game Mode' 'On' 'good' 'Leave it on' 'ms-settings:gaming-gamemode' }

    $hags = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    switch ($hags) {
        2 { Add-Row 'Hardware-accelerated GPU scheduling' 'On' 'good' 'Needed for DLSS Frame Generation; changes need a restart' 'ms-settings:display-advancedgraphics' }
        1 { Add-Row 'Hardware-accelerated GPU scheduling' 'Off' 'warn' 'On is better for most modern cards (needs admin and a restart - switch it in Settings)' 'ms-settings:display-advancedgraphics' }
        default { Add-Row 'Hardware-accelerated GPU scheduling' 'Windows default' 'info' 'Check it in Settings > Graphics (changes need a restart)' 'ms-settings:display-advancedgraphics' }
    }

    $dx = "$(Get-RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings')"
    if ($dx -match 'SwapEffectUpgradeEnable=1') { Add-Row 'Optimizations for windowed games' 'On' 'good' 'Borderless games get full-screen speed and lower latency' 'ms-settings:display-advancedgraphics' }
    elseif ($dx -match 'SwapEffectUpgradeEnable=0') { Add-Row 'Optimizations for windowed games' 'Off' 'warn' 'Turn it on for lower latency in borderless games (Tweaks tab or Settings)' 'ms-settings:display-advancedgraphics' }
    else { Add-Row 'Optimizations for windowed games' 'Windows default' 'info' 'On by default in Windows 11 24H2; earlier versions: turn it on in Settings' 'ms-settings:display-advancedgraphics' }
    if ($dx -match 'VRROptimizeEnable=1') { Add-Row 'Variable refresh rate (for older games)' 'On' 'good' 'G-SYNC / FreeSync also works in games that do not support it themselves' 'ms-settings:display-advancedgraphics' }
    else { Add-Row 'Variable refresh rate (for older games)' 'Off / default' 'info' 'Only matters with a G-SYNC / FreeSync monitor' 'ms-settings:display-advancedgraphics' }

    $dvr = Get-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
    $cap = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
    $hist = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled'
    if ($hist -eq 1) { Add-Row 'Game Bar background recording' 'On (records all the time)' 'warn' 'Costs a few FPS. Turn off "Record what happened" unless you use it (Hallow Clips does this job)' 'ms-settings:gaming-captures' }
    elseif ($dvr -eq 0 -or $cap -eq 0) { Add-Row 'Game Bar captures' 'Off' 'good' 'Nothing records in the background' 'ms-settings:gaming-captures' }
    else { Add-Row 'Game Bar captures' 'Ready (not recording)' 'info' 'Win+Alt+R records only when you ask' 'ms-settings:gaming-captures' }

    if (Get-MouseAccel) { Add-Row 'Mouse acceleration (Enhance pointer precision)' 'On' 'warn' 'Off gives 1:1 aim in shooters (Gaming tab > Mouse acceleration)' 'ms-settings:mousetouchpad' }
    else { Add-Row 'Mouse acceleration (Enhance pointer precision)' 'Off' 'good' '1:1 aim' 'ms-settings:mousetouchpad' }

    $plan = ((powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1')
    Add-Row 'Power plan' "$plan".Trim() 'info' 'Balanced is right for Ryzen 7000 / most CPUs; High performance for older Intel' 'ms-settings:powersleep'

    $fa = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' 'NOC_GLOBAL_SETTING_TOASTS_ENABLED'
    Add-Row 'Notifications during games' $(if ($fa -eq 0) { 'Off' } else { 'Allowed' }) 'info' 'Do not disturb turns on by itself in full-screen games (Settings > Notifications)' 'ms-settings:notifications'

    $hvci = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    Add-Row 'Memory integrity (security)' $(if ($hvci -eq 1) { 'On' } else { 'Off' }) 'info' 'A Windows security feature - shown for information only, the toolkit does not change it' 'windowsdefender://coreisolation'
    $rows
}

# ================================================================ DISPLAY MODES (refresh rate, timed revert)
Import-HallowType 'HallowDisplayMode' @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class HallowDisplayMode {
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
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW")] static extern int ChangeDisplaySettingsExNull(string dev, IntPtr dm, IntPtr hwnd, int flags, IntPtr lParam);
    public class Mon { public string Device, Adapter, Monitor; public bool Primary; public int X, Y, Width, Height, Hz, Bpp, MaxHz, MaxWidth, MaxHeight, MaxHzAtMaxRes; public int[] HzList; }
    public static List<Mon> List() {
        var list = new List<Mon>();
        for (int i = 0; ; i++) {
            var a = new DISPLAY_DEVICE(); a.cb = Marshal.SizeOf(a);
            if (!EnumDisplayDevices(null, i, ref a, 0)) break;
            if ((a.StateFlags & 1) == 0) continue;
            var m = new DISPLAY_DEVICE(); m.cb = Marshal.SizeOf(m);
            string mon = EnumDisplayDevices(a.DeviceName, 0, ref m, 0) ? m.DeviceString : "";
            var cur = new DEVMODE(); cur.dmSize = (short)Marshal.SizeOf(cur);
            if (!EnumDisplaySettings(a.DeviceName, -1, ref cur)) continue;
            var o = new Mon { Device = a.DeviceName, Adapter = a.DeviceString, Monitor = mon, Primary = (a.StateFlags & 4) != 0, X = cur.dmPositionX, Y = cur.dmPositionY,
                Width = cur.dmPelsWidth, Height = cur.dmPelsHeight, Hz = cur.dmDisplayFrequency, Bpp = cur.dmBitsPerPel, MaxHz = cur.dmDisplayFrequency };
            var hz = new SortedSet<int>();
            for (int k = 0; ; k++) {
                var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
                if (!EnumDisplaySettings(a.DeviceName, k, ref dm)) break;
                if (dm.dmBitsPerPel != cur.dmBitsPerPel) continue;
                if (dm.dmPelsWidth == cur.dmPelsWidth && dm.dmPelsHeight == cur.dmPelsHeight) { hz.Add(dm.dmDisplayFrequency); if (dm.dmDisplayFrequency > o.MaxHz) o.MaxHz = dm.dmDisplayFrequency; }
                long px = (long)dm.dmPelsWidth * dm.dmPelsHeight, best = (long)o.MaxWidth * o.MaxHeight;
                if (px > best || (px == best && dm.dmDisplayFrequency > o.MaxHzAtMaxRes)) { o.MaxWidth = dm.dmPelsWidth; o.MaxHeight = dm.dmPelsHeight; o.MaxHzAtMaxRes = dm.dmDisplayFrequency; }
            }
            o.HzList = new int[hz.Count]; hz.CopyTo(o.HzList);
            list.Add(o);
        }
        return list;
    }
    // test = CDS_TEST (asks the driver, changes nothing); save = CDS_UPDATEREGISTRY; neither = change now, not saved.
    // Returns 0 when it worked (DISP_CHANGE_SUCCESSFUL), 1 = restart needed, negative = refused.
    public static int Apply(string dev, int width, int height, int hz, bool test, bool save) {
        var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
        if (!EnumDisplaySettings(dev, -1, ref dm)) return -100;
        dm.dmPelsWidth = width; dm.dmPelsHeight = height; dm.dmDisplayFrequency = hz;
        dm.dmFields = 0x80000 | 0x100000 | 0x400000;
        return ChangeDisplaySettingsEx(dev, ref dm, IntPtr.Zero, test ? 2 : (save ? 1 : 0), IntPtr.Zero);
    }
    // Back to the mode saved in the registry (what it was before a not-saved change).
    public static int RevertToSaved(string dev) { return ChangeDisplaySettingsExNull(dev, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero); }
}
'@

# $script:DisplayDryRun = $true makes every change a CDS_TEST (driver is asked, nothing changes) - used by the tests.
if (-not (Get-Variable -Name DisplayDryRun -Scope Script -ErrorAction SilentlyContinue)) { $script:DisplayDryRun = $false }
function Get-DisplayModes { @([HallowDisplayMode]::List()) }
function Get-DisplayName($Mon, [int]$Index) {
    $n = if ($Mon.Monitor -and $Mon.Monitor -notmatch '^Generic') { $Mon.Monitor } else { 'Monitor' }
    "Screen {0}{1} - {2}" -f $Index, $(if ($Mon.Primary) { ' (main)' } else { '' }), $n
}
function Set-DisplayHzTemporary($Mon, [int]$Hz) {
    $t = [HallowDisplayMode]::Apply($Mon.Device, $Mon.Width, $Mon.Height, $Hz, $true, $false)
    if ($t -ne 0) { return "The driver refused $Hz Hz at $($Mon.Width)x$($Mon.Height) (code $t) - nothing changed." }
    if ($script:DisplayDryRun) { return $null }
    $r = [HallowDisplayMode]::Apply($Mon.Device, $Mon.Width, $Mon.Height, $Hz, $false, $false)
    if ($r -ne 0) { [void][HallowDisplayMode]::RevertToSaved($Mon.Device); return "Windows could not switch to $Hz Hz (code $r) - nothing changed." }
    $null
}
function Save-DisplayHz($Mon, [int]$Hz) {
    if ($script:DisplayDryRun) { return 0 }
    [HallowDisplayMode]::Apply($Mon.Device, $Mon.Width, $Mon.Height, $Hz, $false, $true)
}
function Restore-DisplayHz($Mon) {
    if ($script:DisplayDryRun) { return $true }
    [void][HallowDisplayMode]::RevertToSaved($Mon.Device)
    $now = @(Get-DisplayModes | Where-Object { $_.Device -eq $Mon.Device })[0]
    if ($now -and $now.Hz -ne $Mon.Hz) { [void][HallowDisplayMode]::Apply($Mon.Device, $Mon.Width, $Mon.Height, $Mon.Hz, $false, $true) }   # belt and braces
    $true
}

# ================================================================ RAW INPUT (mouse report rate, keyboard keys)
# Listens on one window only (raw input, no hooks) and only while that window is in front.
Import-HallowType 'HallowRawInput' @'
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices; using System.Windows.Forms;
public class HallowRawInput : NativeWindow {
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort UsagePage, Usage; public uint Flags; public IntPtr Target; }
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] d, uint n, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint hdrSize);
    bool mouse, keyboard; IntPtr buf = IntPtr.Zero; uint bufSize = 0;
    static readonly double TickMs = 1000.0 / Stopwatch.Frequency;
    // mouse
    public long Reports; long last; double[] gaps = new double[1024]; int gapCount, gapNext;
    Queue<long> window = new Queue<long>(); public int PerSecond, PeakPerSecond; public long LastMoveTick;
    // keyboard: key ids are VK codes, made left/right specific; numpad Enter = 0x10D
    public HashSet<int> Down = new HashSet<int>(); public HashSet<int> Seen = new HashSet<int>(); public int MaxDown; public int LastKey = -1; public long KeyEvents;
    public HallowRawInput(IntPtr hwnd, bool wantMouse, bool wantKeyboard) {
        mouse = wantMouse; keyboard = wantKeyboard; AssignHandle(hwnd); Register(false);
    }
    void Register(bool remove) {
        var l = new List<RAWINPUTDEVICE>();
        if (mouse) l.Add(new RAWINPUTDEVICE { UsagePage = 1, Usage = 2, Flags = remove ? 1u : 0u, Target = remove ? IntPtr.Zero : Handle });
        if (keyboard) l.Add(new RAWINPUTDEVICE { UsagePage = 1, Usage = 6, Flags = remove ? 1u : 0u, Target = remove ? IntPtr.Zero : Handle });
        RegisterRawInputDevices(l.ToArray(), (uint)l.Count, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
    }
    public void Stop() { Register(true); if (Handle != IntPtr.Zero) ReleaseHandle(); if (buf != IntPtr.Zero) { Marshal.FreeHGlobal(buf); buf = IntPtr.Zero; } }
    public void Reset() { Reports = 0; gapCount = 0; gapNext = 0; window.Clear(); PerSecond = 0; PeakPerSecond = 0; Down.Clear(); Seen.Clear(); MaxDown = 0; LastKey = -1; KeyEvents = 0; }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x00FF) { try { Read(m.LParam); } catch { } }
        base.WndProc(ref m);
    }
    void Read(IntPtr h) {
        uint hdr = (uint)(8 + 2 * IntPtr.Size), size = 0;
        GetRawInputData(h, 0x10000003, IntPtr.Zero, ref size, hdr);
        if (size == 0) return;
        if (size > bufSize) { if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf); buf = Marshal.AllocHGlobal((int)size); bufSize = size; }
        if (GetRawInputData(h, 0x10000003, buf, ref size, hdr) != size) return;
        int type = Marshal.ReadInt32(buf, 0); int o = (int)hdr;
        if (type == 0 && mouse) {
            int dx = Marshal.ReadInt32(buf, o + 12), dy = Marshal.ReadInt32(buf, o + 16);
            if (dx != 0 || dy != 0) Move(Stopwatch.GetTimestamp());
        } else if (type == 1 && keyboard) {
            int make = (ushort)Marshal.ReadInt16(buf, o), flags = (ushort)Marshal.ReadInt16(buf, o + 2), vk = (ushort)Marshal.ReadInt16(buf, o + 6);
            Key(vk, make, (flags & 2) != 0, (flags & 1) != 0);
        }
    }
    // one mouse report that moved (public so the tests can feed fake timings)
    public void Move(long t) {
        Reports++; LastMoveTick = t;
        if (last != 0) { double gap = (t - last) * TickMs; if (gap < 40) { gaps[gapNext] = gap; gapNext = (gapNext + 1) % gaps.Length; if (gapCount < gaps.Length) gapCount++; } }
        last = t;
        window.Enqueue(t); long cut = t - Stopwatch.Frequency; while (window.Count > 0 && window.Peek() < cut) window.Dequeue();
        PerSecond = window.Count; if (PerSecond > PeakPerSecond) PeakPerSecond = PerSecond;
    }
    // Report rate from the median gap between reports while the mouse keeps moving (0 = not enough data yet).
    public double Rate() {
        if (gapCount < 50) return 0;
        var a = new double[gapCount]; Array.Copy(gaps, a, gapCount); Array.Sort(a);
        double med = a[gapCount / 2]; return med > 0 ? 1000.0 / med : 0;
    }
    public bool Moving() { return LastMoveTick != 0 && (Stopwatch.GetTimestamp() - LastMoveTick) * TickMs < 150; }
    public int KeyId(int vk, int make, bool e0) {
        if (vk == 0x10) return make == 0x36 ? 0xA1 : 0xA0;
        if (vk == 0x11) return e0 ? 0xA3 : 0xA2;
        if (vk == 0x12) return e0 ? 0xA5 : 0xA4;
        if (vk == 0x0D) return e0 ? 0x10D : 0x0D;
        if (!e0) {   // the numpad with Num Lock off sends the navigation keys without the E0 prefix
            switch (vk) { case 0x24: return 0x67; case 0x26: return 0x68; case 0x21: return 0x69; case 0x25: return 0x64; case 0x0C: return 0x65;
                case 0x27: return 0x66; case 0x23: return 0x61; case 0x28: return 0x62; case 0x22: return 0x63; case 0x2D: return 0x60; case 0x2E: return 0x6E; }
        }
        return vk;
    }
    public void Key(int vk, int make, bool e0, bool up) {
        if (vk == 0xFF || vk == 0) return;
        int id = KeyId(vk, make, e0); KeyEvents++;
        if (up) Down.Remove(id); else { Down.Add(id); Seen.Add(id); LastKey = id; if (Down.Count > MaxDown) MaxDown = Down.Count; }
    }
}
'@ @('System.Windows.Forms')

# ================================================================ MOTION / FRAME-SKIP TEST (full screen, Esc exits)
Import-HallowType 'HallowMotionTest' @'
using System; using System.Collections.Generic; using System.Diagnostics; using System.Drawing; using System.Drawing.Drawing2D; using System.Runtime.InteropServices; using System.Windows.Forms;
public class HallowMotionTest : Form {
    [DllImport("dwmapi.dll")] static extern int DwmFlush();
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint msg; public IntPtr w, l; public uint time; public int x, y; }
    [DllImport("user32.dll")] static extern bool PeekMessage(out MSG m, IntPtr h, uint min, uint max, uint remove);
    public long Frame; public double Fps; public int Drops; public int SetHz; public Color Accent = Color.FromArgb(139, 92, 246);
    Stopwatch sw = Stopwatch.StartNew(); double lastMs; Queue<double> times = new Queue<double>();
    public HallowMotionTest(Rectangle bounds, int hz) {
        SetHz = hz > 0 ? hz : 60;
        FormBorderStyle = FormBorderStyle.None; StartPosition = FormStartPosition.Manual; Bounds = bounds; BackColor = Color.Black;
        DoubleBuffered = true; KeyPreview = true; TopMost = true; ShowInTaskbar = false; Text = "Motion test";
        KeyDown += (s, e) => { if (e.KeyCode == Keys.Escape || e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) Close(); };
        MouseClick += (s, e) => { if (e.Button == MouseButtons.Right) Close(); };
        Shown += (s, e) => { Cursor.Hide(); Application.Idle += OnIdle; };
        FormClosed += (s, e) => { Application.Idle -= OnIdle; Cursor.Show(); };
    }
    void OnIdle(object s, EventArgs e) {
        MSG m;
        while (!IsDisposed && Visible && !PeekMessage(out m, IntPtr.Zero, 0, 0, 0)) {
            DwmFlush(); Step(sw.Elapsed.TotalMilliseconds); Invalidate(); Update();
        }
    }
    // one displayed frame at time ms (public so the tests can feed fake timings)
    public void Step(double ms) {
        Frame++;
        if (Frame > 30 && lastMs > 0) { double expect = 1000.0 / SetHz, gap = ms - lastMs; if (gap > expect * 1.5) Drops += (int)Math.Round(gap / expect) - 1; }
        lastMs = ms; times.Enqueue(ms); while (times.Count > 0 && times.Peek() < ms - 1000) times.Dequeue();
        Fps = times.Count > 1 ? (times.Count - 1) * 1000.0 / (ms - times.Peek()) : 0;
    }
    protected override void OnPaint(PaintEventArgs e) { Render(e.Graphics, ClientSize.Width, ClientSize.Height, Frame, Fps, SetHz, Drops, Accent); }
    public static void Render(Graphics g, int w, int h, long frame, double fps, int hz, int drops, Color accent) {
        g.Clear(Color.FromArgb(12, 12, 14));
        using (var f = new Font("Segoe UI", 14f, FontStyle.Bold)) using (var fs = new Font("Segoe UI", 11f)) using (var white = new SolidBrush(Color.White)) using (var mut = new SolidBrush(Color.FromArgb(160, 160, 170))) {
            string head = fps > 0 ? string.Format("Showing {0:0.0} frames a second - screen set to {1} Hz", fps, hz) : string.Format("Screen set to {0} Hz - measuring...", hz);
            g.DrawString(head, f, white, 40, 30);
            bool ok = fps <= 0 || Math.Abs(fps - hz) <= Math.Max(2, hz * 0.03);
            string verdict = fps <= 0 ? "" : ok ? "Matches the refresh rate - every frame reaches the screen." : "Lower than the refresh rate - something is holding frames back (V-Sync, another app, a slow cable or mode).";
            using (var vb = new SolidBrush(ok ? Color.FromArgb(80, 200, 120) : Color.FromArgb(240, 180, 60))) g.DrawString(verdict, fs, vb, 40, 62);
            g.DrawString(string.Format("Skipped frames: {0}", drops), fs, drops > 0 ? (Brush)new SolidBrush(Color.FromArgb(240, 180, 60)) : mut, 40, 86);
            // three lanes of moving blocks: the same block at 3 speeds (pixels per second)
            int[] speeds = { 480, 960, 1920 }; int laneTop = 150, laneH = Math.Max(90, (h - 420) / 3);
            for (int i = 0; i < 3; i++) {
                int y = laneTop + i * laneH; int bw = 120, bh = Math.Min(80, laneH - 30);
                double step = (double)speeds[i] / hz; int span = w + bw;
                int x = (int)((frame * step) % span) - bw;
                using (var lane = new SolidBrush(Color.FromArgb(24, 24, 30))) g.FillRectangle(lane, 0, y, w, bh + 10);
                using (var b = new SolidBrush(accent)) g.FillRectangle(b, x, y + 5, bw, bh);
                g.FillRectangle(white, x + bw / 2 - 4, y + 5, 8, bh);   // sharp edge: blur and ghosting show as a smear around it
                g.DrawString(speeds[i] + " px/s", fs, mut, 40, y + bh + 12);
            }
            // frame-skip row: one square lights per frame
            int cells = 20, cw = Math.Min(48, (w - 80) / cells - 6), cy = h - 200;
            g.DrawString("Frame-skip check: photograph this row with your phone (shutter about 1/10 s). Lit squares should form one unbroken run - gaps mean skipped frames.", fs, mut, 40, cy - 34);
            using (var off = new SolidBrush(Color.FromArgb(40, 40, 48)))
                for (int c = 0; c < cells; c++) g.FillRectangle(frame % cells == c ? white : (Brush)off, 40 + c * (cw + 6), cy, cw, cw);
            g.DrawString("Esc, Space or right-click to close", fs, mut, 40, h - 70);
        }
    }
}
'@ @('System.Windows.Forms', 'System.Drawing')

# ================================================================ ROUTE TO A SERVER (traceroute with pings, background runspace)
# $Out: synchronized ArrayList the window reads while it runs. Gentle: 2 tries per hop, 25 hops max.
$TraceRouteWork = {
    param([string]$Target, $Out, [int]$MaxHops = 25)
    $ping = New-Object System.Net.NetworkInformation.Ping
    $buf = New-Object byte[] 32
    $dest = $null
    try { $dest = ([System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1) } catch { }
    if (-not $dest) { [void]$Out.Add([pscustomobject]@{ Hop = 0; Address = ''; Ms = ''; Note = "Could not find '$Target'" }); return 'failed' }
    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        $addr = $null; $times = @(); $reached = $false
        for ($try = 0; $try -lt 2; $try++) {
            try {
                $opt = New-Object System.Net.NetworkInformation.PingOptions($ttl, $true)
                $sw = [Diagnostics.Stopwatch]::StartNew()
                $r = $ping.Send($dest, 1000, $buf, $opt)
                $ms = [math]::Round($sw.Elapsed.TotalMilliseconds)
                if ($r.Status -eq 'TtlExpired' -or $r.Status -eq 'Success') { $addr = $r.Address.ToString(); $times += $ms; if ($r.Status -eq 'Success') { $reached = $true } }
            } catch { }
        }
        $note = if (-not $addr) { 'no reply (many routers ignore pings - normal)' } elseif ($reached) { 'reached - the address you picked' } elseif ($ttl -eq 1) { 'your router' } elseif ($addr -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)') { 'private network (your provider)' } else { '' }
        [void]$Out.Add([pscustomobject]@{ Hop = $ttl; Address = $(if ($addr) { $addr } else { '*' }); Ms = $(if ($times) { "$(($times | Measure-Object -Minimum).Minimum) ms" } else { '-' }); Note = $note })
        if ($reached) { return 'done' }
    }
    'max hops'
}

function Get-RouterAddress {
    $a = Get-MainAdapter; if (-not $a) { return $null }
    try { (Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction Stop).IPv4DefaultGateway | Select-Object -First 1 -ExpandProperty NextHop } catch { $null }
}

# Hallow Overlay shares the game server's host name in status.json (live.region) only when "Hide the server's IP" is off.
function Get-OverlayServerHost {
    try {
        $st = Get-Content (Join-Path $env:APPDATA 'HallowOverlay\status.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if (-not $st.live -or $st.live.pingTo -ne 'server') { return $null }
        if (((Get-Date) - [datetime]$st.live.updated).TotalMinutes -gt 2) { return $null }
        $r = "$($st.live.region)"
        if ($r -match '^[A-Za-z0-9][A-Za-z0-9\.\-]*\.[A-Za-z0-9\-]+$' -or $r -match '^\d{1,3}(\.\d{1,3}){3}$') { return [pscustomobject]@{ Host = $r; Game = "$($st.live.game)" } }
    } catch { }
    $null
}

# ================================================================ DNS UNDO
# Before the toolkit changes DNS it notes what the adapter had (static servers, or automatic from the router).
function Get-AdapterDnsState($Adapter) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($Adapter.InterfaceGuid)"
    $static = "$(Get-RegValue $key 'NameServer')".Trim()
    [pscustomobject]@{ IfIndex = $Adapter.ifIndex; Adapter = $Adapter.Name; Servers = @($static -split '[,\s]+' | Where-Object { $_ }); Time = (Get-Date).ToString('s') }
}
function Save-DnsUndo($Adapter) {
    $s = Get-Settings
    if ($s.PSObject.Properties.Name -contains 'DnsUndo' -and $s.DnsUndo -and $s.DnsUndo.Adapter -eq $Adapter.Name) { return }   # keep the setting from before the first change
    $s | Add-Member -NotePropertyName DnsUndo -NotePropertyValue (Get-AdapterDnsState $Adapter) -Force; Save-Settings $s
}
function Get-DnsUndo { $s = Get-Settings; if ($s.PSObject.Properties.Name -contains 'DnsUndo') { $s.DnsUndo } else { $null } }
function Undo-DnsChange {
    $u = Get-DnsUndo
    if (-not $u) { Log 'No DNS change to undo - the toolkit has not changed DNS (or it was already undone).'; return }
    if (-not (Need-Admin 'Changing DNS')) { return }
    $a = Get-NetAdapter -Name $u.Adapter -ErrorAction SilentlyContinue
    if (-not $a) { Log "The adapter '$($u.Adapter)' is not here any more - nothing changed."; return }
    $srv = @($u.Servers | Where-Object { $_ })
    if ($srv) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $srv; Log "DNS on $($a.Name) put back to $($srv -join ', ') (what it was before the toolkit changed it)." }
    else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses; Log "DNS on $($a.Name) put back to automatic (from your router), as it was before." }
    Clear-DnsClientCache
    $s = Get-Settings; $s.PSObject.Properties.Remove('DnsUndo'); Save-Settings $s
}

# ================================================================ VERIFY GAME FILES
# Steam verifies in one click; the other launchers have no public link for it, so the toolkit opens them and says where to click.
function Get-GameStore($Game) {
    if ($Game.Store -eq 'Steam' -or $Game.Store -eq 'Xbox' -or $Game.Store -eq 'Epic') { return $Game.Store }
    switch -Regex ("$($Game.Path)") { 'Epic Games' { 'Epic' } 'EA Games|\\EA\\|Origin Games' { 'EA' } 'Ubisoft' { 'Ubisoft' } 'Riot Games' { 'Riot' } 'Battle\.net|Blizzard' { 'Battle.net' } default { 'Other' } }
}
function Get-VerifyPlan($Game) {
    $store = Get-GameStore $Game
    switch ($store) {
        'Steam' { [pscustomobject]@{ Store = $store; Uri = "steam://validate/$($Game.Id)"; Steps = "Steam checks every file of $($Game.Name) and downloads only what's broken or missing. Progress shows in Steam > Downloads." } }
        'Epic' { [pscustomobject]@{ Store = $store; Uri = 'com.epicgames.launcher://'; Steps = "In the Epic Games Launcher: Library > the three dots on $($Game.Name) > Manage > Verify." } }
        'EA' { [pscustomobject]@{ Store = $store; Uri = $null; Steps = "Open the EA app: Library > the three dots on $($Game.Name) > Repair." } }
        'Ubisoft' { [pscustomobject]@{ Store = $store; Uri = 'uplay://'; Steps = "In Ubisoft Connect: Games > $($Game.Name) > Properties > Verify files." } }
        'Battle.net' { [pscustomobject]@{ Store = $store; Uri = 'battlenet://'; Steps = "In Battle.net: pick $($Game.Name), click the gear next to Play > Scan and Repair." } }
        'Riot' { [pscustomobject]@{ Store = $store; Uri = $null; Steps = "Open the Riot Client, click your profile > Settings > $($Game.Name) > Repair." } }
        'Xbox' { [pscustomobject]@{ Store = $store; Uri = 'xbox:'; Steps = "In the Xbox app: right-click $($Game.Name) > Manage > Files > Verify and repair." } }
        default { [pscustomobject]@{ Store = $store; Uri = $null; Steps = "$($Game.Name) isn't from a launcher the toolkit knows - use its own launcher's repair or verify option." } }
    }
}
function Invoke-VerifyGame($Game) {
    $running = Get-RunningGameNow
    if ($running -and $Game.Path -and (Split-Path $Game.Path -Leaf) -eq "$running") { Log "Close $($Game.Name) first - files can't be checked while the game runs."; return }
    $p = Get-VerifyPlan $Game
    if ($p.Uri) { try { Start-Process $p.Uri -ErrorAction Stop } catch { Log "Couldn't open $($p.Store) - is it installed?" } }
    Log "Verify files - $($Game.Name) ($($p.Store)): $($p.Steps)"
}
