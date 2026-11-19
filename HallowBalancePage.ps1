<#
  Hallow Toolkit - Gaming > Background restraint and IdleSaver (v5.13). Dot-sourced by HallowToolkit.ps1 after the pages
  are built (needs New-DarkCombo / New-RowLabel from HallowMorePage.ps1). The tray app does the work.
#>
$f = $script:PageFlows['Gaming']

# ================================================================ BACKGROUND RESTRAINT
Add-Section $f 'Background restraint (ProBalance style - off until you turn it on)' 'gauge-high'
(Add-Note $f 'When a background app keeps hogging the CPU, the tray app lowers it to Below normal priority and puts it back to Normal when it calms down or the game ends. It never touches games, audio and voice apps (Discord, Voicemeeter, Equalizer APO, Hallow Mixer...), Windows itself, Hallow apps, the app in front or anything running as admin.').Height = 52
$rs0 = Get-RestraintSettings
Add-Tool $f 'Background restraint' 'Needs the tray app running' {
    $r = Get-RestraintSettings
    Save-RestraintSettings (-not $r.On) $r.Always $r.Pct $r.Exclude
    Log $(if (-not $r.On) { "Background restraint - ON. The tray app lowers background apps that use more than $($r.Pct)% of the CPU $(if ($r.Always) { 'at any time' } else { 'while a game runs' })." } else { 'Background restraint - OFF. Anything it lowered goes back to Normal within 10 seconds.' })
    if ((Get-RestraintSettings).On -and -not (Test-TrayRunning)) { Start-TrayApp; Log 'Started the tray app (it does the work).' }
} -Primary -Width 260 -Icon 'gauge-high' -State { (Get-RestraintSettings).On } | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
(New-RowLabel $f 'When' 44).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$rsWhen = New-DarkCombo $f 190; [void]$rsWhen.Items.AddRange(@('While a game runs', 'Always')); $rsWhen.SelectedIndex = $(if ($rs0.Always) { 1 } else { 0 })
(New-RowLabel $f 'An app using more than' 160).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$rsPct = New-DarkCombo $f 80; foreach ($p in $RestraintThresholds) { [void]$rsPct.Items.Add("$p%") }; $rsPct.SelectedItem = "$($rs0.Pct)%"
(New-RowLabel $f 'of the whole CPU for 20 seconds' 240).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
(New-RowLabel $f 'Never touch' 80).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$rsExcl = New-Object System.Windows.Forms.TextBox
$rsExcl.Width = 560; $rsExcl.Font = New-Font 10; $rsExcl.BackColor = $C.Panel; $rsExcl.ForeColor = $C.Text; $rsExcl.BorderStyle = 'FixedSingle'
$rsExcl.Margin = New-Object System.Windows.Forms.Padding(0, 6, 10, 8); $rsExcl.Text = ($rs0.Exclude -join ', ')
$f.Controls.Add($rsExcl); $f.SetFlowBreak($rsExcl, $true)
$tips.SetToolTip($rsExcl, 'Your own exclusions: app names without .exe, separated by commas (* works, e.g. Adobe*). They add to the built-in list.')
Add-Tool $f 'Save restraint settings' 'When, how much and never-touch list' {
    $r = Get-RestraintSettings
    $ex = @("$($rsExcl.Text)" -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Save-RestraintSettings $r.On ($rsWhen.SelectedIndex -eq 1) ([int]("$($rsPct.SelectedItem)" -replace '\D', '')) $ex
    $r = Get-RestraintSettings; $rsExcl.Text = ($r.Exclude -join ', ')
    Log "Background restraint settings saved: $(if ($r.Always) { 'always' } else { 'while a game runs' }), over $($r.Pct)% of the CPU, $($r.Exclude.Count) app(s) of your own never touched$(if (-not $r.On) { ' (still OFF - switch it on above)' })."
} -Width 260 -Icon 'floppy-disk' | Out-Null
Add-Tool $f 'Built-in never-touch list' 'Shown in the log below' {
    Log "Never touched (built in): $($RestraintBuiltIn -join ', ')"
    Log 'Also never: processes in the Windows folder, services, game folders (Steam, Epic, Xbox, EA, Ubisoft, Riot), Equalizer APO / Voicemeeter folders, the app in front, anything running as admin, and apps whose priority you set yourself.'
} -Width 260 -Icon 'list' | Out-Null
Add-Tool $f 'Clear restraint log' 'Empties the list below' { Clear-RestraintLog; Update-RestraintLog; Log 'Restraint log cleared.' } -Width 260 -Icon 'eraser' | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
$rsList = New-DarkList $f @(@('When', 150), @('App', 200), @('What', 120), @('Why', 390)) 880 130 $false
$f.SetFlowBreak($rsList, $true)
function Update-RestraintLog {
    $rsList.Items.Clear()
    foreach ($e in @(Get-RestraintLog | Select-Object -First 50)) {
        $t = $null; [void][datetime]::TryParse("$($e.Time)", [ref]$t)
        $li = New-Object System.Windows.Forms.ListViewItem($(if ($t) { $t.ToString('ddd d MMM h:mm:ss tt') } else { "$($e.Time)" }))
        [void]$li.SubItems.Add("$($e.Name)"); [void]$li.SubItems.Add($(if ($e.Action -eq 'Restrained') { 'Lowered' } else { 'Back to Normal' })); [void]$li.SubItems.Add("$($e.Reason)")
        if ($e.Action -eq 'Restrained') { $li.ForeColor = $C.Warn }
        [void]$rsList.Items.Add($li)
    }
    if (-not $rsList.Items.Count) { $li = New-Object System.Windows.Forms.ListViewItem('Nothing restrained yet'); $li.ForeColor = $C.Muted; [void]$rsList.Items.Add($li) }
}
Update-RestraintLog

# ================================================================ IDLESAVER
Add-Section $f 'IdleSaver - power plan while you''re away (off until you turn it on)' 'moon'
$idleNote = Add-Note $f ''
$idleNote.Height = 36
$io0 = Get-IdleSaverSettings
Add-Tool $f 'IdleSaver' 'Needs the tray app running' {
    $o = Get-IdleSaverSettings
    $plan = @($script:IdlePlans | Where-Object Name -eq $idlePlan.SelectedItem)[0]
    if (-not $o.On -and -not $plan) { Log 'Pick the power plan to use while you''re away first.'; return }
    Save-IdleSaverSettings (-not $o.On) ([int]("$($idleMin.SelectedItem)" -replace '\D', '')) $(if ($plan) { $plan.Guid } else { $o.Plan })
    Log $(if (-not $o.On) { "IdleSaver - ON: after $(("$($idleMin.SelectedItem)")) without mouse or keyboard, the tray app switches to $($plan.Name) and back when you return. Never while a game runs or sound is playing." } else { 'IdleSaver - OFF.' })
    if ((Get-IdleSaverSettings).On -and -not (Test-TrayRunning)) { Start-TrayApp; Log 'Started the tray app (it does the work).' }
    Update-IdleNote
} -Primary -Width 260 -Icon 'moon' -State { (Get-IdleSaverSettings).On } | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
(New-RowLabel $f 'After' 44).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$idleMin = New-DarkCombo $f 130; foreach ($m in $IdleMinuteChoices) { [void]$idleMin.Items.Add("$m minutes") }; $idleMin.SelectedItem = "$($io0.Minutes) minutes"
(New-RowLabel $f 'away, switch to' 110).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$idlePlan = New-DarkCombo $f 230
$script:IdlePlans = @(Get-PowerPlans)
foreach ($p in $script:IdlePlans) { [void]$idlePlan.Items.Add($p.Name) }
$pp0 = @($script:IdlePlans | Where-Object Guid -eq $io0.Plan)[0]
if (-not $pp0) { $pp0 = @($script:IdlePlans | Where-Object { $_.Name -match 'saver|balanced' } | Sort-Object { $_.Name -notmatch 'saver' })[0] }   # suggest Power saver
if ($pp0) { $idlePlan.SelectedItem = $pp0.Name }
Add-Tool $f 'Save IdleSaver settings' 'Minutes and power plan' {
    $o = Get-IdleSaverSettings
    $plan = @($script:IdlePlans | Where-Object Name -eq $idlePlan.SelectedItem)[0]
    Save-IdleSaverSettings $o.On ([int]("$($idleMin.SelectedItem)" -replace '\D', '')) $(if ($plan) { $plan.Guid } else { '' })
    Log "IdleSaver settings saved$(if (-not $o.On) { ' (still OFF - switch it on above)' })."; Update-IdleNote
} -Width 260 -Icon 'floppy-disk' | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
function Update-IdleNote {
    $o = Get-IdleSaverSettings; $pp = @($script:IdlePlans | Where-Object Guid -eq $o.Plan)[0]
    $idleNote.Text = $(if ($o.Failed -and $o.Failed -eq $o.Plan) { "Windows would not switch to $(if ($pp) { $pp.Name } else { 'that plan' }) without admin, so IdleSaver doesn't use it. Pick another plan and click Save. " }
        elseif ($o.On) { "On: after $($o.Minutes) minutes away the tray app switches to $(if ($pp) { $pp.Name } else { 'a plan no longer on this PC' }) and back the moment you move the mouse or press a key. " }
        else { 'Off. ' }) + 'Never while a game or game session runs, or while sound has played in the last 5 minutes (music, videos, calls).'
}
Update-IdleNote
