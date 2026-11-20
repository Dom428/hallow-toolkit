<#
  Hallow Toolkit - window code for the v5.14 gamer tools. Dot-sourced by HallowToolkit.ps1 after the pages are built.
    Tools:   mouse report rate, keyboard tester, dead pixel test, motion / frame-skip test
    Network: ping graph + route to a server, Undo DNS change
    Gaming:  display refresh rate (max, with a 15-second revert), shader caches with sizes, Windows gaming settings
    Games:   Verify files
  The logic lives in HallowGamerTools.ps1.
#>

# ---------------------------------------------------------------- small helpers
function New-GtWindow([string]$Title, [int]$W, [int]$H) {
    $win = New-Object System.Windows.Forms.Form
    $win.Text = $Title; $win.Size = New-Object System.Drawing.Size($W, $H); $win.StartPosition = 'CenterParent'
    $win.BackColor = $C.Bg; $win.ForeColor = $C.Text; $win.Font = New-Font 10; $win.FormBorderStyle = 'FixedDialog'; $win.MaximizeBox = $false
    if ($form.Icon) { $win.Icon = $form.Icon }
    $win
}
function New-GtCanvas($Parent) {
    $p = New-Object System.Windows.Forms.Panel; $p.Dock = 'Fill'
    $p.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance, NonPublic').SetValue($p, $true, $null)
    $Parent.Controls.Add($p); $p
}
# A label that works like a button but can't take keyboard focus (so Space / Enter in the key tester never click it).
function New-GtLink($Parent, [string]$Text, [int]$X, [int]$Y, [scriptblock]$Click) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.AutoSize = $false; $l.Size = New-Object System.Drawing.Size(110, 30); $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.TextAlign = 'MiddleCenter'; $l.BackColor = $C.Panel; $l.ForeColor = $C.Text; $l.Cursor = [System.Windows.Forms.Cursors]::Hand; $l.Font = New-Font 9.5
    $l.Add_Click($Click); $l.Add_MouseEnter({ $this.BackColor = $C.PanelHi }); $l.Add_MouseLeave({ $this.BackColor = $C.Panel })
    $Parent.Controls.Add($l); $l
}
function Get-ToolkitScreen { [System.Windows.Forms.Screen]::FromControl($form) }
function Get-ScreenHz($Screen) {
    $m = @(Get-DisplayModes | Where-Object { $_.Device -eq $Screen.DeviceName })[0]
    if ($m) { $m.Hz } else { 60 }
}

# ================================================================ TOOLS: mouse, keyboard, monitor tests
$f = $script:PageFlows['Tools']
Add-Section $f 'Gamer tests - mouse, keyboard and monitor' 'crosshairs'
Add-Tool $f 'Mouse report rate' 'Polling rate test: move the mouse' { Show-MouseRateTest } -Primary -Icon 'computer-mouse' | Out-Null
Add-Tool $f 'Keyboard tester' 'Every key + ghosting check' { Show-KeyboardTest } -Icon 'keyboard' | Out-Null
Add-Tool $f 'Dead pixel test' 'Full-screen colours, Esc to exit' { Show-PixelTest } -Icon 'palette' | Out-Null
Add-Tool $f 'Motion & frame-skip test' 'Refresh rate check, Esc to exit' { Show-MotionTest } -Icon 'tv' | Out-Null
Add-Note $f 'The tests only read the mouse and keyboard while their own window is in front, and save nothing. The screen tests fill the screen the toolkit is on.' | Out-Null

function Show-MouseRateTest {
    $win = New-GtWindow 'Mouse report rate' 760 470
    $canvas = New-GtCanvas $win
    $st = @{ Ri = $null; Hist = New-Object System.Collections.Generic.List[int]; Best = 0.0 }
    $win.Tag = $st
    $canvas.Add_Paint({
        param($s, $e)
        $st = $s.FindForm().Tag; $ri = $st.Ri; if (-not $ri) { return }
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $fBig = New-Font 30 'Bold'; $fT = New-Font 12 'Bold'; $fS = New-Font 9.5
        $bText = New-Object System.Drawing.SolidBrush $C.Text; $bMuted = New-Object System.Drawing.SolidBrush $C.Muted; $bAcc = New-Object System.Drawing.SolidBrush $C.Accent
        $rate = $ri.Rate(); if ($rate -gt 0 -and $ri.Moving()) { $st.Best = [math]::Max($st.Best, $rate) }
        $std = @(125, 250, 500, 1000, 2000, 4000, 8000) | Sort-Object { [math]::Abs($_ - $rate) } | Select-Object -First 1
        if ($rate -le 0) { $g.DrawString('Move the mouse in quick circles inside this window...', $fT, $bText, 24, 24) }
        else {
            $g.DrawString(('{0:N0} Hz' -f $rate), $fBig, $bText, 20, 16)
            $g.DrawString(("about {0} Hz polling rate{1}" -f $std, $(if (-not $ri.Moving()) { '  (paused - keep moving for a fresh reading)' } else { '' })), $fT, $bAcc, 24, 70)
        }
        $g.DrawString(("Reports in the last second: {0:N0}    Peak in one second: {1:N0}    Total reports: {2:N0}" -f $(if ($ri.Moving()) { $ri.PerSecond } else { 0 }), $ri.PeakPerSecond, $ri.Reports), $fS, $bMuted, 24, 102)
        # reports per second over the last 10 seconds
        $gx = 24; $gy = 140; $gw = 700; $gh = 190
        $g.FillRectangle((New-Object System.Drawing.SolidBrush $C.Panel), $gx, $gy, $gw, $gh)
        $max = [math]::Max(1000, (@($st.Hist) + 0 | Measure-Object -Maximum).Maximum)
        $pen = New-Object System.Drawing.Pen($C.Grid, 1)
        foreach ($lvl in 125, 500, 1000, 2000, 4000, 8000) { if ($lvl -le $max) { $y = $gy + $gh - [int]($gh * $lvl / $max); $g.DrawLine($pen, $gx, $y, $gx + $gw, $y); $g.DrawString("$lvl", $fS, $bMuted, $gx + $gw - 40, $y - 16) } }
        $n = $st.Hist.Count; $bw = $gw / 100.0
        for ($i = 0; $i -lt $n; $i++) { $v = $st.Hist[$i]; $h = [int]($gh * $v / $max); $g.FillRectangle($bAcc, [float]($gx + $i * $bw), [float]($gy + $gh - $h), [float]([math]::Max(1, $bw - 1)), [float]$h) }
        $g.DrawString("Best steady reading: $(if ($st.Best -gt 0) { '{0:N0} Hz' -f $st.Best } else { '-' }). Wireless mice often run lower to save battery, and many only reach their full rate while moving fast. Set the rate in your mouse's own app (G HUB, Synapse, iCUE...).", $fS, $bMuted, (New-Object System.Drawing.RectangleF(24, 340, 700, 50)))
    })
    New-GtLink $win 'Start over' 620 395 { $st = $this.FindForm().Tag; $st.Ri.Reset(); $st.Hist.Clear(); $st.Best = 0.0 } | Out-Null
    $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 100
    $tm.Add_Tick({ $st = $win.Tag; if ($st.Ri) { $st.Hist.Add($(if ($st.Ri.Moving()) { $st.Ri.PerSecond } else { 0 })); while ($st.Hist.Count -gt 100) { $st.Hist.RemoveAt(0) } }; $canvas.Invalidate() })
    $win.Add_Shown({ $st = $this.Tag; $st.Ri = New-Object HallowRawInput($this.Handle, $true, $false); $tm.Start() })
    $win.Add_FormClosed({ $tm.Stop(); $tm.Dispose(); $st = $this.Tag; if ($st.Ri) { $st.Ri.Stop() }; if ($st.Best -gt 0) { Log ('Mouse report rate: about {0:N0} Hz at best.' -f $st.Best) } })
    Log 'Mouse report rate test opened.'
    [void]$win.ShowDialog($form)
}

# Keyboard layout (ANSI, full size). Each key: x, y, width, height in key units, VK id (left/right specific), label.
function Get-KeyboardLayout {
    $keys = New-Object System.Collections.Generic.List[object]
    function Row([double]$Y, [double]$X, $Items) {
        foreach ($it in $Items) {
            if ($it -is [double] -or $it -is [int]) { $X += $it; continue }   # a number alone = gap
            $w = $(if ($it.Count -gt 2) { [double]$it[2] } else { 1.0 }); $h = $(if ($it.Count -gt 3) { [double]$it[3] } else { 1.0 })
            $keys.Add([pscustomobject]@{ X = $X; Y = $Y; W = $w; H = $h; Vk = [int]$it[1]; Label = $it[0] }); $X += $w
        }
    }
    Row 0 0 @(@('Esc', 0x1B), 1.0, @('F1', 0x70), @('F2', 0x71), @('F3', 0x72), @('F4', 0x73), 0.5, @('F5', 0x74), @('F6', 0x75), @('F7', 0x76), @('F8', 0x77), 0.5, @('F9', 0x78), @('F10', 0x79), @('F11', 0x7A), @('F12', 0x7B), 0.5, @('PrtSc', 0x2C), @('ScrLk', 0x91), @('Pause', 0x13))
    Row 1.5 0 @(@('`', 0xC0), @('1', 0x31), @('2', 0x32), @('3', 0x33), @('4', 0x34), @('5', 0x35), @('6', 0x36), @('7', 0x37), @('8', 0x38), @('9', 0x39), @('0', 0x30), @('-', 0xBD), @('=', 0xBB), @('Backspace', 0x08, 2), 0.5, @('Ins', 0x2D), @('Home', 0x24), @('PgUp', 0x21), 0.5, @('Num', 0x90), @('/', 0x6F), @('*', 0x6A), @('-', 0x6D))
    Row 2.5 0 @(@('Tab', 0x09, 1.5), @('Q', 0x51), @('W', 0x57), @('E', 0x45), @('R', 0x52), @('T', 0x54), @('Y', 0x59), @('U', 0x55), @('I', 0x49), @('O', 0x4F), @('P', 0x50), @('[', 0xDB), @(']', 0xDD), @('\', 0xDC, 1.5), 0.5, @('Del', 0x2E), @('End', 0x23), @('PgDn', 0x22), 0.5, @('7', 0x67), @('8', 0x68), @('9', 0x69), @('+', 0x6B, 1, 2))
    Row 3.5 0 @(@('Caps', 0x14, 1.75), @('A', 0x41), @('S', 0x53), @('D', 0x44), @('F', 0x46), @('G', 0x47), @('H', 0x48), @('J', 0x4A), @('K', 0x4B), @('L', 0x4C), @(';', 0xBA), @("'", 0xDE), @('Enter', 0x0D, 2.25), 4.0, @('4', 0x64), @('5', 0x65), @('6', 0x66))
    Row 4.5 0 @(@('Shift', 0xA0, 2.25), @('Z', 0x5A), @('X', 0x58), @('C', 0x43), @('V', 0x56), @('B', 0x42), @('N', 0x4E), @('M', 0x4D), @(',', 0xBC), @('.', 0xBE), @('/', 0xBF), @('Shift', 0xA1, 2.75), 1.5, @('Up', 0x26), 1.5, @('1', 0x61), @('2', 0x62), @('3', 0x63), @('Enter', 0x10D, 1, 2))
    Row 5.5 0 @(@('Ctrl', 0xA2, 1.25), @('Win', 0x5B, 1.25), @('Alt', 0xA4, 1.25), @('Space', 0x20, 6.25), @('Alt', 0xA5, 1.25), @('Win', 0x5C, 1.25), @('Menu', 0x5D, 1.25), @('Ctrl', 0xA3, 1.25), 0.5, @('Left', 0x25), @('Down', 0x28), @('Right', 0x27), 0.5, @('0', 0x60, 2), @('.', 0x6E))
    $keys
}

function Show-KeyboardTest {
    $win = New-GtWindow 'Keyboard tester' 1010 470
    $win.KeyPreview = $true
    $win.Add_KeyDown({ param($s, $e) $e.Handled = $true; $e.SuppressKeyPress = $true })
    $win.Add_KeyUp({ param($s, $e) $e.Handled = $true })
    $canvas = New-GtCanvas $win
    $st = @{ Ri = $null; Keys = @(Get-KeyboardLayout) }
    $win.Tag = $st
    $canvas.Add_Paint({
        param($s, $e)
        $st = $s.FindForm().Tag; $ri = $st.Ri; if (-not $ri) { return }
        Draw-KeyboardTest $e.Graphics $st.Keys $ri.Down $ri.Seen $ri.MaxDown
    })
    New-GtLink $win 'Start over' 870 395 { $this.FindForm().Tag.Ri.Reset() } | Out-Null
    $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 30
    $tm.Add_Tick({ $canvas.Invalidate() })
    $win.Add_Shown({ $st = $this.Tag; $st.Ri = New-Object HallowRawInput($this.Handle, $false, $true); $tm.Start() })
    $win.Add_FormClosed({ $tm.Stop(); $tm.Dispose(); $st = $this.Tag; if ($st.Ri) { Log ("Keyboard tester: {0} keys tested, up to {1} held at once." -f $st.Ri.Seen.Count, $st.Ri.MaxDown); $st.Ri.Stop() } })
    Log 'Keyboard tester opened.'
    [void]$win.ShowDialog($form)
}
# Separate from the window so the snapshot test can draw it into a picture.
function Draw-KeyboardTest($g, $Keys, $Down, $Seen, [int]$MaxDown) {
    $g.SmoothingMode = 'AntiAlias'
    $fT = New-Font 11 'Bold'; $fS = New-Font 9.5; $fK = New-Font 8.5
    $bText = New-Object System.Drawing.SolidBrush $C.Text; $bMuted = New-Object System.Drawing.SolidBrush $C.Muted
    $g.DrawString(("Held now: {0}     Most at once: {1}     Keys tested: {2} of {3}" -f $Down.Count, $MaxDown, @($Keys | Where-Object { $Seen.Contains($_.Vk) }).Count, $Keys.Count), $fT, $bText, 20, 12)
    $g.DrawString('Press every key - each one turns green. Ghosting check: hold W, A, S, D, Shift and Space together - all six should light up.', $fS, $bMuted, 20, 38)
    $u = 40; $ox = 20; $oy = 72
    $bPanel = New-Object System.Drawing.SolidBrush $C.Panel; $bAcc = New-Object System.Drawing.SolidBrush $C.Accent
    $bSeen = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 140, 90))
    $bOnAcc = New-Object System.Drawing.SolidBrush $C.AccentText
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    foreach ($k in $Keys) {
        $r = New-Object System.Drawing.RectangleF([float]($ox + $k.X * $u + 2), [float]($oy + $k.Y * $u + 2), [float]($k.W * $u - 4), [float]($k.H * $u - 4))
        $isDown = $Down.Contains($k.Vk); $isSeen = $Seen.Contains($k.Vk)   # (PowerShell names ignore case: not $down / $seen)
        $path = New-RoundPath $r.X $r.Y $r.Width $r.Height 6
        $g.FillPath($(if ($isDown) { $bAcc } elseif ($isSeen) { $bSeen } else { $bPanel }), $path); $path.Dispose()
        $g.DrawString($k.Label, $fK, $(if ($isDown) { $bOnAcc } elseif ($isSeen) { $bText } else { $bMuted }), $r, $sf)
    }
    $g.DrawString('The Windows key, Alt+Tab and Ctrl+Alt+Del still go to Windows. Fn and media keys are handled by the keyboard itself and do not show here. Close with the X.', $fS, $bMuted, 20, 340)
}

function Show-PixelTest {
    $scr = Get-ToolkitScreen
    $colors = @(@('Red', 255, 0, 0), @('Green', 0, 255, 0), @('Blue', 0, 0, 255), @('White', 255, 255, 255), @('Black', 0, 0, 0), @('Grey', 128, 128, 128), @('Cyan', 0, 255, 255), @('Magenta', 255, 0, 255), @('Yellow', 255, 255, 0))
    $win = New-Object System.Windows.Forms.Form
    $win.FormBorderStyle = 'None'; $win.StartPosition = 'Manual'; $win.Bounds = $scr.Bounds; $win.TopMost = $true; $win.ShowInTaskbar = $false; $win.KeyPreview = $true
    $win.Tag = @{ I = 0; Colors = $colors; HintUntil = (Get-Date).AddSeconds(4) }
    $hint = New-Object System.Windows.Forms.Label
    $hint.AutoSize = $true; $hint.Font = New-Font 13; $hint.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 24); $hint.ForeColor = [System.Drawing.Color]::White; $hint.Padding = New-Object System.Windows.Forms.Padding(12)
    $hint.Text = 'Dead pixel test - look for dots that stay one colour. Click / Space / Right arrow = next colour, Left arrow = back, Esc = exit.'
    $hint.Location = New-Object System.Drawing.Point(40, 40); $win.Controls.Add($hint)
    $apply = { param($w) $t = $w.Tag; $col = $t.Colors[$t.I]; $w.BackColor = [System.Drawing.Color]::FromArgb($col[1], $col[2], $col[3]) }
    & $apply $win
    $step = { param($w, [int]$d) $t = $w.Tag; $t.I = ($t.I + $d + $t.Colors.Count) % $t.Colors.Count; & $apply $w }
    $win.Add_KeyDown({ param($s, $e)
        $e.Handled = $true; $e.SuppressKeyPress = $true
        if ($e.KeyCode -eq 'Escape') { $s.Close() } elseif ($e.KeyCode -eq 'Left') { & $step $s -1 } elseif ($e.KeyCode -in 'Right', 'Space', 'Enter', 'Down') { & $step $s 1 } elseif ($e.KeyCode -eq 'Up') { & $step $s -1 } })
    $win.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Right') { & $step $s -1 } else { & $step $s 1 } })
    $hint.Add_Click({ & $step $this.FindForm() 1 })
    $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 4000; $tm.Add_Tick({ $this.Stop(); $hint.Visible = $false })
    $win.Add_Shown({ [System.Windows.Forms.Cursor]::Hide(); $tm.Start() })
    $win.Add_FormClosed({ $tm.Stop(); $tm.Dispose(); [System.Windows.Forms.Cursor]::Show() })
    Log 'Dead pixel test opened (Esc to exit). A pixel that stays black on every colour is dead; one that stays lit is stuck - pixel-fixing videos sometimes revive stuck ones.'
    [void]$win.ShowDialog($form)
}

function Show-MotionTest {
    $scr = Get-ToolkitScreen; $hz = Get-ScreenHz $scr
    $mt = New-Object HallowMotionTest($scr.Bounds, $hz)
    $mt.Accent = $C.Accent
    Log "Motion test opened on the screen set to $hz Hz (Esc to exit)."
    [void]$mt.ShowDialog($form)
    if ($mt.Frame -gt 60) { Log ("Motion test: {0:N1} frames a second shown on a {1} Hz screen, {2} skipped frame(s).{3}" -f $mt.Fps, $hz, $mt.Drops, $(if ([math]::Abs($mt.Fps - $hz) -gt [math]::Max(2, $hz * 0.03)) { ' Lower than the refresh rate: check the cable (DisplayPort / HDMI 2.1 for high refresh), the refresh rate in Windows and that no app is hogging the GPU.' } else { ' Every frame made it to the screen.' })) }
    $mt.Dispose()
}

# ================================================================ NETWORK: ping graph + route, DNS undo
$f = $script:PageFlows['Network']
$undo = Add-Tool $f 'Undo DNS change' 'Back to the DNS you had before' { Undo-DnsChange } -Icon 'clock-rotate-left'
$fast = @($f.Controls | Where-Object { "$($_.Text)" -like 'Use fastest DNS*' })[0]
if ($fast) { $f.Controls.SetChildIndex($undo, $f.Controls.GetChildIndex($fast) + 1); $f.SetFlowBreak($undo, $f.GetFlowBreak($fast)); $f.SetFlowBreak($fast, $false) }
Add-Section $f 'Ping graph and route to a game server' 'route'
Add-Tool $f 'Ping graph & route' 'Live ping, loss, jitter + every hop' { Show-PingGraph } -Primary -Icon 'chart-line' | Out-Null
Add-Note $f 'One small ping a second, so it is fine to leave running while you play. Hallow Overlay shares the game server here when its "Hide the server''s IP" is off.' | Out-Null

function Get-PingTargets {
    $t = New-Object System.Collections.Generic.List[string]
    $o = Get-OverlayServerHost; if ($o) { $t.Add("$($o.Game) server ($($o.Host))") }
    $r = Get-RouterAddress; if ($r) { $t.Add("Your router ($r)") }
    $t.Add('Cloudflare (1.1.1.1)'); $t.Add('Google (8.8.8.8)'); $t.Add('Quad9 (9.9.9.9)')
    $t
}
function Get-PingHost([string]$Text) { $x = "$Text".Trim(); if ($x -match '\(([^()]+)\)\s*$') { $Matches[1].Trim() } else { $x } }
function Get-PingStats($Samples) {
    $Samples = @($Samples); $ok = @($Samples | Where-Object { $_ -ge 0 }); $n = $Samples.Count
    if (-not $n) { return $null }
    $jit = 0.0; if ($ok.Count -gt 1) { $d = 0.0; for ($i = 1; $i -lt $ok.Count; $i++) { $d += [math]::Abs($ok[$i] - $ok[$i - 1]) }; $jit = $d / ($ok.Count - 1) }
    [pscustomobject]@{ Now = $(if ($Samples[-1] -ge 0) { $Samples[-1] } else { $null }); Avg = $(if ($ok) { ($ok | Measure-Object -Average).Average } else { $null })
        Min = $(if ($ok) { ($ok | Measure-Object -Minimum).Minimum } else { $null }); Max = $(if ($ok) { ($ok | Measure-Object -Maximum).Maximum } else { $null })
        Jitter = $jit; Loss = 100.0 * ($n - $ok.Count) / $n; Count = $n }
}
function Draw-PingGraph($g, [int]$W, [int]$H, $Samples, [string]$Target) {
    $g.SmoothingMode = 'AntiAlias'
    $fT = New-Font 12 'Bold'; $fS = New-Font 9.5
    $bText = New-Object System.Drawing.SolidBrush $C.Text; $bMuted = New-Object System.Drawing.SolidBrush $C.Muted
    $s = Get-PingStats $Samples
    if (-not $s) { $g.DrawString("Pick a server or type an address, then click Start.", $fT, $bText, 16, 12); return }
    $fmt = { param($v) if ($null -eq $v) { '-' } else { '{0:N0} ms' -f $v } }
    $g.DrawString(("{0}   now {1}   avg {2}   min {3}   max {4}   jitter {5:N1} ms   loss {6:N1}%" -f $Target, (& $fmt $s.Now), (& $fmt $s.Avg), (& $fmt $s.Min), (& $fmt $s.Max), $s.Jitter, $s.Loss), $fT, $bText, 16, 10)
    $verdict = if ($s.Loss -ge 2) { @("Packets are being lost - expect rubber-banding. Run the route below to see where it starts.", $C.Bad) } elseif ($s.Jitter -ge 15) { @("Ping jumps around a lot (jitter) - Wi-Fi or a busy line? Try a cable, or the 'Lag under load' test.", $C.Warn) } elseif ($s.Avg -ge 100) { @('High ping - a closer server or region will feel better.', $C.Warn) } else { @('Steady connection.', $C.Good) }
    $g.DrawString($verdict[0], $fS, (New-Object System.Drawing.SolidBrush $verdict[1]), 16, 36)
    $gx = 16; $gy = 62; $gw = $W - 32; $gh = $H - 74
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $C.Panel), $gx, $gy, $gw, $gh)
    $top = [math]::Max(50, [math]::Ceiling((@($Samples) + 0 | Measure-Object -Maximum).Maximum / 25) * 25 + 10)
    $pen = New-Object System.Drawing.Pen($C.Grid, 1)
    foreach ($lvl in 25, 50, 100, 150, 200, 300, 500) { if ($lvl -lt $top) { $y = $gy + $gh - [int]($gh * $lvl / $top); $g.DrawLine($pen, $gx, $y, $gx + $gw, $y); $g.DrawString("$lvl ms", $fS, $bMuted, $gx + 4, $y - 16) } }
    $n = 120; $step = $gw / [double]($n - 1); $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    $arr = @($Samples); $off = $n - $arr.Count
    $lp = New-Object System.Drawing.Pen($C.Accent, 2); $bad = New-Object System.Drawing.SolidBrush $C.Bad
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $x = [float]($gx + ($i + $off) * $step)
        if ($arr[$i] -lt 0) { $g.FillRectangle($bad, [float]($x - 2), [float]$gy, [float]4, [float]$gh); if ($pts.Count -gt 1) { $g.DrawLines($lp, $pts.ToArray()) }; $pts.Clear(); continue }
        $pts.Add((New-Object System.Drawing.PointF($x, [float]($gy + $gh - $gh * [math]::Min($arr[$i], $top) / $top))))
    }
    if ($pts.Count -gt 1) { $g.DrawLines($lp, $pts.ToArray()) }
    $g.DrawString('last 2 minutes - red = lost', $fS, $bMuted, ($gx + $gw - 170), ($gy + 4))
}

function Show-PingGraph {
    $win = New-GtWindow 'Ping graph and route' 900 640
    $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 48
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDown'; $combo.Width = 380; $combo.Location = New-Object System.Drawing.Point(14, 12); $combo.Font = New-Font 10
    $combo.BackColor = $C.Panel; $combo.ForeColor = $C.Text; $combo.FlatStyle = 'Flat'
    foreach ($t in Get-PingTargets) { [void]$combo.Items.Add($t) }
    if ($combo.Items.Count) { $combo.SelectedIndex = 0 }
    $top.Controls.Add($combo)
    $mk = { param($text, $x) $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, 10); $b.Size = New-Object System.Drawing.Size(120, 30)
        $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = $C.Grid; $b.BackColor = $C.Panel; $b.ForeColor = $C.Text; $top.Controls.Add($b); $b }
    $bStart = & $mk 'Start' 406; $bRoute = & $mk 'Route' 534
    $tipLbl = New-Object System.Windows.Forms.Label; $tipLbl.Text = 'or type any address'; $tipLbl.ForeColor = $C.Muted; $tipLbl.AutoSize = $true; $tipLbl.Location = New-Object System.Drawing.Point(664, 17); $top.Controls.Add($tipLbl)
    $hops = New-Object System.Windows.Forms.ListView
    $hops.View = 'Details'; $hops.FullRowSelect = $true; $hops.Dock = 'Bottom'; $hops.Height = 220; $hops.BackColor = $C.Panel; $hops.ForeColor = $C.Text; $hops.BorderStyle = 'None'; $hops.Font = New-Font 9.5
    foreach ($col in @(@('Hop', 50), @('Address', 170), @('Time', 80), @('', 540))) { [void]$hops.Columns.Add($col[0], $col[1]) }   # (not $c: names ignore case, $c would hide the colours in $C)
    $hops.OwnerDraw = $true
    $hops.Add_DrawColumnHeader({ param($s, $e)
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $C.PanelHi), $e.Bounds)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, (New-Font 8.5 'Bold'), (New-Object System.Drawing.Rectangle(($e.Bounds.X + 6), $e.Bounds.Y, $e.Bounds.Width, $e.Bounds.Height)), $C.Muted, 'VerticalCenter, Left') })
    $hops.Add_DrawItem({ param($s, $e) $e.DrawDefault = $true }); $hops.Add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true })
    $canvas = New-GtCanvas $win
    $win.Controls.Add($hops); $win.Controls.Add($top); $canvas.BringToFront()
    $st = @{ Samples = New-Object System.Collections.Generic.List[double]; Task = $null; Ping = (New-Object System.Net.NetworkInformation.Ping); Host = ''; Running = $false; Route = $null; RouteShown = 0 }
    $win.Tag = $st
    $canvas.Add_Paint({ param($s, $e) $st = $s.FindForm().Tag; Draw-PingGraph $e.Graphics $s.Width $s.Height $st.Samples $st.Host })
    $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 1000
    $tm.Add_Tick({
        $st = $win.Tag
        if ($st.Task) {
            if (-not $st.Task.IsCompleted) { return }
            $v = -1.0; try { if (-not $st.Task.IsFaulted -and $st.Task.Result.Status -eq 'Success') { $v = [double]$st.Task.Result.RoundtripTime } } catch { }
            $st.Samples.Add($v); while ($st.Samples.Count -gt 120) { $st.Samples.RemoveAt(0) }
            $st.Task = $null; $canvas.Invalidate()
        }
        if ($st.Running) { try { $st.Task = $st.Ping.SendPingAsync($st.Host, 1000) } catch { $st.Samples.Add(-1.0) } }
    })
    $bStart.Add_Click({
        $st = $win.Tag
        if ($st.Running) { $st.Running = $false; $bStart.Text = 'Start'; return }
        $h = Get-PingHost $combo.Text; if (-not $h) { return }
        if ($h -ne $st.Host) { $st.Samples.Clear(); $st.Host = $h }
        $st.Running = $true; $bStart.Text = 'Stop'; $tm.Start(); $canvas.Invalidate()
    })
    $rt = New-Object System.Windows.Forms.Timer; $rt.Interval = 300
    $rt.Add_Tick({
        $st = $win.Tag; if (-not $st.Route) { return }
        while ($st.RouteShown -lt $st.Route.Count) {
            $h = $st.Route[$st.RouteShown]; $st.RouteShown++
            $it = New-Object System.Windows.Forms.ListViewItem("$($h.Hop)"); [void]$it.SubItems.Add($h.Address); [void]$it.SubItems.Add($h.Ms); [void]$it.SubItems.Add($h.Note)
            if ($h.Address -eq '*') { $it.ForeColor = $C.Muted }
            [void]$hops.Items.Add($it)
        }
    })
    $bRoute.Add_Click({
        $st = $win.Tag
        $h = Get-PingHost $combo.Text; if (-not $h) { return }
        $hops.Items.Clear(); $st.Route = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList)); $st.RouteShown = 0
        $script:RouteWin = $win
        Start-Background "Route to $h" $TraceRouteWork @($h, $st.Route, 25) {
            param($o)
            $res = "$(@($o)[-1])"
            Log $(switch ($res) { 'done' { 'Route finished - the first hop where the time jumps (and stays high) is where the lag comes from.' } 'failed' { 'Route: that address could not be found.' } default { 'Route: the server did not answer within 25 hops (some servers block pings - the hops before it still help).' } })
        }
        $rt.Start()
    })
    $win.Add_FormClosed({ $tm.Stop(); $tm.Dispose(); $rt.Stop(); $rt.Dispose(); $this.Tag.Running = $false; try { $this.Tag.Ping.Dispose() } catch { } })
    Log 'Ping graph opened.'
    [void]$win.ShowDialog($form)
}

# ================================================================ GAMING: display refresh rate, shader caches, Windows gaming settings
$f = $script:PageFlows['Gaming']
Add-Section $f 'Display refresh rate (bought a 144 / 240 Hz monitor? make sure Windows uses it)' 'display'
$dispList = New-DarkList $f @(@('Screen', 250), @('Resolution', 110), @('Refresh now', 100), @('Best here', 90), @('Biggest mode', 150), @('', 150)) 870 112 $false
$f.SetFlowBreak($dispList, $true)
function Update-DisplayList {
    $dispList.BeginUpdate(); $dispList.Items.Clear(); $i = 0
    foreach ($m in Get-DisplayModes) {
        $i++
        $it = New-Object System.Windows.Forms.ListViewItem((Get-DisplayName $m $i))
        [void]$it.SubItems.Add("$($m.Width) x $($m.Height)"); [void]$it.SubItems.Add("$($m.Hz) Hz"); [void]$it.SubItems.Add("$($m.MaxHz) Hz")
        [void]$it.SubItems.Add("$($m.MaxWidth) x $($m.MaxHeight) @ $($m.MaxHzAtMaxRes) Hz")
        [void]$it.SubItems.Add($(if ($m.MaxHz -gt $m.Hz + 1) { 'Can go faster' } else { 'At its fastest' }))
        if ($m.MaxHz -gt $m.Hz + 1) { $it.ForeColor = $C.Warn }
        $it.Tag = $m; [void]$dispList.Items.Add($it)
    }
    $dispList.EndUpdate()
}
Add-Tool $f 'Use max refresh rate' 'Selected screen - 15 s to keep or go back' {
    $it = if ($dispList.SelectedItems.Count) { $dispList.SelectedItems[0] } else { @($dispList.Items | Where-Object { $_.Tag.MaxHz -gt $_.Tag.Hz + 1 })[0] }
    if (-not $it) { Log 'Every screen already runs at its fastest refresh rate.'; return }
    $m = $it.Tag
    if ($m.MaxHz -le $m.Hz + 1) { Log "$($it.Text) already runs at its fastest refresh rate ($($m.Hz) Hz)."; return }
    $g = Get-RunningGameNow; if ($g) { Log "Close $g first - changing the screen mode can minimise or crash a running game."; return }
    $err = Set-DisplayHzTemporary $m $m.MaxHz
    if ($err) { Log $err; return }
    if (Show-KeepDisplayDialog "$($m.MaxHz) Hz" "$($m.Hz) Hz") {
        $r = Save-DisplayHz $m $m.MaxHz
        Log $(if ($r -eq 0) { "$($it.Text) now runs at $($m.MaxHz) Hz (kept). Change it back any time in Settings > Display > Advanced display." } else { "Windows switched to $($m.MaxHz) Hz but couldn't save it (code $r) - it may go back after a restart." })
    } else { [void](Restore-DisplayHz $m); Log "$($it.Text) put back to $($m.Hz) Hz." }
    Update-DisplayList
} -Primary -Icon 'display' | Out-Null
Add-Tool $f 'Check displays' 'Read the screens again' { Update-DisplayList; Log 'Display list refreshed.' } -Width 210 -Icon 'arrows-rotate' | Out-Null
Add-Tool $f 'Advanced display settings' 'Windows Settings page' { Start-Process 'ms-settings:display-advanced' } -Width 230 -Icon 'gear' | Out-Null
[void]$script:AfterShown.Add({ Update-DisplayList })

# "Keep these display settings?" - goes back by itself after 15 seconds (the screen may be blank if the mode doesn't work).
function Show-KeepDisplayDialog([string]$New, [string]$Old, [int]$Seconds = 15) {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Keep these display settings?'; $d.Size = New-Object System.Drawing.Size(460, 190); $d.StartPosition = 'CenterScreen'; $d.TopMost = $true
    $d.BackColor = $C.Bg; $d.ForeColor = $C.Text; $d.Font = New-Font 10; $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    if ($form.Icon) { $d.Icon = $form.Icon }
    $l = New-Object System.Windows.Forms.Label; $l.AutoSize = $false; $l.Size = New-Object System.Drawing.Size(420, 60); $l.Location = New-Object System.Drawing.Point(16, 14)
    $d.Tag = @{ Left = $Seconds; Label = $l; Old = $Old; New = $New }
    $l.Text = "The screen now runs at $New. Keep it?`nGoing back to $Old in $Seconds seconds."
    $d.Controls.Add($l)
    $keep = New-Object System.Windows.Forms.Button; $keep.Text = 'Keep'; $keep.DialogResult = 'OK'; $keep.Location = New-Object System.Drawing.Point(206, 98); $keep.Size = New-Object System.Drawing.Size(110, 32)
    $back = New-Object System.Windows.Forms.Button; $back.Text = 'Go back'; $back.DialogResult = 'Cancel'; $back.Location = New-Object System.Drawing.Point(324, 98); $back.Size = New-Object System.Drawing.Size(110, 32)
    foreach ($b in $keep, $back) { $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = $C.Grid; $b.BackColor = $C.Panel; $b.ForeColor = $C.Text; $d.Controls.Add($b) }
    $d.AcceptButton = $back; $d.CancelButton = $back   # Enter / Esc = go back; keeping needs a click on Keep
    $t = New-Object System.Windows.Forms.Timer; $t.Interval = 1000
    $t.Add_Tick({ $s = $d.Tag; $s.Left--; $s.Label.Text = "The screen now runs at $($s.New). Keep it?`nGoing back to $($s.Old) in $($s.Left) seconds."; if ($s.Left -le 0) { $this.Stop(); $d.DialogResult = 'Cancel'; $d.Close() } })
    $d.Add_Shown({ $t.Start(); $back.Focus() })
    $r = $d.ShowDialog($form); $t.Stop(); $t.Dispose(); $d.Dispose()
    $r -eq 'OK'
}

Add-Section $f 'Shader caches - every graphics card and Steam, game by game' 'cubes'
(Add-Note $f 'Compiled shaders the driver and games keep so levels load without stutter. Clearing helps after a driver update or when a game stutters or crashes on loading; everything is rebuilt by itself (the first match afterwards can load slower). Only while no game runs.').Height = 40
Add-Tool $f 'Scan shader caches' 'NVIDIA, AMD, Intel, DirectX, Steam' {
    $shList.Items.Clear()
    $spots = @(Get-ShaderCacheSpots)
    if (-not $spots) { Log 'No shader caches found.'; return }
    Start-Background 'Shader cache scan' $ShaderSizeWork (, $spots) {
        param($out)
        $rows = @($out | Where-Object { $_.Who } | Sort-Object Bytes -Descending); $total = 0.0
        $shList.BeginUpdate()
        foreach ($r in $rows) {
            $li = New-Object System.Windows.Forms.ListViewItem($r.Who)
            [void]$li.SubItems.Add($r.What); [void]$li.SubItems.Add((Format-Size $r.Bytes)); [void]$li.SubItems.Add(($r.Dirs -join '; '))
            $li.Tag = $r; $li.Checked = ($r.Bytes -ge 1MB); $li.ToolTipText = ($r.Dirs -join "`n")
            [void]$shList.Items.Add($li); $total += $r.Bytes
        }
        $shList.EndUpdate()
        Log "Shader caches: $(Format-Size $total) in $($rows.Count) place(s). Caches over 1 MB are ticked - Clear ticked caches when no game is running."
    }
} -Primary -Icon 'magnifying-glass' | Out-Null
Add-Tool $f 'Clear ticked caches' 'Rebuilt by the driver and games' {
    $rows = @($shList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $rows) { Log 'Scan first, then tick the caches to clear.'; return }
    $g = Get-RunningGameNow; if ($g) { Log "Close $g first - its shader cache is in use."; return }
    $sum = ($rows | Measure-Object Bytes -Sum).Sum
    if (-not (Confirm-Action "Clear $($rows.Count) shader cache(s), about $(Format-Size $sum)?`n`nThese are only compiled shaders - no games, saves or settings. The graphics driver and the games rebuild them by themselves; the first time you play afterwards, loading can take longer or stutter once.`n`nFiles in use are skipped.")) { return }
    [void](Clear-ShaderCacheSpots $rows); $shList.Items.Clear()
} -Icon 'broom' | Out-Null
$shList = New-DarkList $f @(@('Who', 80), @('What', 300), @('Size', 90), @('Where', 370)) 870 210 $true
$shList.ShowItemToolTips = $true; $f.SetFlowBreak($shList, $true)

Add-Section $f 'Windows gaming settings (read-only - click a row, then Open in Settings)' 'toggle-on'
$gsList = New-DarkList $f @(@('Setting', 290), @('Now', 160), @('Tip', 420)) 870 250 $false
$gsList.ShowItemToolTips = $true; $f.SetFlowBreak($gsList, $true)
function Update-GamingSettingsList {
    $gsList.BeginUpdate(); $gsList.Items.Clear()
    foreach ($r in Get-GamingSettingsStatus) {
        $it = New-Object System.Windows.Forms.ListViewItem($r.Setting); [void]$it.SubItems.Add($r.Now); [void]$it.SubItems.Add($r.Advice)
        $it.Tag = $r; $it.ToolTipText = $r.Advice
        if ($r.Level -eq 'warn') { $it.ForeColor = $C.Warn } elseif ($r.Level -eq 'good') { $it.ForeColor = $C.Good }
        [void]$gsList.Items.Add($it)
    }
    $gsList.EndUpdate()
}
$gsOpen = {
    if (-not $gsList.SelectedItems.Count) { Log 'Click a setting in the list first.'; return }
    $r = $gsList.SelectedItems[0].Tag
    Start-Process $r.Link; Log "Opened Windows settings for: $($r.Setting)"
}
$gsList.Add_DoubleClick($gsOpen)
Add-Tool $f 'Open in Settings' 'The right page for the selected row' $gsOpen -Icon 'arrow-up-right-from-square' | Out-Null
Add-Tool $f 'Check settings' 'Read them again' { Update-GamingSettingsList; Log 'Windows gaming settings read again.' } -Width 210 -Icon 'arrows-rotate' | Out-Null
[void]$script:AfterShown.Add({ Update-GamingSettingsList })

# ================================================================ GAMES: verify files
$f = $script:PageFlows['Games']
$vb = Add-Tool $f 'Verify files' 'Repair a broken install' { $g = Get-SelectedGame; if ($g) { Invoke-VerifyGame $g } } -Width 210 -Icon 'check-double'
$of = @($f.Controls | Where-Object { "$($_.Text)" -like "Open folder`n*" })[0]
if ($of) { $f.Controls.SetChildIndex($vb, $f.Controls.GetChildIndex($of) + 1) }
