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
    $b1 = Add-Tool $card 'Open' '' ([scriptblock]::Create("Invoke-FamilyMain '$($app.Name)'")) -Primary -Width 122 -Icon 'play'
    $b2 = Add-Tool $card 'Update' '' ([scriptblock]::Create("Invoke-FamilyInstall '$($app.Name)'")) -Width 122 -Icon 'arrows-rotate'
    $b3 = Add-Tool $card 'GitHub' '' ([scriptblock]::Create("Start-Process 'https://github.com/$(Get-FamilyRepo $app.Name)'")) -Width 122 -Icon 'arrow-up-right-from-square'
    $x = 16
    foreach ($b in $b1, $b2, $b3) { $b.Size = New-Object System.Drawing.Size(122, 42); $b.Location = New-Object System.Drawing.Point($x, 94); $x += 132 }
    $tips.SetToolTip($b3, "Source, changes and roadmap of Hallow $($app.Name)")
    $script:FamilyCards[$app.Name] = @{ State = $state; Ver = $ver; Main = $b1; Update = $b2; Page = $b3 }
}
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)

function Update-FamilyCards {
    $fc = Get-FamilyCache
    $famNote.Text = 'Free and open source. Install and Update get the newest release from GitHub (checksum checked) and install it for you only - no admin. ' +
        $(if ($fc -and $fc.checked) { try { 'Updates checked {0:ddd h:mm tt}.' -f [datetime]::Parse("$($fc.checked)") } catch { '' } } else { 'Checking for updates...' })
    foreach ($s in @(Get-FamilyStatus)) {
        $k = $script:FamilyCards[$s.Name]; if (-not $k) { continue }
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
    if (Open-FamilyApp $App) { Log "Opening Hallow $App."; return }
    Invoke-FamilyInstall $App
}
function Invoke-FamilyInstall([string]$App) {
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
$script:PageShowHooks['Hallow'] = { Update-FamilyCards; Start-FamilyUpdateCheck }
