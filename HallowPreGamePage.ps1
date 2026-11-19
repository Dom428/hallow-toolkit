<#
  Hallow Toolkit - Gaming > Pre-game check and Tune-up > Scheduled clean-up (v5.9). Dot-sourced by HallowToolkit.ps1
  after the pages are built (needs Show-CheckRows from HallowFamilyPage.ps1 and New-DarkCombo).
#>

# ================================================================ GAMING: PRE-GAME CHECK (at the top of the page)
$f = $script:PageFlows['Gaming']
$n0 = $f.Controls.Count
Add-Section $f 'Pre-game check' 'clipboard-check'
(Add-Note $f 'A quick read-only look before you play: restarts waiting, app updates, RAM, game drive space, GPU / CPU, background hogs, NVIDIA driver age and your Hallow apps. Nothing changes until you click a fix.').Height = 36
Add-Tool $f 'Pre-game check' 'Is the PC ready to play?' { Start-PreGameCheck } -Primary -Icon 'clipboard-check' | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
$preRows = New-Object System.Windows.Forms.FlowLayoutPanel
$preRows.Text = 'Pre-game results'; $preRows.FlowDirection = 'TopDown'; $preRows.WrapContents = $false; $preRows.AutoSize = $true; $preRows.AutoSizeMode = 'GrowAndShrink'
$preRows.MinimumSize = New-Object System.Drawing.Size(860, 0); $preRows.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
$f.Controls.Add($preRows); $f.SetFlowBreak($preRows, $true)
$new = @($f.Controls | Select-Object -Skip $n0)
for ($i = 0; $i -lt $new.Count; $i++) { $f.Controls.SetChildIndex($new[$i], $i) }   # move the section to the top
if ($n0 -gt 0) { $f.SetFlowBreak($new[-1], $true) }

$PreGameFixes = @{
    winupdate  = @('Open Windows Update', 'arrows-rotate', "Start-Process 'ms-settings:windowsupdate'; Log 'Opened Windows Update - restart from there when it suits you.'")
    updateapps = @('Update apps', 'download', 'Invoke-UpdateApps')
    storage    = @('Find what to remove', 'hard-drive', "Show-Page 'Storage'")
    closehogs  = @('Close them', 'circle-xmark', 'Close-PreGameHogs')
    nvidia     = @('NVIDIA drivers page', 'arrow-up-right-from-square', "Start-Process 'https://www.nvidia.com/en-us/drivers/'")
    taskmgr    = @("What's using it", 'list-check', 'Start-Process taskmgr.exe')
    start      = @('Start it', 'play', 'Log (Invoke-FamilyFix ''{0}'' ''start'')')
}
function Close-PreGameHogs {
    $names = @("$($script:PreGameHogs)" -split ',' | Where-Object { $_ })
    if (-not $names) { return }
    if (-not (Confirm-Action "Close $($names -join ', ')?`n`nUnsaved work in them may be lost.")) { return }
    [void](Close-Apps $names); Log "Closed $($names -join ', ')."
}
function Show-PreGameResults($Lines) {
    $rows = foreach ($l in @($Lines | Where-Object { $_.Level })) {
        if ($l.Key -eq 'hogs') { $script:PreGameHogs = $l.Arg }
        $fx = $PreGameFixes["$($l.Fix)"]
        [pscustomobject]@{ Title = $l.Text; Level = $l.Level; FixTitle = $(if ($fx) { $fx[0] }); FixIcon = $(if ($fx) { $fx[1] }); FixCode = $(if ($fx) { ($fx[2] -f $l.Arg) + '; Start-PreGameCheck -Quick' }) }
    }
    Show-CheckRows $preRows @($rows)
}
# -Quick (after a fix): skips the slow winget list
function Start-PreGameCheck([switch]$Quick) {
    Start-Background 'Pre-game check' $PreGameWork @(, (Get-PreGameOptions -NoWinget:$Quick)) {
        param($o)
        $lines = @($o | Where-Object { $_.Level })
        Show-PreGameResults $lines
        $warn = @($lines | Where-Object Level -ne 'good').Count
        Log $(if ($warn) { "Pre-game check: $warn thing(s) worth a look - see the Gaming tab." } else { 'Pre-game check: all good - have fun.' })
    }
}
if ($Run -eq 'PreGame') {   # from the tray menu (snapshots: run it at once, without the slow winget list)
    if ($env:HALLOW_SNAP) { Show-PreGameResults (& $PreGameWork (Get-PreGameOptions -NoWinget)) } else { [void]$script:AfterShown.Add({ Start-PreGameCheck }) }
}

# ================================================================ TUNE-UP: SCHEDULED CLEAN-UP (off by default)
$f = $script:PageFlows['Tune-up']
Add-Section $f 'Scheduled clean-up (off until you turn it on)' 'clock'
$cleanNote = Add-Note $f ''
$cleanNote.Height = 36
$script:CleanBoxes = @{}
$sc0 = Get-CleanSchedule
foreach ($k in $CleanItems.Keys) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $CleanItems[$k]; $cb.Checked = (@($sc0.Items) -contains $k); $cb.AutoSize = $false; $cb.Width = 280; $cb.Height = 24
    $cb.ForeColor = $C.Text; $cb.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 2)
    $f.Controls.Add($cb); $script:CleanBoxes[$k] = $cb
}
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
(New-RowLabel $f 'Every' 50).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$cleanFreq = New-DarkCombo $f 120; [void]$cleanFreq.Items.AddRange(@('Weekly', 'Monthly'))
(New-RowLabel $f 'on' 26).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$cleanDay = New-DarkCombo $f 150
(New-RowLabel $f 'at' 24).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$cleanTime = New-DarkCombo $f 110
foreach ($h in 0..23) { foreach ($m in 0, 30) { [void]$cleanTime.Items.Add(('{0:00}:{1:00}' -f $h, $m)) } }
function Set-CleanDayItems {
    $cleanDay.Items.Clear()
    if ($cleanFreq.SelectedItem -eq 'Monthly') { foreach ($d in 1..28) { [void]$cleanDay.Items.Add("day $d") } }
    else { foreach ($d in 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') { [void]$cleanDay.Items.Add($d) } }
}
$cleanFreq.SelectedItem = $(if ($sc0.Freq -eq 'Monthly') { 'Monthly' } else { 'Weekly' }); Set-CleanDayItems
$cleanDay.SelectedItem = $(if ($sc0.Freq -eq 'Monthly') { "day $($sc0.DayOfMonth)" } else { "$($sc0.Day)" }); if ($cleanDay.SelectedIndex -lt 0) { $cleanDay.SelectedIndex = 0 }
$cleanTime.SelectedItem = "$($sc0.Time)"; if ($cleanTime.SelectedIndex -lt 0) { $cleanTime.SelectedItem = '04:00' }
$cleanFreq.Add_SelectedIndexChanged({ Set-CleanDayItems; $cleanDay.SelectedIndex = 0 })
$f.SetFlowBreak($cleanTime, $true)
function Read-CleanSchedule {
    $s = Get-CleanSchedule
    $s.Items = @($script:CleanBoxes.Keys | Where-Object { $script:CleanBoxes[$_].Checked })
    $s.Freq = "$($cleanFreq.SelectedItem)"; $s.Time = "$($cleanTime.SelectedItem)"
    if ($s.Freq -eq 'Monthly') { $s.DayOfMonth = [int]("$($cleanDay.SelectedItem)" -replace '\D', '') } else { $s.Day = "$($cleanDay.SelectedItem)" }
    $s
}
function Update-CleanNote {
    $s = Get-CleanSchedule; $on = $s.On -and (Get-ScheduledTask -TaskName $CleanTaskName -ErrorAction SilentlyContinue)
    $when = $(if ($s.Freq -eq 'Monthly') { "on day $($s.DayOfMonth) of each month" } else { "every $($s.Day)" })
    $last = @(Get-CleanReports | Where-Object { -not $_.DryRun })[0]
    $cleanNote.Text = $(if ($on) { "On: $when at $($s.Time) (or the next time the PC is on), cleaning $(@($s.Items).Count) item(s). " } else { 'Off. Tick what to clean, pick when, then switch it on. ' }) +
        $(if ($last) { "Last run $([datetime]::Parse($last.Time).ToString('ddd d MMM')): $(Format-CleanReport $last)." } else { '' })
}
Add-Tool $f 'Scheduled clean-up' 'Weekly or monthly' {
    $s = Read-CleanSchedule
    if ((Get-CleanSchedule).On -and (Get-ScheduledTask -TaskName $CleanTaskName -ErrorAction SilentlyContinue)) {
        Unregister-CleanTask; $s.On = $false; Save-CleanSchedule $s; Log 'Scheduled clean-up - OFF.'
    } else {
        if (-not @($s.Items).Count) { Log 'Tick at least one thing to clean first.'; return }
        $s.On = $true; Save-CleanSchedule $s; Register-CleanTask $s
        Log "Scheduled clean-up - ON: $(if ($s.Freq -eq 'Monthly') { "day $($s.DayOfMonth) of each month" } else { "every $($s.Day)" }) at $($s.Time). The tray shows what it freed."
        if (-not $IsAdmin -and (@($s.Items) | Where-Object { $_ -in 'WinTemp', 'DeliveryOpt', 'Trim' })) { Log 'Note: the toolkit is not running as admin, so Windows temp, the update cache and TRIM will be skipped.' }
    }
    Update-CleanNote
} -Primary -Width 210 -Icon 'clock' -State { (Get-CleanSchedule).On -and [bool](Get-ScheduledTask -TaskName $CleanTaskName -ErrorAction SilentlyContinue) } | Out-Null
Add-Tool $f 'Save changes' 'Items and time above' {
    $s = Read-CleanSchedule; Save-CleanSchedule $s
    if ($s.On) { Register-CleanTask $s; Log 'Scheduled clean-up updated.' } else { Log 'Saved - switch Scheduled clean-up on to use it.' }
    Update-CleanNote
} -Width 210 -Icon 'floppy-disk' | Out-Null
Add-Tool $f 'Preview' 'What it would free now' {
    $items = @((Read-CleanSchedule).Items)
    if (-not $items.Count) { Log 'Tick at least one thing to clean first.'; return }
    Start-Background 'Clean-up preview' { param($Root, $Items) $script:LogBox = $null; . (Join-Path $Root 'HallowCore.ps1'); Invoke-CleanItems $Items -DryRun -NoSave } @($HallowRoot, $items) {
        param($o) $r = @($o | Where-Object { $_.PSObject.Properties.Name -contains 'TotalBytes' })[0]
        if ($r) { Log "Preview (nothing deleted): $(Format-CleanReport $r)" }
    }
} -Width 210 -Icon 'magnifying-glass' | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
$cleanList = New-DarkList $f @(@('When', 150), @('Freed', 100), @('What', 600)) 880 130 $false
$f.SetFlowBreak($cleanList, $true)
function Update-CleanReports {
    $cleanList.Items.Clear()
    foreach ($r in @(Get-CleanReports | Select-Object -First 20)) {
        $li = New-Object System.Windows.Forms.ListViewItem(([datetime]::Parse($r.Time)).ToString('ddd d MMM h:mm tt'))
        [void]$li.SubItems.Add($(if ($r.DryRun) { 'preview' } else { Format-Size $r.TotalBytes }))
        [void]$li.SubItems.Add((@($r.Items | ForEach-Object { "$($_.Item): $(if ($_.Bytes -gt 0) { Format-Size $_.Bytes } else { $_.Note })" }) -join '; '))
        [void]$cleanList.Items.Add($li)
    }
    if (-not $cleanList.Items.Count) { $li = New-Object System.Windows.Forms.ListViewItem('No reports yet'); $li.ForeColor = $C.Muted; [void]$cleanList.Items.Add($li) }
}
Update-CleanNote; Update-CleanReports
