<#
  Hallow Toolkit - tune-up, monitor, health, gaming, games, network, storage and quick tools for this PC.
  Double-click "Hallow Toolkit.bat" (or the Desktop shortcut) and click Yes on the admin prompt.

  Headless modes:
    -Mode Report   print a health report
    -Mode Quick    run the Quick Clean-up (add -NoRecycleBin to keep the Recycle Bin)
    -Mode Crash    print the crash detective report
#>
param(
    [ValidateSet('Gui', 'Report', 'Quick', 'Crash', 'Backup')]
    [string]$Mode = 'Gui',
    [switch]$NoRecycleBin,
    [string]$StartPage = 'Tune-up'
)

$ErrorActionPreference = 'Continue'
$script:LogBox = $null
. (Join-Path $PSScriptRoot 'HallowCore.ps1')

if ($Mode -eq 'Gui' -and -not $IsAdmin -and -not $env:HALLOW_NO_ELEVATE) {
    try {
        Start-Process powershell.exe -Verb RunAs -ErrorAction Stop -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-StartPage', $StartPage)
        exit
    } catch { $env:HALLOW_NO_ELEVATE = '1' }
}

if ($Mode -eq 'Report') { Invoke-HealthReport; return }
if ($Mode -eq 'Quick') { Invoke-QuickClean (-not $NoRecycleBin); return }
if ($Mode -eq 'Crash') { Invoke-CrashDetective; return }
if ($Mode -eq 'Backup') { & $SaveBackupWork (Get-DefaultBackupDir) 5 $false | ForEach-Object { Log "$_" }; return }

# ================================================================ WINDOW

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function RGB($r, $g, $b) { [System.Drawing.Color]::FromArgb($r, $g, $b) }
# ---- themes (Tools tab > Theme; saved in settings.json). Accent = buttons/highlights, Second = section headers.
$ThemeAccents = [ordered]@{
    'Orange' = @{ Accent = RGB 255 122 26;  Hover = RGB 255 150 70;  Second = RGB 160 110 255 }
    'Purple' = @{ Accent = RGB 168 112 255; Hover = RGB 190 148 255; Second = RGB 90 200 200 }
    'Blue'   = @{ Accent = RGB 70 150 255;  Hover = RGB 110 175 255; Second = RGB 168 120 255 }
    'Green'  = @{ Accent = RGB 60 205 125;  Hover = RGB 100 225 155; Second = RGB 120 170 255 }
    'Red'    = @{ Accent = RGB 245 75 85;   Hover = RGB 255 110 118; Second = RGB 255 170 90 }
    'Pink'   = @{ Accent = RGB 255 105 185; Hover = RGB 255 140 205; Second = RGB 160 120 255 }
}
$ThemeBases = [ordered]@{
    'Hallow'   = @{ Bg = RGB 18 16 24; Nav = RGB 26 22 34; Panel = RGB 36 31 46; PanelHi = RGB 52 44 66; Muted = RGB 160 152 176; Grid = RGB 58 52 70 }
    'Graphite' = @{ Bg = RGB 20 20 22; Nav = RGB 28 28 31; Panel = RGB 38 38 42; PanelHi = RGB 55 55 61; Muted = RGB 158 158 166; Grid = RGB 60 60 66 }
    'Navy'     = @{ Bg = RGB 13 17 27; Nav = RGB 19 25 39; Panel = RGB 29 37 55; PanelHi = RGB 43 53 77; Muted = RGB 150 160 184; Grid = RGB 52 62 86 }
    'OLED'     = @{ Bg = RGB 0 0 0;    Nav = RGB 10 10 12; Panel = RGB 22 22 26; PanelHi = RGB 40 40 46; Muted = RGB 150 150 160; Grid = RGB 50 50 56 }
}
$ts = Get-Settings
$ta = $ThemeAccents["$($ts.Theme)"]; if (-not $ta) { $ta = $ThemeAccents['Orange'] }
$tb = $ThemeBases["$($ts.ThemeBase)"]; if (-not $tb) { $tb = $ThemeBases['Hallow'] }
$C = @{
    Bg = $tb.Bg; Nav = $tb.Nav; Panel = $tb.Panel; PanelHi = $tb.PanelHi; Grid = $tb.Grid
    Accent = $ta.Accent; AccentHover = $ta.Hover; AccentText = RGB 20 12 4; Purple = $ta.Second
    Text = RGB 236 232 244; Muted = $tb.Muted; Good = RGB 110 210 140; Warn = RGB 240 190 90; Bad = RGB 240 90 90
}
function New-Font([float]$Size, [string]$Style = 'Regular', [string]$Family = 'Segoe UI') { New-Object System.Drawing.Font($Family, $Size, [System.Drawing.FontStyle]$Style) }

$form = New-Object System.Windows.Forms.Form
$form.Text = $AppName
$form.Size = New-Object System.Drawing.Size(1200, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 680)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $C.Bg
$form.ForeColor = $C.Text
$form.Font = New-Font 10
$iconPath = Join-Path $PSScriptRoot 'hallow.ico'
if (Test-Path $iconPath) { try { $form.Icon = New-Object System.Drawing.Icon $iconPath } catch { } }

# ---- right side (Fill added first so docked edges win)
$right = New-Object System.Windows.Forms.Panel
$right.Dock = 'Fill'
$right.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 16)
$form.Controls.Add($right)

$pagesHost = New-Object System.Windows.Forms.Panel
$pagesHost.Dock = 'Fill'
$right.Controls.Add($pagesHost)

$logWrap = New-Object System.Windows.Forms.Panel
$logWrap.Dock = 'Bottom'; $logWrap.Height = 210
$logWrap.Padding = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
$right.Controls.Add($logWrap)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.ReadOnly = $true; $log.WordWrap = $true
$log.BackColor = $C.Panel; $log.ForeColor = $C.Text; $log.BorderStyle = 'None'
$log.Font = New-Font 9.5 'Regular' 'Consolas'; $log.Dock = 'Fill'
$logWrap.Controls.Add($log)
$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = 'ACTIVITY'; $logTitle.Dock = 'Top'; $logTitle.Height = 22; $logTitle.ForeColor = $C.Muted; $logTitle.Font = New-Font 8.5 'Bold'
$logWrap.Controls.Add($logTitle)
$script:LogBox = $log

# ---- left navigation
$nav = New-Object System.Windows.Forms.Panel
$nav.Dock = 'Left'; $nav.Width = 220; $nav.BackColor = $C.Nav
$form.Controls.Add($nav)

$brand = New-Object System.Windows.Forms.Label
$brand.Text = 'HALLOW'; $brand.Font = New-Font 22 'Bold'; $brand.ForeColor = $C.Accent
$brand.Location = New-Object System.Drawing.Point(22, 20); $brand.AutoSize = $true
$nav.Controls.Add($brand)
$brand2 = New-Object System.Windows.Forms.Label
$brand2.Text = "TOOLKIT  v$AppVersion"; $brand2.Font = New-Font 9 'Bold'; $brand2.ForeColor = $C.Purple
$brand2.Location = New-Object System.Drawing.Point(25, 66); $brand2.AutoSize = $true
$nav.Controls.Add($brand2)

$adminLbl = New-Object System.Windows.Forms.Label
$adminLbl.AutoSize = $false; $adminLbl.Width = 190; $adminLbl.Height = 40
$adminLbl.Location = New-Object System.Drawing.Point(22, 715); $adminLbl.Anchor = 'Bottom, Left'
$adminLbl.Font = New-Font 8.5
if ($IsAdmin) { $adminLbl.Text = "Admin mode`nAll tools available"; $adminLbl.ForeColor = $C.Good }
else { $adminLbl.Text = "Limited mode (no admin)`nSome tools are skipped"; $adminLbl.ForeColor = $C.Warn }
$nav.Controls.Add($adminLbl)

$pages = [ordered]@{}
$script:PageFlows = @{}
$navButtons = New-Object System.Collections.Generic.List[System.Windows.Forms.Button]
$allButtons = New-Object System.Collections.Generic.List[System.Windows.Forms.Button]
$navY = 104
$script:CurrentPage = ''

function Show-Page([string]$Name) {
    foreach ($k in $pages.Keys) { $pages[$k].Visible = ($k -eq $Name) }
    foreach ($b in $navButtons) {
        $on = ($b.Tag -eq $Name)
        if ($on) { $b.BackColor = $C.PanelHi; $b.ForeColor = $C.Accent }
        else { $b.BackColor = $C.Nav; $b.ForeColor = $C.Text }
        if ($script:NavIcons.ContainsKey($b.Tag)) { $b.Image = $script:NavIcons[$b.Tag][[int]$on] }
    }
    $script:CurrentPage = $Name
    if ($Name -eq 'Games' -and -not $script:GamesLoaded) { Update-GameList }
    if ($Name -eq 'Monitor') { [void]$form.BeginInvoke([Action]{ try { Update-Monitor } catch { } }) }
    if ($Name -eq 'Uninstall' -and -not $script:ProgramsLoading) { Update-ProgramList }
    if ($script:PageShowHooks -and $script:PageShowHooks.ContainsKey($Name)) { $h = $script:PageShowHooks[$Name]; $script:PageShowHooks.Remove($Name); & $h }
}

$PageIcons = @{
    'Tune-up' = 'wand-magic-sparkles'; 'Monitor' = 'gauge-high'; 'Health' = 'heart-pulse'; 'Gaming' = 'rocket'; 'Games' = 'gamepad'
    'Network' = 'wifi'; 'Server' = 'server'; 'Storage' = 'hard-drive'; 'Uninstall' = 'trash-can'; 'Tools' = 'screwdriver-wrench'
    'Tweaks' = 'sliders'; 'Dev' = 'code'; 'Drivers' = 'microchip'; 'Mic' = 'microphone'; 'Apps' = 'download'
}
$script:NavIcons = @{}
function Add-Page([string]$Name, [string]$Glyph, [string]$Subtitle) {
    $page = New-Object System.Windows.Forms.Panel
    $page.Dock = 'Fill'; $page.Visible = $false
    $pagesHost.Controls.Add($page)
    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'; $flow.AutoScroll = $true; $flow.WrapContents = $true
    $flow.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $page.Controls.Add($flow)
    $head = New-Object System.Windows.Forms.Panel
    $head.Dock = 'Top'; $head.Height = 64
    $page.Controls.Add($head)
    $t = New-Object System.Windows.Forms.Label
    $t.Text = $Name; $t.Font = New-Font 20 'Bold'; $t.AutoSize = $true; $t.Location = New-Object System.Drawing.Point(0, 0)
    $head.Controls.Add($t)
    $s = New-Object System.Windows.Forms.Label
    $s.Text = $Subtitle; $s.ForeColor = $C.Muted; $s.AutoSize = $true; $s.Location = New-Object System.Drawing.Point(3, 38)
    $head.Controls.Add($s)
    $pages[$Name] = $page; $script:PageFlows[$Name] = $flow

    $nb = New-Object System.Windows.Forms.Button
    $nb.Text = "  $Glyph   $Name"; $nb.Tag = $Name; $nb.UseMnemonic = $false
    $nb.FlatStyle = 'Flat'; $nb.FlatAppearance.BorderSize = 0; $nb.FlatAppearance.MouseOverBackColor = $C.Panel
    $nb.TextAlign = 'MiddleLeft'; $nb.Font = New-Font 11 'Bold'
    $pageIcon = $PageIcons[$Name]
    if ($pageIcon -and (Test-IconFont)) {
        $script:NavIcons[$Name] = @((Get-Icon $pageIcon $C.Muted 18), (Get-Icon $pageIcon $C.Accent 18))
        $nb.Text = "  $Name"; $nb.Image = $script:NavIcons[$Name][0]
        $nb.ImageAlign = 'MiddleLeft'; $nb.TextImageRelation = 'ImageBeforeText'
        $nb.Padding = New-Object System.Windows.Forms.Padding(20, 0, 0, 0)
    }
    $nb.Size = New-Object System.Drawing.Size(220, 36); $nb.Location = New-Object System.Drawing.Point(0, $script:navY)
    $nb.Cursor = [System.Windows.Forms.Cursors]::Hand
    $nb.Add_Click({ Show-Page $this.Tag })
    $nav.Controls.Add($nb); $navButtons.Add($nb)
    $script:navY += 38
    return $flow
}

function Add-Section($Flow, [string]$Text, [string]$Icon) {
    $l = New-Object System.Windows.Forms.Label
    $l.UseMnemonic = $false; $l.Text = $Text.ToUpper(); $l.ForeColor = $C.Purple; $l.Font = New-Font 8.5 'Bold'
    $l.AutoSize = $false; $l.Width = 860; $l.Height = 28; $l.TextAlign = 'BottomLeft'
    $l.Margin = New-Object System.Windows.Forms.Padding(2, 8, 0, 4)
    if (Test-IconFont) {
        if (-not $Icon) { $Icon = Get-ToolIconName $Text; if ($Icon -eq 'circle-chevron-right') { $Icon = 'caret-right' } }
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Image = Get-Icon $Icon $C.Purple 14; $pb.Size = New-Object System.Drawing.Size(14, 14)
        $pb.Margin = New-Object System.Windows.Forms.Padding(2, 20, 0, 4)
        if ($Flow.Controls.Count) { $Flow.SetFlowBreak($Flow.Controls[$Flow.Controls.Count - 1], $true) }   # icon starts a new row
        $Flow.Controls.Add($pb)
        $l.Width = 840; $l.Margin = New-Object System.Windows.Forms.Padding(4, 8, 0, 4)
    }
    $Flow.Controls.Add($l); $Flow.SetFlowBreak($l, $true)
}

function Add-Note($Flow, [string]$Text) {
    $l = New-Object System.Windows.Forms.Label
    $l.UseMnemonic = $false; $l.Text = $Text; $l.ForeColor = $C.Muted; $l.Font = New-Font 9
    $l.AutoSize = $false; $l.Width = 860; $l.Height = 22
    $l.Margin = New-Object System.Windows.Forms.Padding(2, 0, 0, 6)
    $Flow.Controls.Add($l); $Flow.SetFlowBreak($l, $true)
    $l
}

$tips = New-Object System.Windows.Forms.ToolTip
# Tool buttons are drawn by hand: icon in its own column, title on top, a smaller dimmer description under it.
# The button's Text stays "Title`nDescription" (tooltips, screen readers and code that renames a button keep working).
$script:PrimaryButtons = New-Object 'System.Collections.Generic.HashSet[object]'
$script:BtnTitleFont = New-Object System.Drawing.Font('Segoe UI Semibold', [float]9.75, [System.Drawing.FontStyle]::Regular)
$script:BtnDescFont = New-Object System.Drawing.Font('Segoe UI', [float]8.75, [System.Drawing.FontStyle]::Regular)
$script:ToggleStates = @{}   # button -> scriptblock returning $true when the setting is on
$script:ToggleCache = @{}    # button -> last known state (painted as a toggle switch)
# A phone-style toggle switch, 40x22: green track with the knob on the right = on, grey with the knob on the left = off.
# -Pending draws a yellow ring (changed but not applied yet).
function Draw-Switch($g, [int]$X, [int]$Y, [bool]$On, [switch]$Pending, [bool]$Enabled = $true) {
    $W = 40; $H = 22
    $old = $g.SmoothingMode; $g.SmoothingMode = 'AntiAlias'
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($X, $Y, $H, $H, 90, 180); $path.AddArc(($X + $W - $H), $Y, $H, $H, 270, 180); $path.CloseFigure()
    $track = if ($On) { $C.Good } else { [System.Drawing.Color]::FromArgb(88, 86, 100) }
    if (-not $Enabled) { $track = [System.Drawing.Color]::FromArgb(140, $track) }
    $br = New-Object System.Drawing.SolidBrush($track); $g.FillPath($br, $path); $br.Dispose()
    if ($Pending) { $pen = New-Object System.Drawing.Pen($C.Warn, 2); $g.DrawPath($pen, $path); $pen.Dispose() }
    $path.Dispose()
    $k = $H - 6; $kx = $(if ($On) { $X + $W - $k - 3 } else { $X + 3 })
    $kb = New-Object System.Drawing.SolidBrush($(if ($On) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(205, 202, 214) }))
    $g.FillEllipse($kb, $kx, ($Y + 3), $k, $k); $kb.Dispose()
    $g.SmoothingMode = $old
}
function Update-ToggleStates {
    foreach ($b in @($script:ToggleStates.Keys)) {
        try { $script:ToggleCache[$b] = [bool](& $script:ToggleStates[$b]) } catch { [void]$script:ToggleCache.Remove($b) }
        $b.Invalidate()
    }
}
$script:ToolPaint = {
    param($s, $e)
    $g = $e.Graphics; $w = $s.Width; $h = $s.Height
    $prim = $script:PrimaryButtons.Contains($s)
    $hot = $s.Enabled -and $s.ClientRectangle.Contains($s.PointToClient([System.Windows.Forms.Cursor]::Position))
    $bg = if ($prim) { if ($hot) { $C.AccentHover } else { $C.Accent } } else { if ($hot) { $C.PanelHi } else { $C.Panel } }
    $g.Clear($bg)
    $x = 14
    if ($s.Image) {
        $img = $s.Image
        if ($s.Enabled) { $g.DrawImage($img, $x, [int](($h - $img.Height) / 2), $img.Width, $img.Height) }
        else { [System.Windows.Forms.ControlPaint]::DrawImageDisabled($g, $img, $x, [int](($h - $img.Height) / 2), $bg) }
        $x += 20 + 12
    }
    $parts = "$($s.Text)" -split "`n", 2
    $title = $parts[0]; $desc = $(if ($parts.Count -gt 1) { $parts[1] } else { '' })
    # description colour: muted on panels; on the accent button, text colour blended 25% toward the background
    $dc = if ($prim) { [System.Drawing.Color]::FromArgb([int]($C.AccentText.R * 0.75 + $bg.R * 0.25), [int]($C.AccentText.G * 0.75 + $bg.G * 0.25), [int]($C.AccentText.B * 0.75 + $bg.B * 0.25)) } else { $C.Muted }
    $tc = if ($prim) { if ($s.Enabled) { $C.AccentText } else { $dc } } elseif ($s.Enabled) { $C.Text } else { $C.Muted }
    $tw = $w - $x - 10
    # on/off settings: a toggle switch on the right shows the current state
    if ($script:ToggleCache.ContainsKey($s)) {
        Draw-Switch $g ($w - 52) ([int](($h - 22) / 2)) $script:ToggleCache[$s] -Enabled:$s.Enabled
        $tw -= 50
    }
    $flagsT = [System.Windows.Forms.TextFormatFlags]'Left, Top, SingleLine, EndEllipsis, NoPrefix'
    $flagsD = [System.Windows.Forms.TextFormatFlags]'Left, Top, WordBreak, EndEllipsis, NoPrefix'
    $th = [System.Windows.Forms.TextRenderer]::MeasureText($g, $title, $script:BtnTitleFont, (New-Object System.Drawing.Size($tw, 100)), $flagsT).Height
    $dh = if ($desc) { [math]::Min(32, [System.Windows.Forms.TextRenderer]::MeasureText($g, $desc, $script:BtnDescFont, (New-Object System.Drawing.Size($tw, 100)), $flagsD).Height) } else { 0 }
    $y = [int](($h - $th - $dh - $(if ($desc) { 1 } else { 0 })) / 2)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $title, $script:BtnTitleFont, (New-Object System.Drawing.Rectangle($x, $y, $tw, $th)), $tc, $flagsT)
    if ($desc) { [System.Windows.Forms.TextRenderer]::DrawText($g, $desc, $script:BtnDescFont, (New-Object System.Drawing.Rectangle($x, ($y + $th + 1), $tw, $dh)), $dc, $bg, $flagsD) }
}
function Add-Tool($Flow, [string]$Title, [string]$Desc, [scriptblock]$Action, [switch]$Primary, [int]$Width = 278, [string]$Icon, [scriptblock]$State) {
    $b = New-Object System.Windows.Forms.Button
    $b.UseMnemonic = $false; $b.Text = "$Title`n$Desc"
    if (Test-IconFont) {
        if (-not $Icon) { $Icon = Get-ToolIconName $Title }
        $b.Image = Get-Icon $Icon $(if ($Primary) { $C.AccentText } else { $C.Accent }) 20
        $b.ImageAlign = 'MiddleLeft'; $b.TextImageRelation = 'ImageBeforeText'
    }
    if ($Primary) { [void]$script:PrimaryButtons.Add($b) }
    $b.Add_Paint($script:ToolPaint)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $(if ($Primary) { $C.Accent } else { $C.Panel })
    $b.ForeColor = $(if ($Primary) { $C.AccentText } else { $C.Text })
    $b.FlatAppearance.MouseOverBackColor = $(if ($Primary) { $C.AccentHover } else { $C.PanelHi })
    $b.Size = New-Object System.Drawing.Size($Width, 64)
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    $b.TextAlign = 'MiddleLeft'; $b.Padding = New-Object System.Windows.Forms.Padding(12, 0, 6, 0)
    $b.Font = New-Font 9.5 $(if ($Primary) { 'Bold' } else { 'Regular' })
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Tag = $Action
    if ($State) { $script:ToggleStates[$b] = $State; $Desc = "$Desc. Green switch = on right now, grey = off. Click to switch." }
    $tips.SetToolTip($b, $Desc)
    $b.Add_Click({
        $act = $this.Tag
        foreach ($x in $allButtons) { $x.Enabled = $false }
        $form.UseWaitCursor = $true
        try { & $act } catch { Log "ERROR: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))" }
        finally { $form.UseWaitCursor = $false; foreach ($x in $allButtons) { $x.Enabled = $true }; if ($script:ToggleStates.ContainsKey($this)) { Update-ToggleStates } }
    })
    $Flow.Controls.Add($b); $allButtons.Add($b)
    $b
}

# Dark list with optional checkboxes. Columns: @(@('Title', width), ...)
function New-DarkList($Flow, $Columns, [int]$Width, [int]$Height, [bool]$Checks) {
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $Checks; $lv.HideSelection = $false
    $lv.BackColor = $C.Panel; $lv.ForeColor = $C.Text; $lv.BorderStyle = 'None'
    $lv.Font = New-Font 9.5; $lv.Size = New-Object System.Drawing.Size($Width, $Height)
    $lv.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    foreach ($c in $Columns) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $lv.OwnerDraw = $true
    $lv.Add_DrawColumnHeader({
        param($s, $e)
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $C.PanelHi), $e.Bounds)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, (New-Font 8.5 'Bold'),
            (New-Object System.Drawing.Rectangle(($e.Bounds.X + 6), $e.Bounds.Y, $e.Bounds.Width, $e.Bounds.Height)), $C.Muted, 'VerticalCenter, Left')
    })
    $lv.Add_DrawItem({ param($s, $e) $e.DrawDefault = $true })
    $lv.Add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true })
    $Flow.Controls.Add($lv)
    $lv
}

# ---- background jobs (long tasks run off the UI thread)
$script:Jobs = New-Object System.Collections.ArrayList
function Start-Background([string]$Name, [scriptblock]$Work, [object[]]$ArgList, [scriptblock]$OnDone) {
    $ps = [powershell]::Create()
    [void]$ps.AddScript($Work.ToString())
    foreach ($a in $ArgList) { [void]$ps.AddArgument($a) }
    [void]$script:Jobs.Add([pscustomobject]@{ Name = $Name; PS = $ps; Handle = $ps.BeginInvoke(); Started = Get-Date; OnDone = $OnDone })
    Log "$Name - running in the background, you can keep using the toolkit..."
}
$jobTimer = New-Object System.Windows.Forms.Timer
$jobTimer.Interval = 500
$jobTimer.Add_Tick({
    foreach ($j in @($script:Jobs)) {
        if (-not $j.Handle.IsCompleted) { continue }
        $script:Jobs.Remove($j)
        try {
            $out = @($j.PS.EndInvoke($j.Handle))
            if ($j.OnDone) { & $j.OnDone $out } else { foreach ($line in $out) { Log "$line" } }
        } catch { Log "$($j.Name) failed: $($_.Exception.Message)" }
        Log ("{0} - finished in {1:N0}s" -f $j.Name, ((Get-Date) - $j.Started).TotalSeconds)
        $j.PS.Dispose()
    }
})
$jobTimer.Start()

# ================================================================ PAGE: TUNE-UP
$script:Drives = @(Get-DriveSpace)
$script:AfterShown = New-Object System.Collections.ArrayList   # slow list-filling runs right after the window appears
[void]$script:AfterShown.Add({ Update-ToggleStates })
$f = Add-Page 'Tune-up' ([char]0x2726) 'Clean junk, check health and keep Windows up to date'
Add-Section $f 'One click'
Add-Tool $f 'Quick Clean-up' 'Temp files, caches, DNS, SSD TRIM' { Invoke-QuickClean $script:recycle.Checked } -Primary | Out-Null
Add-Tool $f 'Health report' 'Updates, disks, RAM, crashes' { Invoke-HealthReport } | Out-Null
$script:recycle = New-Object System.Windows.Forms.CheckBox
$script:recycle.Text = 'Quick Clean-up also empties the Recycle Bin (permanent)'
$script:recycle.Checked = $true; $script:recycle.AutoSize = $true; $script:recycle.ForeColor = $C.Muted
$script:recycle.Margin = New-Object System.Windows.Forms.Padding(4, 20, 0, 0)
$f.Controls.Add($script:recycle); $f.SetFlowBreak($script:recycle, $true)
Add-Section $f 'Updates & repair'
Add-Tool $f 'Update all apps' 'winget upgrade --all (new window)' { Invoke-UpdateApps } | Out-Null
Add-Tool $f 'Unblock Windows updates' 'Remove version pin, open Windows Update' { Invoke-UnblockWindowsUpdates } | Out-Null
Add-Tool $f 'Repair Windows files' 'DISM + SFC (new window, 10-30 min)' { Invoke-RepairWindows } | Out-Null
Add-Section $f 'App updates (checked each time the toolkit opens)'
Add-Tool $f 'Check app updates' 'Apps with a newer version (winget)' { Start-AppUpdateCheck } -Primary | Out-Null
Add-Tool $f 'Update ticked apps' 'Silent installs, one at a time' { Install-AppUpdates } | Out-Null
Add-Tool $f 'Tick all / none' 'Toggle every app in the list' {
    $all = @($appUpList.Items | Where-Object { -not $_.Checked }).Count -gt 0
    foreach ($i in $appUpList.Items) { $i.Checked = $all }
} | Out-Null
$appUpList = New-DarkList $f @(@('App', 300), @('Id', 250), @('Installed', 150), @('New version', 150)) 860 150 $true
$f.SetFlowBreak($appUpList, $true)
$script:AppQuiet = $false
function Start-AppUpdateCheck([switch]$Quiet) {
    $appUpList.Items.Clear(); $script:AppQuiet = [bool]$Quiet
    Start-Background 'App update check' $WingetListWork @() {
        param($out)
        $first = @($out)[0]
        if ($first -and $first.Error) { if (-not $script:AppQuiet) { Log $first.Error }; return }
        $n = 0
        foreach ($a in $out) {
            if (-not $a.Id) { continue }
            $li = New-Object System.Windows.Forms.ListViewItem("$($a.Name)")
            foreach ($v in $a.Id, $a.Version, $a.Available) { [void]$li.SubItems.Add("$v") }
            $li.Tag = $a; $li.Checked = $true; $li.ForeColor = $C.Accent
            [void]$appUpList.Items.Add($li); $n++
        }
        if ($n) { Log "$n app update(s) available - Tune-up tab > App updates: $(@($out | Where-Object Id | ForEach-Object Name) -join ', ')" }
        elseif (-not $script:AppQuiet) { Log 'All your apps are up to date.' }
    }
}
function Install-AppUpdates {
    $items = @($appUpList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $items) { Log 'Tick at least one app first (or click Check app updates).'; return }
    $list = ($items | ForEach-Object { "  - $($_.Name)  $($_.Version) > $($_.Available)" }) -join "`n"
    if (-not (Confirm-Action "Update these apps?`n`n$list`n`nClose them first if they are open. Some installers show a UAC prompt - click Yes on it.")) { return }
    Start-Background "Updating $($items.Count) app(s)" $WingetUpgradeWork @(, [object[]]$items) {
        param($out)
        foreach ($l in $out) { Log "$l" }
        Start-AppUpdateCheck -Quiet
    }
}
[void]$script:AfterShown.Add({ Start-AppUpdateCheck -Quiet })
[void]$script:AfterShown.Add({ if (-not (Test-Path $IconFontFile)) { Start-Background 'Icon font' $IconFontFetchWork @($IconFontUrl, $IconFontFile, $IconFontSha) { param($o) foreach ($l in $o) { Log "$l" } } } })
Add-Section $f 'Automatic'
Add-Tool $f 'Weekly auto clean-up' 'Sundays 3 AM' { Invoke-ToggleWeeklyClean } -State { [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) } | Out-Null
Add-Tool $f 'Startup apps' 'Choose what launches with Windows' { Start-Process 'ms-settings:startupapps'; Log 'Opened Startup apps.' } | Out-Null

# ================================================================ PAGE: MONITOR
$f = Add-Page 'Monitor' ([char]0x25C9) 'Live usage - updates every 2 seconds while this page is open'
$tiles = @{}
function Add-Tile($Flow, [string]$Key, [string]$Title) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Size = New-Object System.Drawing.Size(278, 118); $p.BackColor = $C.Panel
    $p.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    $t = New-Object System.Windows.Forms.Label
    $t.Text = $Title.ToUpper(); $t.ForeColor = $C.Muted; $t.Font = New-Font 8.5 'Bold'
    $t.Location = New-Object System.Drawing.Point(14, 12); $t.AutoSize = $true
    $v = New-Object System.Windows.Forms.Label
    $v.Text = '...'; $v.Font = New-Font 22 'Bold'; $v.Location = New-Object System.Drawing.Point(11, 32); $v.AutoSize = $true
    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = ''; $sub.ForeColor = $C.Muted; $sub.Font = New-Font 8.5; $sub.Location = New-Object System.Drawing.Point(14, 74); $sub.AutoSize = $true
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Location = New-Object System.Drawing.Point(14, 98); $bar.Size = New-Object System.Drawing.Size(250, 6); $bar.BackColor = $C.PanelHi
    $fill = New-Object System.Windows.Forms.Panel
    $fill.Location = New-Object System.Drawing.Point(0, 0); $fill.Size = New-Object System.Drawing.Size(0, 6); $fill.BackColor = $C.Accent
    $bar.Controls.Add($fill)
    $p.Controls.AddRange(@($t, $v, $sub, $bar))
    $Flow.Controls.Add($p)
    $tiles[$Key] = @{ Value = $v; Sub = $sub; Fill = $fill }
}
function Set-Tile([string]$Key, [string]$Value, [string]$Sub, [double]$Pct, [double]$WarnAt = 75, [double]$BadAt = 90) {
    $t = $tiles[$Key]; if (-not $t) { return }
    $t.Value.Text = $Value; $t.Sub.Text = $Sub
    $pct = [math]::Max(0.0, [math]::Min(100.0, $Pct))
    $t.Fill.Width = [int](250 * $pct / 100)
    $t.Fill.BackColor = $(if ($pct -ge $BadAt) { $C.Bad } elseif ($pct -ge $WarnAt) { $C.Warn } else { $C.Accent })
}
Add-Section $f 'Performance'
Add-Tile $f 'cpu' 'CPU load'
Add-Tile $f 'cputemp' 'CPU temperature'
Add-Tile $f 'ram' 'Memory'
Add-Tile $f 'gpu' 'GPU load'
Add-Tile $f 'gputemp' 'GPU temperature'
Add-Tile $f 'vram' 'GPU memory'
Add-Tile $f 'net' 'Network'
Add-Section $f 'Drives'
foreach ($d in $script:Drives) { Add-Tile $f ("disk" + $d.Drive) ("Drive {0} {1}" -f $d.Drive, $d.Label) }
Add-Section $f 'Top memory users'
$topList = New-Object System.Windows.Forms.Label
$topList.Font = New-Font 9.5 'Regular' 'Consolas'; $topList.ForeColor = $C.Text; $topList.AutoSize = $true
$f.Controls.Add($topList)

# performance counters are slow to create, so they are set up the first time the Monitor tab is opened
$script:cpuCounter = $null; $script:netCat = $null; $script:MonInit = $false
$netCounters = @{}
$nvsmi = $NvSmi
function Initialize-Monitor {
    if ($script:MonInit) { return }; $script:MonInit = $true
    try { $script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter('Processor Information', '% Processor Utility', '_Total'); [void]$script:cpuCounter.NextValue() } catch {
        try { $script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total'); [void]$script:cpuCounter.NextValue() } catch { $script:cpuCounter = $null }
    }
    try { $script:netCat = New-Object System.Diagnostics.PerformanceCounterCategory('Network Interface') } catch { }
}
$script:monTick = 0
$script:lhmMissSince = $null

function Update-Monitor {
    Initialize-Monitor
    if ($cpuCounter) {
        $cpu = [math]::Min(100.0, $cpuCounter.NextValue())
        Set-Tile 'cpu' ('{0:N0}%' -f $cpu) "$env:NUMBER_OF_PROCESSORS threads" $cpu
    }
    if (-not $script:lhmMissSince -or ((Get-Date) - $script:lhmMissSince).TotalSeconds -gt 30) {
        $ct = Get-LhmCpuTemp
        if ($null -ne $ct) { $script:lhmMissSince = $null; Set-Tile 'cputemp' ("{0:N0} $([char]0xB0)C" -f $ct) 'Ryzen 7000 runs up to 95 C by design' $ct 85 95 }
        else { $script:lhmMissSince = Get-Date; Set-Tile 'cputemp' 'n/a' 'Tools > Install CPU temp sensor' 0 }
    }
    $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
    $tot = $os.TotalVisibleMemorySize / 1MB; $used = $tot - $os.FreePhysicalMemory / 1MB
    Set-Tile 'ram' ('{0:N1} GB' -f $used) ('of {0:N0} GB ({1:N0}%)' -f $tot, (100 * $used / $tot)) (100 * $used / $tot)
    if ($nvsmi) {
        $q = & $nvsmi '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,name' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if ($q) {
            $v = $q -split ',\s*'
            Set-Tile 'gpu' ("$($v[0])%") ("{0}  {1:N0} W" -f $v[5], [double]$v[4]) ([double]$v[0])
            Set-Tile 'gputemp' ("$($v[1]) $([char]0xB0)C") 'Under 83 C is normal under load' ([double]$v[1]) 75 83
            Set-Tile 'vram' ('{0:N1} GB' -f ([double]$v[2] / 1024)) ('of {0:N0} GB' -f ([double]$v[3] / 1024)) (100 * [double]$v[2] / [double]$v[3])
        }
    } else { Set-Tile 'gpu' 'n/a' 'NVIDIA driver tools not found' 0 }
    if ($netCat) {
        $down = 0; $upl = 0
        foreach ($inst in $netCat.GetInstanceNames()) {
            try {
                if (-not $netCounters.ContainsKey($inst)) {
                    $netCounters[$inst] = @(
                        (New-Object System.Diagnostics.PerformanceCounter('Network Interface', 'Bytes Received/sec', $inst)),
                        (New-Object System.Diagnostics.PerformanceCounter('Network Interface', 'Bytes Sent/sec', $inst)))
                }
                $r = $netCounters[$inst][0].NextValue(); $s = $netCounters[$inst][1].NextValue()
                if ($r -gt $down) { $down = $r }; if ($s -gt $upl) { $upl = $s }
            } catch { }
        }
        Set-Tile 'net' ('{0:N1} Mb/s' -f ($down * 8 / 1MB)) ('down  |  {0:N1} Mb/s up' -f ($upl * 8 / 1MB)) ([math]::Min(100.0, $down * 8 / 1MB / 10))
    }
    if ($script:monTick % 5 -eq 0) {
        foreach ($d in Get-DriveSpace) {
            Set-Tile ("disk" + $d.Drive) ('{0:N0} GB free' -f $d.FreeGB) ('of {0:N0} GB ({1}% free)' -f $d.SizeGB, $d.FreePct) (100 - $d.FreePct) 80 88
        }
        $topList.Text = (Get-Process | Group-Object ProcessName | ForEach-Object {
                [pscustomobject]@{ N = $_.Name; MB = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB }
            } | Sort-Object MB -Descending | Select-Object -First 8 | ForEach-Object { '{0,-30} {1,7:N0} MB' -f $_.N, $_.MB }) -join "`r`n"
    }
    $script:monTick++
}
$monTimer = New-Object System.Windows.Forms.Timer
$monTimer.Interval = 2000
$monTimer.Add_Tick({ if ($script:CurrentPage -eq 'Monitor' -and $form.WindowState -ne 'Minimized') { try { Update-Monitor } catch { if (-not $script:MonErrLogged) { $script:MonErrLogged = $true; Log "Monitor error: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))" } } } })
$monTimer.Start()

# ================================================================ PAGE: HEALTH
$f = Add-Page 'Health' ([char]0x2665) 'Find out why the PC crashes and check RAM, drives and drivers'
Add-Section $f 'System check (run it after a BIOS update, EXPO change or new driver)'
Add-Tool $f 'Run system check' 'BIOS, EXPO, ReBAR, Secure Boot, temps, errors' { Start-SystemCheck } -Primary | Out-Null
Add-Tool $f 'Copy results' 'Paste into Discord or a forum' {
    if (-not $chkList.Items.Count) { Log 'Run the system check first.'; return }
    $txt = ($chkList.Items | ForEach-Object { "[{0}] {1}: {2}{3}" -f $_.SubItems[2].Text, $_.Text, $_.SubItems[1].Text, $(if ($_.SubItems[3].Text) { "  - $($_.SubItems[3].Text)" } else { '' }) }) -join "`r`n"
    [System.Windows.Forms.Clipboard]::SetText("Hallow Toolkit system check $(Get-Date -Format 'yyyy-MM-dd HH:mm')`r`n$txt"); Log 'System check copied to the clipboard.'
} | Out-Null
$chkList = New-DarkList $f @(@('Check', 200), @('Result', 270), @('Status', 60), @('What to do', 326)) 860 300 $false
$chkList.ShowItemToolTips = $true; $f.SetFlowBreak($chkList, $true)
function Start-SystemCheck {
    $chkList.Items.Clear()
    Start-Background 'System check' $SystemCheckWork @() {
        param($out)
        $fix = @(); $look = @()
        foreach ($r in $out) {
            if (-not $r.Check) { continue }
            $li = New-Object System.Windows.Forms.ListViewItem("$($r.Check)")
            $mark = switch ($r.Verdict) { 'Good' { 'OK' } 'Warn' { 'CHECK' } 'Bad' { 'FIX' } default { 'info' } }
            foreach ($v in $r.Value, $mark, $r.Advice) { [void]$li.SubItems.Add("$v") }
            $li.ToolTipText = "$($r.Advice)"; $li.Tag = $r
            $li.ForeColor = switch ($r.Verdict) { 'Good' { $C.Good } 'Warn' { $C.Warn } 'Bad' { $C.Bad } default { $C.Muted } }
            [void]$chkList.Items.Add($li)
            if ($r.Verdict -eq 'Bad') { $fix += $r } elseif ($r.Verdict -eq 'Warn') { $look += $r }
        }
        if (-not $fix -and -not $look) { Log 'System check: everything looks good.' }
        else {
            Log ("System check: {0} to fix, {1} to look at." -f $fix.Count, $look.Count)
            foreach ($r in $fix + $look) { Log ("  {0}: {1} - {2}" -f $r.Check, $r.Value, $r.Advice) }
        }
    }
}
# BIOS changed since last time (e.g. you just flashed it)? Run the check so you notice if EXPO got reset.
[void]$script:AfterShown.Add({
    $s = Get-Settings; $now = "$((Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion)".Trim()
    if ($s.LastBios -and $s.LastBios -ne $now) {
        Log "BIOS changed from $($s.LastBios) to $now - running a system check (BIOS updates usually turn EXPO off)."
        Show-Page 'Health'; Start-SystemCheck
    }
    if ($s.LastBios -ne $now) { $s.LastBios = $now; Save-Settings $s }
})
Add-Section $f 'Crashes'
Add-Tool $f 'Crash detective' 'What caused each crash, in plain English' { Invoke-CrashDetective } -Primary | Out-Null
Add-Tool $f 'Reliability history' 'Windows crash timeline' { Start-Process perfmon.exe '/rel'; Log 'Opened Reliability history.' } | Out-Null
Add-Section $f 'Startup speed' 'stopwatch'
Add-Tool $f 'Boot time' 'How long Windows takes to start + what slows it' { Invoke-BootTime } | Out-Null
Add-Tool $f 'Startup apps' 'Turn off apps that slow the start' { Show-Page 'Tweaks' } -Icon 'gear' | Out-Null
Add-Section $f 'Memory (RAM)'
Add-Tool $f 'Memory info' 'Speed, EXPO status, last test result' { Invoke-MemoryInfo } | Out-Null
Add-Tool $f 'Run memory test' 'Windows Memory Diagnostic (on restart)' { Invoke-MemoryTest } | Out-Null
Add-Section $f 'Drives & drivers'
Add-Tool $f 'Drive health' 'SSD wear, temperature, errors' { Invoke-SsdHealth } | Out-Null
Add-Tool $f 'Driver check' 'GPU, network, audio driver ages' { Invoke-DriverCheck } | Out-Null
Add-Tool $f 'Get NVIDIA driver' 'Opens the NVIDIA app or website' {
    $app = Get-ChildItem 'C:\Program Files\NVIDIA Corporation\NVIDIA app' -Recurse -Filter 'NVIDIA app.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($app) { Start-Process $app.FullName; Log 'Opened the NVIDIA app - go to Drivers.' }
    else { Start-Process 'https://www.nvidia.com/en-us/geforce/drivers/'; Log 'Opened the NVIDIA driver page.' }
} | Out-Null
Add-Tool $f 'Optional driver updates' 'From Windows Update' { Start-Process 'ms-settings:windowsupdate-optionalupdates'; Log 'Opened optional updates.' } | Out-Null

# ================================================================ PAGE: GAMING
$f = Add-Page 'Gaming' ([char]0x25B6) 'Free up the PC before you play'
Add-Section $f 'Game session (one click before you play, one after)'
$script:SessionNote = Add-Note $f ''
function Update-SessionNote {
    $g = Get-GameSession
    if ($g) {
        $d = [datetime]::MinValue; [void][datetime]::TryParse("$($g.Started)", [ref]$d)
        $script:SessionNote.Text = "ON since {0:HH:mm} - {1} app(s) closed, High performance{2}. Click End game session when you are done." -f $d, @($g.Reopen).Count, $(if ($g.PausedWU) { ', Windows Update paused' } else { '' })
        $script:SessionNote.ForeColor = $C.Accent
    } else {
        $script:SessionNote.Text = 'Off. Start closes your Auto Boost apps (list below), switches to High performance and pauses Windows Update. End puts it all back.'
        $script:SessionNote.ForeColor = $C.Muted
    }
}
Add-Tool $f 'Start game session' 'Close Boost apps, max power, pause updates' { Start-GameSession; Update-SessionNote; Update-AppList } -Primary | Out-Null
Add-Tool $f 'End game session' 'Put everything back the way it was' { Stop-GameSession; Update-SessionNote } | Out-Null
Update-SessionNote
Add-Section $f 'Boost'
Add-Tool $f 'Gaming tweaks' 'Game Mode + GPU scheduling on' { Invoke-GamingTweaks } -Primary | Out-Null
Add-Tool $f 'Power: Balanced' 'Best for Ryzen 7000 (recommended)' { Set-PowerPlan 'SCHEME_BALANCED' } | Out-Null
Add-Tool $f 'Power: High performance' 'Max clocks, more heat & power' { Set-PowerPlan 'SCHEME_MIN' } | Out-Null
Add-Tool $f 'Mouse acceleration' 'Toggle "Enhance pointer precision"' { Set-MouseAccel (-not (Get-MouseAccel)) } | Out-Null
Add-Tool $f 'Clear shader cache' 'Fixes stutter after driver updates' { Clear-ShaderCache } | Out-Null
Add-Tool $f 'Shader cache size' 'Bigger NVIDIA cache = less stutter' { Show-ShaderCacheTip } | Out-Null
Add-Tool $f 'PBO + Curve Optimizer' 'Step-by-step BIOS guide for Ryzen' { Show-PboGuide } | Out-Null
Add-Section $f 'Games on the graphics card (stops Windows using the weak CPU graphics)'
Add-Tool $f 'Find my games' 'Lists each game and its GPU setting' {
    $gpuList.Items.Clear()
    $all = @(Get-GameExes)
    foreach ($g in $all) {
        $li = New-Object System.Windows.Forms.ListViewItem($g.Game)
        [void]$li.SubItems.Add($g.Exe); [void]$li.SubItems.Add($(if ($g.Pinned) { 'Graphics card' } else { 'Let Windows decide' }))
        $li.Tag = $g; $li.ToolTipText = $g.Path; $li.Checked = -not $g.Pinned
        $li.ForeColor = $(if ($g.Pinned) { $C.Good } else { $C.Text })
        [void]$gpuList.Items.Add($li)
    }
    $todo = @($all | Where-Object { -not $_.Pinned }).Count
    Log ("Found {0} game program(s); {1} not pinned to the graphics card yet{2}." -f $all.Count, $todo, $(if ($todo) { ' - they are ticked, click Pin ticked games' } else { '' }))
} -Primary | Out-Null
Add-Tool $f 'Pin ticked games' 'Always use the graphics card' {
    $paths = @($gpuList.CheckedItems | ForEach-Object { $_.Tag.Path })
    if (-not $paths) { Log 'Click Find my games, then tick the ones to pin.'; return }
    Set-GameGpu $paths
    foreach ($i in $gpuList.CheckedItems) { $i.SubItems[2].Text = 'Graphics card'; $i.ForeColor = $C.Good; $i.Checked = $false }
} | Out-Null
$gpuList = New-DarkList $f @(@('Game', 300), @('Program', 330), @('Runs on', 220)) 860 170 $true
$gpuList.ShowItemToolTips = $true; $f.SetFlowBreak($gpuList, $true)
Add-Section $f 'Close background apps (tick, then Close selected)'
$appList = New-Object System.Windows.Forms.CheckedListBox
$appList.Size = New-Object System.Drawing.Size(566, 214); $appList.CheckOnClick = $true
$appList.BackColor = $C.Panel; $appList.ForeColor = $C.Text; $appList.BorderStyle = 'None'
$appList.Font = New-Font 10 'Regular' 'Consolas'
$appList.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
$f.Controls.Add($appList)
function Update-AppList {
    $appList.Items.Clear()
    $boost = (Get-Settings).BoostApps
    foreach ($a in Get-ClosableApps) {
        [void]$appList.Items.Add(('{0,-28} {1,7:N0} MB' -f $a.Name, $a.MB), ($boost -contains $a.Name))
    }
}
function Get-TickedApps { @($appList.CheckedItems | ForEach-Object { ($_ -split '\s+')[0] }) }
$side = New-Object System.Windows.Forms.FlowLayoutPanel
$side.FlowDirection = 'TopDown'; $side.Size = New-Object System.Drawing.Size(290, 222); $side.WrapContents = $false
$f.Controls.Add($side)
Add-Tool $side 'Refresh list' 'Show apps running now' { Update-AppList; Log "Found $($appList.Items.Count) apps you can close." } | Out-Null
Add-Tool $side 'Close selected apps' 'Frees RAM and CPU for your game' {
    $names = Get-TickedApps
    if (-not $names) { Log 'Tick the apps to close first.'; return }
    if (Confirm-Action ("Close these apps?`n`n" + ($names -join "`n") + "`n`nUnsaved work in them will be lost.")) { Close-Apps $names | Out-Null; Update-AppList }
} | Out-Null
Add-Tool $side 'Save as Auto Boost list' 'Tray app closes these when a game starts' {
    $s = Get-Settings; $s.BoostApps = @(Get-TickedApps); Save-Settings $s
    Log ("Auto Game Boost list saved: {0}" -f $(if ($s.BoostApps) { $s.BoostApps -join ', ' } else { '(empty)' }))
} | Out-Null
Add-Section $f 'Auto Game Boost + panic key (tray app)'
Add-Note $f 'The tray app (orange H by the clock) closes your Auto Boost apps when a game starts and reopens them after. Ctrl+Alt+End force-closes a frozen game.' | Out-Null
Add-Tool $f 'Start tray app' 'Auto Game Boost + panic key' { Start-TrayApp } -Primary | Out-Null
Add-Tool $f 'Tray app with Windows' 'Starts by itself when you sign in' { Set-TrayAtStartup (-not (Test-TrayAtStartup)) } -State { Test-TrayAtStartup } | Out-Null
Add-Tool $f 'Game Mode settings' 'Windows gaming options' { Start-Process 'ms-settings:gaming-gamemode' } | Out-Null

# ================================================================ PAGE: GAMES
$f = Add-Page 'Games' ([char]0x265C) 'Every installed game, its size and when you last played it'
$gamesList = New-DarkList $f @(@('Game', 330), @('Store', 70), @('Size', 90), @('Last played', 110), @('Location', 260)) 880 330 $false
$gamesList.Sorting = 'None'
$gamesNote = Add-Note $f ''
function Get-SelectedGame { if ($gamesList.SelectedItems.Count) { $gamesList.SelectedItems[0].Tag } else { Log 'Click a game in the list first.'; $null } }
function Update-GameList {
    $script:GamesLoaded = $true
    $gamesList.Items.Clear()
    $games = @(Get-SteamGames)
    $xboxFolders = @()
    foreach ($root in Get-GameRoots | Where-Object { $_ -notmatch 'steamapps' }) {
        foreach ($d in Get-ChildItem $root -Directory -ErrorAction SilentlyContinue) {
            $games += [pscustomobject]@{ Name = $d.Name; Store = $(if ($root -match 'Xbox') { 'Xbox' } elseif ($root -match 'Epic') { 'Epic' } else { 'Other' })
                Id = $null; Bytes = -1; LastPlayed = $null; Path = $d.FullName }
            $xboxFolders += $d.FullName
        }
    }
    $script:AllGames = $games
    Show-Games
    $gamesNote.Text = "{0} games. Steam sizes shown; Xbox/other folders are being measured..." -f $games.Count
    if ($xboxFolders) {
        Start-Background 'Measuring Xbox/other game folders' $XboxSizeWork (, $xboxFolders) {
            param($out)
            foreach ($r in $out) { foreach ($g in $script:AllGames) { if ($g.Path -eq $r.Path) { $g.Bytes = $r.Bytes } } }
            Show-Games
        }
    }
}
function Show-Games {
    $gamesList.BeginUpdate(); $gamesList.Items.Clear()
    # hide tiny add-on folders (e.g. Call of Duty 'DLC / Game Stub' packs) once measured
    $shown = @($script:AllGames | Where-Object { $_.Bytes -lt 0 -or $_.Bytes -ge 200MB -or $_.Store -eq 'Steam' })
    foreach ($g in $shown | Sort-Object Bytes -Descending) {
        $it = New-Object System.Windows.Forms.ListViewItem($g.Name)
        [void]$it.SubItems.Add($g.Store)
        [void]$it.SubItems.Add($(if ($g.Bytes -ge 0) { Format-Size $g.Bytes } else { '...' }))
        [void]$it.SubItems.Add($(if ($g.LastPlayed) { '{0:yyyy-MM-dd}' -f $g.LastPlayed } else { '-' }))
        [void]$it.SubItems.Add($g.Path)
        $it.Tag = $g
        [void]$gamesList.Items.Add($it)
    }
    $gamesList.EndUpdate()
    $sum = ($script:AllGames | Where-Object Bytes -gt 0 | Measure-Object Bytes -Sum).Sum
    $hidden = $script:AllGames.Count - $shown.Count
    $gamesNote.Text = "{0} games using {1} in total.{2}" -f $shown.Count, (Format-Size $sum), $(if ($hidden) { " ($hidden small add-on folders hidden)" } else { '' })
}
Add-Tool $f 'Play' 'Launch the selected game' {
    $g = Get-SelectedGame; if (-not $g) { return }
    if ($g.Store -eq 'Steam') { Start-Process "steam://rungameid/$($g.Id)"; Log "Launching $($g.Name)..." }
    elseif ($g.Store -eq 'Xbox') { Start-Process 'xbox:'; Log 'Opened the Xbox app - start the game from there.' }
    else { Start-Process explorer.exe $g.Path }
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Uninstall' 'Through Steam / Windows' {
    $g = Get-SelectedGame; if (-not $g) { return }
    if ($g.Store -eq 'Steam') { Start-Process "steam://uninstall/$($g.Id)"; Log "Steam will ask to confirm uninstalling $($g.Name)." }
    else { Start-Process 'ms-settings:appsfeatures'; Log "Find '$($g.Name)' in the list and click Uninstall (or use the Xbox app)." }
} -Width 210 | Out-Null
Add-Tool $f 'Open folder' 'Show game files' { $g = Get-SelectedGame; if ($g) { Start-Process explorer.exe $g.Path } } -Width 210 | Out-Null
Add-Tool $f 'Refresh' 'Rescan installed games' { Update-GameList } -Width 210 | Out-Null
Add-Note $f 'Moving Steam games to another drive? See "Move Steam games" further down this page.' | Out-Null

# ================================================================ PAGE: NETWORK
$f = Add-Page 'Network' ([char]0x2301) 'Speed, ping, DNS and connection fixes'
Add-Section $f 'Test'
Add-Tool $f 'Speed test' 'Download + upload (Cloudflare)' { Start-Background 'Speed test' $SpeedTestWork @() } -Primary | Out-Null
Add-Tool $f 'Ping test' 'Latency, jitter, packet loss' {
    $gw = $null; $a = Get-MainAdapter
    if ($a) { $gw = ((Get-NetIPConfiguration -InterfaceIndex $a.ifIndex).IPv4DefaultGateway | Select-Object -First 1).NextHop }
    $targets = @()
    if ($gw) { $targets += [pscustomobject]@{ Name = "Router ($gw)"; Host = $gw } }
    $targets += [pscustomobject]@{ Name = 'Cloudflare (1.1.1.1)'; Host = '1.1.1.1' }
    $targets += [pscustomobject]@{ Name = 'Google (8.8.8.8)'; Host = '8.8.8.8' }
    Start-Background 'Ping test' $PingWork (, $targets)
} | Out-Null
Add-Tool $f 'Apps using internet' 'Which apps are connected now' { Invoke-WhoIsOnline } | Out-Null
Add-Tool $f 'My network info' 'Adapter, speed, IP, DNS, VPNs' { Invoke-NetworkInfo } | Out-Null
Add-Section $f 'Fix'
Add-Tool $f 'Flush DNS' 'Fixes sites that will not load' { Clear-DnsClientCache; Log 'DNS cache flushed.' } | Out-Null
Add-Tool $f 'Use Cloudflare DNS' 'Fast, private DNS (1.1.1.1)' { Set-GamingDns $true } | Out-Null
Add-Tool $f 'Reset DNS to automatic' 'Undo Cloudflare DNS' { Set-GamingDns $false } | Out-Null
Add-Tool $f 'Reset network' 'Winsock + TCP/IP reset (restart needed)' { Invoke-NetworkReset } | Out-Null

# ================================================================ PAGE: SERVER
$f = Add-Page 'Server' ([char]0x25A3) 'Media apps, your own servers and drive space - is everything up?'
Add-Section $f 'Status' 'server'
Add-Tool $f 'Check now' 'Apps, servers and drives' { Start-ServerCheck } -Primary -Width 210 | Out-Null
Add-Tool $f 'Open web page' 'Selected app or server' {
    $r = Get-SelectedServer; if (-not $r) { return }
    if ($r.Web) { Start-Process $r.Web; Log "Opened $($r.Web)" } elseif ($r.Kind -eq 'Drive') { Start-Process explorer.exe $r.Path } else { Log "$($r.Name) has no web page." }
} -Width 210 -Icon 'arrow-up-right-from-square' | Out-Null
Add-Tool $f 'Start / restart' 'Selected app on this PC' {
    $r = Get-SelectedServer; if (-not $r) { return }
    if ($r.Kind -eq 'Drive') { Log 'Pick an app, not a drive.'; return }
    if (Confirm-Action "Start or restart $($r.Name)?") { Start-ServerApp $r; Start-ServerCheck }
} -Width 210 -Icon 'rotate' | Out-Null
Add-Tool $f 'Add a server' 'Website or IP to watch' {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $url = [Microsoft.VisualBasic.Interaction]::InputBox("Address to check, for example:`n  https://myserver.example.com`n  http://192.168.1.50:8096/health", 'Add a server', '')
    if (-not $url.Trim()) { return }
    $guess = ($url -replace '^https?://', '' -split '[/:]')[0]
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('Name to show for it:', 'Add a server', $guess)
    if (-not $name.Trim()) { $name = $guess }
    Add-ServerCheck $name.Trim() $url.Trim(); Start-ServerCheck
} -Width 210 -Icon 'plus' | Out-Null
$srvList = New-DarkList $f @(@('Name', 210), @('Status', 120), @('Details', 520)) 860 330 $false
$srvList.ShowItemToolTips = $true; $f.SetFlowBreak($srvList, $true)
function Get-SelectedServer { if ($srvList.SelectedItems.Count) { $srvList.SelectedItems[0].Tag } else { Log 'Click a row in the list first.'; $null } }
function Start-ServerCheck {
    $script:SrvChecking = $true
    Start-Background 'Server check' $ServerCheckWork @($ServerCatalog, (Get-ServerChecks), (Get-ServerHidden)) {
        param($out)
        $script:SrvChecking = $false
        $srvList.Items.Clear(); $bad = @()
        foreach ($r in $out | Where-Object { $_.Name }) {
            $li = New-Object System.Windows.Forms.ListViewItem("$($r.Name)")
            [void]$li.SubItems.Add("$($r.Status)"); [void]$li.SubItems.Add("$($r.Detail)")
            $li.Tag = $r; $li.ToolTipText = "$($r.Detail)"
            $li.ForeColor = switch ($r.Verdict) { 'Good' { $C.Good } 'Warn' { $C.Warn } 'Bad' { $C.Bad } default { $C.Muted } }
            [void]$srvList.Items.Add($li)
            if ($r.Verdict -ne 'Good') { $bad += $r }
        }
        if ($bad) { Log ("Server check: {0} need a look - {1}" -f $bad.Count, (($bad | ForEach-Object { "$($_.Name) ($($_.Status))" }) -join ', ')) }
        else { Log 'Server check: everything is up.' }
    }
}
Add-Section $f 'Manage' 'sliders'
Add-Tool $f 'Remove / hide' 'Selected row' {
    $r = Get-SelectedServer; if ($r) { Remove-ServerRow $r; Start-ServerCheck }
} -Width 210 -Icon 'eye-slash' | Out-Null
Add-Tool $f 'Show hidden apps' 'Bring hidden apps back' { Show-HiddenServerApps; Log 'Hidden apps will show again.'; Start-ServerCheck } -Width 210 -Icon 'list' | Out-Null
Add-Tool $f 'Tray alerts' 'Pop-up when something goes down' {
    $s = Get-Settings; $s.ServerAlerts = -not $s.ServerAlerts; Save-Settings $s
    Log ("Server alerts from the tray app are now {0}. The tray checks every 5 minutes." -f $(if ($s.ServerAlerts) { 'on' } else { 'off' }))
} -Width 210 -Icon 'triangle-exclamation' -State { [bool](Get-Settings).ServerAlerts } | Out-Null
Add-Note $f 'Apps are found automatically (Radarr, Sonarr, Prowlarr, Jellyfin, Emby, Plex, qBittorrent, Tailscale...). Servers you add stay on this PC only.' | Out-Null
if (-not $script:PageShowHooks) { $script:PageShowHooks = @{} }
$script:PageShowHooks['Server'] = { Start-ServerCheck }

# ================================================================ PAGE: STORAGE
$f = Add-Page 'Storage' ([char]0x25A4) 'Find and remove what is eating your disk space'
Add-Section $f 'Where to look'
$where = New-Object System.Windows.Forms.ComboBox
$where.DropDownStyle = 'DropDownList'; $where.Width = 566; $where.Font = New-Font 10.5
$where.BackColor = $C.Panel; $where.ForeColor = $C.Text; $where.FlatStyle = 'Flat'
$where.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
foreach ($d in $script:Drives) { [void]$where.Items.Add("$($d.Drive)\") }
[void]$where.Items.Add($env:USERPROFILE)
$dl = Join-Path $env:USERPROFILE 'Downloads'; [void]$where.Items.Add($dl)
$where.SelectedIndex = $where.Items.Count - 2
$f.Controls.Add($where); $f.SetFlowBreak($where, $true)

$script:ResultRecycle = $true
function Show-Results([string]$Title, $Items, [bool]$Recycle, [bool]$TickAll) {
    $resultList.Items.Clear()
    $script:ResultRecycle = $Recycle
    $total = 0
    foreach ($r in @($Items) | Where-Object { $_ } | Sort-Object Bytes -Descending) {
        $it = New-Object System.Windows.Forms.ListViewItem((Format-Size $r.Bytes))
        [void]$it.SubItems.Add($r.Path); [void]$it.SubItems.Add([string]$r.Info)
        $it.Tag = $r.Path; $it.Checked = $TickAll
        [void]$resultList.Items.Add($it); $total += $r.Bytes
    }
    $resultNote.Text = "{0}: {1} item(s), {2} total. {3}" -f $Title, $resultList.Items.Count, (Format-Size $total),
        $(if ($Recycle) { 'Removing sends them to the Recycle Bin.' } else { 'Removing deletes them permanently (they can be rebuilt).' })
    Log $resultNote.Text
}

Add-Tool $f 'Biggest folders' 'Top folders by size' {
    Start-Background "Folder scan of $($where.SelectedItem)" $SizeScanWork @($where.SelectedItem, 'folders') { param($o) Show-Results 'Biggest folders' ($o | Sort-Object Bytes -Descending | Select-Object -First 25) $true $false }
} -Primary | Out-Null
Add-Tool $f 'Huge files (1 GB+)' 'Old installers, videos, ISOs' {
    Start-Background "Big-file scan of $($where.SelectedItem)" $SizeScanWork @($where.SelectedItem, 'files') { param($o) Show-Results 'Huge files' $o $true $false }
} | Out-Null
Add-Tool $f 'Downloads cleaner' 'Installers, archives, old files' {
    Start-Background 'Downloads scan' $DownloadsScanWork @($dl) { param($o) Show-Results 'Downloads clutter' $o $true $false }
} | Out-Null
Add-Tool $f 'Project cleaner' 'node_modules, Unity Library, builds' {
    Start-Background "Project scan of $($where.SelectedItem)" $ProjectScanWork @($where.SelectedItem) { param($o) Show-Results 'Rebuildable project junk' $o $false $false }
} | Out-Null
Add-Tool $f 'Duplicate files' 'Same file saved twice' {
    Start-Background "Duplicate scan of $($where.SelectedItem)" $DuplicateScanWork @($where.SelectedItem) { param($o) Show-Results 'Duplicate copies (oldest copy is kept)' $o $true $false }
} | Out-Null
Add-Tool $f 'Open in Explorer' 'Browse the selected place' { Start-Process explorer.exe $where.SelectedItem } | Out-Null

Add-Section $f 'Results (tick what to remove)'
$resultList = New-DarkList $f @(@('Size', 90), @('Path', 520), @('Details', 260)) 880 260 $true
$resultList.Add_DoubleClick({ if ($resultList.SelectedItems.Count) { $p = $resultList.SelectedItems[0].Tag; Start-Process explorer.exe "/select,`"$p`"" } })
$resultNote = Add-Note $f 'Run a scan above. Double-click a result to show it in Explorer.'
Add-Tool $f 'Remove ticked' 'Recycle / delete the ticked items' {
    $paths = @($resultList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $paths) { Log 'Tick some results first.'; return }
    $how = if ($script:ResultRecycle) { 'move to the Recycle Bin' } else { 'PERMANENTLY delete' }
    if (Confirm-Action ("{0} {1} item(s)?`n`n{2}" -f $how, $paths.Count, (($paths | Select-Object -First 12) -join "`n"))) {
        Remove-Paths $paths $script:ResultRecycle
        foreach ($i in @($resultList.CheckedItems)) { if (-not (Test-Path -LiteralPath $i.Tag)) { $resultList.Items.Remove($i) } }
    }
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Tick all' 'Select every result' { foreach ($i in $resultList.Items) { $i.Checked = $true } } -Width 210 | Out-Null
Add-Tool $f 'Untick all' 'Clear selection' { foreach ($i in $resultList.Items) { $i.Checked = $false } } -Width 210 | Out-Null
Add-Section $f 'More'
Add-Tool $f 'Empty Recycle Bin' 'Permanently delete what is in it' {
    if (Confirm-Action 'Permanently delete everything in the Recycle Bin?') { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Log 'Recycle Bin emptied.' }
} | Out-Null
Add-Tool $f 'Windows Disk Cleanup' 'Old updates, thumbnails, etc.' { Start-Process cleanmgr.exe; Log 'Opened Disk Cleanup - tick "Clean up system files" for more.' } | Out-Null
Add-Tool $f 'Uninstall apps' 'Installed apps list' { Start-Process 'ms-settings:appsfeatures' } | Out-Null

# ================================================================ PAGE: UNINSTALL
$f = Add-Page 'Uninstall' ([char]0x2716) 'Remove programs and games completely - uninstall, then sweep up the leftovers'
Add-Section $f '1. Pick a program or game'
$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Width = 566; $searchBox.Font = New-Font 11; $searchBox.BackColor = $C.Panel; $searchBox.ForeColor = $C.Text; $searchBox.BorderStyle = 'FixedSingle'
$searchBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 8)
$f.Controls.Add($searchBox)
$searchHint = New-Object System.Windows.Forms.Label
$searchHint.Text = 'type to search'; $searchHint.ForeColor = $C.Muted; $searchHint.AutoSize = $true
$searchHint.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
$f.Controls.Add($searchHint); $f.SetFlowBreak($searchHint, $true)
$progList = New-DarkList $f @(@('Program', 380), @('Publisher', 220), @('Size', 85), @('Installed', 95), @('Type', 75)) 880 220 $false
$progNote = Add-Note $f 'Loading installed programs...'
$script:Programs = @()

function Show-Programs {
    $q = $searchBox.Text.Trim()
    $progList.BeginUpdate(); $progList.Items.Clear()
    foreach ($p in $script:Programs) {
        if ($q -and $p.Name -notlike "*$q*" -and $p.Publisher -notlike "*$q*") { continue }
        $it = New-Object System.Windows.Forms.ListViewItem($p.Name)
        [void]$it.SubItems.Add($p.Publisher)
        [void]$it.SubItems.Add($(if ($p.Bytes -gt 0) { Format-Size $p.Bytes } else { '-' }))
        [void]$it.SubItems.Add($(if ($p.Installed) { '{0:yyyy-MM-dd}' -f $p.Installed } else { '-' }))
        [void]$it.SubItems.Add($p.Type)
        $it.Tag = $p
        [void]$progList.Items.Add($it)
    }
    $progList.EndUpdate()
    $progNote.Text = "{0} of {1} programs shown. Click one, then Uninstall (or just Scan leftovers for something already removed)." -f $progList.Items.Count, $script:Programs.Count
}
function Update-ProgramList {
    $script:ProgramsLoading = $true
    Start-Background 'Reading installed programs' $ProgramListWork @() {
        param($o)
        $script:Programs = @($o | Where-Object { $_ } | Sort-Object Name)
        Show-Programs
    }
}
$searchBox.Add_TextChanged({ Show-Programs })
function Get-PickedProgram {
    if ($progList.SelectedItems.Count) { return $progList.SelectedItems[0].Tag }
    if ($script:UninstallTarget) { return $script:UninstallTarget }
    Log 'Click a program in the list first.'; $null
}

Add-Section $f '2. Uninstall, then scan for leftovers'
$levelPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$levelPanel.Size = New-Object System.Drawing.Size(880, 34); $levelPanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
$levels = @(
    @('Safe', 'Safe'),
    @('Moderate', 'Moderate (recommended)'),
    @('Advanced', 'Advanced (review carefully)'))
$script:LevelRadios = @{}
foreach ($lv in $levels) {
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = $lv[1]; $rb.Tag = $lv[0]; $rb.AutoSize = $true; $rb.ForeColor = $C.Text; $rb.UseMnemonic = $false
    $rb.Margin = New-Object System.Windows.Forms.Padding(0, 6, 18, 0)
    if ($lv[0] -eq 'Moderate') { $rb.Checked = $true }
    $levelPanel.Controls.Add($rb); $script:LevelRadios[$lv[0]] = $rb
}
$f.Controls.Add($levelPanel); $f.SetFlowBreak($levelPanel, $true)
Add-Note $f 'Safe: install + same-name folders.   Moderate: + registry, shortcuts, temp.   Advanced: + similar names, services, tasks.' | Out-Null
$script:UninstallFlow = $f
function Get-ScanLevel { foreach ($k in 'Safe', 'Moderate', 'Advanced') { if ($script:LevelRadios[$k].Checked) { return $k } }; 'Moderate' }

function Show-Leftovers([string]$Title, $Items) {
    $leftList.BeginUpdate(); $leftList.Items.Clear()
    $total = 0; $ticked = 0
    foreach ($r in @($Items) | Where-Object { $_ -and $_.Path } | Sort-Object Level, @{ e = { $_.Bytes }; Descending = $true }) {
        $it = New-Object System.Windows.Forms.ListViewItem($r.Type)
        [void]$it.SubItems.Add($r.Path)
        [void]$it.SubItems.Add($(if ($r.Type -in 'Folder', 'File') { Format-Size $r.Bytes } else { '' }))
        [void]$it.SubItems.Add(("{0}: {1}" -f @('', 'Safe', 'Moderate', 'Advanced')[$r.Level], $r.Why))
        $it.Tag = $r; $it.Checked = [bool]$r.Tick
        if ($r.Level -ge 3) { $it.ForeColor = $C.Warn }
        [void]$leftList.Items.Add($it); $total += $r.Bytes; if ($r.Tick) { $ticked++ }
    }
    $leftList.EndUpdate()
    $leftNote.Text = "{0}: {1} leftover(s), {2}. {3} pre-ticked. Yellow = Advanced finds - check before removing." -f $Title, $leftList.Items.Count, (Format-Size $total), $ticked
    Log $leftNote.Text
    if ($leftList.Items.Count -eq 0) { Log 'Nothing left behind - clean uninstall.' }
    $script:UninstallFlow.ScrollControlIntoView($leftNote)
}

Add-Tool $f 'Uninstall' 'Runs the official uninstaller' {
    $p = Get-PickedProgram; if (-not $p) { return }
    if (-not (Confirm-Action "Uninstall $($p.Name)?`n`nIts own uninstaller will open. Afterwards, click 'Scan leftovers'.")) { return }
    $script:UninstallTarget = $p
    Invoke-ProgramUninstall $p
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Scan leftovers' 'Find what the uninstaller left' {
    $p = Get-PickedProgram; if (-not $p) { return }
    $script:UninstallTarget = $p
    $others = @($script:Programs | Where-Object { -not [object]::ReferenceEquals($_, $p) -and -not ($_.Name -eq $p.Name -and $_.Version -eq $p.Version) })
    $still = ($p.Key -and (Test-Path $p.Key) -and $p.InstallLocation -and (Test-Path -LiteralPath $p.InstallLocation)) -or ($p.Type -eq 'Store' -and (Get-AppxPackage | Where-Object PackageFullName -eq $p.Package))
    if ($still) { Log "Note: $($p.Name) still looks installed - uninstall it first, or the results include its live files." }
    $lv = Get-ScanLevel
    Start-Background "$lv leftover scan for $($p.Name)" $LeftoverScanWork @($p, $lv, $others) { param($o) Show-Leftovers "Leftovers of $($script:UninstallTarget.Name) ($(Get-ScanLevel))" $o }
} -Width 210 | Out-Null
Add-Tool $f 'Leftover finder' 'Old folders from removed apps' {
    if (-not $script:Programs) { Log 'Wait for the program list to load first.'; return }
    $running = @(Get-Process | ForEach-Object { try { $_.Path } catch { } } | Where-Object { $_ } | Select-Object -Unique)
    Start-Background 'Leftover finder' $OrphanScanWork (@(, $script:Programs) + @(, $running)) { param($o) Show-Leftovers 'Folders from apps that are no longer installed' $o }
} -Width 210 | Out-Null
Add-Tool $f 'Refresh list' 'Re-read installed programs' { $searchBox.Text = ''; Update-ProgramList } -Width 210 | Out-Null

Add-Section $f '3. Tick what to remove'
$leftList = New-DarkList $f @(@('Type', 70), @('Item', 470), @('Size', 80), @('Why', 235)) 880 230 $true
$leftList.Add_DoubleClick({
    if (-not $leftList.SelectedItems.Count) { return }
    $r = $leftList.SelectedItems[0].Tag
    if ($r.Type -in 'Folder', 'File') { Start-Process explorer.exe "/select,`"$($r.Path)`"" } else { Log "$($r.Type): $($r.Path)" }
})
$leftNote = Add-Note $f 'Files and folders go to the Recycle Bin. Registry keys, services and tasks are backed up first.'
Add-Tool $f 'Remove ticked' 'Recycle files, back up + remove the rest' {
    $items = @($leftList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $items) { Log 'Tick some leftovers first.'; return }
    $summary = ($items | Group-Object Type | ForEach-Object { "$($_.Count) $($_.Name)(s)" }) -join ', '
    $adv = @($items | Where-Object Level -ge 3).Count
    $msg = "Remove $summary?`n`nFiles/folders go to the Recycle Bin. Registry, services and tasks are backed up to the toolkit's backups folder."
    if ($adv) { $msg += "`n`n$adv of them are Advanced (similar-name) finds - make sure they belong to the removed program." }
    if (-not (Confirm-Action $msg)) { return }
    Remove-LeftoverItems $items
    foreach ($it in @($leftList.CheckedItems)) { if (-not (Test-LeftoverExists $it.Tag)) { $leftList.Items.Remove($it) } }
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Tick all' 'Select every leftover' { foreach ($i in $leftList.Items) { $i.Checked = $true } } -Width 210 | Out-Null
Add-Tool $f 'Untick all' 'Clear selection' { foreach ($i in $leftList.Items) { $i.Checked = $false } } -Width 210 | Out-Null
Add-Tool $f 'Open backups' 'Restore a registry backup' {
    $b = Join-Path $HallowRoot 'backups'; New-Item -ItemType Directory -Force $b | Out-Null; Start-Process explorer.exe $b
} -Width 210 | Out-Null

. (Join-Path $PSScriptRoot 'HallowExtraPages.ps1')
. (Join-Path $PSScriptRoot 'HallowDriverPage.ps1')
. (Join-Path $PSScriptRoot 'HallowMicPage.ps1')
. (Join-Path $PSScriptRoot 'HallowAppsPage.ps1')
. (Join-Path $PSScriptRoot 'HallowGameExtrasPage.ps1')
. (Join-Path $PSScriptRoot 'HallowMorePage.ps1')

# ================================================================ PAGE: TOOLS
$f = Add-Page 'Tools' ([char]0x2692) 'Handy Windows tools in one place'
Add-Section $f 'Info'
Add-Tool $f 'Copy my PC specs' 'For Discord, forums, support' { Copy-Specs } -Primary | Out-Null
Add-Tool $f 'Open log folder' 'Every action is logged' { Start-Process explorer.exe $LogDir } | Out-Null
Add-Tool $f 'Install CPU temp sensor' 'LibreHardwareMonitor (free, winget)' { Install-Lhm } | Out-Null

Add-Section $f 'Theme (saved - the window reopens to apply it)' 'star'
function Set-Theme([string]$Key, [string]$Value) {
    if ($script:Jobs.Count) { Log "Wait for '$($script:Jobs[0].Name)' to finish, then pick the theme again."; return }
    $s = Get-Settings; $s | Add-Member -NotePropertyName $Key -NotePropertyValue $Value -Force; Save-Settings $s
    Log "Theme: $Value - reopening the window..."
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"", '-StartPage', 'Tools')
    $form.Close()
}
function Add-Swatch($Flow, [string]$Text, $Back, $Fore, $Border, [bool]$On, [scriptblock]$Click, [bool]$Break) {
    $b = New-Object System.Windows.Forms.Button
    $b.UseMnemonic = $false; $b.Text = $(if ($On) { "$Text  (on)" } else { $Text })
    $b.FlatStyle = 'Flat'; $b.BackColor = $Back; $b.ForeColor = $Fore
    $b.FlatAppearance.BorderColor = $Border; $b.FlatAppearance.BorderSize = $(if ($On) { 3 } else { 1 })
    $b.FlatAppearance.MouseOverBackColor = $Back
    $b.Size = New-Object System.Drawing.Size(132, 40); $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    $b.Font = New-Font 9.5 $(if ($On) { 'Bold' } else { 'Regular' }); $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Tag = $Click; $b.Add_Click({ & $this.Tag })
    $Flow.Controls.Add($b); if ($Break) { $Flow.SetFlowBreak($b, $true) }
}
$curAccent = $(if ($ThemeAccents.Contains("$($ts.Theme)")) { "$($ts.Theme)" } else { 'Orange' })
$curBase = $(if ($ThemeBases.Contains("$($ts.ThemeBase)")) { "$($ts.ThemeBase)" } else { 'Hallow' })
$keys = @($ThemeAccents.Keys)
foreach ($k in $keys) {
    Add-Swatch $f $k $ThemeAccents[$k].Accent $C.AccentText $C.Text ($k -eq $curAccent) ([scriptblock]::Create("Set-Theme 'Theme' '$k'")) ($k -eq $keys[-1])
}
$keys = @($ThemeBases.Keys)
foreach ($k in $keys) {
    $label = @{ 'Hallow' = 'Hallow dark'; 'Graphite' = 'Graphite'; 'Navy' = 'Navy'; 'OLED' = 'OLED black' }[$k]
    Add-Swatch $f $label $ThemeBases[$k].Bg $C.Text $(if ($k -eq $curBase) { $C.Accent } else { $ThemeBases[$k].PanelHi }) ($k -eq $curBase) ([scriptblock]::Create("Set-Theme 'ThemeBase' '$k'")) ($k -eq $keys[-1])
}
Add-Note $f 'Top row: accent colour for buttons, icons and highlights. Bottom row: background. Your pick is kept across updates and goes along with Share your setup.' | Out-Null

Add-Section $f 'Toolkit updates'
Add-Tool $f 'Check for toolkit updates' 'Get the newest Hallow Toolkit' { Start-SelfUpdateCheck } -Primary | Out-Null
Add-Tool $f 'Auto update check' 'Checks when the toolkit opens' { Switch-AutoUpdate } -State { [bool](Get-Settings).AutoUpdate } | Out-Null
Add-Section $f 'Share your setup (tweaks + Boost list + toolkit settings)'
Add-Tool $f 'Export my setup' 'Save a file to send to a friend' {
    $d = New-Object System.Windows.Forms.SaveFileDialog
    $d.Filter = 'Hallow setup (*.hallow.json)|*.hallow.json'; $d.FileName = "$env:USERNAME-setup.hallow.json"
    $d.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($d.ShowDialog() -eq 'OK') { Export-HallowSetup $d.FileName }
} | Out-Null
Add-Tool $f 'Import a setup' 'Copy a friend''s tweaks and settings' {
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'Hallow setup (*.hallow.json)|*.hallow.json|All files|*.*'; $d.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($d.ShowDialog() -ne 'OK') { return }
    $plan = Read-HallowSetup $d.FileName
    $on = ($plan.TurnOn | ForEach-Object { "  + $($_.Name)" }) -join "`n"
    $off = ($plan.TurnOff | ForEach-Object { "  - $($_.Name)" }) -join "`n"
    $msg = "Setup from $($plan.Source.From) ($($plan.Source.Created)).`n`nBoost list: $(@($plan.Source.Settings.BoostApps) -join ', ')`n`n"
    $msg += $(if ($on) { "Turns ON:`n$on`n`n" } else { "No new tweaks to turn on.`n`n" })
    if ($off) { $msg += "They have these OFF (you have them on):`n$off`n`n" }
    $msg += 'Apply it?'
    if (-not (Confirm-Action $msg)) { return }
    $alsoOff = $false
    if ($off) { $alsoOff = [System.Windows.Forms.MessageBox]::Show("Also turn OFF the $(@($plan.TurnOff).Count) tweak(s) they don't use?`n(No keeps yours as they are.)", $AppName, 'YesNo', 'Question') -eq 'Yes' }
    Import-HallowSetup $plan $alsoOff
    Update-TweakBoxes
    Log 'Setup imported. Restart Explorer (button below) if taskbar changes do not show yet.'
} | Out-Null
Add-Section $f 'Quick fixes'
Add-Tool $f 'Fix audio' 'No sound / crackling - restart audio' { Repair-Audio } | Out-Null
Add-Tool $f 'Fix Bluetooth' 'Device will not connect' { Repair-Bluetooth } | Out-Null
Add-Tool $f 'Fix Start search' 'Search box blank or stuck' { Repair-Search } | Out-Null
Add-Tool $f 'Reset Microsoft Store' 'Store downloads stuck or failing' { Repair-Store } | Out-Null
Add-Tool $f 'Rebuild icons & thumbnails' 'Blank or wrong icons' {
    if (Confirm-Action 'Rebuild the icon and thumbnail cache? Explorer (taskbar + folders) restarts for a moment.') { Repair-IconCache }
} | Out-Null
Add-Tool $f 'Sync clock' 'Game login / certificate errors' { Sync-Clock } | Out-Null
Add-Tool $f 'Reset Windows Update' 'Updates stuck or failing' {
    if (Confirm-Action "Reset Windows Update?`n`nStops the update services, moves the download cache aside and starts them again. Any half-downloaded updates download again.") { Reset-WindowsUpdate }
} | Out-Null
Add-Section $f 'Fixes'
Add-Tool $f 'Restart Explorer' 'Stuck taskbar or Start menu' { Restart-Explorer } | Out-Null
Add-Tool $f 'Create restore point' 'Safety net before big changes' { New-RestorePoint } | Out-Null
Add-Tool $f 'Restart into BIOS' 'For BIOS updates (EZ Flash)' { Restart-ToBios } | Out-Null
Add-Section $f 'Windows tools'
$launchers = @(
    @('Task Manager', 'What is running right now', 'taskmgr.exe', ''),
    @('Resource Monitor', 'Live per-app network & disk', 'resmon.exe', ''),
    @('Device Manager', 'Drivers and hardware', 'devmgmt.msc', ''),
    @('Event Viewer', 'Crash and error logs', 'eventvwr.msc', ''),
    @('Services', 'Background services', 'services.msc', ''),
    @('Disk Management', 'Partitions and drives', 'diskmgmt.msc', ''),
    @('System Properties', 'Restore, performance, PC name', 'sysdm.cpl', ''),
    @('Windows Update', 'Check for updates', 'ms-settings:windowsupdate', ''),
    @('Startup apps', 'What launches with Windows', 'ms-settings:startupapps', '')
)
foreach ($l in $launchers) {
    $code = "Start-Process -FilePath '$($l[2])'"
    if ($l[3]) { $code += " -ArgumentList '$($l[3])'" }
    $code += "; Log 'Opened $($l[0]).'"
    Add-Tool $f $l[0] $l[1] ([scriptblock]::Create($code)) | Out-Null
}

# ---- go
$form.Add_Shown({
    if (-not $pages.Contains($StartPage)) { $StartPage = 'Tune-up' }
    Show-Page $StartPage
    Log "$AppName v$AppVersion ready. Start with Quick Clean-up, or explore the tabs on the left."
    [void]$script:AfterShown.Insert(0, { Update-AppList })
    $t = New-Object System.Windows.Forms.Timer; $t.Interval = 30
    $t.Add_Tick({
        $this.Stop()
        foreach ($a in $script:AfterShown) { try { & $a } catch { Log "Startup task failed: $($_.Exception.Message)" }; [System.Windows.Forms.Application]::DoEvents() }
    })
    $t.Start()
})
$form.Add_FormClosing({ $monTimer.Stop(); $jobTimer.Stop() })
[void]$form.ShowDialog()
