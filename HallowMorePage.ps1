<#
  Hallow Toolkit - window sections for HallowMore.ps1: game launch check (Gaming), audio switcher (Mic),
  Windows Update control (Tune-up), Steam library mover (Games), lag under load (Network).
  Dot-sourced by HallowToolkit.ps1 after the pages exist.
#>

function New-DarkCombo($Flow, [int]$Width) {
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.DropDownStyle = 'DropDownList'; $cb.Width = $Width; $cb.Font = New-Font 10
    $cb.BackColor = $C.Panel; $cb.ForeColor = $C.Text; $cb.FlatStyle = 'Flat'
    $cb.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 8)
    $Flow.Controls.Add($cb); $cb
}
function New-RowLabel($Flow, [string]$Text, [int]$Width) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.AutoSize = $false; $l.Width = $Width; $l.Height = 30; $l.TextAlign = 'MiddleLeft'; $l.ForeColor = $C.Muted; $l.UseMnemonic = $false
    $l.Margin = New-Object System.Windows.Forms.Padding(2, 2, 6, 6)
    $Flow.Controls.Add($l); $l
}

# ================================================================ GAMING: game won't launch?
$f = $script:PageFlows['Gaming']
Add-Section $f 'Game won''t launch or crashes at start?' 'circle-question'
Add-Note $f 'Checks what usually stops games starting: missing runtimes, switched-off anti-cheat, Windows Security blocking saves, a pending restart, a full drive.' | Out-Null
$script:LaunchRows = @()
function Update-LaunchCheck {
    $launchList.Items.Clear()
    $script:LaunchRows = @(Get-GameLaunchCheck)
    foreach ($r in $script:LaunchRows | Sort-Object { @{ Problem = 0; Note = 1; OK = 2 }[$_.State] }) {
        $li = New-Object System.Windows.Forms.ListViewItem($r.Area)
        [void]$li.SubItems.Add($r.Item); [void]$li.SubItems.Add($(if ($r.State -eq 'OK') { 'OK' } elseif ($r.State -eq 'Note') { 'Note' } else { 'Problem' })); [void]$li.SubItems.Add($r.Detail)
        $li.ForeColor = $(if ($r.State -eq 'Problem') { $C.Bad } elseif ($r.State -eq 'Note') { $C.Warn } else { $C.Good })
        $li.ToolTipText = $r.Detail
        [void]$launchList.Items.Add($li)
    }
    $bad = @($script:LaunchRows | Where-Object State -eq 'Problem')
    Log ("Game launch check: {0}" -f $(if ($bad) { "$($bad.Count) problem(s) - $(($bad | ForEach-Object { $_.Item }) -join ', '). Click Fix problems." } else { 'nothing wrong found.' }))
}
Add-Tool $f 'Check now' 'Runtimes, anti-cheat, security, restart' { Update-LaunchCheck } -Primary -Width 210 | Out-Null
Add-Tool $f 'Fix problems' 'Install / turn back on what''s missing' {
    $fix = @($script:LaunchRows | Where-Object { $_.State -eq 'Problem' -and $_.Fix })
    if (-not $fix) { Log 'Nothing the toolkit can fix automatically. Click Check now first, or see the list for what to do.'; return }
    if (-not (Confirm-Action ("Fix these?`n`n" + (($fix | ForEach-Object { "  - $($_.Item)" }) -join "`n") + "`n`nRuntimes install silently from Microsoft. Anti-cheat services are set back to their normal start type."))) { return }
    $ids = @($fix | Where-Object { $_.Fix -like 'winget:*' } | ForEach-Object { $_.Fix.Substring(7) })
    foreach ($r in $fix | Where-Object { $_.Fix -like 'service:*' }) {
        if (-not (Need-Admin "Turning $($r.Item) back on")) { break }
        $name = $r.Fix.Substring(8)
        try { Set-Service -Name $name -StartupType $AntiCheatServices[$name][1] -ErrorAction Stop; Log "$($r.Item): set back to $($AntiCheatServices[$name][1])." } catch { Log "$($r.Item): could not change it - $($_.Exception.Message)" }
    }
    if ($fix | Where-Object Fix -eq 'open:cfa') {
        Start-Process 'windowsdefender://ransomwareprotection/'
        Log 'Opened Windows Security > Ransomware protection. Either click "Allow an app through Controlled folder access" and add your game, or turn Controlled folder access off.'
    }
    if ($ids) { Start-Background 'Installing game runtimes' $LaunchRuntimeInstallWork @(, $ids) { param($o) foreach ($l in $o) { Log "$l" }; Update-LaunchCheck } }
    else { Update-LaunchCheck }
} -Width 210 | Out-Null
$launchList = New-DarkList $f @(@('Area', 120), @('What', 270), @('Status', 80), @('Details', 400)) 880 170 $false
$launchList.ShowItemToolTips = $true; $f.SetFlowBreak($launchList, $true)

# ================================================================ MIC: audio switcher
$f = $script:PageFlows['Mic']
Add-Section $f 'Audio switcher - flip between speakers and headset' 'headphones'
Add-Note $f 'Pick two setups, then switch here, from the tray menu or with Ctrl+Alt+Home. Using SteelSeries Sonar? Switch inside Sonar.' | Out-Null
$script:AudioCombos = @()
foreach ($i in 0, 1) {
    New-RowLabel $f "Setup $($i + 1)" 70 | Out-Null
    New-RowLabel $f 'Sound to' 62 | Out-Null
    $o = New-DarkCombo $f 330
    New-RowLabel $f 'Mic' 34 | Out-Null
    $m = New-DarkCombo $f 300
    $f.SetFlowBreak($m, $true)
    $script:AudioCombos += , @($o, $m)
}
function Update-AudioCombos {
    $outs = @([HallowAudioOut]::List(0)); $mics = @([HallowAudioOut]::List(1)); $saved = @(Get-AudioSetups)
    for ($i = 0; $i -lt 2; $i++) {
        $o = $script:AudioCombos[$i][0]; $m = $script:AudioCombos[$i][1]
        $o.Items.Clear(); $m.Items.Clear(); [void]$m.Items.Add('(leave the mic as it is)')
        $o.Tag = $outs; $m.Tag = @($null) + $mics
        foreach ($d in $outs) { [void]$o.Items.Add($d.Name + $(if ($d.IsDefault) { '   (in use now)' } else { '' })) }
        foreach ($d in $mics) { [void]$m.Items.Add($d.Name + $(if ($d.IsDefault) { '   (in use now)' } else { '' })) }
        $s = $(if ($saved.Count -gt $i) { $saved[$i] })
        $oi = $(if ($s) { [array]::IndexOf(@($outs.Id), $s.Out) } else { -1 }); $o.SelectedIndex = $(if ($oi -ge 0) { $oi } elseif ($outs.Count -gt $i) { $i } else { -1 })
        $mi = $(if ($s -and $s.Mic) { [array]::IndexOf(@($mics.Id), $s.Mic) } else { -1 }); $m.SelectedIndex = $(if ($mi -ge 0) { $mi + 1 } else { 0 })
    }
}
Add-Tool $f 'Save setups' 'Remember both setups' {
    $setups = @()
    for ($i = 0; $i -lt 2; $i++) {
        $o = $script:AudioCombos[$i][0]; $m = $script:AudioCombos[$i][1]
        if ($o.SelectedIndex -lt 0) { Log "Pick where the sound goes for setup $($i + 1)."; return }
        $od = @($o.Tag)[$o.SelectedIndex]; $md = @($m.Tag)[$m.SelectedIndex]
        $setups += [pscustomobject]@{ Name = $od.Name; Out = $od.Id; OutName = $od.Name; Mic = $(if ($md) { $md.Id } else { '' }); MicName = $(if ($md) { $md.Name } else { '' }) }
    }
    if ($setups[0].Out -eq $setups[1].Out) { Log 'Both setups send sound to the same device - pick two different ones.'; return }
    $s = Get-Settings; $s | Add-Member AudioSetups $setups -Force; Save-Settings $s
    Log "Saved. Setup 1: $($setups[0].OutName). Setup 2: $($setups[1].OutName). Switch here, from the tray menu, or Ctrl+Alt+Home."
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Switch now' 'Flip to the other setup' { Log (Switch-AudioSetup); Update-AudioCombos } -Width 210 | Out-Null
Add-Tool $f 'Refresh devices' 'After plugging something in' { Update-AudioCombos } -Width 210 | Out-Null
[void]$script:AfterShown.Add({ try { Update-AudioCombos } catch { Log "Audio switcher: $($_.Exception.Message)" } })

# ================================================================ TUNE-UP: Windows Update control
$f = $script:PageFlows['Tune-up']
Add-Section $f 'Windows Update control' 'rotate'
Add-Tool $f 'Pause updates' '7 days - no surprise restarts' {
    if (Test-UpdatesPaused) { Set-UpdatesPausedFor 0 } else { Set-UpdatesPausedFor 7 }
} -Width 278 -State { Test-UpdatesPaused } | Out-Null
Add-Tool $f 'Block driver updates' 'Keep the drivers you picked' {
    Set-WuDriversBlocked (-not (Test-WuDriversBlocked))
} -Width 278 -State { Test-WuDriversBlocked } | Out-Null
Add-Tool $f 'Update history' 'What installed, what failed and why' {
    Start-Background 'Windows Update history' $WuHistoryWork @() {
        param($o)
        $wuList.Items.Clear()
        $rows = @($o | Where-Object { $_.Title })
        foreach ($r in $rows) {
            $li = New-Object System.Windows.Forms.ListViewItem(('{0:yyyy-MM-dd HH:mm}' -f $r.Date))
            [void]$li.SubItems.Add($r.Title); [void]$li.SubItems.Add($r.Result)
            $why = $(if ($r.Result -match 'Failed|errors') { $(if ($WuErrors[$r.Code]) { "$($r.Code): $($WuErrors[$r.Code])" } else { "$($r.Code) - search this code, or Tools > Quick fixes > Windows Update reset" }) } else { '' })
            [void]$li.SubItems.Add($why); $li.ToolTipText = "$($r.Title)`n$why"
            $li.ForeColor = $(if ($r.Result -eq 'Failed') { $C.Bad } elseif ($r.Result -match 'errors|Cancelled') { $C.Warn } else { $C.Text })
            [void]$wuList.Items.Add($li)
        }
        $failed = @($rows | Where-Object Result -eq 'Failed')
        Log ("Windows Update history: {0} updates, {1} failed." -f $rows.Count, $failed.Count)
    }
} -Width 278 | Out-Null
$wuList = New-DarkList $f @(@('When', 125), @('Update', 430), @('Result', 110), @('Why it failed', 215)) 880 170 $false
$wuList.ShowItemToolTips = $true; $f.SetFlowBreak($wuList, $true)

# ================================================================ GAMES: move Steam games between drives
$f = $script:PageFlows['Games']
Add-Section $f 'Move Steam games to another drive' 'truck-moving'
Add-Note $f 'Pick games (Ctrl+click for several) and where to move them. Steam is closed while they move. New drive? Add it in Steam > Settings > Storage.' | Out-Null
function Update-SteamMoveList {
    $steamMoveList.Items.Clear()
    $games = @(Get-SteamLibraryGames | Sort-Object Bytes -Descending)
    foreach ($g in $games) {
        $li = New-Object System.Windows.Forms.ListViewItem($g.Name)
        [void]$li.SubItems.Add($g.Library); [void]$li.SubItems.Add((Format-Size $g.Bytes)); $li.Tag = $g
        [void]$steamMoveList.Items.Add($li)
    }
    $steamTarget.Items.Clear()
    foreach ($l in @(Get-SteamLibraries)) {
        $root = [IO.Path]::GetPathRoot($l); $free = try { (New-Object IO.DriveInfo $root).AvailableFreeSpace } catch { 0 }
        [void]$steamTarget.Items.Add(('{0}   ({1} free)' -f $l, (Format-Size $free)))
    }
    if ($steamTarget.Items.Count) { $steamTarget.SelectedIndex = $steamTarget.Items.Count - 1 }
    Log "Steam: $($games.Count) games in $($steamTarget.Items.Count) libraries."
}
Add-Tool $f 'Find Steam games' 'List games and libraries' { Update-SteamMoveList } -Primary -Width 210 | Out-Null
(New-RowLabel $f 'Move to' 60).Margin = New-Object System.Windows.Forms.Padding(2, 18, 6, 6)
$steamTarget = New-DarkCombo $f 360
$steamTarget.Margin = New-Object System.Windows.Forms.Padding(0, 20, 10, 8)
Add-Tool $f 'Move selected' 'Steam closes while it moves' {
    $sel = @($steamMoveList.SelectedItems | ForEach-Object { $_.Tag })
    if (-not $sel) { Log 'Click the game(s) to move first.'; return }
    if ($steamTarget.SelectedIndex -lt 0) { Log 'Pick the library to move to.'; return }
    $target = @(Get-SteamLibraries)[$steamTarget.SelectedIndex]
    $sel = @($sel | Where-Object { $_.Library -ne $target })
    if (-not $sel) { Log 'Those games are already in that library.'; return }
    $need = ($sel | Measure-Object Bytes -Sum).Sum
    $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($target))).AvailableFreeSpace
    if ($need * 1.05 -gt $free) { Log ("Not enough space: they need {0}, {1} has {2} free." -f (Format-Size $need), $target, (Format-Size $free)); return }
    if (-not (Confirm-Action ("Move to $target ?`n`n" + (($sel | ForEach-Object { "  - $($_.Name) ($(Format-Size $_.Bytes))" }) -join "`n") + "`n`nSteam will be closed. Big games take a few minutes - don't open Steam until the log says it's done."))) { return }
    if (Get-Process steam -ErrorAction SilentlyContinue) {
        Start-Process 'steam://exit'
        for ($i = 0; $i -lt 30 -and (Get-Process steam -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
        if (Get-Process steam -ErrorAction SilentlyContinue) { Log 'Steam did not close - close it from its tray icon and try again.'; return }
    }
    Start-Background 'Moving Steam games' $SteamMoveWork @($sel, $target) { param($o) foreach ($l in $o) { Log "$l" }; Update-SteamMoveList }
} -Width 210 | Out-Null
$f.SetFlowBreak($script:PageFlows['Games'].Controls[$script:PageFlows['Games'].Controls.Count - 1], $true)
$steamMoveList = New-DarkList $f @(@('Game', 380), @('Library', 340), @('Size', 120)) 880 190 $false
$steamMoveList.MultiSelect = $true; $f.SetFlowBreak($steamMoveList, $true)

# ================================================================ NETWORK: lag under load
$f = $script:PageFlows['Network']
Add-Section $f 'Lag spikes when someone streams or downloads?' 'wave-square'
Add-Tool $f 'Lag under load test' 'Ping while the line is busy (~30 s)' { Start-Background 'Lag under load test' $BufferbloatWork @() } -Primary | Out-Null
Add-Note $f 'Measures how much your ping rises while downloading and uploading (bufferbloat). Grade A or better = no lag spikes from other traffic.' | Out-Null

# ================================================================ HEALTH: security check (v4.3)
# Slow checks run in a background runspace that loads the toolkit's own functions.
$CoreWork = { param([string]$Root, [string]$Fn) $script:LogBox = $null; . (Join-Path $Root 'HallowCore.ps1'); & $Fn }
$f = $script:PageFlows['Health']
Add-Section $f 'Security check' 'shield-halved'
Add-Note $f 'Read-only: antivirus, firewall, UAC, old file sharing, Remote Desktop, odd startup programs, what''s open to your network, risky browser extensions.' | Out-Null
$script:SecRows = @()
function Show-SecurityRows($Rows) {
    $secList.Items.Clear(); $script:SecRows = @($Rows | Where-Object { $_.PSObject.Properties.Name -contains 'State' })
    foreach ($r in $script:SecRows | Sort-Object { @{ Problem = 0; Note = 1; OK = 2 }[$_.State] }, Area, Check) {
        $li = New-Object System.Windows.Forms.ListViewItem($r.Area)
        [void]$li.SubItems.Add($r.Check); [void]$li.SubItems.Add($r.State); [void]$li.SubItems.Add($r.Detail)
        $li.ForeColor = $(if ($r.State -eq 'Problem') { $C.Bad } elseif ($r.State -eq 'Note') { $C.Warn } else { $C.Good })
        $li.ToolTipText = $r.Detail; $li.Tag = $r
        [void]$secList.Items.Add($li)
    }
    $bad = @($script:SecRows | Where-Object State -eq 'Problem'); $notes = @($script:SecRows | Where-Object State -eq 'Note')
    Log ("Security check: {0}, {1} thing(s) worth a look. Double-click a row to open its setting." -f $(if ($bad) { "$($bad.Count) problem(s)" } else { 'no problems' }), $notes.Count)
}
Add-Tool $f 'Check security' 'Read-only, about 5 seconds' { Start-Background 'Security check' $CoreWork @($HallowRoot, 'Get-SecurityCheck') { param($o) Show-SecurityRows $o } } -Primary -Width 210 | Out-Null
Add-Tool $f 'Quick virus scan' 'Microsoft Defender, in the background' {
    Start-Background 'Defender quick scan' { try { Start-MpScan -ScanType QuickScan -ErrorAction Stop; 'Quick scan finished - Windows Security shows anything it found.' } catch { "Quick scan could not start: $($_.Exception.Message)" } } @()
} -Width 210 | Out-Null
Add-Tool $f 'Update virus definitions' 'Get the newest Defender definitions' {
    Start-Background 'Defender definitions update' { try { Update-MpSignature -ErrorAction Stop; 'Virus definitions are up to date.' } catch { "Could not update: $($_.Exception.Message)" } } @()
} -Width 210 | Out-Null
$secList = New-DarkList $f @(@('Area', 110), @('Check', 300), @('Status', 70), @('Details', 400)) 880 190 $false
$secList.ShowItemToolTips = $true; $f.SetFlowBreak($secList, $true)
$secList.Add_DoubleClick({
    $r = $secList.SelectedItems[0].Tag; if (-not $r) { return }
    switch ($r.Fix) {
        '' { Log "$($r.Check): $($r.Detail)" }
        'sigs' { Start-Background 'Defender definitions update' { try { Update-MpSignature -ErrorAction Stop; 'Virus definitions are up to date.' } catch { "Could not update: $($_.Exception.Message)" } } @() }
        'scan' { Start-Process 'windowsdefender://threat/'; Log 'Opened Windows Security - click Quick scan, or use the Quick virus scan button.' }
        'startup' { Start-Process 'ms-settings:startupapps'; Log "Opened Startup apps - turn off $($r.Check) there if you don't need it." }
        default { Start-Process $r.Fix; Log "Opened the setting for: $($r.Check)" }
    }
})

# ================================================================ TOOLS: before / after snapshot (v4.3)
$f = $script:PageFlows['Tools']
Add-Section $f 'Before / after snapshot' 'camera'
Add-Note $f 'Snapshot before installing something sketchy, then Compare to see the apps, startup items, services and extensions it added.' | Out-Null
function Update-SnapshotCombo {
    $snapPick.Items.Clear()
    foreach ($s in Get-SnapshotFiles) { [void]$snapPick.Items.Add(($s.BaseName -replace '^snapshot-', '' -replace '_(\d\d)(\d\d)(\d\d)$', ' $1:$2:$3')) }
    if ($snapPick.Items.Count) { $snapPick.SelectedIndex = 0 } else { [void]$snapPick.Items.Add('(no snapshots yet)'); $snapPick.SelectedIndex = 0 }
}
Add-Tool $f 'Take snapshot' 'Save what''s installed now' {
    Start-Background 'Snapshot' $CoreWork @($HallowRoot, 'Save-SystemSnapshot') { param($o) foreach ($l in $o | Where-Object { $_ -is [string] -and $_ -notlike '*.json' }) { Log $l }; Update-SnapshotCombo; Log 'Snapshot saved. Install or update things, then click Compare with now.' }
} -Primary -Width 210 | Out-Null
(New-RowLabel $f 'Compare' 64).Margin = New-Object System.Windows.Forms.Padding(2, 18, 6, 6)
$snapPick = New-DarkCombo $f 220
$snapPick.Margin = New-Object System.Windows.Forms.Padding(0, 20, 10, 8)
Add-Tool $f 'Compare with now' 'What changed since then' {
    $files = @(Get-SnapshotFiles)
    if (-not $files -or $snapPick.SelectedIndex -ge $files.Count) { Log 'Take a snapshot first.'; return }
    $old = Get-Content -LiteralPath $files[$snapPick.SelectedIndex].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:SnapOld = $old
    Start-Background 'Snapshot compare' $CoreWork @($HallowRoot, 'Get-SystemSnapshot') {
        param($o)
        $now = $o | Where-Object { $_ -is [System.Collections.IDictionary] } | Select-Object -First 1
        $rows = @(Compare-SystemSnapshot $script:SnapOld $now)
        $snapList.Items.Clear()
        foreach ($r in $rows | Sort-Object Change, Kind, Item) {
            $li = New-Object System.Windows.Forms.ListViewItem($r.Change)
            [void]$li.SubItems.Add($r.Kind); [void]$li.SubItems.Add($r.Item); [void]$li.SubItems.Add($r.Detail); $li.ToolTipText = "$($r.Item)`n$($r.Detail)"
            $li.ForeColor = $(if ($r.Change -eq 'Added') { $C.Warn } elseif ($r.Change -eq 'Removed') { $C.Muted } else { $C.Text })
            [void]$snapList.Items.Add($li)
        }
        $added = @($rows | Where-Object Change -eq 'Added').Count
        Log ("Compared with {0}: {1} added, {2} removed, {3} changed." -f $snapPick.SelectedItem, $added, @($rows | Where-Object Change -eq 'Removed').Count, @($rows | Where-Object Change -eq 'Changed').Count)
    }
} -Width 210 | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
$snapList = New-DarkList $f @(@('Change', 80), @('Kind', 120), @('Item', 400), @('Details', 280)) 880 180 $false
$snapList.ShowItemToolTips = $true; $f.SetFlowBreak($snapList, $true)
[void]$script:AfterShown.Add({ Update-SnapshotCombo })
