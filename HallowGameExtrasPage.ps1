<#
  Hallow Toolkit - window code for v4.0 extras: launcher caches (Storage tab), controller check (Gaming tab),
  saved Wi-Fi passwords (Network tab). Dot-sourced by HallowToolkit.ps1 after the main pages exist.
#>

# ---------------------------------------------------------------- STORAGE: launcher caches
$f = $script:PageFlows['Storage']
Add-Section $f 'Game launcher caches (web pages, downloads, logs - never games or saves)' 'gamepad'
Add-Tool $f 'Scan launcher caches' 'Steam, Epic, Battle.net, EA, Ubisoft, Discord...' {
    $lcList.Items.Clear()
    Start-Background 'Launcher cache scan' $LauncherCacheScanWork @(, $LauncherCaches) {
        param($out)
        $rows = @($out | Where-Object App | Sort-Object Bytes -Descending)
        $total = 0.0
        foreach ($r in $rows) {
            $li = New-Object System.Windows.Forms.ListViewItem($r.App)
            [void]$li.SubItems.Add($r.What); [void]$li.SubItems.Add((Format-Size $r.Bytes)); [void]$li.SubItems.Add($(if ($r.Running) { 'Open - close it first' } else { '' }))
            $li.Tag = $r; $li.Checked = -not $r.Running; $li.ToolTipText = ($r.Dirs -join "`n")
            if ($r.Running) { $li.ForeColor = $C.Warn }
            [void]$lcList.Items.Add($li); $total += $r.Bytes
        }
        Log $(if ($rows) { "Launcher caches: $(Format-Size $total) in $($rows.Count) place(s). Tick and click Clear ticked." } else { 'Launcher caches: nothing worth clearing.' })
    }
} -Primary -Icon 'magnifying-glass' | Out-Null
Add-Tool $f 'Clear ticked caches' 'Launchers rebuild them as needed' {
    $rows = @($lcList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $rows) { Log 'Scan first, then tick what to clear.'; return }
    if (Confirm-Action "Clear $($rows.Count) launcher cache(s)?`n`nOnly web pages, download caches and logs are removed. Games, saves, settings and logins stay. Launchers that are open are skipped.") {
        Clear-LauncherCaches $rows; $lcList.Items.Clear()
    }
} -Icon 'broom' | Out-Null
$lcList = New-DarkList $f @(@('Launcher', 160), @('What', 380), @('Size', 100), @('', 200)) 860 200 $true
$lcList.ShowItemToolTips = $true; $f.SetFlowBreak($lcList, $true)

# ---------------------------------------------------------------- GAMING: controller check
$f = $script:PageFlows['Gaming']
Add-Section $f 'Controllers' 'gamepad'
Add-Tool $f 'Controller check' 'Live buttons, sticks, drift + battery' { Show-ControllerCheck } -Primary -Icon 'gamepad' | Out-Null
Add-Tool $f 'Windows controller settings' 'Old "Game Controllers" panel' { Start-Process joy.cpl; Log 'Opened Game Controllers (joy.cpl).' } -Icon 'gear' | Out-Null

function Show-ControllerCheck {
    $win = New-Object System.Windows.Forms.Form
    $win.Text = 'Controller check'; $win.Size = New-Object System.Drawing.Size(760, 470); $win.StartPosition = 'CenterParent'
    $win.BackColor = $C.Bg; $win.ForeColor = $C.Text; $win.Font = New-Font 10; $win.FormBorderStyle = 'FixedDialog'; $win.MaximizeBox = $false
    if ($form.Icon) { $win.Icon = $form.Icon }
    $canvas = New-Object System.Windows.Forms.Panel; $canvas.Dock = 'Fill'
    $canvas.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance, NonPublic').SetValue($canvas, $true, $null)
    $win.Controls.Add($canvas)
    $script:PadOther = Get-OtherControllers
    $script:PadSlot = -1; $script:PadState = $null; $script:PadMaxRest = @{ L = 0.0; R = 0.0 }
    $canvas.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $fT = New-Font 12 'Bold'; $fS = New-Font 9.5; $fB = New-Font 9 'Bold'
        $bMuted = New-Object System.Drawing.SolidBrush $C.Muted; $bText = New-Object System.Drawing.SolidBrush $C.Text
        $bAcc = New-Object System.Drawing.SolidBrush $C.Accent; $bPanel = New-Object System.Drawing.SolidBrush $C.Panel
        $pen = New-Object System.Drawing.Pen($C.PanelHi, 2)
        if ($script:PadSlot -lt 0) {
            $g.DrawString('No Xbox-style (XInput) controller found.', $fT, $bText, 24, 24)
            $g.DrawString("Plug one in or turn it on - this window updates by itself.`n`nPlayStation, Switch and other controllers use DirectInput: games see them through`nSteam Input or DS4Windows, so they don't show here.", $fS, $bMuted, 24, 60)
            if ($script:PadOther) { $g.DrawString("Other controllers Windows sees:`n  " + ($script:PadOther -join "`n  "), $fS, $bText, 24, 170) }
            return
        }
        $p = $script:PadState
        $bat = [HallowPad]::Battery($script:PadSlot)
        $batTxt = switch ($bat) { 0 { 'wired' } 1 { 'battery EMPTY' } 2 { 'battery low' } 3 { 'battery medium' } 4 { 'battery full' } default { 'battery unknown' } }
        $g.DrawString("Controller $($script:PadSlot + 1)  -  $batTxt", $fT, $bText, 24, 16)
        # sticks
        foreach ($st in @(@('Left stick', 120, $p.LX, $p.LY, 'L'), @('Right stick', 380, $p.RX, $p.RY, 'R'))) {
            $cx = $st[1]; $cy = 170; $r = 70
            $g.FillEllipse($bPanel, $cx - $r, $cy - $r, 2 * $r, 2 * $r); $g.DrawEllipse($pen, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
            $dz = $r * 0.1; $g.DrawEllipse($pen, $cx - $dz, $cy - $dz, 2 * $dz, 2 * $dz)
            $x = [double]$st[2] / 32768; $y = [double]$st[3] / 32768; $mag = [math]::Min(1.0, [math]::Sqrt($x * $x + $y * $y))
            $g.FillEllipse($bAcc, $cx + $x * $r - 8, $cy - $y * $r - 8, 16, 16)
            $g.DrawString(("{0}  {1:N0}%" -f $st[0], ($mag * 100)), $fS, $bText, $cx - $r, $cy + $r + 8)
            $rest = $script:PadMaxRest[$st[4]]
            $verdict = if ($rest -ge 0.15) { 'DRIFT - raise the in-game deadzone' } elseif ($rest -ge 0.08) { 'slight drift' } else { 'centre OK' }
            $g.DrawString(("at rest: {0:N0}%  {1}" -f ($rest * 100), $verdict), $fS, $(if ($rest -ge 0.08) { New-Object System.Drawing.SolidBrush $C.Warn } else { $bMuted }), $cx - $r, $cy + $r + 28)
        }
        # triggers
        foreach ($t in @(@('LT', 560, $p.LT), @('RT', 640, $p.RT))) {
            $g.FillRectangle($bPanel, $t[1], 100, 40, 140)
            $hgt = [int](140 * $t[2] / 255); $g.FillRectangle($bAcc, $t[1], 240 - $hgt, 40, $hgt)
            $g.DrawString(("{0} {1:N0}%" -f $t[0], ($t[2] / 2.55)), $fS, $bText, $t[1] - 4, 246)
        }
        # buttons
        $bx = 24; $by = 330
        foreach ($k in $PadButtons.Keys) {
            $on = ($p.Buttons -band $PadButtons[$k]) -ne 0
            $w = [int]$g.MeasureString($k, $fB).Width + 16
            $g.FillRectangle($(if ($on) { $bAcc } else { $bPanel }), $bx, $by, $w, 28)
            $g.DrawString($k, $fB, $(if ($on) { New-Object System.Drawing.SolidBrush $C.AccentText } else { $bMuted }), $bx + 8, $by + 6)
            $bx += $w + 6; if ($bx -gt 680) { $bx = 24; $by += 34 }
        }
        $g.DrawString('Press every button - each lights up. Let go of the sticks to measure drift.', $fS, $bMuted, 24, 400)
    })
    $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 50
    $tm.Add_Tick({
        $found = -1; $pad = $null
        for ($i = 0; $i -lt 4; $i++) { $tmp = New-Object HallowPad+GAMEPAD; if ([HallowPad]::Get($i, [ref]$tmp)) { $found = $i; $pad = $tmp; break } }
        if ($found -lt 0 -and $env:HALLOW_FAKEPAD) {   # testing without a controller: A + RB held, left stick drifting 12%, RT half
            $pad = New-Object HallowPad+GAMEPAD; $pad.Buttons = 0x1000 -bor 0x0200; $pad.LX = 3900; $pad.LY = -500; $pad.RX = 20000; $pad.RY = 15000; $pad.RT = 128; $found = 0
            $script:PadMaxRest = @{ L = 0.12; R = 0.02 }
        }
        if ($found -ne $script:PadSlot) { $script:PadMaxRest = @{ L = 0.0; R = 0.0 } }
        $script:PadSlot = $found; $script:PadState = $pad
        if ($pad -and $pad.Buttons -eq 0 -and $pad.LT -lt 10 -and $pad.RT -lt 10) {
            foreach ($s in @(@('L', $pad.LX, $pad.LY), @('R', $pad.RX, $pad.RY))) {
                $m = [math]::Sqrt([math]::Pow($s[1] / 32768, 2) + [math]::Pow($s[2] / 32768, 2))
                # only count "resting" readings (under 35%) so a deliberate push doesn't look like drift
                if ($m -lt 0.35) { if ($m -gt $script:PadMaxRest[$s[0]]) { $script:PadMaxRest[$s[0]] = [math]::Round($m, 3) } }
            }
        }
        $canvas.Invalidate()
    })
    $win.Add_FormClosed({ $tm.Stop(); $tm.Dispose() })
    $tm.Start()
    Log 'Controller check opened.'
    [void]$win.ShowDialog($form)
}

# ---------------------------------------------------------------- NETWORK: saved Wi-Fi passwords
$f = $script:PageFlows['Network']
Add-Section $f 'Saved Wi-Fi' 'wifi'
Add-Tool $f 'Saved Wi-Fi passwords' 'For a friend or a new device' { Show-WifiPasswords } -Icon 'lock' | Out-Null
function Show-WifiPasswords {
    $rows = @(Get-WifiPasswords)
    if (-not $rows) { Log 'This PC has no saved Wi-Fi networks (or no Wi-Fi adapter).'; return }
    $win = New-Object System.Windows.Forms.Form
    $win.Text = 'Saved Wi-Fi passwords'; $win.Size = New-Object System.Drawing.Size(620, 380); $win.StartPosition = 'CenterParent'
    $win.BackColor = $C.Bg; $win.ForeColor = $C.Text; $win.Font = New-Font 10
    if ($form.Icon) { $win.Icon = $form.Icon }
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.Dock = 'Fill'; $lv.BackColor = $C.Panel; $lv.ForeColor = $C.Text; $lv.BorderStyle = 'None'
    [void]$lv.Columns.Add('Network', 230); [void]$lv.Columns.Add('Password', 230); [void]$lv.Columns.Add('Security', 120)
    foreach ($r in $rows) { $li = New-Object System.Windows.Forms.ListViewItem($r.Network); [void]$li.SubItems.Add($r.Password); [void]$li.SubItems.Add("$($r.Security)"); [void]$lv.Items.Add($li) }
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Copy password'; $btn.Dock = 'Bottom'; $btn.Height = 40; $btn.FlatStyle = 'Flat'; $btn.BackColor = $C.AccentFill; $btn.ForeColor = $C.AccentText
    $btn.Add_Click({ if ($lv.SelectedItems.Count) { [System.Windows.Forms.Clipboard]::SetText($lv.SelectedItems[0].SubItems[1].Text); $btn.Text = 'Copied!' } })
    $win.Controls.Add($lv); $win.Controls.Add($btn)
    Log "Showing $($rows.Count) saved Wi-Fi network(s). Passwords are only shown in that window, never saved to the log."
    [void]$win.ShowDialog($form)
}
if ($env:HALLOW_FAKEPAD) { [void]$script:AfterShown.Add({ Show-ControllerCheck }) }   # test hook: opens the check with a fake controller
