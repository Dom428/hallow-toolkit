<#
  Hallow Toolkit - background restraint and IdleSaver (v5.13, Process Lasso style). Both off until you turn them on.
   - Background restraint (ProBalance): a background app that keeps hogging the CPU while a game runs (or at any time,
     if you pick that) is lowered to Below normal priority, and put back to Normal when it calms down or the game ends.
     Never: games, audio apps, Windows/system processes, Hallow apps, the app in front, anything it can't change.
   - IdleSaver: when nobody has touched the mouse or keyboard for N minutes, switch to a chosen power plan; switch back
     the moment you return. Never while a game runs or something is playing sound.
  The tray app runs both. No window code. Dot-sourced by HallowCore.ps1.
#>

Import-HallowType 'HallowIdle' @'
using System; using System.Runtime.InteropServices;
public static class HallowIdle {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO i);
    // seconds since the last mouse / keyboard / controller input in this session
    public static double IdleSeconds() {
        LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref i)) return 0;
        return unchecked((uint)Environment.TickCount - i.dwTime) / 1000.0;
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int flow, int mask, out IMMDeviceCollection list);
    }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        [PreserveSig] int GetCount(out uint n);
        [PreserveSig] int Item(uint i, out IMMDevice dev);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float v); }

    // loudest peak (0..1) on any active playback device right now; -1 when it can't be read
    public static float PlaybackPeak() {
        try {
            IMMDeviceEnumerator en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCo());
            IMMDeviceCollection list;
            if (en.EnumAudioEndpoints(0, 1, out list) != 0) return -1;
            uint n; list.GetCount(out n);
            float max = 0; Guid iid = typeof(IAudioMeterInformation).GUID;
            for (uint i = 0; i < n; i++) {
                IMMDevice d; if (list.Item(i, out d) != 0) continue;
                object o; if (d.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) continue;
                float v; if (((IAudioMeterInformation)o).GetPeakValue(out v) == 0 && v > max) max = v;
                Marshal.ReleaseComObject(o); Marshal.ReleaseComObject(d);
            }
            Marshal.ReleaseComObject(list); Marshal.ReleaseComObject(en);
            return max;
        } catch { return -1; }
    }
}
'@

# ================================================================ shared: is a game running?
# Hallow Hub's status.json lists the games it sees running (only trusted while Hub itself runs).
function Test-HubPlaying {
    if (-not (Get-Process HallowHub -ErrorAction SilentlyContinue)) { return $false }
    try { $st = Get-Content (Join-Path $env:APPDATA 'HallowHub\status.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json; return (@($st.playing | Where-Object { $_ }).Count -gt 0) } catch { return $false }
}

# the tray app holds this mutex while it runs
function Test-TrayRunning { $m = $null; if ([System.Threading.Mutex]::TryOpenExisting('Local\HallowToolkitTray', [ref]$m)) { $m.Dispose(); $true } else { $false } }

# ================================================================ BACKGROUND RESTRAINT
# Never touched, whatever the settings say (process names, * wildcards). Your own exclusions add to this list.
$RestraintBuiltIn = @(
    # Windows and security
    'System', 'Idle', 'Registry', 'Secure System', 'MemCompression', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'svchost',
    'dwm', 'explorer', 'fontdrvhost', 'sihost', 'ctfmon', 'taskhostw', 'RuntimeBroker', 'ShellExperienceHost', 'StartMenuExperienceHost',
    'SearchHost', 'TextInputHost', 'LockApp', 'SecurityHealthService', 'SecurityHealthSystray', 'MsMpEng', 'NisSrv', 'MpDefenderCoreService',
    'conhost', 'dllhost', 'WmiPrvSE', 'Taskmgr', 'powershell', 'pwsh', 'SystemInformer', 'ProcessHacker', 'procexp*', 'ProcessLasso*', 'bitsumsessionagent',
    # audio and voice
    'audiodg', 'EqualizerAPO*', 'Peace', 'voicemeeter*', 'VBVoicemeeter*', 'vbaudio*', 'Discord*', 'SteelSeries*', 'Sonar*', 'NVIDIA Broadcast',
    'RTX Voice', 'Krisp*', 'WaveLink*', 'Wave Link', 'TeamSpeak*', 'ts3client*', 'Mumble', 'Spotify', 'foobar2000', 'AIMP*', 'iCUE*', 'Lghub*',
    # recording, overlays, anti-cheat
    'obs64', 'obs32', 'obs', 'GameOverlayUI', 'NVIDIA Share', 'NVIDIA Overlay', 'nvcontainer', 'nvsphelper64', 'RadeonSoftware', 'amdow', 'AMDRSServ',
    'EasyAntiCheat*', 'BEService*', 'BattlEye*', 'vgc', 'vgtray', 'FACEIT*', 'EAAntiCheat*', 'Medal*',
    # the Hallow apps
    'Hallow*')
# path parts that mark an audio app even under another name
$RestraintBuiltInPaths = @('\EqualizerAPO\', '\VB\Voicemeeter\', '\Hallow ')
$RestraintThresholds = @(10, 15, 25, 40)   # % of the whole CPU, held for about 20 seconds

function Get-RestraintSettings {
    $s = Get-Settings
    [pscustomobject]@{
        On      = [bool]$s.Restraint
        Always  = ("$($s.RestraintMode)" -eq 'Always')
        Pct     = $(if ($RestraintThresholds -contains [int]$s.RestraintPct) { [int]$s.RestraintPct } else { 15 })
        Exclude = @($s.RestraintExclude | ForEach-Object { "$_".Trim() -replace '\.exe$', '' } | Where-Object { $_ })
    }
}
function Save-RestraintSettings([bool]$On, [bool]$Always, [int]$Pct, [string[]]$Exclude) {
    $s = Get-Settings
    $s | Add-Member Restraint $On -Force; $s | Add-Member RestraintMode $(if ($Always) { 'Always' } else { 'Game' }) -Force
    $s | Add-Member RestraintPct $Pct -Force
    $s | Add-Member RestraintExclude @($Exclude | ForEach-Object { "$_".Trim() -replace '\.exe$', '' } | Where-Object { $_ } | Sort-Object -Unique) -Force
    Save-Settings $s
}

function Test-NameMatch([string]$Name, [string[]]$Patterns) { foreach ($x in $Patterns) { if ($x -and $Name -like $x) { return $true } }; $false }

# Why a process must not be lowered ('' = it may be). $Ctx: GameRoots, Protect (names), Exclude, Foreground (pid), Self (pids)
function Get-RestraintBlock($Proc, $Ctx) {
    $n = $Proc.ProcessName
    if ($Proc.Id -le 4) { return 'system' }
    if ($Ctx.Self -contains $Proc.Id) { return 'the toolkit' }
    try { if ($Proc.SessionId -eq 0) { return 'service' } } catch { return 'protected' }
    if (Test-NameMatch $n $RestraintBuiltIn) { return 'built-in list' }
    if (Test-NameMatch $n $Ctx.Exclude) { return 'your exclusions' }
    if ($Ctx.Protect -contains $n) { return 'the game' }
    if ($Ctx.Foreground -and $Proc.Id -eq $Ctx.Foreground) { return 'in front' }
    $path = $null; try { $path = $Proc.Path } catch { }
    if (-not $path) { return 'protected' }   # can't read its path = elevated or protected
    if ($path.StartsWith($env:windir + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'Windows' }
    foreach ($x in $RestraintBuiltInPaths) { if ($path.IndexOf($x, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return 'built-in list' } }
    foreach ($r in @($Ctx.GameRoots)) { if ($r -and $path.StartsWith($r.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'a game' } }
    ''
}

function New-RestraintState {
    @{ Last = @{}; LastTime = $null; Hot = @{}; Calm = @{}; Restrained = @{}; Skip = New-Object 'System.Collections.Generic.HashSet[string]'; Roots = @(); RootsAt = [datetime]::MinValue }
}
function Get-ProcKey($Proc) { try { "$($Proc.Id):$($Proc.StartTime.Ticks)" } catch { $null } }

# Puts one restrained process back to Normal (only if it is still the same process and still Below normal).
function Restore-RestrainedProcess($State, [string]$Key, [string]$Reason) {
    $r = $State.Restrained[$Key]; $State.Restrained.Remove($Key); $State.Calm.Remove($Key)
    if (-not $r) { return }
    $p = Get-Process -Id $r.Id -ErrorAction SilentlyContinue
    $back = $false
    if ($p -and (Get-ProcKey $p) -eq $Key) {
        try { if ("$($p.PriorityClass)" -eq 'BelowNormal') { $p.PriorityClass = 'Normal' }; $back = $true } catch { }
    }
    [pscustomobject]@{ Time = (Get-Date).ToString('s'); Action = 'Restored'; Name = $r.Name; Id = $r.Id; Pct = $null; Reason = $(if ($p) { $Reason } else { 'it closed' }); Ok = ($back -or -not $p) }
}
function Restore-AllRestrained($State, [string]$Reason) {
    foreach ($k in @($State.Restrained.Keys)) { Restore-RestrainedProcess $State $k $Reason }
}

# One pass (the tray calls it every 10 s). $Active = restraint should be working now (on, and a game runs or Always).
# Returns what changed: objects with Action Restrained / Restored.
function Invoke-RestraintPass($State, [bool]$Active, [double]$Threshold = 15, $Ctx, [int]$HotPasses = 2, [int]$CalmPasses = 3, [string]$EndReason = 'the game ended') {
    $now = Get-Date; $ncpu = [Environment]::ProcessorCount
    $elapsed = $(if ($State.LastTime) { ($now - $State.LastTime).TotalSeconds } else { 0 })
    $cur = @{}; $pct = @{}; $byKey = @{}
    foreach ($p in @(Get-Process)) {
        $k = Get-ProcKey $p; if (-not $k) { continue }   # no start time = protected process
        $ms = $null; try { $ms = $p.TotalProcessorTime.TotalMilliseconds } catch { continue }
        $cur[$k] = $ms; $byKey[$k] = $p
        if ($elapsed -gt 0.5 -and $State.Last.ContainsKey($k)) { $pct[$k] = [math]::Max(0, ($ms - $State.Last[$k]) / ($elapsed * 1000 * $ncpu) * 100) }
    }
    $State.Last = $cur; $State.LastTime = $now
    $out = @()
    # restrained ones: put back when they calm down, close, or restraint stops
    foreach ($k in @($State.Restrained.Keys)) {
        if (-not $byKey.ContainsKey($k)) { $out += Restore-RestrainedProcess $State $k 'it closed'; continue }
        if (-not $Active) { $out += Restore-RestrainedProcess $State $k $EndReason; continue }
        if ($pct.ContainsKey($k) -and $pct[$k] -lt ($Threshold / 2)) {
            $State.Calm[$k] = 1 + [int]$State.Calm[$k]
            if ($State.Calm[$k] -ge $CalmPasses) { $out += Restore-RestrainedProcess $State $k 'it calmed down' }
        } else { $State.Calm.Remove($k) }
    }
    if (-not $Active) { $State.Hot = @{}; return $out }
    # new hogs: over the threshold for $HotPasses passes in a row
    $hot = @{}
    foreach ($k in $pct.Keys) {
        if ($pct[$k] -lt $Threshold -or $State.Restrained.ContainsKey($k) -or $State.Skip.Contains($k)) { continue }
        $hot[$k] = 1 + [int]$State.Hot[$k]
        if ($hot[$k] -lt $HotPasses) { continue }
        $p = $byKey[$k]
        $why = Get-RestraintBlock $p $Ctx
        if (-not $why -and "$($p.PriorityClass)" -ne 'Normal') { $why = 'priority already changed' }   # someone chose its priority - leave it
        if ($why -eq 'in front') { continue }   # the app you're using - check again next time
        if ($why) { [void]$State.Skip.Add($k); continue }
        try {
            $p.PriorityClass = 'BelowNormal'
            $State.Restrained[$k] = @{ Id = $p.Id; Name = $p.ProcessName; Since = $now }
            $out += [pscustomobject]@{ Time = $now.ToString('s'); Action = 'Restrained'; Name = $p.ProcessName; Id = $p.Id; Pct = [math]::Round($pct[$k]); Reason = "used $([math]::Round($pct[$k]))% of the CPU"; Ok = $true }
        } catch { [void]$State.Skip.Add($k) }   # elevated or protected - can't change it, don't try again
    }
    $State.Hot = $hot
    $out
}

# ---- the small log of what it restrained (logs\restraint.json, newest first, last 100)
$RestraintLogFile = Join-Path $LogDir 'restraint.json'
function Get-RestraintLog { if (Test-Path $RestraintLogFile) { try { @(Get-Content $RestraintLogFile -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) } catch { @() } } else { @() } }
function Add-RestraintLog($Events) {
    $ev = @($Events | Where-Object { $_ }); if (-not $ev.Count) { return }
    [array]::Reverse($ev)
    $all = @($ev | Select-Object Time, Action, Name, Id, Pct, Reason) + @(Get-RestraintLog) | Select-Object -First 100
    try { ConvertTo-Json @($all) -Depth 3 | Set-Content $RestraintLogFile -Encoding UTF8 } catch { }
}
function Clear-RestraintLog { Remove-Item $RestraintLogFile -Force -ErrorAction SilentlyContinue }

# ================================================================ IDLESAVER
$IdleMinuteChoices = @(5, 10, 15, 20, 30, 60)
function Get-IdleSaverSettings {
    $s = Get-Settings
    [pscustomobject]@{
        On      = [bool]$s.IdleSaver
        Minutes = $(if ($IdleMinuteChoices -contains [int]$s.IdleMinutes) { [int]$s.IdleMinutes } else { 15 })
        Plan    = "$($s.IdlePlan)".ToLower()
        Failed  = "$($s.IdleFailed)"
    }
}
function Save-IdleSaverSettings([bool]$On, [int]$Minutes, [string]$Plan) {
    $s = Get-Settings
    $s | Add-Member IdleSaver $On -Force; $s | Add-Member IdleMinutes $Minutes -Force; $s | Add-Member IdlePlan "$Plan".ToLower() -Force
    $s | Add-Member IdleFailed '' -Force   # a new choice gets a fresh try
    Save-Settings $s
}
function Get-IdleSeconds { [HallowIdle]::IdleSeconds() }
function Get-PlaybackPeak { [HallowIdle]::PlaybackPeak() }

# Switches the power plan and checks it took. Never asks for admin: if Windows refuses, returns $false.
function Set-PowerPlanChecked([string]$Guid) {
    try { $null = & powercfg.exe /setactive $Guid 2>&1 } catch { }
    return ((Get-ActiveSchemeGuid) -eq $Guid)
}

function New-IdleState { @{ LastSound = [datetime]::MinValue; Switched = $null } }

# One pass (the tray calls it every 10 s). Returns a message when it switched plans, $null otherwise.
# $Opt: On, Minutes, Plan, Failed; $GameActive: a game or game session is running.
function Invoke-IdleSaverPass($State, $Opt, [bool]$GameActive, [double]$IdleSec = -1, [double]$Peak = -2) {
    $now = Get-Date
    if ($IdleSec -lt 0) { $IdleSec = Get-IdleSeconds }
    if ($Peak -lt -1) { $Peak = Get-PlaybackPeak }
    $sound = ($Peak -lt 0 -or $Peak -gt 0.01)   # can't read the meter = assume sound (stay out of the way)
    if ($sound) { $State.LastSound = $now }
    $sw = $State.Switched
    if ($sw) {
        $back = $(if (-not $Opt.On) { 'IdleSaver turned off' } elseif ($GameActive) { 'a game started' } elseif ($IdleSec -lt $sw.Idle -or $IdleSec -lt ($now - $sw.At).TotalSeconds) { 'you are back' } elseif ($sound) { 'sound started playing' })
        if (-not $back) { return $null }
        $State.Switched = $null; Clear-IdleSwitchedMark
        if ((Get-ActiveSchemeGuid) -ne $sw.Set) { return "IdleSaver: $back - the power plan was already changed by something else, left it." }
        if (Set-PowerPlanChecked $sw.Prev) { return "IdleSaver: $back - power plan back to $(Get-SchemeName)." }
        return "IdleSaver: $back - could not switch the power plan back."
    }
    if (-not $Opt.On -or -not $Opt.Plan -or $GameActive -or $sound) { return $null }
    if (($now - $State.LastSound).TotalMinutes -lt 5) { return $null }   # sound in the last 5 minutes = probably a video / music session
    if ($IdleSec -lt $Opt.Minutes * 60) { return $null }
    if ($Opt.Failed -and $Opt.Failed -eq $Opt.Plan) { return $null }   # Windows refused this plan before
    $prev = Get-ActiveSchemeGuid
    if (-not $prev -or $prev -eq $Opt.Plan) { return $null }
    if (-not @(Get-PowerPlans | Where-Object Guid -eq $Opt.Plan).Count) { return $null }   # plan was deleted
    if (Set-PowerPlanChecked $Opt.Plan) {
        $State.Switched = @{ Prev = $prev; Set = $Opt.Plan; At = $now; Idle = $IdleSec }   # idle time only drops when you touch something
        $s = Get-Settings; $s | Add-Member IdleSwitched ([pscustomobject]@{ Prev = $prev; Set = $Opt.Plan }) -Force; Save-Settings $s
        return "IdleSaver: away for $([math]::Floor($IdleSec / 60)) min - power plan $(Get-SchemeName) until you're back."
    }
    $s = Get-Settings; $s | Add-Member IdleFailed $Opt.Plan -Force; Save-Settings $s
    "IdleSaver: Windows would not switch to that power plan without admin - IdleSaver won't try it again. Pick another plan on the Gaming tab."
}
function Clear-IdleSwitchedMark { $s = Get-Settings; if ($s.PSObject.Properties.Name -contains 'IdleSwitched' -and $s.IdleSwitched) { $s | Add-Member IdleSwitched $null -Force; Save-Settings $s } }
# Tray start / exit: if IdleSaver switched the plan and the tray stopped before you came back, put it back.
function Restore-IdleLeftover {
    $s = Get-Settings; $l = $s.IdleSwitched
    if (-not $l -or -not $l.Prev) { return $null }
    Clear-IdleSwitchedMark
    if ((Get-ActiveSchemeGuid) -eq "$($l.Set)" -and (Set-PowerPlanChecked "$($l.Prev)")) { return "IdleSaver: power plan back to $(Get-SchemeName)." }
    $null
}
