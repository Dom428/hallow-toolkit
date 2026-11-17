<#
  Hallow Toolkit - "game won't launch" check, audio switcher, Windows Update control, Steam library mover
  and the lag-under-load (bufferbloat) test. No window code. Dot-sourced by HallowCore.ps1.
#>

# ================================================================ GAME WON'T LAUNCH CHECK
# Rows: Area, Item, State ('OK' | 'Problem' | 'Note'), Detail, Fix (key for Repair-GameLaunch, or '')
$AntiCheatServices = [ordered]@{
    'EasyAntiCheat' = @('Easy Anti-Cheat', 'Manual'); 'EasyAntiCheat_EOS' = @('Easy Anti-Cheat (Epic)', 'Manual')
    'BEService' = @('BattlEye', 'Manual'); 'vgc' = @('Riot Vanguard', 'Automatic'); 'FACEIT' = @('FACEIT Anti-Cheat', 'Manual')
    'PnkBstrA' = @('PunkBuster', 'Manual'); 'mhyprot3' = @('HoYoverse anti-cheat', 'Manual')
}
$LaunchRuntimes = @(
    @{ Item = 'Visual C++ 2015-2022 (64-bit)'; Id = 'Microsoft.VCRedist.2015+.x64'; Test = { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue).Installed -eq 1 } }
    @{ Item = 'Visual C++ 2015-2022 (32-bit)'; Id = 'Microsoft.VCRedist.2015+.x86'; Test = { (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86' -ErrorAction SilentlyContinue).Installed -eq 1 } }
    @{ Item = 'DirectX 9/10/11 extras (d3dx9, xinput1_3...)'; Id = 'Microsoft.DirectX'; Test = { (Test-Path "$env:WINDIR\System32\d3dx9_43.dll") -and (Test-Path "$env:WINDIR\SysWOW64\d3dx9_43.dll") -and (Test-Path "$env:WINDIR\System32\xinput1_3.dll") } }
    @{ Item = '.NET 8 Desktop Runtime'; Id = 'Microsoft.DotNet.DesktopRuntime.8'; Test = { [bool](Get-ChildItem "$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App" -Directory -Filter '8.*' -ErrorAction SilentlyContinue) } }
    @{ Item = 'Edge WebView2 (launchers use it)'; Id = 'Microsoft.EdgeWebView2Runtime'; Test = { [bool]((Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue).pv) } }
)
$OverlayProcs = [ordered]@{ 'RTSS' = 'RivaTuner overlay'; 'MSIAfterburner' = 'MSI Afterburner'; 'Overwolf' = 'Overwolf'; 'Medal' = 'Medal'; 'obs64' = 'OBS (game capture)'; 'NVIDIA Overlay' = 'NVIDIA overlay'; 'GameBar' = 'Xbox Game Bar' }

function Get-GameLaunchCheck {
    foreach ($r in $LaunchRuntimes) {
        $ok = [bool](& $r.Test)
        [pscustomobject]@{ Area = 'Runtime'; Item = $r.Item; State = $(if ($ok) { 'OK' } else { 'Problem' }); Detail = $(if ($ok) { 'Installed' } else { 'Missing - many games need this ("missing .dll" errors)' }); Fix = $(if ($ok) { '' } else { "winget:$($r.Id)" }) }
    }
    foreach ($k in $AntiCheatServices.Keys) {
        $s = Get-Service -Name $k -ErrorAction SilentlyContinue
        if (-not $s) { continue }
        $bad = $s.StartType -eq 'Disabled'
        [pscustomobject]@{ Area = 'Anti-cheat'; Item = $AntiCheatServices[$k][0]; State = $(if ($bad) { 'Problem' } else { 'OK' })
            Detail = $(if ($bad) { 'Turned off (Disabled) - games that use it won''t start' } else { "Ready ($($s.StartType), $($s.Status.ToString().ToLower()))" }); Fix = $(if ($bad) { "service:$k" } else { '' }) }
    }
    $cfa = $null; try { $cfa = (Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess } catch { }
    if ($cfa -eq 1) {
        [pscustomobject]@{ Area = 'Windows Security'; Item = 'Controlled folder access is ON'; State = 'Problem'; Detail = 'Blocks games from writing saves/settings in Documents - games crash on save or won''t start. Allow the game, or turn it off.'; Fix = 'open:cfa' }
    } elseif ($cfa -eq 0) { [pscustomobject]@{ Area = 'Windows Security'; Item = 'Controlled folder access'; State = 'OK'; Detail = 'Off - not blocking game saves'; Fix = '' } }
    $reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    if ($reboot) { [pscustomobject]@{ Area = 'Windows'; Item = 'Restart pending'; State = 'Problem'; Detail = 'An update is waiting for a restart - anti-cheat and new drivers often fail until you restart'; Fix = '' } }
    foreach ($d in @(Get-DriveSpace)) {
        if ($d.FreePct -lt 5) { [pscustomobject]@{ Area = 'Storage'; Item = "Drive $($d.Drive) almost full"; State = 'Problem'; Detail = ('{0} GB free - games fail to update or patch' -f $d.FreeGB); Fix = '' } }
    }
    foreach ($k in $OverlayProcs.Keys) {
        if (Get-Process -Name $k -ErrorAction SilentlyContinue) { [pscustomobject]@{ Area = 'Overlay'; Item = $OverlayProcs[$k]; State = 'Note'; Detail = 'Running - if one game crashes at start, close this and try again'; Fix = '' } }
    }
}

# Background-safe: installs missing runtimes with winget. Items = winget IDs.
$LaunchRuntimeInstallWork = {
    param([string[]]$Ids)
    foreach ($id in $Ids) {
        "Installing $id ..."
        $null = winget install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        $hex = '0x{0:X8}' -f $LASTEXITCODE
        if ($LASTEXITCODE -eq 0 -or $hex -in '0x8A150061', '0x8A15002B') { '   done' } elseif ($hex -eq '0x8A150109') { '   done - restart the PC to finish' } else { "   failed (winget code $hex)" }
    }
}

# ================================================================ AUDIO SWITCHER (speakers <-> headset)
Import-HallowType 'HallowAudioOut' @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public class HallowAudioDevice { public string Id; public string Name; public bool IsDefault; }
public static class HallowAudioOut {
    [StructLayout(LayoutKind.Sequential)] public struct PKEY { public Guid fmtid; public int pid; public PKEY(Guid g, int p) { fmtid = g; pid = p; } }
    [StructLayout(LayoutKind.Sequential)] public struct PROPVARIANT { public ushort vt; public ushort r1, r2, r3; public IntPtr p; public IntPtr p2; }
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);
    // COM objects are created by CLSID (not [ComImport] classes) so this never clashes with HallowMic's identical classes
    static object Create(string clsid) { return Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid(clsid))); }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IMMDeviceCollection list);
        [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev);
    }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection { [PreserveSig] int GetCount(out uint n); [PreserveSig] int Item(uint i, out IMMDevice dev); }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
        [PreserveSig] int OpenPropertyStore(int access, out IPropertyStore ps);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    }
    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        [PreserveSig] int GetCount(out int n); [PreserveSig] int GetAt(int i, out PKEY k); [PreserveSig] int GetValue(ref PKEY k, out PROPVARIANT v);
    }
    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig {
        [PreserveSig] int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, out IntPtr f);
        [PreserveSig] int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, int def, out IntPtr f);
        [PreserveSig] int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
        [PreserveSig] int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr f, IntPtr m);
        [PreserveSig] int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, int def, out long a, out long b);
        [PreserveSig] int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr p);
        [PreserveSig] int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr m);
        [PreserveSig] int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr m);
        [PreserveSig] int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, int fx, ref PKEY k, out PROPVARIANT v);
        [PreserveSig] int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, int fx, ref PKEY k, ref PROPVARIANT v);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
    }
    static readonly PKEY FriendlyName = new PKEY(new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), 14);
    static IMMDeviceEnumerator Enum() { return (IMMDeviceEnumerator)Create("BCDE0395-E52F-467C-8E3D-C4579291692E"); }
    // flow: 0 = speakers/headphones (render), 1 = mics (capture)
    public static string DefaultId(int flow) {
        IMMDevice d; if (Enum().GetDefaultAudioEndpoint(flow, 0, out d) < 0 || d == null) return null;
        string id; d.GetId(out id); return id;
    }
    public static List<HallowAudioDevice> List(int flow) {
        var res = new List<HallowAudioDevice>(); string def = DefaultId(flow);
        IMMDeviceCollection col; if (Enum().EnumAudioEndpoints(flow, 1, out col) < 0) return res;
        uint n; col.GetCount(out n);
        for (uint i = 0; i < n; i++) {
            IMMDevice d; if (col.Item(i, out d) < 0) continue;
            var a = new HallowAudioDevice(); d.GetId(out a.Id); a.IsDefault = a.Id == def; a.Name = a.Id;
            IPropertyStore ps; if (d.OpenPropertyStore(0, out ps) >= 0) { PKEY k = FriendlyName; PROPVARIANT v; if (ps.GetValue(ref k, out v) >= 0) { if (v.vt == 31) a.Name = Marshal.PtrToStringUni(v.p); PropVariantClear(ref v); } }
            res.Add(a);
        }
        return res;
    }
    // sets the device as default for games/apps (0), media (1) and calls (2)
    public static void SetDefault(string id) {
        var pc = (IPolicyConfig)Create("870af99c-171d-4f9e-af0d-e63df40c2bc9");
        for (int role = 0; role < 3; role++) { int hr = pc.SetDefaultEndpoint(id, role); if (hr < 0) throw new Exception("Setting the default device failed (0x" + hr.ToString("X8") + ")"); }
    }
}
'@

# Settings.AudioSetups = @( @{ Name; Out; OutName; Mic; MicName }, @{ ... } ) - two setups to flip between.
function Get-AudioSetups { $s = Get-Settings; if ($s.PSObject.Properties.Name -contains 'AudioSetups' -and $s.AudioSetups) { @($s.AudioSetups) } else { @() } }
function Switch-AudioSetup([int]$To = -1) {
    $setups = @(Get-AudioSetups | Where-Object { $_.Out })
    if ($setups.Count -lt 2) { return 'Set up both audio setups first (Mic tab > Audio switcher).' }
    $outs = @([HallowAudioOut]::List(0)); $mics = @([HallowAudioOut]::List(1))
    if ($To -lt 0) { $cur = [HallowAudioOut]::DefaultId(0); $To = $(if ($cur -eq $setups[0].Out) { 1 } else { 0 }) }
    $t = $setups[$To]
    if (-not ($outs | Where-Object Id -eq $t.Out)) { return "$($t.OutName) isn't plugged in or is turned off." }
    [HallowAudioOut]::SetDefault($t.Out)
    $msg = "Audio: $($t.Name) - sound to $($t.OutName)"
    if ($t.Mic) {
        if ($mics | Where-Object Id -eq $t.Mic) { [HallowAudioOut]::SetDefault($t.Mic); $msg += ", mic $($t.MicName)" }
        else { $msg += " (mic $($t.MicName) isn't plugged in)" }
    }
    $msg
}

# ================================================================ WINDOWS UPDATE CONTROL
$WuPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
function Test-WuDriversBlocked { (Get-ItemProperty $WuPolicyKey -ErrorAction SilentlyContinue).ExcludeWUDriversInQualityUpdate -eq 1 }
function Set-WuDriversBlocked([bool]$Block) {
    if (-not (Need-Admin 'Changing Windows Update driver settings')) { return }
    if ($Block) {
        if (-not (Test-Path $WuPolicyKey)) { New-Item $WuPolicyKey -Force | Out-Null }
        Set-ItemProperty $WuPolicyKey -Name ExcludeWUDriversInQualityUpdate -Value 1 -Type DWord
        Log 'Windows Update will no longer install drivers. Your NVIDIA and motherboard drivers stay the versions you picked (update them from the Drivers tab or the maker).'
    } else {
        Remove-ItemProperty $WuPolicyKey -Name ExcludeWUDriversInQualityUpdate -ErrorAction SilentlyContinue
        Log 'Windows Update may install drivers again (Windows default).'
    }
}
function Set-UpdatesPausedFor([int]$Days) {
    if (-not (Need-Admin 'Pausing Windows Update')) { return }
    if ($Days -le 0) { foreach ($n in $WuPauseNames) { Remove-ItemProperty $WuPauseKey -Name $n -ErrorAction SilentlyContinue }; Log 'Windows Update resumed - it will check for updates again.'; return }
    if (-not (Test-Path $WuPauseKey)) { New-Item $WuPauseKey -Force | Out-Null }
    $now = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); $end = [datetime]::UtcNow.AddDays($Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
    foreach ($n in $WuPauseNames) { Set-ItemProperty $WuPauseKey -Name $n -Value $(if ($n -match 'Start') { $now } else { $end }) -Type String }
    Log ("Windows Update paused for {0} days (until {1:ddd d MMM}). Security updates wait too - don't leave it paused for long." -f $Days, (Get-Date).AddDays($Days))
}
$WuErrors = @{
    '0x80073D02' = 'the app was open while it updated - close it and retry'; '0x80070005' = 'access denied - run Windows Update again or restart'
    '0x800F0922' = 'not enough space on the system reserved partition, or VPN blocked it'; '0x80070070' = 'not enough disk space'
    '0x800F081F' = 'Windows files are damaged - Tune-up tab > Repair Windows files'; '0x8024402C' = 'could not reach Microsoft - check internet/VPN/DNS'
    '0x80240034' = 'download failed - retry'; '0x8007000D' = 'the download was corrupt - Tools > Quick fixes > Windows Update reset'
    '0x80070643' = 'installer failed (often .NET or Defender) - retry after a restart'; '0x800F0831' = 'a previous update is missing - Windows Update reset'
    '0x80244022' = 'Microsoft''s servers were busy - retry later'; '0x80246017' = 'download needs admin rights - retry'
}
# Background-safe: the last 60 Windows Update installs, newest first.
$WuHistoryWork = {
    $sess = New-Object -ComObject Microsoft.Update.Session
    $srch = $sess.CreateUpdateSearcher()
    $n = $srch.GetTotalHistoryCount()
    if ($n -le 0) { return }
    foreach ($h in $srch.QueryHistory(0, [math]::Min(60, $n))) {
        if (-not $h.Title) { continue }
        $res = switch ($h.ResultCode) { 1 { 'In progress' } 2 { 'Installed' } 3 { 'Installed (with errors)' } 4 { 'Failed' } 5 { 'Cancelled' } default { 'Unknown' } }
        [pscustomobject]@{ Date = $h.Date.ToLocalTime(); Title = $h.Title; Result = $res; Code = $(if ($h.HResult) { '0x{0:X8}' -f $h.HResult } else { '' }) }
    }
}

# ================================================================ STEAM LIBRARY MOVER
function Read-AcfValue([string]$Text, [string]$Key) { if ($Text -match "(?m)^\s*`"$Key`"\s+`"([^`"]*)`"") { $Matches[1] } }
function Get-SteamLibraryGames {
    foreach ($lib in @(Get-SteamLibraries)) {
        $apps = Join-Path $lib 'steamapps'
        foreach ($acf in Get-ChildItem $apps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
            $t = Get-Content -LiteralPath $acf.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $dir = Read-AcfValue $t 'installdir'; if (-not $dir) { continue }
            $full = Join-Path $apps "common\$dir"
            if (-not (Test-Path -LiteralPath $full)) { continue }
            [pscustomobject]@{ AppId = (Read-AcfValue $t 'appid'); Name = (Read-AcfValue $t 'name'); Library = $lib; InstallDir = $dir; Path = $full
                Bytes = [double](Read-AcfValue $t 'SizeOnDisk'); Manifest = $acf.FullName }
        }
    }
}
# Background-safe: moves one Steam game to another library. Steam must be closed (checked before starting).
$SteamMoveWork = {
    param([object[]]$Games, [string]$Target)
    foreach ($Game in $Games) {
    $dstApps = Join-Path $Target 'steamapps'
    $dst = Join-Path $dstApps "common\$($Game.InstallDir)"
    if (Test-Path -LiteralPath $dst) { "SKIPPED $($Game.Name): $dst already exists - the game seems to be in both places."; continue }
    "Moving $($Game.Name) to $Target ..."
    $null = robocopy $Game.Path $dst /E /MOVE /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { "FAILED $($Game.Name): robocopy error $LASTEXITCODE. Files already copied are in $dst - check both folders before starting Steam."; return }
    Move-Item -LiteralPath $Game.Manifest -Destination $dstApps -Force
    $ws = Join-Path (Split-Path $Game.Manifest) "workshop\content\$($Game.AppId)"
    if (Test-Path -LiteralPath $ws) {
        $null = robocopy $ws (Join-Path $dstApps "workshop\content\$($Game.AppId)") /E /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
        $wsAcf = Join-Path (Split-Path $Game.Manifest) "workshop\appworkshop_$($Game.AppId).acf"
        if (Test-Path -LiteralPath $wsAcf) { New-Item -ItemType Directory -Force (Join-Path $dstApps 'workshop') | Out-Null; Move-Item -LiteralPath $wsAcf -Destination (Join-Path $dstApps 'workshop') -Force }
        '   workshop mods moved too'
    }
    if (Test-Path -LiteralPath $Game.Path) { Remove-Item -LiteralPath $Game.Path -Recurse -Force -ErrorAction SilentlyContinue }
    "DONE: $($Game.Name) is now in $Target."
    }
    'Open Steam - it finds moved games in their new library by itself.'
}

# ================================================================ LAG UNDER LOAD (bufferbloat)
# Background-safe: ping while idle, while downloading and while uploading. Grade = how much the ping rises.
$BufferbloatWork = {
    $target = '1.1.1.1'
    # $Load: scriptblock that starts transfers and returns their tasks; restarted whenever they all finish, so the line stays busy
    function PingFor([double]$Seconds, [scriptblock]$Load) {
        $p = New-Object System.Net.NetworkInformation.Ping; $res = New-Object System.Collections.Generic.List[double]
        $tasks = @(); if ($Load) { $tasks = @(& $Load); Start-Sleep -Milliseconds 800 }
        $end = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $end) {
            if ($Load -and -not @($tasks | Where-Object { -not $_.IsCompleted }).Count) { $tasks = @(& $Load) }
            try { $r = $p.Send($target, 1000); if ($r.Status -eq 'Success') { $res.Add($r.RoundtripTime) } } catch { }
            Start-Sleep -Milliseconds 200
        }
        $res
    }
    function Median($a) { $s = @($a | Sort-Object); if (-not $s.Count) { return $null }; $s[[int][math]::Floor($s.Count / 2)] }
    function Grade($rise) { if ($null -eq $rise) { '?' } elseif ($rise -lt 5) { 'A+' } elseif ($rise -lt 30) { 'A' } elseif ($rise -lt 60) { 'B' } elseif ($rise -lt 200) { 'C' } elseif ($rise -lt 400) { 'D' } else { 'F' } }
    $idle = Median (PingFor 5)
    if ($null -eq $idle) { 'Could not ping Cloudflare (1.1.1.1) - check your connection or VPN.'; return }
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 16
    $down = Median (PingFor 8 { for ($i = 0; $i -lt 4; $i++) { (New-Object Net.WebClient).DownloadDataTaskAsync("https://speed.cloudflare.com/__down?bytes=50000000&r=$(Get-Random)") } })
    Start-Sleep -Seconds 3   # let the downloads drain
    $script:UpData = New-Object byte[] 20000000
    $up = Median (PingFor 8 { for ($i = 0; $i -lt 3; $i++) { (New-Object Net.WebClient).UploadDataTaskAsync('https://speed.cloudflare.com/__up', 'POST', $script:UpData) } })
    $rd = $(if ($null -ne $down) { $down - $idle }); $ru = $(if ($null -ne $up) { $up - $idle })
    $worst = @($rd, $ru | Where-Object { $null -ne $_ } | Sort-Object -Descending)[0]
    'Lag under load (bufferbloat) - ping to Cloudflare:'
    '  Idle:                {0,4} ms' -f $idle
    '  While downloading:   {0,4} ms   (+{1} ms)  grade {2}' -f $down, $rd, (Grade $rd)
    '  While uploading:     {0,4} ms   (+{1} ms)  grade {2}' -f $up, $ru, (Grade $ru)
    "Overall grade: $(Grade $worst)"
    if ($worst -ge 60) { 'Your ping jumps when the connection is busy (someone streaming or downloading = lag spikes in game). Fix: turn on SQM / Smart Queue / QoS in your router, or set it to about 90% of your speed.' }
    else { 'Your ping stays steady even when the connection is busy - downloads and streams on your network won''t cause lag spikes.' }
}
