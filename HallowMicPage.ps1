<#
  Hallow Toolkit - Mic page (window code). Dot-sourced by HallowToolkit.ps1. The fixes themselves live in HallowMic.ps1.
#>

if (-not $script:PageShowHooks) { $script:PageShowHooks = @{} }

# ================================================================ PAGE: MIC
$f = Add-Page 'Mic' ([char]0x25CE) 'Quiet in games but fine in Discord? Fix the Windows mic settings games use'
Add-Section $f 'Your microphones (click one to check it)'
$micList = New-DarkList $f @(@('Microphone', 360), @('Level', 64), @('Boost', 70), @('Games', 64), @('Calls', 60), @('Exclusive', 80), @('Muted', 60), @('Type', 82)) 860 150 $false
$f.SetFlowBreak($micList, $true)
$micList.MultiSelect = $false
$script:MicNote = Add-Note $f 'Reading microphones...'
$script:MicNote.Height = 64; $script:MicNote.ForeColor = $C.Text
$script:Mics = @(); $script:MicSelId = $null

# ---- live meter
$meterBox = New-Object System.Windows.Forms.Panel
$meterBox.Size = New-Object System.Drawing.Size(860, 26); $meterBox.BackColor = $C.Panel
$meterBox.Margin = New-Object System.Windows.Forms.Padding(2, 0, 0, 4)
$meterBar = New-Object System.Windows.Forms.Panel
$meterBar.Location = New-Object System.Drawing.Point(0, 0); $meterBar.Size = New-Object System.Drawing.Size(0, 26); $meterBar.BackColor = $C.Good
$meterBox.Controls.Add($meterBar)
foreach ($pct in 50, 85) {   # guide lines: aim to land between them when talking normally
    $g = New-Object System.Windows.Forms.Panel
    $g.Size = New-Object System.Drawing.Size(2, 26); $g.Location = New-Object System.Drawing.Point([int](860 * $pct / 100), 0); $g.BackColor = $C.PanelHi
    $meterBox.Controls.Add($g); $g.BringToFront()
}
$f.Controls.Add($meterBox); $f.SetFlowBreak($meterBox, $true)
$script:MeterNote = Add-Note $f 'Live meter: talk normally - the bar should reach the middle and peak between the two lines. This is what games hear from the selected mic.'
$script:Meter = $null; $script:MeterPeak = 0.0; $script:MeterHold = 0.0; $script:MeterHoldAt = [datetime]::MinValue; $script:MeterFailed = $null

function Stop-MicMeter { if ($script:Meter) { try { $script:Meter.Dispose() } catch { }; $script:Meter = $null }; $meterBar.Width = 0 }
function Update-MicMeter {
    if (-not $script:MicSelId) { return }
    if ($script:Meter -and $script:Meter.Id -ne $script:MicSelId) { Stop-MicMeter }
    if (-not $script:Meter) {
        if ($script:MeterFailed -eq $script:MicSelId) { return }
        try { $script:Meter = New-Object 'HallowMic+Meter' $script:MicSelId; $script:MeterHold = 0 }
        catch { $script:MeterFailed = $script:MicSelId; $script:MeterNote.Text = "Live meter unavailable for this mic: $($_.Exception.InnerException.Message)"; return }
    }
    $p = [double]$script:Meter.Peak()
    $script:MeterPeak = [math]::Max($p, $script:MeterPeak * 0.85)            # smooth the fall
    $shown = [math]::Sqrt($script:MeterPeak)                                  # sqrt so normal speech isn't a sliver
    $meterBar.Width = [int](860 * [math]::Min(1, $shown))
    $meterBar.BackColor = if ($shown -ge 0.97) { $C.Bad } elseif ($shown -ge 0.5) { $C.Good } else { $C.Warn }
    if ($shown -gt $script:MeterHold -or ((Get-Date) - $script:MeterHoldAt).TotalSeconds -gt 3) { $script:MeterHold = $shown; $script:MeterHoldAt = Get-Date }
    $verdict = if ($script:MeterHold -lt 0.05) { 'silent - talk to test' } elseif ($script:MeterHold -lt 0.5) { 'QUIET - games will hear you faintly' } elseif ($script:MeterHold -lt 0.97) { 'good' } else { 'clipping - too loud, lower Boost or gain' }
    $script:MeterNote.Text = "Live meter (what games hear from the selected mic): loudest {0:N0}% - {1}" -f ($script:MeterHold * 100), $verdict
}
$micTimer = New-Object System.Windows.Forms.Timer
$micTimer.Interval = 60
$micTimer.Add_Tick({
    if ($script:CurrentPage -eq 'Mic' -and $form.WindowState -ne 'Minimized') { try { Update-MicMeter } catch { Stop-MicMeter } }
    elseif ($script:Meter) { Stop-MicMeter }
})
$micTimer.Start()
$form.Add_FormClosing({ $micTimer.Stop(); $driftTimer.Stop(); Stop-MicMeter })

# ---- drift watch: while the page is open, catch an app (usually Discord's auto-adjust) lowering the mic level by itself
$script:MicLastLevels = @{}; $script:MicDriftWarned = @{}
function Test-MicDrift {
    $t = Get-SelectedMic; if (-not $t) { return }
    foreach ($m in (Get-MicFixSet $t $script:Mics)) {
        $now = $null; try { $now = [HallowMic]::GetLevel($m.Id) } catch { continue }
        $was = $script:MicLastLevels[$m.Id]; $script:MicLastLevels[$m.Id] = $now
        if ($null -eq $was -or $now -ge $was - 0.05 -or $script:MicDriftWarned[$m.Id]) { continue }
        $script:MicDriftWarned[$m.Id] = $true
        $who = if (Get-Process Discord -ErrorAction SilentlyContinue) { "Discord is running - its 'Automatically adjust input volume' does exactly this" } else { 'an app with automatic mic volume (Discord, Teams, Zoom, SteelSeries GG...) is doing this' }
        Log ("{0} just dropped from {1:N0}% to {2:N0}% by itself. {3}. Turn that setting off, or games will keep hearing you quietly." -f $m.Name, ($was * 100), ($now * 100), $who)
        $script:MicNote.Text = "Something is lowering $($m.Name) by itself ($([math]::Round($was * 100))% -> $([math]::Round($now * 100))%). $who.`nTurn it off (see the Discord tip below), then click Fix my mic again."
        $script:MicNote.ForeColor = $C.Bad
        Update-MicListLevels
    }
}
function Update-MicListLevels {
    foreach ($li in $micList.Items) { try { $li.SubItems[1].Text = '{0:N0}%' -f ([HallowMic]::GetLevel($li.Tag) * 100) } catch { } }
}
$driftTimer = New-Object System.Windows.Forms.Timer
$driftTimer.Interval = 2000
$driftTimer.Add_Tick({ if ($script:CurrentPage -eq 'Mic' -and $form.WindowState -ne 'Minimized') { try { Test-MicDrift } catch { } } })
$driftTimer.Start()

function Get-SelectedMic { $script:Mics | Where-Object Id -eq $script:MicSelId | Select-Object -First 1 }

function Update-MicPage {
    try { $script:Mics = @(Get-MicSetup) } catch { $script:MicNote.Text = "Could not read microphones: $($_.Exception.Message)"; return }
    if (-not ($script:Mics | Where-Object Id -eq $script:MicSelId)) { $script:MicSelId = ($script:Mics | Where-Object IsDefault | Select-Object -First 1).Id }
    $micList.BeginUpdate(); $micList.Items.Clear()
    foreach ($m in $script:Mics) {
        $li = New-Object System.Windows.Forms.ListViewItem($m.Name)
        $boost = if ($m.HasBoost) { '{0:+0;-0;0} dB' -f $m.BoostDb } else { '-' }
        $excl = switch ($m.Exclusive) { 1 { 'Allowed' } 0 { 'Off' } default { '?' } }
        foreach ($v in (Format-MicLevel $m), $boost, $(if ($m.IsDefault) { 'Yes' } else { '' }), $(if ($m.IsComms) { 'Yes' } else { '' }), $excl, $(if ($m.Muted) { 'MUTED' } else { '' }), $(if ($m.IsVirtual) { 'Virtual' } else { 'Real mic' })) { [void]$li.SubItems.Add("$v") }
        $li.Tag = $m.Id; $li.UseItemStyleForSubItems = $false
        if ($m.Level -ge 0 -and $m.Level -lt (Get-MicWant $m) - 0.05) { $li.SubItems[1].ForeColor = $C.Warn }
        if ($m.Muted) { $li.SubItems[6].ForeColor = $C.Bad }
        if ($m.Exclusive -eq 1) { $li.SubItems[5].ForeColor = $C.Warn }
        if ($m.IsDefault) { $li.ForeColor = $C.Accent }
        [void]$micList.Items.Add($li)
        if ($m.Id -eq $script:MicSelId) { $li.Selected = $true }
    }
    $micList.EndUpdate()
    Update-LevelRow
    Update-MicNote
}

function Update-MicNote {
    $m = Get-SelectedMic
    if (-not $m) { $script:MicNote.Text = 'No microphone found. Plug one in, then click Refresh.'; $script:MicNote.ForeColor = $C.Warn; return }
    $probs = @(Get-MicProblems $m $script:Mics)
    $head = $m.Name + $(if ($m.IsVirtual) { '  (virtual mic - the real mics behind it are checked too)' } else { '' })
    if ($probs.Count) {
        $script:MicNote.Text = "$head`nFound: " + ($probs -join '; ') + ".`nClick Fix my mic."
        $script:MicNote.ForeColor = $C.Warn
    } else {
        $script:MicNote.Text = "$head`nWindows settings look right. Still quiet? Check the meter, try Mic Boost, and turn off Discord's auto-adjust (tip below)."
        $script:MicNote.ForeColor = $C.Good
    }
}

$micList.Add_SelectedIndexChanged({
    if ($micList.SelectedItems.Count) { $script:MicSelId = $micList.SelectedItems[0].Tag; $script:MeterFailed = $null; Update-MicNote; Update-LevelRow }
})
$script:PageShowHooks['Mic'] = { Update-MicPage }

function Invoke-MicAction([scriptblock]$Do) {
    $m = Get-SelectedMic
    if (-not $m) { Log 'Pick a microphone in the list first.'; return }
    try { & $Do $m } catch { $e = $_.Exception; if ($e.InnerException) { $e = $e.InnerException }; Log "Mic: $($e.Message)" }
    $script:MicLastLevels = @{}; $script:MicDriftWarned = @{}   # watch for drift again after a fix
    Update-MicPage
}

# ---- your level: not everyone wants 100% (a close mic on a stand can pick up the whole room)
Add-Section $f 'Your mic level'
$lvlRow = New-Object System.Windows.Forms.FlowLayoutPanel
$lvlRow.Size = New-Object System.Drawing.Size(860, 34); $lvlRow.WrapContents = $false
$lvlRow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
$lvlLbl = New-Object System.Windows.Forms.Label
$lvlLbl.Text = 'Keep'; $lvlLbl.AutoSize = $true; $lvlLbl.Font = New-Font 10; $lvlLbl.Margin = New-Object System.Windows.Forms.Padding(2, 7, 6, 0)
$lvlMic = New-Object System.Windows.Forms.ComboBox
$lvlMic.DropDownStyle = 'DropDownList'; $lvlMic.Width = 330; $lvlMic.Font = New-Font 9.5; $lvlMic.FlatStyle = 'Flat'
$lvlMic.BackColor = $C.Panel; $lvlMic.ForeColor = $C.Text; $lvlMic.Margin = New-Object System.Windows.Forms.Padding(0, 4, 6, 0)
$lvlAt = New-Object System.Windows.Forms.Label
$lvlAt.Text = 'at'; $lvlAt.AutoSize = $true; $lvlAt.Font = New-Font 10; $lvlAt.Margin = New-Object System.Windows.Forms.Padding(0, 7, 6, 0)
$lvlBox = New-Object System.Windows.Forms.NumericUpDown
$lvlBox.Minimum = 5; $lvlBox.Maximum = 100; $lvlBox.Increment = 5; $lvlBox.Width = 64; $lvlBox.Font = New-Font 10; $lvlBox.Value = 100
$lvlBox.BackColor = $C.Panel; $lvlBox.ForeColor = $C.Text; $lvlBox.BorderStyle = 'FixedSingle'; $lvlBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 4, 0)
$lvlPct = New-Object System.Windows.Forms.Label
$lvlPct.Text = '%  - lower it if the mic picks up keyboard and room noise.'
$lvlPct.AutoSize = $true; $lvlPct.ForeColor = $C.Muted; $lvlPct.Font = New-Font 9; $lvlPct.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$lvlRow.Controls.AddRange(@($lvlLbl, $lvlMic, $lvlAt, $lvlBox, $lvlPct))
$f.Controls.Add($lvlRow); $f.SetFlowBreak($lvlRow, $true)
Add-Note $f 'Each real mic remembers its own level (100% unless you change it). Virtual mics like Sonar always stay at 100%.' | Out-Null

$script:LvlLoading = $false
function Get-LevelMic { $n = "$($lvlMic.SelectedItem)"; $script:Mics | Where-Object { $_.Name -eq $n -and -not $_.IsVirtual } | Select-Object -First 1 }
function Update-LevelRow {
    $script:LvlLoading = $true
    try {
        $keep = "$($lvlMic.SelectedItem)"
        $sel = Get-SelectedMic
        if ($sel -and -not $sel.IsVirtual) { $keep = $sel.Name }
        $lvlMic.Items.Clear()
        foreach ($m in ($script:Mics | Where-Object { -not $_.IsVirtual })) { [void]$lvlMic.Items.Add($m.Name) }
        if ($keep -and $lvlMic.Items.Contains($keep)) { $lvlMic.SelectedItem = $keep } elseif ($lvlMic.Items.Count) {
            # nothing picked yet: the real mic with a custom level, else the first one
            $custom = $script:Mics | Where-Object { -not $_.IsVirtual -and (Get-MicTarget $_) -lt 1 } | Select-Object -First 1
            if ($custom) { $lvlMic.SelectedItem = $custom.Name } else { $lvlMic.SelectedIndex = 0 }
        }
        $m = Get-LevelMic; if ($m) { $lvlBox.Value = [decimal][math]::Round((Get-MicTarget $m) * 100) }
    } finally { $script:LvlLoading = $false }
}
$lvlMic.Add_SelectedIndexChanged({
    if ($script:LvlLoading) { return }
    $m = Get-LevelMic; if ($m) { $script:LvlLoading = $true; $lvlBox.Value = [decimal][math]::Round((Get-MicTarget $m) * 100); $script:LvlLoading = $false }
})
$lvlBox.Add_ValueChanged({
    if ($script:LvlLoading) { return }
    $m = Get-LevelMic; if (-not $m) { return }
    Set-MicTarget $m ([int]$lvlBox.Value); Update-MicNote
})
$lvlBox.Add_Leave({ $m = Get-LevelMic; if ($m) { Log "$($m.Name) will be kept at $([int]$lvlBox.Value)%. Click Set my level (or Fix my mic) to apply it." } })
Add-Tool $f 'Use its current level' 'Like how it is now? Remember it' {
    $m = Get-LevelMic; if (-not $m) { Log 'Pick a real mic in the Keep box first.'; return }
    $pct = [int][math]::Max(5, [math]::Round([HallowMic]::GetLevel($m.Id) * 100))
    Set-MicTarget $m $pct; Update-MicPage
    Log "Remembered $pct% for $($m.Name). Fix my mic and the tray will keep it there."
} -Width 210 | Out-Null
Add-Tool $f 'Set my level' 'Apply the level above now' {
    $m = Get-LevelMic; if (-not $m) { Log 'Pick a real mic in the Keep box first.'; return }
    $want = Get-MicTarget $m
    [HallowMic]::SetLevel($m.Id, $want); if ($m.Muted) { [HallowMic]::SetMute($m.Id, $false) }
    Log "$($m.Name): level $(Format-MicLevel $m) -> $(Format-Pct $want)."
    $script:MicLastLevels = @{}; $script:MicDriftWarned = @{}; Update-MicPage
} -Width 210 | Out-Null

Add-Section $f 'Fix it'
Add-Tool $f 'Fix my mic' 'Your level, default for games + calls' {
    Invoke-MicAction { param($m)
        $n = Repair-Mic $m $script:Mics
        if ($n) { Log "Mic fixed ($n change(s)). Talk and watch the meter - it should now reach the middle. Restart the game if it was open." }
        else { Log 'Nothing to fix in Windows for this mic. If games still hear you quietly, try Boost +10 dB and check Discord''s auto-adjust (tip below).' }
    }
} -Primary | Out-Null
Add-Tool $f 'Fix + Mic Boost +10 dB' 'For quiet mics (can add a little hiss)' {
    Invoke-MicAction { param($m)
        $set = @(Get-MicFixSet $m $script:Mics)
        if (-not ($set | Where-Object HasBoost)) { Log 'No Mic Boost control on this mic (normal for USB mics like the QuadCast). Use its gain knob, or the level in its own app.' }
        $n = Repair-Mic $m $script:Mics -Boost
        Log "Done ($n change(s))."
    }
} | Out-Null
Add-Tool $f 'Refresh' 'Read the mic settings again' { Update-MicPage; Log 'Mic list refreshed.' } | Out-Null

Add-Section $f 'One setting at a time'
Add-Tool $f 'Make default' 'For games AND calls' {
    Invoke-MicAction { param($m) [HallowMic]::SetDefault($m.Id); Log "$($m.Name) is now the default mic for games and calls." }
} -Width 210 | Out-Null
Add-Tool $f 'Block exclusive control' 'Stops apps locking the mic for themselves' {
    Invoke-MicAction { param($m) [HallowMic]::SetExclusive($m.Id, $false); Log "$($m.Name): exclusive control is off." }
} -Width 210 | Out-Null
Add-Tool $f 'Mic Boost off' 'If you hear hiss or clipping' {
    Invoke-MicAction { param($m)
        if (-not $m.HasBoost) { Log 'This mic has no Mic Boost control.'; return }
        [void][HallowMic]::SetBoost($m.Id, 0); Log "$($m.Name): Mic Boost off."
    }
} -Width 210 | Out-Null
Add-Tool $f 'Stop call ducking' 'Windows won''t lower sounds on calls' {
    Set-CallDuckingOff; Log 'Windows will no longer turn sounds down during calls.'; Update-MicNote
} -Width 210 | Out-Null
Add-Tool $f 'Keep my mic level' 'Tray app puts it back if lowered (on/off)' {
    $s = Get-Settings; $on = -not [bool]$s.KeepMicLevel
    $s | Add-Member KeepMicLevel $on -Force; Save-Settings $s
    if ($on) {
        Log "Keep my mic level: ON. The tray app checks every 30 seconds and puts your mics back to your levels if Discord or anything else lowers it."
        if (-not (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object CommandLine -like '*HallowTray.ps1*')) { Start-TrayApp }
    } else { Log 'Keep my mic level: OFF.' }
} -Width 210 | Out-Null
Add-Tool $f 'Windows sound settings' 'Recording tab (old Control Panel)' { Start-Process control.exe 'mmsys.cpl,,1' } -Width 210 | Out-Null
Add-Tool $f 'Mic privacy settings' 'Let games use the mic' { Start-Process 'ms-settings:privacy-microphone' } -Width 210 | Out-Null

Add-Section $f 'Discord tip (the toolkit can''t change this one for you)'
$tip = Add-Note $f "Discord > User Settings > Voice & Video: turn OFF 'Automatically adjust input volume' (it can lower the Windows level while Discord runs), then set Input Volume back to about 100%. With that off and Windows at your level, you sound the same in Discord and in games."
$tip.Height = 40
