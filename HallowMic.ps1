<#
  Hallow Toolkit - microphone fixes (no window code, so the tray app can use it too). Dot-sourced by HallowCore.ps1.
  Why games hear you quietly when Discord doesn't: Discord boosts a low Windows mic level by itself, games use the raw level.
  This reads and fixes the Windows side: level, mute, Mic Boost, default devices, exclusive control and call ducking.
#>

Import-HallowType 'HallowMic' @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class HallowMicDevice {
    public string Id; public string Name;
    public float Level; public bool Muted;
    public bool IsDefault; public bool IsComms;
    public int Exclusive = -1;               // 1 = apps may take exclusive control, 0 = not allowed, -1 = unknown
    public bool HasBoost; public float BoostDb; public float BoostMin; public float BoostMax; public float BoostStep;
}

public static class HallowMic {
    [StructLayout(LayoutKind.Sequential)] public struct PKEY { public Guid fmtid; public int pid; public PKEY(Guid g, int p) { fmtid = g; pid = p; } }
    [StructLayout(LayoutKind.Sequential)] public struct PROPVARIANT { public ushort vt; public ushort r1, r2, r3; public IntPtr p; public IntPtr p2; }
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }
    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigCo { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IMMDeviceCollection list);
        [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice dev);
    }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        [PreserveSig] int GetCount(out uint n);
        [PreserveSig] int Item(uint i, out IMMDevice dev);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
        [PreserveSig] int OpenPropertyStore(int access, out IPropertyStore ps);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }
    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        [PreserveSig] int GetCount(out int n);
        [PreserveSig] int GetAt(int i, out PKEY k);
        [PreserveSig] int GetValue(ref PKEY k, out PROPVARIANT v);
        [PreserveSig] int SetValue(ref PKEY k, ref PROPVARIANT v);
        [PreserveSig] int Commit();
    }
    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr n);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr n);
        [PreserveSig] int GetChannelCount(out uint n);
        [PreserveSig] int SetMasterVolumeLevel(float db, ref Guid ctx);
        [PreserveSig] int SetMasterVolumeLevelScalar(float v, ref Guid ctx);
        [PreserveSig] int GetMasterVolumeLevel(out float db);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float v);
        [PreserveSig] int SetChannelVolumeLevel(uint c, float db, ref Guid ctx);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint c, float v, ref Guid ctx);
        [PreserveSig] int GetChannelVolumeLevel(uint c, out float db);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint c, out float v);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool m);
    }
    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float v); }
    [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioClient {
        [PreserveSig] int Initialize(int share, uint flags, long buf, long period, IntPtr fmt, IntPtr session);
        [PreserveSig] int GetBufferSize(out uint n);
        [PreserveSig] int GetStreamLatency(out long l);
        [PreserveSig] int GetCurrentPadding(out uint n);
        [PreserveSig] int IsFormatSupported(int share, IntPtr fmt, out IntPtr closest);
        [PreserveSig] int GetMixFormat(out IntPtr fmt);
        [PreserveSig] int GetDevicePeriod(out long def, out long min);
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
        [PreserveSig] int Reset();
        [PreserveSig] int SetEventHandle(IntPtr h);
        [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioCaptureClient {
        [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devPos, out ulong qpc);
        [PreserveSig] int ReleaseBuffer(uint frames);
        [PreserveSig] int GetNextPacketSize(out uint frames);
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
        [PreserveSig] int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
    }
    // device topology (used to find the "Microphone Boost" control)
    [ComImport, Guid("2A07407E-6497-4A18-9787-32F79BD0D98F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDeviceTopology {
        [PreserveSig] int GetConnectorCount(out uint n);
        [PreserveSig] int GetConnector(uint i, out IConnector c);
    }
    [ComImport, Guid("9c2c4058-23f5-41de-877a-df3af236a09e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IConnector {
        [PreserveSig] int GetType(out int t);
        [PreserveSig] int GetDataFlow(out int f);
        [PreserveSig] int ConnectTo(IConnector c);
        [PreserveSig] int Disconnect();
        [PreserveSig] int IsConnected([MarshalAs(UnmanagedType.Bool)] out bool b);
        [PreserveSig] int GetConnectedTo(out IConnector c);
    }
    [ComImport, Guid("AE2DE0E4-5BCA-4F2D-AA46-5D13F8FDB3A9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPart {
        [PreserveSig] int GetName([MarshalAs(UnmanagedType.LPWStr)] out string n);
        [PreserveSig] int GetLocalId(out uint id);
        [PreserveSig] int GetGlobalId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetPartType(out int t);
        [PreserveSig] int GetSubType(out Guid g);
        [PreserveSig] int GetControlInterfaceCount(out uint n);
        [PreserveSig] int GetControlInterface(uint i, out IntPtr c);
        [PreserveSig] int EnumPartsIncoming(out IPartsList l);
        [PreserveSig] int EnumPartsOutgoing(out IPartsList l);
        [PreserveSig] int GetTopologyObject(out IntPtr t);
        [PreserveSig] int Activate(int ctx, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [ComImport, Guid("6DAA848C-5EB0-45CC-AEA5-998A2CDA1FFB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPartsList {
        [PreserveSig] int GetCount(out uint n);
        [PreserveSig] int GetPart(uint i, out IPart p);
    }
    [ComImport, Guid("7FB7B48F-531D-44A2-BCB3-5AD5A134B3DC"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioVolumeLevel {
        [PreserveSig] int GetChannelCount(out uint n);
        [PreserveSig] int GetLevelRange(uint c, out float min, out float max, out float step);
        [PreserveSig] int GetLevel(uint c, out float db);
        [PreserveSig] int SetLevel(uint c, float db, ref Guid ctx);
        [PreserveSig] int SetLevelUniform(float db, ref Guid ctx);
    }

    const int CAPTURE = 1, ACTIVE = 1, CLSCTX_ALL = 23;
    static readonly PKEY FriendlyName = new PKEY(new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), 14);
    static readonly PKEY ExclusiveKey = new PKEY(new Guid("b3f8fa53-0004-438e-9003-51a46e139bfc"), 3);
    static Guid IID_Volume = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
    static Guid IID_Meter = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
    static Guid IID_Client = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
    static Guid IID_Capture = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
    static Guid IID_Topology = new Guid("2A07407E-6497-4A18-9787-32F79BD0D98F");
    static Guid IID_VolumeLevel = new Guid("7FB7B48F-531D-44A2-BCB3-5AD5A134B3DC");

    static IMMDeviceEnumerator Enum() { return (IMMDeviceEnumerator)new MMDeviceEnumeratorCo(); }
    static void Check(int hr, string what) { if (hr < 0) throw new Exception(what + " failed (0x" + hr.ToString("X8") + ")"); }

    static IMMDevice Device(string id) {
        IMMDevice d; Check(Enum().GetDevice(id, out d), "Opening the mic"); return d;
    }
    static string DefaultId(int role) {
        IMMDevice d; if (Enum().GetDefaultAudioEndpoint(CAPTURE, role, out d) < 0 || d == null) return null;
        string id; d.GetId(out id); return id;
    }
    static T Activate<T>(IMMDevice d, Guid iid) where T : class {
        object o; Check(d.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out o), "Opening the mic control"); return (T)o;
    }

    public static string DefaultMicId() { return DefaultId(0); }

    public static List<HallowMicDevice> List() {
        var res = new List<HallowMicDevice>();
        string defId = DefaultId(0), comId = DefaultId(2);
        IMMDeviceCollection col; Check(Enum().EnumAudioEndpoints(CAPTURE, ACTIVE, out col), "Listing mics");
        uint n; col.GetCount(out n);
        for (uint i = 0; i < n; i++) {
            IMMDevice d; if (col.Item(i, out d) < 0) continue;
            var m = new HallowMicDevice();
            d.GetId(out m.Id);
            m.Name = ReadString(d, FriendlyName) ?? m.Id;
            m.IsDefault = m.Id == defId; m.IsComms = m.Id == comId;
            try { var v = Activate<IAudioEndpointVolume>(d, IID_Volume); v.GetMasterVolumeLevelScalar(out m.Level); v.GetMute(out m.Muted); } catch { m.Level = -1; }
            m.Exclusive = ReadExclusive(d);
            try { ReadBoost(d, m); } catch { }
            res.Add(m);
        }
        return res;
    }

    static string ReadString(IMMDevice d, PKEY k) {
        IPropertyStore ps; if (d.OpenPropertyStore(0, out ps) < 0) return null;
        PROPVARIANT v; if (ps.GetValue(ref k, out v) < 0) return null;
        string s = v.vt == 31 ? Marshal.PtrToStringUni(v.p) : null;
        PropVariantClear(ref v); return s;
    }
    static int ReadExclusive(IMMDevice d) {
        IPropertyStore ps; if (d.OpenPropertyStore(0, out ps) < 0) return -1;
        PKEY k = ExclusiveKey; PROPVARIANT v; if (ps.GetValue(ref k, out v) < 0) return -1;
        int r;
        if (v.vt == 0) r = 1;                                        // never set = Windows default (allowed)
        else if (v.vt == 11) r = ((short)v.p.ToInt64()) != 0 ? 1 : 0; // VT_BOOL
        else if (v.vt == 19 || v.vt == 3) r = v.p.ToInt64() != 0 ? 1 : 0;
        else r = -1;
        PropVariantClear(ref v); return r;
    }

    public static void SetLevel(string id, float level) {
        var v = Activate<IAudioEndpointVolume>(Device(id), IID_Volume); Guid g = Guid.Empty;
        Check(v.SetMasterVolumeLevelScalar(Math.Max(0f, Math.Min(1f, level)), ref g), "Setting the mic level");
    }
    public static void SetMute(string id, bool mute) {
        var v = Activate<IAudioEndpointVolume>(Device(id), IID_Volume); Guid g = Guid.Empty;
        Check(v.SetMute(mute, ref g), "Unmuting the mic");
    }
    public static float GetLevel(string id) {
        var v = Activate<IAudioEndpointVolume>(Device(id), IID_Volume); float f; Check(v.GetMasterVolumeLevelScalar(out f), "Reading the mic level"); return f;
    }

    // role 0 = default device (games, most apps), 1 = multimedia, 2 = communications (calls, some games' voice chat)
    public static void SetDefault(string id) {
        var pc = (IPolicyConfig)new PolicyConfigCo();
        for (int role = 0; role < 3; role++) Check(pc.SetDefaultEndpoint(id, role), "Setting the default mic");
    }

    public static void SetExclusive(string id, bool allow) {
        var pc = (IPolicyConfig)new PolicyConfigCo();
        PKEY k = ExclusiveKey;
        var v = new PROPVARIANT(); v.vt = 11; v.p = new IntPtr(allow ? 0xFFFF : 0);
        Check(pc.SetPropertyValue(id, 0, ref k, ref v), "Changing exclusive control");
    }
    public static int GetExclusive(string id) { return ReadExclusive(Device(id)); }

    // ---- Microphone Boost: walk the driver's topology upstream of the mic for a volume part named "...Boost..."
    static IAudioVolumeLevel FindBoost(IMMDevice d) {
        var topo = Activate<IDeviceTopology>(d, IID_Topology);
        uint n; topo.GetConnectorCount(out n);
        var seen = new HashSet<string>();
        for (uint i = 0; i < n; i++) {
            IConnector c; if (topo.GetConnector(i, out c) < 0) continue;
            IConnector to; if (c.GetConnectedTo(out to) < 0 || to == null) continue;
            var found = Walk(to as IPart, seen, 0);
            if (found != null) return found;
        }
        return null;
    }
    static IAudioVolumeLevel Walk(IPart p, HashSet<string> seen, int depth) {
        if (p == null || depth > 25) return null;
        string gid; p.GetGlobalId(out gid);
        if (gid != null && !seen.Add(gid)) return null;
        string name; p.GetName(out name); int type; p.GetPartType(out type);
        if (type == 1 && name != null && name.IndexOf("boost", StringComparison.OrdinalIgnoreCase) >= 0) {
            object o; Guid iid = IID_VolumeLevel;
            if (p.Activate(CLSCTX_ALL, ref iid, out o) >= 0 && o is IAudioVolumeLevel) return (IAudioVolumeLevel)o;
        }
        IPartsList list; if (p.EnumPartsIncoming(out list) < 0 || list == null) return null;
        uint n; list.GetCount(out n);
        for (uint i = 0; i < n; i++) {
            IPart q; if (list.GetPart(i, out q) < 0) continue;
            var r = Walk(q, seen, depth + 1); if (r != null) return r;
        }
        return null;
    }
    static void ReadBoost(IMMDevice d, HallowMicDevice m) {
        var b = FindBoost(d); if (b == null) return;
        if (b.GetLevelRange(0, out m.BoostMin, out m.BoostMax, out m.BoostStep) < 0) return;
        if (b.GetLevel(0, out m.BoostDb) < 0) return;
        m.HasBoost = m.BoostMax > m.BoostMin;
    }
    public static float SetBoost(string id, float db) {
        var b = FindBoost(Device(id)); if (b == null) throw new Exception("This mic has no Microphone Boost control");
        float min, max, step; Check(b.GetLevelRange(0, out min, out max, out step), "Reading Mic Boost");
        float v = Math.Max(min, Math.Min(max, db));
        if (step > 0) v = min + (float)Math.Round((v - min) / step) * step;
        Guid g = Guid.Empty; Check(b.SetLevelUniform(v, ref g), "Setting Mic Boost");
        return v;
    }

    // ---- live meter: record from the mic (shared mode, nothing is saved) and measure the loudest sample since the last call
    public class Meter : IDisposable {
        IAudioClient client; IAudioMeterInformation meter; IAudioCaptureClient cap;
        int channels, bits; bool isFloat;
        public string Id;
        public Meter(string id) {
            Id = id;
            var d = Device(id);
            meter = Activate<IAudioMeterInformation>(d, IID_Meter);
            client = Activate<IAudioClient>(d, IID_Client);
            IntPtr fmt; Check(client.GetMixFormat(out fmt), "Reading the mic format");
            try {
                ushort tag = (ushort)Marshal.ReadInt16(fmt, 0);
                channels = Marshal.ReadInt16(fmt, 2); bits = Marshal.ReadInt16(fmt, 14);
                isFloat = tag == 3 || (tag == 0xFFFE && Marshal.ReadInt32(fmt, 24) == 3);
                Check(client.Initialize(0, 0, 2000000, 0, fmt, IntPtr.Zero), "Opening the mic for the meter");
            } finally { Marshal.FreeCoTaskMem(fmt); }
            object o; Guid iid = IID_Capture; Check(client.GetService(ref iid, out o), "Opening the mic stream"); cap = (IAudioCaptureClient)o;
            Check(client.Start(), "Starting the meter");
        }
        public float Peak() {
            float best = 0;
            if (cap != null) {
                uint next;
                while (cap.GetNextPacketSize(out next) >= 0 && next > 0) {
                    IntPtr data; uint frames, flags; ulong a, b;
                    if (cap.GetBuffer(out data, out frames, out flags, out a, out b) < 0) break;
                    if ((flags & 2) == 0 && data != IntPtr.Zero) {        // 2 = silent packet
                        int n = (int)frames * channels;
                        if (isFloat && bits == 32) { var buf = new float[n]; Marshal.Copy(data, buf, 0, n); foreach (var s in buf) { float v = Math.Abs(s); if (v > best) best = v; } }
                        else if (bits == 16) { var buf = new short[n]; Marshal.Copy(data, buf, 0, n); foreach (var s in buf) { float v = Math.Abs(s / 32768f); if (v > best) best = v; } }
                        else if (bits == 32) { var buf = new int[n]; Marshal.Copy(data, buf, 0, n); foreach (var s in buf) { float v = Math.Abs(s / 2147483648f); if (v > best) best = v; } }
                    }
                    cap.ReleaseBuffer(frames);
                }
            }
            float m = 0; if (meter != null) meter.GetPeakValue(out m);
            return Math.Min(1f, Math.Max(best, m));
        }
        public void Dispose() {
            if (client != null) { try { client.Stop(); } catch { } Marshal.ReleaseComObject(client); client = null; }
            if (cap != null) { Marshal.ReleaseComObject(cap); cap = null; }
            if (meter != null) { Marshal.ReleaseComObject(meter); meter = null; }
        }
    }
}
'@

# ---- PowerShell side
$DuckKey = 'HKCU:\Software\Microsoft\Multimedia\Audio'
function Get-Mics { @([HallowMic]::List()) }
function Get-DefaultMic { Get-Mics | Where-Object IsDefault | Select-Object -First 1 }

# 0 = mute other sounds, 1 = lower 80% (Windows default), 2 = lower 50%, 3 = do nothing
function Get-CallDucking { $v = (Get-ItemProperty $DuckKey -Name UserDuckingPreference -ErrorAction SilentlyContinue).UserDuckingPreference; if ($null -eq $v) { 1 } else { [int]$v } }
function Set-CallDuckingOff { New-Item $DuckKey -Force -ErrorAction SilentlyContinue | Out-Null; Set-ItemProperty $DuckKey -Name UserDuckingPreference -Value 3 -Type DWord }

# Windows privacy switch: "Let desktop apps access your microphone" - if it's off, games hear nothing at all
function Get-MicPrivacy {
    $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
    $all = (Get-ItemProperty $base -Name Value -ErrorAction SilentlyContinue).Value
    $desk = (Get-ItemProperty "$base\NonPackaged" -Name Value -ErrorAction SilentlyContinue).Value
    [pscustomobject]@{ AllApps = ($all -ne 'Deny'); DesktopApps = ($desk -ne 'Deny') }
}

function Format-MicLevel($m) { if ($m.Level -lt 0) { '?' } else { '{0:N0}%' -f ($m.Level * 100) } }

# Your chosen level per real mic (Mic page > Your mic level), saved by mic name. Default 100%. Lower suits a close mic
# on a stand that shouldn't pick up the whole room. Virtual mics (Sonar etc.) always go to 100% so they don't cut it again.
function Get-MicTarget($m) {
    $t = (Get-Settings).MicTargets
    if ($t -and $t.PSObject.Properties[$m.Name]) { $v = [double]$t.PSObject.Properties[$m.Name].Value; if ($v -ge 5 -and $v -le 100) { return $v / 100 } }
    1.0
}
function Set-MicTarget($m, [int]$Pct) {
    $s = Get-Settings; $t = [ordered]@{}
    if ($s.MicTargets) { foreach ($p in $s.MicTargets.PSObject.Properties) { $t[$p.Name] = $p.Value } }
    if ($Pct -ge 100) { $t.Remove($m.Name) } else { $t[$m.Name] = $Pct }
    $s | Add-Member MicTargets ([pscustomobject]$t) -Force; Save-Settings $s
}
function Get-MicWant($m) { if ($m.IsVirtual) { 1.0 } else { Get-MicTarget $m } }
function Format-Pct([double]$v) { '{0:N0}%' -f ($v * 100) }

# Virtual mics (SteelSeries Sonar, Voicemeeter, NVIDIA Broadcast, Wave Link...) sit between your real mic and games.
# Games hear the virtual mic, so a low level on the REAL mic behind it makes you quiet everywhere except apps that boost it (Discord).
$VirtualMicPattern = 'Sonar|Voicemeeter|VB-Audio|Virtual|Broadcast|Wave Link|Elgato Wave|Krisp|Voicemod|CABLE Output|Steam Streaming|Stream Out'
function Get-MicSetup {
    $mics = @(Get-Mics)
    foreach ($m in $mics) { $m | Add-Member -NotePropertyName IsVirtual -NotePropertyValue ($m.Name -match $VirtualMicPattern) -Force }
    $mics
}

# The mics a fix should touch: the target, plus every real mic when the target is a virtual one (we can't see which real mic feeds it).
function Get-MicFixSet($Target, $Mics) {
    if ($Target.IsVirtual) { @($Target) + @($Mics | Where-Object { -not $_.IsVirtual -and $_.Id -ne $Target.Id }) } else { @($Target) }
}

# Lists what is wrong, in plain words. Empty = nothing found.
function Get-MicProblems($Target, $Mics) {
    $p = New-Object System.Collections.Generic.List[string]
    foreach ($m in (Get-MicFixSet $Target $Mics)) {
        $who = if ($m.Id -eq $Target.Id) { 'this mic' } else { "$($m.Name) (feeds your virtual mic)" }
        if ($m.Muted) { $p.Add("$who is muted in Windows") }
        $want = Get-MicWant $m
        if ($m.Level -ge 0 -and $m.Level -lt $want - 0.05) { $p.Add("$who is at $(Format-MicLevel $m) in Windows (you want $(Format-Pct $want))") }
        if ($m.Exclusive -eq 1) { $p.Add("apps may take exclusive control of $who") }
    }
    if (-not $Target.IsDefault) { $p.Add('it is not the Default Device (most games use that one)') }
    if (-not $Target.IsComms) { $p.Add('it is not the Default Communications Device (some games and voice chats use that one)') }
    if ((Get-CallDucking) -ne 3) { $p.Add('Windows turns other sounds down during calls') }
    $priv = Get-MicPrivacy
    if (-not $priv.AllApps -or -not $priv.DesktopApps) { $p.Add('Windows privacy settings block desktop apps from the mic') }
    $p
}

# One-click fix. Boost is only raised when asked, because it adds hiss on some mics. Returns how many things changed.
function Repair-Mic($Target, $Mics, [switch]$Boost) {
    $did = 0
    foreach ($m in (Get-MicFixSet $Target $Mics)) {
        if ($m.Muted) { [HallowMic]::SetMute($m.Id, $false); Log "Unmuted $($m.Name)."; $did++ }
        $want = Get-MicWant $m
        if ($m.Level -ge 0 -and [math]::Abs($m.Level - $want) -gt 0.01) { [HallowMic]::SetLevel($m.Id, $want); Log "$($m.Name): level $(Format-MicLevel $m) -> $(Format-Pct $want)."; $did++ }
        if ($m.Exclusive -ne 0) {
            try { [HallowMic]::SetExclusive($m.Id, $false); Log "$($m.Name): apps can no longer take exclusive control of it."; $did++ }
            catch { Log "Could not turn off exclusive control for $($m.Name): $($_.Exception.Message). Untick it in Sound settings > Recording > Properties > Advanced." }
        }
        if ($Boost -and $m.HasBoost -and $m.BoostDb -lt 10) {
            $v = [HallowMic]::SetBoost($m.Id, 10); Log ("{0}: Mic Boost {1:+0;-0;0} dB -> {2:+0;-0;0} dB." -f $m.Name, $m.BoostDb, $v); $did++
        }
    }
    if (-not ($Target.IsDefault -and $Target.IsComms)) { [HallowMic]::SetDefault($Target.Id); Log "$($Target.Name) is now the default mic for games AND calls."; $did++ }
    if ((Get-CallDucking) -ne 3) { Set-CallDuckingOff; Log 'Windows will no longer turn sounds down during calls ("Do nothing").'; $did++ }
    $priv = Get-MicPrivacy
    if (-not $priv.AllApps -or -not $priv.DesktopApps) {
        Log 'Windows privacy settings are blocking apps from the mic. Turn on "Microphone access" and "Let desktop apps access your microphone" in the page that just opened.'
        Start-Process 'ms-settings:privacy-microphone'
    }
    if ($Target.IsVirtual -and $Target.Name -match 'Sonar') { Log 'Using SteelSeries Sonar: also check the Mic volume in SteelSeries GG > Sonar > Mic - Sonar has its own level on top of Windows.' }
    $did
}

# Tray: put the mic(s) back to your level if something lowered them. Returns what it fixed.
function Restore-MicLevels {
    $mics = @(Get-MicSetup); $t = $mics | Where-Object IsDefault | Select-Object -First 1
    if (-not $t) { return @() }
    $fixed = @()
    foreach ($m in (Get-MicFixSet $t $mics)) {
        $want = Get-MicWant $m
        if ($m.Level -ge 0 -and $m.Level -lt $want - 0.05) { try { [HallowMic]::SetLevel($m.Id, $want); $fixed += "$($m.Name) ($(Format-MicLevel $m))" } catch { } }
    }
    $fixed
}
