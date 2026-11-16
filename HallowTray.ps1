<#
  Hallow Toolkit tray app (orange H by the clock).
   - Auto Game Boost: when a game starts, closes the apps on your Auto Boost list; reopens them when you quit.
   - Panic key: Ctrl+Alt+End force-closes the app/game in front (for frozen games).
#>
param([switch]$Once)   # -Once: run one detection pass and print what it sees (for testing)

$ErrorActionPreference = 'Continue'
$script:LogBox = $null
. (Join-Path $PSScriptRoot 'HallowCore.ps1')
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
$miSession.Checked = [bool](Get-GameSession)
$miSession.Add_Click({
    if (Get-GameSession) { Stop-GameSession; Notify 'Game session ended - power plan, updates and apps are back to normal.' }
    else { Start-GameSession; Notify 'Game session on - Boost apps closed, High performance power. Click again when done.' }
    $miSession.Checked = [bool](Get-GameSession)
})
[void]$menu.Items.Add($miSession)
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
$miExit.Add_Click({ $timer.Stop(); $icon.Visible = $false; if ($hotkey) { $hotkey.Dispose() }; [System.Windows.Forms.Application]::Exit() })
if (Test-IconFont) {
    $ic = [System.Drawing.Color]::FromArgb(70, 60, 90)
    foreach ($pair in @(@($miOpen, 'screwdriver-wrench'), @($miMon, 'gauge-high'), @($miServer, 'server'), @($miClean, 'broom'), @($miSession, 'rocket'), @($miExit, 'power-off'))) {
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
$icon.Add_BalloonTipClicked({ if ($script:AlertPage -eq 'Server') { $script:AlertPage = ''; $miServer.PerformClick() } else { $miOpen.PerformClick() } })

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
    if ($down) { $script:AlertPage = 'Server'; Notify ("Server alert: {0}. Click for details." -f ($down -join '; ')) }
    elseif ($back) { Notify ("Back up: {0}" -f ($back -join ', ')) }
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
        if ($g -and -not $script:InGame) {
            $script:InGame = $g.Name; $script:Misses = 0; $script:HotWarned = $false
            $script:SessStart = Get-Date; $script:Samples = New-Object System.Collections.Generic.List[object]
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
                if ($miRecord.Checked -and $script:Samples.Count -ge 2) {
                    $sum = Save-GameSession $name $script:SessStart $script:Samples
                    if ($sum) {
                        $bits = @("$($sum.Minutes) min")
                        if ($null -ne $sum.GpuTempMax) { $bits += ('GPU max {0:N0} C' -f $sum.GpuTempMax) }
                        if ($null -ne $sum.GpuAvg) { $bits += ('GPU avg {0:N0}%' -f $sum.GpuAvg) }
                        if ($null -ne $sum.VramMax) { $bits += ('VRAM {0:N1} GB' -f $sum.VramMax) }
                        Notify ("Session saved - {0}: {1}. See Games tab." -f $name, ($bits -join ', '))
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
        } elseif ($g) { $script:Misses = 0 }
    } catch { Log "[tray] error: $($_.Exception.Message)" }
})
$timer.Start()

Log '[tray] Hallow tray app started.'
[System.Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
