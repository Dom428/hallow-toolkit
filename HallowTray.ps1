<#
  Hallow Toolkit tray app (orange H by the clock).
   - Auto Game Boost: when a game starts, closes the apps on your Auto Boost list; reopens them when you quit.
   - Panic key: Ctrl+Alt+End force-closes the app/game in front (for frozen games).
#>
param([switch]$Once)   # -Once: run one detection pass and print what it sees (for testing)

$ErrorActionPreference = 'Continue'
$script:LogBox = $null
. (Join-Path $PSScriptRoot 'HallowCore.ps1')
trap { Write-HallowCrash $_ 'Hallow Toolkit tray' | Out-Null; continue }   # v5.8: crash reports
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$IgnoreFolders = @('wallpaper_engine', 'Steamworks Shared', 'Steam Controller Configs', 'SteamVR', 'Steam Linux Runtime')
$IgnoreProcs = @('crashpad_handler', 'UnityCrashHandler64', 'UnityCrashHandler32', 'CrashReportClient', 'wallpaper32', 'wallpaper64', 'webwallpaper32')

function Find-RunningGame {
    $roots = Get-GameRoots
    foreach ($p in Get-Process) {
        if ($IgnoreProcs -contains $p.ProcessName) { continue }
        $path = $null; try { $path = $p.Path } catch { }
        if (-not $path) { continue }
        foreach ($r in $roots) {
            if ($path.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $folder = ($path.Substring($r.Length + 1) -split '\\')[0]
                if ($IgnoreFolders -notcontains $folder) { return [pscustomobject]@{ Name = $folder; Process = $p.ProcessName; Id = $p.Id } }
            }
        }
    }
    $null
}

if ($Once) {
    $g = Find-RunningGame
    "Game roots: $((Get-GameRoots) -join ' | ')"
    "Running game: $(if ($g) { "$($g.Name) ($($g.Process))" } else { 'none' })"
    "Settings: $((Get-Settings) | ConvertTo-Json -Compress)"
    return
}

# ---- single instance
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\HallowToolkitTray', [ref]$created)
if (-not $created) { return }

Import-HallowType 'HallowHotKey' @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms;
public class HallowHotKey : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    public event EventHandler Pressed;
    public bool Ok;
    public HallowHotKey(uint mods, uint vk) { CreateHandle(new CreateParams()); Ok = RegisterHotKey(Handle, 1, mods, vk); }
    protected override void WndProc(ref Message m) { if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty); base.WndProc(ref m); }
    public void Dispose() { UnregisterHotKey(Handle, 1); DestroyHandle(); }
}
'@ @('System.Windows.Forms')

$settings = Get-Settings
$icon = New-Object System.Windows.Forms.NotifyIcon
$iconFile = Join-Path $HallowRoot 'hallow.ico'
$icon.Icon = $(if (Test-Path $iconFile) { New-Object System.Drawing.Icon $iconFile } else { [System.Drawing.SystemIcons]::Application })
$icon.Text = 'Hallow Toolkit'
$icon.Visible = $true

function Notify([string]$Text) { $icon.ShowBalloonTip(3000, 'Hallow Toolkit', $Text, 'Info'); Log "[tray] $Text" }

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $menu.Items.Add('Open Hallow Toolkit')
$miOpen.Font = New-Object System.Drawing.Font($miOpen.Font, [System.Drawing.FontStyle]::Bold)
$miOpen.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"") })
$miMon = $menu.Items.Add('Open Monitor')
$miMon.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"", '-StartPage', 'Monitor') })
$miServer = $menu.Items.Add('Server status')
$miServer.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"", '-StartPage', 'Server') })
$miClean = $menu.Items.Add('Quick Clean-up (keeps Recycle Bin)')
$miClean.Add_Click({
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"", '-Mode', 'Quick', '-NoRecycleBin')
    Notify 'Quick Clean-up is running in the background.'
})
$miSession = New-Object System.Windows.Forms.ToolStripMenuItem('Game session')
# the rocket icon hides the tick mark, so the text says whether a session is on
function Update-SessionItem { $on = [bool](Get-GameSession); $miSession.Checked = $on; $miSession.Text = $(if ($on) { 'Game session: ON  (click to end)' } else { 'Start game session' }) }
Update-SessionItem
$miSession.Add_Click({
    if (Get-GameSession) { Stop-GameSession; Notify 'Game session ended - power plan, updates and apps are back to normal.' }
    else { Stop-IdleSaverNow; Start-GameSession; Notify 'Game session on - Boost apps closed, High performance power. Click again when done.' }
    Update-SessionItem
})
[void]$menu.Items.Add($miSession)
$miPreGame = New-Object System.Windows.Forms.ToolStripMenuItem('Game-ready check')
$miPreGame.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"", '-StartPage', 'Gaming', '-Run', 'PreGame') })
[void]$menu.Items.Add($miPreGame)
$miAudio = New-Object System.Windows.Forms.ToolStripMenuItem('Switch audio (speakers / headset)   Ctrl+Alt+Home')
$miAudio.Add_Click({ try { Notify (Switch-AudioSetup) } catch { Notify "Audio switch failed: $($_.Exception.Message)" } })
[void]$menu.Items.Add($miAudio)
$miTimer = New-Object System.Windows.Forms.ToolStripMenuItem('Sleep / shut down timer')
foreach ($opt in @(@('Shut down in 30 minutes', 'shutdown', 30), @('Shut down in 1 hour', 'shutdown', 60), @('Shut down in 2 hours', 'shutdown', 120), @('Shut down in 3 hours', 'shutdown', 180), @('-'),
        @('Sleep in 30 minutes', 'sleep', 30), @('Sleep in 1 hour', 'sleep', 60), @('Sleep in 2 hours', 'sleep', 120), @('-'), @('Cancel timer', 'cancel', 0))) {
    if ($opt[0] -eq '-') { [void]$miTimer.DropDownItems.Add('-'); continue }
    $it = New-Object System.Windows.Forms.ToolStripMenuItem($opt[0]); $it.Tag = @($opt[1], $opt[2])
    $it.Add_Click({ Set-PowerTimer $this.Tag[0] $this.Tag[1] })
    [void]$miTimer.DropDownItems.Add($it)
}
[void]$menu.Items.Add($miTimer)
[void]$menu.Items.Add('-')
$miBoost =New-Object System.Windows.Forms.ToolStripMenuItem('Auto Game Boost')
$miBoost.CheckOnClick = $true; $miBoost.Checked = [bool]$settings.AutoBoost
$miBoost.Add_Click({ $s = Get-Settings; $s.AutoBoost = $miBoost.Checked; Save-Settings $s })
[void]$menu.Items.Add($miBoost)
$miReopen = New-Object System.Windows.Forms.ToolStripMenuItem('Reopen apps after the game')
$miReopen.CheckOnClick = $true; $miReopen.Checked = [bool]$settings.ReopenAfterGame
$miReopen.Add_Click({ $s = Get-Settings; $s.ReopenAfterGame = $miReopen.Checked; Save-Settings $s })
[void]$menu.Items.Add($miReopen)
$miRecord = New-Object System.Windows.Forms.ToolStripMenuItem('Record game sessions')
$miRecord.CheckOnClick = $true
$miRecord.Checked = -not ($settings.PSObject.Properties.Name -contains 'RecordSessions' -and $settings.RecordSessions -eq $false)
$miRecord.Add_Click({ $s = Get-Settings; $s | Add-Member RecordSessions $miRecord.Checked -Force; Save-Settings $s })
[void]$menu.Items.Add($miRecord)
$miPrio = New-Object System.Windows.Forms.ToolStripMenuItem('Game priority boost (High CPU priority)')
$miPrio.CheckOnClick = $true; $miPrio.Checked = -not ($settings.PSObject.Properties.Name -contains 'GamePriority' -and $settings.GamePriority -eq $false)
$miPrio.Add_Click({ $s = Get-Settings; $s | Add-Member GamePriority $miPrio.Checked -Force; Save-Settings $s })
[void]$menu.Items.Add($miPrio)
$miPanic = New-Object System.Windows.Forms.ToolStripMenuItem('Panic key: Ctrl+Alt+End')
$miPanic.CheckOnClick = $true; $miPanic.Checked = [bool]$settings.PanicHotkey
$miPanic.Add_Click({ $s = Get-Settings; $s.PanicHotkey = $miPanic.Checked; Save-Settings $s })
[void]$menu.Items.Add($miPanic)
$miStartup = New-Object System.Windows.Forms.ToolStripMenuItem('Start with Windows')
$miStartup.CheckOnClick = $true; $miStartup.Checked = (Test-TrayAtStartup)
$miStartup.Add_Click({ Set-TrayAtStartup $miStartup.Checked })
[void]$menu.Items.Add($miStartup)
[void]$menu.Items.Add('-')
$miExit = $menu.Items.Add('Exit tray app')
$miExit.Add_Click({ Restore-RulePower; Stop-Balance; $timer.Stop(); $dashTimer.Stop(); if ($script:Dash) { try { $script:Dash.Stop() } catch { } }; $icon.Visible = $false; if ($hotkey) { $hotkey.Dispose() }; if ($audioKey) { $audioKey.Dispose() }; [System.Windows.Forms.Application]::Exit() })
if (Test-IconFont) {
    $ic = [System.Drawing.Color]::FromArgb(70, 60, 90)
    foreach ($pair in @(@($miOpen, 'screwdriver-wrench'), @($miMon, 'gauge-high'), @($miServer, 'server'), @($miClean, 'broom'), @($miSession, 'rocket'), @($miPreGame, 'clipboard-check'), @($miAudio, 'volume-high'), @($miTimer, 'moon'), @($miExit, 'power-off'))) {
        $pair[0].Image = Get-Icon $pair[1] $ic 16
    }
}
$icon.ContextMenuStrip = $menu
$icon.Add_DoubleClick({ $miOpen.PerformClick() })

# ---- panic key
$Protected = @('explorer', 'dwm', 'csrss', 'winlogon', 'svchost', 'lsass', 'services', 'System', 'Idle', 'ShellExperienceHost', 'StartMenuExperienceHost', 'SearchHost', 'TextInputHost')
$hotkey = New-Object HallowHotKey(0x4003, 0x23)   # MOD_ALT|MOD_CONTROL|MOD_NOREPEAT, VK_END
$hotkey.add_Pressed({
    if (-not $miPanic.Checked) { return }
    $h = [HallowNative]::GetForegroundWindow(); $procId = [uint32]0
    [void][HallowNative]::GetWindowThreadProcessId($h, [ref]$procId)
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $p -or $Protected -contains $p.ProcessName -or $p.Id -eq $PID) { Notify 'Panic key: nothing to close in front.'; return }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Notify "Panic key: force-closed $($p.ProcessName)."
})
if (-not $hotkey.Ok) { Log '[tray] Could not register Ctrl+Alt+End (another app uses it).' }
# ---- audio switch key: Ctrl+Alt+Home flips between the two audio setups (Mic tab > Audio switcher)
$audioKey = New-Object HallowHotKey(0x4003, 0x24)   # MOD_ALT|MOD_CONTROL|MOD_NOREPEAT, VK_HOME
$audioKey.add_Pressed({ try { Notify (Switch-AudioSetup) } catch { Notify "Audio switch failed: $($_.Exception.Message)" } })
if (-not $audioKey.Ok) { Log '[tray] Could not register Ctrl+Alt+Home (another app uses it).' }

# ---- toolkit update notice (checks GitHub in the background, at most every 12 hours)
$script:UpdJob = $null; $script:Ticks = 0
function Start-TrayUpdateCheck {
    $s = Get-Settings
    if (-not $s.AutoUpdate -or $script:UpdJob) { return }
    $last = [datetime]::MinValue; [void][datetime]::TryParse("$($s.LastTrayUpdateCheck)", [ref]$last)
    if (((Get-Date) - $last).TotalHours -lt 12) { return }
    $ps = [powershell]::Create(); [void]$ps.AddScript($SelfUpdateCheckWork.ToString()).AddArgument($UpdateRepo)
    $script:UpdJob = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function Complete-TrayUpdateCheck {
    if (-not $script:UpdJob -or -not $script:UpdJob.H.IsCompleted) { return }
    try { $r = @($script:UpdJob.PS.EndInvoke($script:UpdJob.H))[0] } catch { $r = $null }
    $script:UpdJob.PS.Dispose(); $script:UpdJob = $null
    $s = Get-Settings; $s | Add-Member LastTrayUpdateCheck ((Get-Date).ToString('o')) -Force; Save-Settings $s
    if ($r -and -not $r.Error -and (Test-NewerVersion $r.Version $AppVersion)) {
        Notify "Hallow Toolkit v$($r.Version) is out (you have v$AppVersion). Click here to open the toolkit and update."
    }
}
$icon.Add_BalloonTipClicked({
    if ($script:AlertPage -eq 'Server') { $script:AlertPage = ''; $miServer.PerformClick() }
    elseif ($script:AlertPage -eq 'Hallow') { $script:AlertPage = ''; Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"", '-StartPage', 'Hallow') }
    else { $miOpen.PerformClick() }
})

# ---- v5.7: links between the Hallow apps - checked quietly once a day; a pop-up only when something is red.
# Off when Tray alerts (Server tab) are off.
$script:LinkJob = $null
function Start-TrayLinkCheck {
    $s = Get-Settings
    if ($script:LinkJob -or -not $s.ServerAlerts) { return }
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ("$($s.LastLinkCheck)" -eq $today) { return }
    if (-not @($FamilyApps | Where-Object { Test-FamilyInstalled $_.Name }).Count) { return }
    $s | Add-Member LastLinkCheck $today -Force; Save-Settings $s
    $ps = [powershell]::Create(); [void]$ps.AddScript($FamilyLinkCheckWork.ToString()).AddArgument([string[]]@($FamilyApps | ForEach-Object Name)).AddArgument((Get-LinkCheckOptions))
    $script:LinkJob = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function Complete-TrayLinkCheck {
    if (-not $script:LinkJob -or -not $script:LinkJob.H.IsCompleted) { return }
    try { $lines = @($script:LinkJob.PS.EndInvoke($script:LinkJob.H) | Where-Object { $_.Level }) } catch { $lines = @() }
    $script:LinkJob.PS.Dispose(); $script:LinkJob = $null
    $red = @($lines | Where-Object { $_.Level -eq 'bad' })
    Log ("[tray] Hallow app links: {0} green, {1} amber, {2} red." -f @($lines | Where-Object Level -eq 'good').Count, @($lines | Where-Object Level -eq 'warn').Count, $red.Count)
    if ($red.Count -and (Get-Settings).ServerAlerts) {
        $msg = ($red | ForEach-Object { "Hallow $($_.App): $($_.Text)" }) -join '; '
        if ($msg.Length -gt 180) { $msg = $msg.Substring(0, 177) + '...' }
        $script:AlertPage = 'Hallow'; Notify "$msg. Click to open Check links."
    }
}

# ---- server alerts: every 5 minutes; tells you when an app/server that was up goes down (twice in a row), or a drive is nearly full
$script:SrvJob = $null; $script:SrvState = @{}; $script:DriveWarned = @{}; $script:AlertPage = ''
function Start-TrayServerCheck {
    if ($script:SrvJob) { return }
    if (-not (Get-Settings).ServerAlerts) { $script:SrvState = @{}; return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($ServerCheckWork.ToString()).AddArgument($ServerCatalog).AddArgument((Get-ServerChecks)).AddArgument((Get-ServerHidden))
    $script:SrvJob = @{ PS = $ps; H = $ps.BeginInvoke() }
}
function Complete-TrayServerCheck {
    if (-not $script:SrvJob -or -not $script:SrvJob.H.IsCompleted) { return }
    try { $rows = @($script:SrvJob.PS.EndInvoke($script:SrvJob.H)) } catch { $rows = @() }
    $script:SrvJob.PS.Dispose(); $script:SrvJob = $null
    $script:DashState.Servers = $rows
    $down = @(); $back = @()
    foreach ($r in $rows) {
        if (-not $r.Key) { continue }
        if ($r.Kind -eq 'Drive') {
            if ($r.Verdict -eq 'Bad' -and $script:DriveWarned[$r.Key] -ne (Get-Date).Date) { $script:DriveWarned[$r.Key] = (Get-Date).Date; $down += "$($r.Name) is nearly full ($($r.Detail))" }
            continue
        }
        if (-not $script:SrvState.ContainsKey($r.Key)) { $script:SrvState[$r.Key] = @{ SeenUp = $false; Fails = 0; Alerted = $false } }
        $st = $script:SrvState[$r.Key]
        if ($r.Verdict -eq 'Good') {
            if ($st.Alerted) { $back += $r.Name }
            $st.SeenUp = $true; $st.Fails = 0; $st.Alerted = $false
        } else {
            $st.Fails++
            if ($st.SeenUp -and $st.Fails -eq 2 -and -not $st.Alerted) { $st.Alerted = $true; $down += "$($r.Name) - $($r.Status)" }
        }
    }
    if ($down) {
        $script:AlertPage = 'Server'; Notify ("Server alert: {0}. Click for details." -f ($down -join '; '))
        if (Get-LinkSetting 'DiscordServer' $true) { Send-DiscordPostAsync 'Server alert' (($down | ForEach-Object { "- $_" }) -join "`n") 0xF05A5A }
    }
    elseif ($back) {
        Notify ("Back up: {0}" -f ($back -join ', '))
        if (Get-LinkSetting 'DiscordServer' $true) { Send-DiscordPostAsync 'Back up' ($back -join ', ') 0x6ED28C }
    }
}

# ---- phone dashboard: read-only status page on the Tailscale address (Server tab > Phone dashboard)
$script:DashState = @{ InGame = $null; GameStart = Get-Date; Servers = @(); Timer = $null }
$script:Dash = $null; $script:DashIP = $null
function Update-Dashboard {
    $want = Get-LinkSetting 'PhoneDashboard' $false
    $ip = $(if ($want) { Get-TailscaleIP })
    if ($script:Dash -and (-not $want -or $ip -ne $script:DashIP)) { try { $script:Dash.Stop() } catch { }; $script:Dash = $null; Log '[tray] Phone dashboard stopped.' }
    if ($want -and $ip -and -not $script:Dash) {
        $script:Dash = Start-DashboardListener $ip; $script:DashIP = $ip
        if ($script:Dash) { Log "[tray] Phone dashboard on at http://${ip}:$DashPort/ (key hidden)" } else { Log '[tray] Phone dashboard could not start (port 5190 in use?).' }
    }
}
$dashTimer = New-Object System.Windows.Forms.Timer
$dashTimer.Interval = 300
$dashTimer.Add_Tick({ if ($script:Dash) { try { Invoke-DashboardPoll $script:Dash $script:DashState } catch { Log "[tray] dashboard: $($_.Exception.Message)" } } })
$dashTimer.Start()

# ---- sleep / shut down timer (tray menu)
$script:PowerTimer = $null
function Set-PowerTimer([string]$Action, [int]$Minutes) {
    if ($Action -eq 'cancel') {
        if ($script:PowerTimer -and $script:PowerTimer.Fired) { & shutdown.exe /a 2>$null }
        $script:PowerTimer = $null; $script:DashState.Timer = $null; $miTimer.Text = 'Sleep / shut down timer'; Notify 'Timer cancelled.'; return
    }
    $at = (Get-Date).AddMinutes($Minutes)
    $script:PowerTimer = @{ Action = $Action; At = $at; Warned = $false; Fired = $false; Postponed = $false }
    $label = "{0} at {1:h:mm tt}" -f $(if ($Action -eq 'shutdown') { 'Shut down' } else { 'Sleep' }), $at
    $script:DashState.Timer = $label; $miTimer.Text = "Timer: $label"
    Notify "$label. Right-click the tray icon > Timer > Cancel to stop it."
}
function Test-PowerTimer {
    $t = $script:PowerTimer; if (-not $t -or $t.Fired) { return }
    $left = ($t.At - (Get-Date)).TotalSeconds
    if ($left -le 0 -and $script:InGame -and -not $t.Postponed) {
        $t.At = (Get-Date).AddMinutes(15); $t.Warned = $false; $t.Postponed = $true
        $script:DashState.Timer = "{0} at {1:h:mm tt}" -f $(if ($t.Action -eq 'shutdown') { 'Shut down' } else { 'Sleep' }), $t.At; $miTimer.Text = "Timer: $($script:DashState.Timer)"
        Notify "You're still playing $($script:InGame) - timer moved 15 minutes."; return
    }
    if ($left -le 60 -and -not $t.Warned) { $t.Warned = $true; Notify ("{0} in 1 minute. Right-click the tray icon > Timer > Cancel to stop." -f $(if ($t.Action -eq 'shutdown') { 'Shutting down' } else { 'Going to sleep' })) }
    if ($left -le 0) {
        $t.Fired = $true; $miTimer.Text = 'Sleep / shut down timer'; $script:DashState.Timer = $null
        if ($t.Action -eq 'shutdown') { Log '[tray] Timer: shutting down.'; & shutdown.exe /s /t 30 /c 'Hallow Toolkit timer - shutting down in 30 seconds.' }
        else { Log '[tray] Timer: sleep.'; $script:PowerTimer = $null; [void][System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false) }
    }
}

# ---- v5.10 per-game rules: put the power plan back (only if nothing else changed it meanwhile)
$script:Rule = $null; $script:RulePower = $null
function Restore-RulePower {
    $rp = $script:RulePower; $script:RulePower = $null
    if (-not $rp) { return }
    try { if ((Get-ActiveSchemeGuid) -eq $rp.Set) { powercfg /setactive $rp.Prev | Out-Null; Log "[tray] Power plan back to $(Get-SchemeName)" } } catch { }
}

# ---- v5.13 background restraint (ProBalance style) + IdleSaver - both off until turned on on the Gaming tab
$script:Restraint = New-RestraintState; $script:Idle = New-IdleState; $script:RuleGame = $null
$m = Restore-IdleLeftover; if ($m) { Log "[tray] $m" }   # the tray stopped while you were away last time
function Stop-IdleSaverNow { if ($script:Idle.Switched) { $m = Invoke-IdleSaverPass $script:Idle (Get-IdleSaverSettings) $true; if ($m) { Log "[tray] $m" } } }
function Stop-Balance {
    $ev = @(Restore-AllRestrained $script:Restraint 'the tray app closed'); Add-RestraintLog $ev
    if ($script:Idle.Switched) { $sw = $script:Idle.Switched; $script:Idle.Switched = $null; Clear-IdleSwitchedMark; if ((Get-ActiveSchemeGuid) -eq $sw.Set) { [void](Set-PowerPlanChecked $sw.Prev) } }
}
function Invoke-BalancePasses($Game) {
    $gameOn = [bool]$script:InGame -or [bool](Get-GameSession) -or (Test-HubPlaying)
    $rs = Get-RestraintSettings
    $active = $rs.On -and ($rs.Always -or $gameOn)
    if ($active -or $script:Restraint.Restrained.Count) {
        if (((Get-Date) - $script:Restraint.RootsAt).TotalMinutes -ge 5) { $script:Restraint.Roots = @(Get-GameRoots); $script:Restraint.RootsAt = Get-Date }
        $fg = [uint32]0; [void][HallowNative]::GetWindowThreadProcessId([HallowNative]::GetForegroundWindow(), [ref]$fg)
        $ctx = @{ GameRoots = $script:Restraint.Roots; Protect = @(@($(if ($Game) { $Game.Process }), $script:RuleGame) | Where-Object { $_ }); Exclude = $rs.Exclude; Foreground = [int]$fg; Self = @($PID) }
        $ev = @(Invoke-RestraintPass $script:Restraint $active $rs.Pct $ctx 2 3 $(if ($rs.On) { 'the game ended' } else { 'restraint was turned off' }))
        if ($ev.Count) { Add-RestraintLog $ev; foreach ($e in $ev) { Log "[tray] Background restraint: $($e.Action.ToLower()) $($e.Name) - $($e.Reason)" } }
    } else { $script:Restraint.LastTime = $null; $script:Restraint.Hot = @{} }   # nothing to do: start fresh next time
    $io = Get-IdleSaverSettings
    if ($io.On -or $script:Idle.Switched) { $m = Invoke-IdleSaverPass $script:Idle $io $gameOn; if ($m) { Log "[tray] $m" } }
}

# ---- auto game boost loop
$script:InGame = $null; $script:Closed = @(); $script:Misses = 0; $script:HotWarned = $false
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({
    try {
        $script:Ticks++
        if ($script:Ticks % 720 -eq 1) { Start-TrayUpdateCheck }   # at start, then hourly (the 12-hour limit is inside)
        Complete-TrayUpdateCheck
        if ($script:Ticks % 6 -eq 1 -and (Get-Settings).KeepMicLevel) {   # every 30 s
            $fixedMics = @(Restore-MicLevels)
            if ($fixedMics.Count -and -not $script:MicWarned) {
                $script:MicWarned = $true
                Notify "Something lowered your mic ($($fixedMics -join ', ')) - put it back to your level. If it keeps happening, turn off Discord's 'Automatically adjust input volume'."
            } elseif ($fixedMics.Count) { Log "[tray] Mic put back to your level: $($fixedMics -join ', ')" }
        }
        if ($script:Ticks % 60 -eq 2) { Start-TrayServerCheck }   # 5 minutes
        if ($script:Ticks % 720 -eq 60) { Start-TrayLinkCheck }    # 5 minutes after start, then hourly (once a day is inside)
        Complete-TrayLinkCheck
        if ($script:Ticks % 12 -eq 7) {   # every minute: a new scheduled clean-up report -> show what it freed (once)
            try {
                $rep = @(Get-CleanReports | Where-Object { -not $_.DryRun })[0]
                if ($rep -and "$((Get-Settings).LastCleanReportShown)" -ne (Split-Path -Leaf $rep.File)) {
                    $s = Get-Settings; $s | Add-Member LastCleanReportShown (Split-Path -Leaf $rep.File) -Force; Save-Settings $s
                    if (((Get-Date) - [datetime]::Parse($rep.Time)).TotalDays -lt 2) { Notify "Scheduled clean-up: $(Format-CleanReport $rep)" }
                }
            } catch { }
        }
        Complete-TrayServerCheck
        $g = Find-RunningGame
        if ($script:InGame -and $miRecord.Checked) { try { $script:Samples.Add((Get-SessionSample)) } catch { } }
        # overheat alert while playing (once per game)
        if ($script:InGame -and -not $script:HotWarned -and $NvSmi) {
            $gt = $null
            if ($miRecord.Checked -and $script:Samples.Count) { $gt = $script:Samples[$script:Samples.Count - 1].gtemp }
            else { $q = & $NvSmi '--query-gpu=temperature.gpu' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1; if ($q) { $gt = [double]$q } }
            if ($null -ne $gt -and $gt -ge 85) {
                $script:HotWarned = $true
                Notify ("GPU is running hot: {0:N0} C in {1}. Check case fans and dust, or cap your FPS in the game." -f $gt, $script:InGame)
            }
        }
        $script:DashState.InGame = $script:InGame
        if ($script:Ticks % 12 -eq 1) { Update-Dashboard }   # every minute: start/stop the phone dashboard to match the setting
        Test-PowerTimer
        if ((Get-DiscordWebhook) -and ((Get-LinkSetting 'DiscordNowPlaying' $false) -or (Get-LinkSetting 'DiscordMicStatus' $false))) {
            try { Update-MixerPosts (Invoke-Mixer '/state') } catch { Log "[tray] mixer posts: $($_.Exception.Message)" }
        }
        if ((Get-DiscordWebhook) -and (Get-LinkSetting 'DiscordClips' $false)) {
            try { Update-ClipPosts (Get-ClipsStatus) } catch { Log "[tray] clip posts: $($_.Exception.Message -replace 'https?://\S+', '(webhook)')" }
        } else { $script:ClipPost.Since = $null; Complete-ClipPost }   # off: start fresh next time it's turned on
        if ($g -and -not $script:InGame) {
            $script:InGame = $g.Name; $script:Misses = 0; $script:HotWarned = $false
            $script:DashState.InGame = $g.Name; $script:DashState.GameStart = Get-Date
            $script:SessStart = Get-Date; $script:Samples = New-Object System.Collections.Generic.List[object]
            Stop-IdleSaverNow   # v5.13: away power plan off before the game's own plan
            # v5.10: this game's rule (priority, cores, power plan)
            $script:Rule = Find-GameRule $g; $script:RuleDone = New-Object 'System.Collections.Generic.HashSet[int]'; $script:RuleGame = $g.Process
            if ($script:Rule) {
                $n = @(Set-GameRuleProcesses $script:Rule $g.Process $script:RuleDone).Count
                $pw = ''
                if ($script:Rule.Power) {
                    $prev = Get-ActiveSchemeGuid
                    if ($prev -and $prev -ne $script:Rule.Power) { powercfg /setactive $script:Rule.Power | Out-Null; $script:RulePower = @{ Prev = $prev; Set = $script:Rule.Power }; $pw = ", power plan $(Get-SchemeName)" }
                }
                Log "[tray] Rule for $($g.Name): $($RulePriorities[$script:Rule.Priority]) priority, $($RuleAffinities[$script:Rule.Affinity].ToLower())$pw ($n process(es))"
            }
            if ($miPrio.Checked -and -not $script:Rule) { $pn = Set-GamePriority $g.Id; if ($pn) { Log "[tray] $pn set to High priority" } }
            $s = Get-Settings
            if ($s.AutoBoost -and $s.BoostApps.Count) {
                $running = @($s.BoostApps | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
                if ($running) {
                    $script:Closed = Close-Apps $running -Quiet
                    Notify ("Game Boost for {0}: closed {1}" -f $g.Name, ($running -join ', '))
                } else { $script:Closed = @(); Log "[tray] Game started: $($g.Name) (no boost apps were running)" }
            }
        } elseif (-not $g -and $script:InGame) {
            $script:Misses++
            if ($script:Misses -ge 2) {
                $name = $script:InGame; $script:InGame = $null
                Restore-RulePower; $script:Rule = $null
                if ($miRecord.Checked -and $script:Samples.Count -ge 2) {
                    $sum = Save-GameSession $name $script:SessStart $script:Samples
                    if ($sum) {
                        $bits = @("$($sum.Minutes) min")
                        if ($null -ne $sum.GpuTempMax) { $bits += ('GPU max {0:N0} C' -f $sum.GpuTempMax) }
                        if ($null -ne $sum.GpuAvg) { $bits += ('GPU avg {0:N0}%' -f $sum.GpuAvg) }
                        if ($null -ne $sum.VramMax) { $bits += ('VRAM {0:N1} GB' -f $sum.VramMax) }
                        Notify ("Session saved - {0}: {1}. See Games tab." -f $name, ($bits -join ', '))
                        if (Get-LinkSetting 'DiscordSessions' $true) { Send-DiscordPostAsync "Played $name" ($bits -join ' | ') 0xA98BE0 }
                    }
                }
                $s = Get-Settings
                if ($s.ReopenAfterGame -and $script:Closed.Count) {
                    $back = @()
                    foreach ($p in $script:Closed) {
                        try { Start-Process -FilePath $p -WindowStyle Minimized -ErrorAction Stop; $back += [IO.Path]::GetFileNameWithoutExtension($p) } catch { Log "[tray] Could not reopen $p" }
                    }
                    if ($back) { Notify ("{0} closed - reopened {1}" -f $name, ($back -join ', ')) }
                } else { Log "[tray] Game closed: $name" }
                $script:Closed = @()
            }
        } elseif ($g) { $script:Misses = 0; if ($script:Rule) { [void](Set-GameRuleProcesses $script:Rule $script:RuleGame $script:RuleDone) } }   # processes the game starts later
        if ($script:Ticks % 2 -eq 0) { try { Invoke-BalancePasses $g } catch { Log "[tray] restraint / IdleSaver: $($_.Exception.Message)" } }   # v5.13, every 10 s
    } catch { Log "[tray] error: $($_.Exception.Message)" }
})
$timer.Start()

Log '[tray] Hallow tray app started.'
try { [System.Windows.Forms.Application]::Run() } catch { Write-HallowCrash $_ 'Hallow Toolkit tray' | Out-Null; throw }
$mutex.ReleaseMutex()
