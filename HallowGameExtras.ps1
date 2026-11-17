<#
  Hallow Toolkit - launcher cache cleaner, controller check (XInput), game priority boost and saved Wi-Fi passwords.
  No window code. Dot-sourced by HallowCore.ps1.
#>

# ================================================================ LAUNCHER CACHES
# Only web/download caches and logs - never games, saves, settings or login data. Each launcher rebuilds these itself.
$LauncherCaches = @(
    @{ App = 'Steam'; Proc = 'steam', 'steamwebhelper'; What = 'store/web page cache'; Path = "$env:LOCALAPPDATA\Steam\htmlcache" }
    @{ App = 'Steam'; Proc = 'steam', 'steamwebhelper'; What = 'download cache'; Path = "${env:ProgramFiles(x86)}\Steam\appcache\httpcache" }
    @{ App = 'Steam'; Proc = 'steam', 'steamwebhelper'; What = 'old logs and crash dumps'; Path = "${env:ProgramFiles(x86)}\Steam\logs", "${env:ProgramFiles(x86)}\Steam\dumps" }
    @{ App = 'Epic Games'; Proc = 'EpicGamesLauncher', 'EpicWebHelper'; What = 'web cache and logs'; Path = "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache*", "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs" }
    @{ App = 'Battle.net'; Proc = 'Battle.net', 'Agent'; What = 'web cache'; Path = "$env:LOCALAPPDATA\Battle.net\Cache", "$env:LOCALAPPDATA\Battle.net\BrowserCaches" }
    @{ App = 'EA app'; Proc = 'EADesktop', 'EABackgroundService'; What = 'web cache and logs'; Path = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\CEF\BrowserCache", "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Logs" }
    @{ App = 'Ubisoft Connect'; Proc = 'upc', 'UbisoftConnect'; What = 'launcher cache (Ubisoft''s own fix for a stuck launcher)'; Path = "$env:LOCALAPPDATA\Ubisoft Game Launcher\cache" }
    @{ App = 'Riot Client'; Proc = 'RiotClientServices', 'RiotClientUx'; What = 'web cache and logs'; Path = "$env:LOCALAPPDATA\Riot Games\Riot Client\Data\Cache", "$env:LOCALAPPDATA\Riot Games\Riot Client\Logs" }
    @{ App = 'GOG Galaxy'; Proc = 'GalaxyClient'; What = 'web cache'; Path = "$env:LOCALAPPDATA\GOG.com\Galaxy\webcache", "$env:ProgramData\GOG.com\Galaxy\webcache" }
    @{ App = 'Discord'; Proc = 'Discord'; What = 'image/video cache'; Path = "$env:APPDATA\discord\Cache", "$env:APPDATA\discord\Code Cache", "$env:APPDATA\discord\GPUCache" }
    @{ App = 'Medal'; Proc = 'Medal'; What = 'web cache'; Path = "$env:APPDATA\Medal\Cache" }
)

# Background-safe: returns one row per cache that exists and has something in it.
$LauncherCacheScanWork = {
    param($Caches)
    foreach ($c in $Caches) {
        $dirs = @(foreach ($p in $c.Path) { Get-Item $p -Force -ErrorAction SilentlyContinue | Where-Object PSIsContainer | ForEach-Object FullName })
        if (-not $dirs) { continue }
        $bytes = 0.0
        foreach ($d in $dirs) { $bytes += [double]((Get-ChildItem -LiteralPath $d -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) }
        if ($bytes -lt 1MB) { continue }
        $running = @(Get-Process -Name $c.Proc -ErrorAction SilentlyContinue).Count -gt 0
        [pscustomobject]@{ App = $c.App; What = $c.What; Bytes = $bytes; Dirs = $dirs; Running = $running; Proc = $c.Proc }
    }
}

function Clear-LauncherCaches($Rows) {
    Log '===== LAUNCHER CACHES ====='
    $freed = 0.0
    foreach ($r in $Rows) {
        if (@(Get-Process -Name $r.Proc -ErrorAction SilentlyContinue).Count) { Log "  $($r.App) is open - skipped. Close it (and its tray icon) and run this again."; continue }
        $before = $r.Bytes
        foreach ($d in $r.Dirs) {
            Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        $left = 0.0; foreach ($d in $r.Dirs) { $left += [double]((Get-ChildItem -LiteralPath $d -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) }
        $freed += [math]::Max(0.0, $before - $left)
        Log ("  {0} {1}: freed {2}" -f $r.App, $r.What, (Format-Size ($before - $left)))
    }
    Log "Freed $(Format-Size $freed) in total. Launchers rebuild these caches as needed - games, saves and logins are untouched."
}

# ================================================================ CONTROLLERS (XInput: Xbox and most PC pads)
Import-HallowType 'HallowPad' @'
using System; using System.Runtime.InteropServices;
public static class HallowPad {
    [StructLayout(LayoutKind.Sequential)] public struct GAMEPAD { public ushort Buttons; public byte LT, RT; public short LX, LY, RX, RY; }
    [StructLayout(LayoutKind.Sequential)] public struct STATE { public uint Packet; public GAMEPAD Pad; }
    [StructLayout(LayoutKind.Sequential)] public struct BATTERY { public byte Type, Level; }
    [DllImport("xinput1_4.dll")] static extern uint XInputGetState(uint i, out STATE s);
    [DllImport("xinput1_4.dll")] static extern uint XInputGetBatteryInformation(uint i, byte dev, out BATTERY b);
    public static bool Get(int i, out GAMEPAD p) { STATE s; bool ok = XInputGetState((uint)i, out s) == 0; p = s.Pad; return ok; }
    // returns -1 not connected/unknown, 0 wired, 1 empty, 2 low, 3 medium, 4 full
    public static int Battery(int i) { BATTERY b; if (XInputGetBatteryInformation((uint)i, 0, out b) != 0) return -1; if (b.Type == 1) return 0; if (b.Type == 0 || b.Type == 0xFF) return -1; return b.Level + 1; }
}
'@

$PadButtons = [ordered]@{ 'A' = 0x1000; 'B' = 0x2000; 'X' = 0x4000; 'Y' = 0x8000; 'LB' = 0x0100; 'RB' = 0x0200; 'Back' = 0x0020; 'Start' = 0x0010
    'LS' = 0x0040; 'RS' = 0x0080; 'Up' = 0x0001; 'Down' = 0x0002; 'Left' = 0x0004; 'Right' = 0x0008 }

# Other controllers Windows sees (PlayStation, Switch Pro, wheels, flight sticks...) - these don't show in XInput.
function Get-OtherControllers {
    @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -match 'game controller|gamepad|joystick|racing wheel|DualSense|DualShock|Wireless Controller|Pro Controller|8BitDo' -and
        $_.FriendlyName -notmatch 'Xbox|XINPUT'
    } | Select-Object -ExpandProperty FriendlyName -Unique)
}

# ================================================================ GAME PRIORITY (used by the tray app)
function Set-GamePriority([int]$ProcessId) {
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        if ($p.PriorityClass -eq 'High' -or $p.PriorityClass -eq 'RealTime') { return $null }
        $p.PriorityClass = 'High'; return $p.ProcessName
    } catch { return $null }   # anti-cheat protected games refuse - that's fine
}

# ================================================================ SAVED WI-FI PASSWORDS
# Returns Network, Password, Security for every Wi-Fi profile saved on this PC. Never logged or written to disk.
function Get-WifiPasswords {
    $names = @(netsh wlan show profiles 2>$null | ForEach-Object { if ($_ -match '^\s*All User Profile\s*:\s*(.+)$') { $Matches[1].Trim() } })
    foreach ($n in $names) {
        $out = netsh wlan show profile name="$n" key=clear 2>$null
        $key = ($out | ForEach-Object { if ($_ -match '^\s*Key Content\s*:\s*(.*)$') { $Matches[1] } } | Select-Object -First 1)
        $auth = ($out | ForEach-Object { if ($_ -match '^\s*Authentication\s*:\s*(.*)$') { $Matches[1].Trim() } } | Select-Object -First 1)
        [pscustomobject]@{ Network = $n; Password = $(if ($key) { $key } elseif ($auth -match 'Open') { '(open network - no password)' } else { '(hidden - open the toolkit as admin)' }); Security = $auth }
    }
}
