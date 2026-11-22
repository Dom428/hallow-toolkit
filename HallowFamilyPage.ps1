<#
  Hallow Toolkit - the Hallow page (v5.5): one card per Hallow family app - installed or not, running or not,
  update available - with Open / Install / Update. Dot-sourced by HallowToolkit.ps1 (needs its window helpers).
#>
if (-not $script:PageShowHooks) { $script:PageShowHooks = @{} }
$PageIcons['Hallow'] = 'layer-group'
$f = Add-Page 'Hallow' ([char]0x2756) 'The Hallow apps on this PC - open, install and update them'
Add-Section $f 'Hallow apps' 'layer-group'
$famNote = Add-Note $f ''
$famNote.Height = 36

# a rounded card: the parent's colour outside the corners, panel colour inside, hairline border
$script:FamilyCardPaint = {
    param($s, $e)
    $g = $e.Graphics
    $g.Clear($(if ($s.Parent) { $s.Parent.BackColor } else { $C.Bg })); $g.SmoothingMode = 'AntiAlias'
    $rp = New-RoundPath 0 0 ($s.Width - 1) ($s.Height - 1) 12
    $br = New-Object System.Drawing.SolidBrush($C.Panel); $g.FillPath($br, $rp); $br.Dispose()
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, $C.Grid), 1); $g.DrawPath($pen, $rp); $pen.Dispose()
    $rp.Dispose(); $g.SmoothingMode = 'Default'
}
function New-FamilyLabel($Parent, [int]$X, [int]$Y, [int]$W, [int]$H, $Font, $Color) {
    $l = New-Object System.Windows.Forms.Label
    $l.UseMnemonic = $false; $l.AutoSize = $false; $l.BackColor = $C.Panel; $l.ForeColor = $Color; $l.Font = $Font
    $l.Location = New-Object System.Drawing.Point($X, $Y); $l.Size = New-Object System.Drawing.Size($W, $H)
    $Parent.Controls.Add($l); $l
}
# card buttons are tool buttons, smaller; primary (accent) or not can change with the app's state
function Set-FamilyButton($B, [string]$Title, [string]$Icon, [bool]$Primary) {
    $key = "$Title|$Icon|$Primary"
    if ($script:FamilyBtnLook[$B] -eq $key) { return }   # unchanged: no repaint
    $script:FamilyBtnLook[$B] = $key
    $B.Text = "$Title`n"
    if ($Primary) { [void]$script:PrimaryButtons.Add($B) } else { [void]$script:PrimaryButtons.Remove($B) }
    if (Test-IconFont) { $B.Image = Get-Icon $Icon $(if ($Primary) { $C.AccentText } else { $C.Accent }) 18 }
    $B.Invalidate()
}
$script:FamilyBtnLook = @{}
$script:FamilyCards = [ordered]@{}
$script:FamilyBusy = @{}
foreach ($app in $FamilyApps) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(425, 150); $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
    $card.BackColor = $C.Panel; $card.Add_Paint($script:FamilyCardPaint)
    $f.Controls.Add($card)
    if (Test-IconFont) {
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Image = Get-Icon $app.Icon $C.Accent 26; $pb.Size = New-Object System.Drawing.Size(26, 26); $pb.Location = New-Object System.Drawing.Point(16, 15); $pb.BackColor = $C.Panel
        $card.Controls.Add($pb)
    }
    $title = New-FamilyLabel $card 52 13 230 28 (New-Font 12.5 'Bold') $C.Text
    $title.Text = "Hallow $($app.Name)"
    $state = New-FamilyLabel $card 282 17 128 22 (New-Font 9 'Bold') $C.Muted
    $state.TextAlign = 'TopRight'
    $desc = New-FamilyLabel $card 16 46 394 20 (New-Font 9) $C.Muted
    $desc.Text = $app.Desc
    $ver = New-FamilyLabel $card 16 68 394 20 (New-Font 9) $C.Text
    $b1 = Add-Tool $card $(if ($app.Kind -eq 'Extension') { 'Install steps' } else { 'Open' }) '' ([scriptblock]::Create("Invoke-FamilyMain '$($app.Name)'")) -Primary -Width 122 -Icon 'play'
    $b2 = Add-Tool $card 'Update' '' ([scriptblock]::Create("Invoke-FamilyInstall '$($app.Name)'")) -Width 122 -Icon 'arrows-rotate'
    $b3 = Add-Tool $card 'GitHub' '' ([scriptblock]::Create("Start-Process 'https://github.com/$(Get-FamilyRepo $app.Name)'")) -Width 122 -Icon 'arrow-up-right-from-square'
    $x = 16
    foreach ($b in $b1, $b2, $b3) { $b.Size = New-Object System.Drawing.Size(122, 42); $b.Location = New-Object System.Drawing.Point($x, 94); $x += 132 }
    $tips.SetToolTip($b3, "Source, changes and roadmap of Hallow $($app.Name)")
    if ($app.Kind -eq 'Extension') { $tips.SetToolTip($b1, 'How to add it to Chrome, Edge, Brave, Opera or Firefox (opens its README)'); $tips.SetToolTip($b2, 'Opens the newest release - download the zip for your browser') }
    $script:FamilyCards[$app.Name] = @{ State = $state; Ver = $ver; Main = $b1; Update = $b2; Page = $b3 }
}
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)

# ---- v5.8: one accent colour for every Hallow app (theme.json)
Add-Section $f 'Hallow accent - one colour for all the Hallow apps' 'star'
$accentNote = Add-Note $f ''
$accentNote.Height = 36
$script:AccentButtons = @()
function Update-AccentPicker {
    $cur = Get-HallowAccentHex
    $accentNote.Text = $(if ($cur) { "Hallow accent: $cur. Apps with ""Use the Hallow accent"" on (the default) switch to it straight away. The toolkit uses it when Tools > Theme is set to Hallow accent." }
        else { 'Not set - each app uses its own colour. Pick one and every Hallow app with "Use the Hallow accent" on (the default) switches to it straight away.' })
    foreach ($b in $script:AccentButtons) { $on = ("$($b.Tag)" -eq $cur); $b.FlatAppearance.BorderSize = $(if ($on) { 3 } else { 1 }); $b.Text = $(if ($on) { "$($b.AccessibleName)  (on)" } else { $b.AccessibleName }) }
}
function Set-AccentFromPicker([string]$Hex) {
    try { Set-HallowAccent $Hex } catch { Log "Could not save the Hallow accent: $($_.Exception.Message)"; return }
    Update-AccentPicker
    if (Get-Command Update-HallowTerminalAfterLook -ErrorAction SilentlyContinue) { Update-HallowTerminalAfterLook }   # v5.18
    Log ("Hallow accent set to {0} - the Hallow apps pick it up now.{1}" -f $Hex, $(if ("$((Get-Settings).Theme)" -eq 'Shared') { ' The toolkit shows it next time it opens (or pick it again in Tools > Theme).' } else { ' To use it in the toolkit too: Tools > Theme > Hallow accent.' }))
}
foreach ($k in @($HallowAccents.Keys) + 'Custom...') {
    $b = New-Object System.Windows.Forms.Button
    $b.UseMnemonic = $false; $b.FlatStyle = 'Flat'; $b.Size = New-Object System.Drawing.Size(88, 36); $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 8)
    $b.Font = New-Font 9; $b.Cursor = [System.Windows.Forms.Cursors]::Hand; $b.AccessibleName = $k
    if ($k -eq 'Custom...') {
        $b.Text = $k; $b.BackColor = $C.Panel; $b.ForeColor = $C.Text; $b.FlatAppearance.BorderColor = $C.Grid
        $b.Add_Click({
            $cd = New-Object System.Windows.Forms.ColorDialog; $cd.FullOpen = $true
            $cur = Get-HallowAccentHex; if ($cur) { $cd.Color = ConvertFrom-HexColor $cur }
            if ($cd.ShowDialog($form) -eq 'OK') { Set-AccentFromPicker ('#{0:X2}{1:X2}{2:X2}' -f $cd.Color.R, $cd.Color.G, $cd.Color.B) }
        })
    } else {
        $hex = $HallowAccents[$k]; $col = ConvertFrom-HexColor $hex
        $b.Text = $k; $b.Tag = $hex; $b.BackColor = $col; $b.FlatAppearance.MouseOverBackColor = $col; $b.FlatAppearance.BorderColor = $C.Text
        $b.AccessibleDescription = 'hallow-fixed'
        $b.ForeColor = $(if ((0.299 * $col.R + 0.587 * $col.G + 0.114 * $col.B) -lt 140) { [System.Drawing.Color]::White } else { RGB 20 12 4 })
        $b.Add_Click({ Set-AccentFromPicker "$($this.Tag)" })
        $script:AccentButtons += $b
    }
    $f.Controls.Add($b)
}
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
Update-AccentPicker

# ---- v5.16: light / dark for all the Hallow apps (theme.json "mode")
$modeNote = Add-Note $f ''
$modeNote.Height = 36
$script:ModeButtons = @()
function Update-ModePicker {
    $cur = Get-HallowMode
    $win = $(if ($cur -eq 'system') { $wl = Get-WindowsAppsLight; " Windows is set to $(if ($wl) { 'light' } else { 'dark' }) right now." } else { '' })
    $modeNote.Text = "Light or dark: $($HallowModes[$cur]).$win Every Hallow app switches straight away, unless its own Settings > Look is set to Light or Dark. The toolkit's own: Tools > Theme > Look."
    foreach ($b in $script:ModeButtons) { $on = ("$($b.AccessibleName)" -eq $cur); $b.Text = $(if ($on) { "$($HallowModes[$b.AccessibleName])  (on)" } else { $HallowModes[$b.AccessibleName] }); $b.FlatAppearance.BorderSize = $(if ($on) { 3 } else { 1 }); $b.FlatAppearance.BorderColor = $(if ($on) { $C.Accent } else { $C.Grid }) }
}
function Set-ModeFromPicker([string]$Mode) {
    try { Set-HallowMode $Mode } catch { Log "Could not save light / dark: $($_.Exception.Message)"; return }
    [void](Update-ToolkitLook); Update-ModePicker; if (Get-Command Update-LookPicker -ErrorAction SilentlyContinue) { Update-LookPicker }
    Log "Hallow apps: $($HallowModes[$Mode]) - they switch now."
    if (Get-Command Update-HallowTerminalAfterLook -ErrorAction SilentlyContinue) { Update-HallowTerminalAfterLook }   # v5.18
}
foreach ($k in @($HallowModes.Keys)) {
    $b = New-Object System.Windows.Forms.Button
    $b.UseMnemonic = $false; $b.FlatStyle = 'Flat'; $b.Size = New-Object System.Drawing.Size($(if ($k -eq 'system') { 170 } else { 110 }), 36); $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 8)
    $b.Font = New-Font 9; $b.Cursor = [System.Windows.Forms.Cursors]::Hand; $b.AccessibleName = $k
    $b.BackColor = $C.Panel; $b.ForeColor = $C.Text; $b.FlatAppearance.MouseOverBackColor = $C.PanelHi
    if (Test-IconFont) { $b.Image = Get-Icon @{ light = 'sun'; dark = 'moon'; system = 'desktop' }[$k] $C.Accent 16; $b.ImageAlign = 'MiddleLeft'; $b.TextImageRelation = 'ImageBeforeText'; $b.Padding = New-Object System.Windows.Forms.Padding(8, 0, 4, 0) }
    $b.Add_Click({ Set-ModeFromPicker "$($this.AccessibleName)" })
    $f.Controls.Add($b); $script:ModeButtons += $b
}
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
Update-ModePicker

# ---- v5.7: Check links - is each app running, answering the others, starting with Windows...
Add-Section $f 'Links between the apps' 'link'
(Add-Note $f 'Green = fine, amber = worth a look, red = something is broken. The tray app also checks once a day and pops up only when something is red (if Tray alerts on the Server tab is on).').Height = 36
Add-Tool $f 'Check links' 'Are the Hallow apps talking to each other?' { Start-LinkCheck } -Primary -Icon 'link' | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
$linkRows = New-Object System.Windows.Forms.FlowLayoutPanel
$linkRows.Text = 'Link results'   # not shown (lets snapshots scroll here)
$linkRows.FlowDirection = 'TopDown'; $linkRows.WrapContents = $false; $linkRows.AutoSize = $true; $linkRows.AutoSizeMode = 'GrowAndShrink'
$linkRows.MinimumSize = New-Object System.Drawing.Size(860, 0); $linkRows.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$f.Controls.Add($linkRows); $f.SetFlowBreak($linkRows, $true)
$FixTitles = @{ start = 'Start it'; autostart = 'Turn on Start with Windows'; open = 'Open settings'; crash = 'Show'; shieldsteps = 'Install steps'; shieldrelease = 'Newest release' }
# Rows: Title, Level (good / warn / bad), FixTitle, FixIcon, FixCode (PowerShell run when its button is clicked)
function Show-CheckRows($Panel, $Rows) {
    foreach ($oldRow in @($Panel.Controls)) { foreach ($b in @($oldRow.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })) { [void]$allButtons.Remove($b) }; $oldRow.Dispose() }
    $Panel.Controls.Clear()
    foreach ($l in @($Rows | Where-Object { $_.Level })) {
        $row = New-Object System.Windows.Forms.Panel
        $row.Size = New-Object System.Drawing.Size(860, 38); $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2); $row.BackColor = $C.Bg
        $col = switch ($l.Level) { 'good' { $C.Good } 'bad' { $C.Bad } default { $C.Warn } }
        if (Test-IconFont) {
            $pb = New-Object System.Windows.Forms.PictureBox
            $pb.Image = Get-Icon $(switch ($l.Level) { 'good' { 'circle-check' } 'bad' { 'circle-xmark' } default { 'triangle-exclamation' } }) $col 16
            $pb.Size = New-Object System.Drawing.Size(16, 16); $pb.Location = New-Object System.Drawing.Point(4, 11); $row.Controls.Add($pb)
        }
        $t = New-Object System.Windows.Forms.Label
        $t.UseMnemonic = $false; $t.AutoSize = $false; $t.Location = New-Object System.Drawing.Point(28, 0); $t.Size = New-Object System.Drawing.Size(550, 38)
        $t.TextAlign = 'MiddleLeft'; $t.Font = New-Font 9.5; $t.ForeColor = $(if ($l.Level -eq 'good') { $C.Text } else { $col })
        $t.Text = "$($l.Title)"; $row.Controls.Add($t)
        if ($l.FixCode -and $l.FixTitle) {
            $b = Add-Tool $row $l.FixTitle '' ([scriptblock]::Create($l.FixCode)) -Width 270 -Icon $(if ($l.FixIcon) { $l.FixIcon } else { 'gear' })
            $b.Size = New-Object System.Drawing.Size(270, 34); $b.Location = New-Object System.Drawing.Point(586, 2)
        }
        $Panel.Controls.Add($row)
    }
}
function Show-LinkResults($Lines) {
    $rows = foreach ($l in @($Lines | Where-Object { $_.Level })) {
        $fix = $(if ($l.Fix -and $FixTitles[$l.Fix]) { $l.Fix })
        [pscustomobject]@{ Title = "Hallow $($l.App) - $($l.Text)"; Level = $l.Level; FixTitle = $(if ($fix) { $FixTitles[$fix] })
            FixIcon = $(switch ($fix) { 'start' { 'play' } 'autostart' { 'power-off' } 'crash' { 'file-lines' } 'shieldsteps' { 'book' } 'shieldrelease' { 'arrow-up-right-from-square' } default { 'gear' } })
            FixCode = $(if ($fix) { "Log (Invoke-FamilyFix '$($l.App)' '$fix'); Start-LinkCheck" }) }
    }
    Show-CheckRows $linkRows @($rows)
}function Start-LinkCheck {
    Start-Background 'Check links' $FamilyLinkCheckWork @([string[]]@($FamilyApps | ForEach-Object Name), (Get-LinkCheckOptions)) {
        param($o)
        $lines = @($o | Where-Object { $_.Level })
        Show-LinkResults $lines
        if (-not $lines.Count) { Log 'Check links: no Hallow apps are installed yet.'; return }
        Log ('Check links: {0} green, {1} amber, {2} red.' -f @($lines | Where-Object Level -eq 'good').Count, @($lines | Where-Object Level -eq 'warn').Count, @($lines | Where-Object Level -eq 'bad').Count)
    }
}

function Update-FamilyCards {
    $fc = Get-FamilyCache
    $famNote.Text = 'Free and open source. Install and Update get the newest release from GitHub (checksum checked) and install it for you only - no admin. ' +
        $(if ($fc -and $fc.checked) { try { 'Updates checked {0:ddd h:mm tt}.' -f [datetime]::Parse("$($fc.checked)") } catch { '' } } else { 'Checking for updates...' })
    foreach ($s in @(Get-FamilyStatus)) {
        $k = $script:FamilyCards[$s.Name]; if (-not $k) { continue }
        if ($s.Kind -eq 'Extension') {   # v5.15: Hallow Shield - a browser extension, found in the browsers' extension lists
            $v = Format-FamilyVersion $s.Version; $l = Format-FamilyVersion $s.Latest
            $k.State.Text = $(if ($s.Installed) { "In $($s.Where)" } else { 'Not found' }); $k.State.ForeColor = $(if ($s.Installed) { $C.Good } else { $C.Muted })
            if (-not $s.Installed) { $k.Ver.Text = 'Not in Chrome, Edge, Brave or Opera' + $(if ($l) { " - newest is $l" } else { '' }) + ' (Firefox: temporary add-on)'; $k.Ver.ForeColor = $C.Muted }
            elseif ($s.Update) { $k.Ver.Text = "Version $v - $l is out: unzip it over the same folder, then reload"; $k.Ver.ForeColor = $C.Warn }
            else { $k.Ver.Text = "Version $v" + $(if ($l) { ' - up to date' } else { '' }); $k.Ver.ForeColor = $C.Text }
            Set-FamilyButton $k.Main 'Install steps' 'book' (-not $s.Update)
            Set-FamilyButton $k.Update $(if ($s.Installed) { 'Get update' } else { 'Download' }) 'download' $true
            $k.Update.Visible = (-not $s.Installed -or $s.Update); $k.Page.Left = $(if ($k.Update.Visible) { 280 } else { 148 })
            continue
        }
        $busy = $script:FamilyBusy[$s.Name]
        if ($busy) { $k.State.Text = $busy; $k.State.ForeColor = $C.Warn }
        elseif ($s.Running) { $k.State.Text = 'Running'; $k.State.ForeColor = $C.Good }
        elseif ($s.Installed) { $k.State.Text = 'Not running'; $k.State.ForeColor = $C.Muted }
        else { $k.State.Text = 'Not installed'; $k.State.ForeColor = $C.Muted }
        $v = Format-FamilyVersion $s.Version; $l = Format-FamilyVersion $s.Latest
        if (-not $s.Installed) { $k.Ver.Text = $(if ($l) { "Newest version: $l" } else { 'Not on this PC yet' }); $k.Ver.ForeColor = $C.Muted }
        elseif ($s.Update) { $k.Ver.Text = "Version $v - $l is out"; $k.Ver.ForeColor = $C.Warn }
        else { $k.Ver.Text = "Version $v" + $(if ($l) { ' - up to date' } else { '' }); $k.Ver.ForeColor = $C.Text }
        if ($s.Installed) { Set-FamilyButton $k.Main 'Open' 'play' (-not $s.Update) } else { Set-FamilyButton $k.Main 'Install' 'download' $true }
        Set-FamilyButton $k.Update 'Update' 'arrows-rotate' $true
        $k.Update.Visible = $s.Update; $k.Page.Left = $(if ($s.Update) { 280 } else { 148 })
    }
}
function Invoke-FamilyMain([string]$App) {
    if (Test-FamilyExtension $App) { Start-Process $ShieldStepsUrl; Log "Opened Hallow $App's install steps: unzip it into a folder of its own, then the browser's Extensions page > Developer mode > Load unpacked."; return }
    if (Open-FamilyApp $App) { Log "Opening Hallow $App."; return }
    Invoke-FamilyInstall $App
}
function Invoke-FamilyInstall([string]$App) {
    if (Test-FamilyExtension $App) { Start-Process $ShieldReleaseUrl; Log "Opened the newest Hallow $App release - download the zip for your browser (the toolkit never installs browser extensions itself)."; return }
    if ($script:FamilyBusy[$App]) { Log "Hallow $App is already downloading."; return }
    $running = [bool](Get-Process "Hallow$App" -ErrorAction SilentlyContinue)
    if ($running -and -not (Confirm-Action "Update Hallow $App?`n`nIt closes for a moment while the new version installs, then opens again.")) { return }
    $script:FamilyBusy[$App] = 'Downloading...'; Update-FamilyCards
    Log "Getting Hallow $App from GitHub..."
    Start-Background "Hallow $App download" $FamilyInstallWork @($App) ([scriptblock]::Create(@"
param(`$o)
`$script:FamilyBusy.Remove('$App')
if (-not `$o -or `$o[0].Error) { Log "Hallow ${App}: `$(if (`$o) { `$o[0].Error } else { 'download failed' })"; Update-FamilyCards; return }
Start-FamilyInstaller '$App' `$o[0].Installer
Log "Hallow $App `$(`$o[0].Version) downloaded and checksum checked - installing in a separate window; it opens when done."
`$script:FamilyBusy['$App'] = 'Installing...'; `$script:FamilyInstallStarted['$App'] = Get-Date
Update-FamilyCards
"@))
}
$script:FamilyInstallStarted = @{}

# update check in a quiet background runspace (no Activity lines): at most every few hours, failures silent
$script:FamilyCheck = $null
function Start-FamilyUpdateCheck {
    if ($script:FamilyCheck -or -not (Test-FamilyCheckDue)) { return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($FamilyCheckWork.ToString()).AddArgument([string[]]@($FamilyApps | ForEach-Object Name)).AddArgument($FamilyCacheFile)
    $script:FamilyCheck = @{ PS = $ps; Handle = $ps.BeginInvoke() }
}
$famTimer = New-Object System.Windows.Forms.Timer
$famTimer.Interval = 2000
$famTimer.Add_Tick({
    try {
        if ($script:FamilyCheck -and $script:FamilyCheck.Handle.IsCompleted) {
            try { [void]$script:FamilyCheck.PS.EndInvoke($script:FamilyCheck.Handle) } catch { }
            $script:FamilyCheck.PS.Dispose(); $script:FamilyCheck = $null
            if ($script:CurrentPage -eq 'Hallow') { Update-FamilyCards }
        }
        # an installer window is open: show "Installing..." until the app runs again (or 2 minutes pass)
        foreach ($a in @($script:FamilyInstallStarted.Keys)) {
            $age = ((Get-Date) - $script:FamilyInstallStarted[$a]).TotalSeconds
            if (($age -gt 6 -and (Get-Process "Hallow$a" -ErrorAction SilentlyContinue)) -or $age -gt 120) { $script:FamilyInstallStarted.Remove($a); $script:FamilyBusy.Remove($a) }
        }
        if ($script:CurrentPage -eq 'Hallow') { Update-FamilyCards }
    } catch { }
})
$famTimer.Start()
$form.Add_FormClosing({ $famTimer.Stop() })
$script:PageShowHooks['Hallow'] = { Update-FamilyCards; Start-FamilyUpdateCheck; if ($env:HALLOW_SNAP) { Show-LinkResults (& $FamilyLinkCheckWork ([string[]]@($FamilyApps | ForEach-Object Name)) (Get-LinkCheckOptions)) } elseif ($StartPage -eq 'Hallow') { Start-LinkCheck } }   # opened from the tray's link alert: check straight away
