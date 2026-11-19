<#
  Hallow Toolkit - System page, Tweaks presets and browser clean-up (v5.12). Dot-sourced by HallowToolkit.ps1.
#>
if (-not $script:PageShowHooks) { $script:PageShowHooks = @{} }

# ================================================================ PAGE: SYSTEM (read-only, like HWiNFO's summary)
$PageIcons['System'] = 'circle-info'
$f = Add-Page 'System' ([char]0x2139) 'What is in this PC: CPU, graphics, memory, motherboard, BIOS, Windows and drive health'
Add-Section $f 'This PC' 'circle-info'
Add-Tool $f 'Refresh' 'Read it all again' { Start-SystemInfo } -Width 210 -Icon 'arrows-rotate' | Out-Null
Add-Tool $f 'Copy all' 'For Discord, forums, support' {
    $txt = ($sysList.Items | ForEach-Object { "$($_.Text): $($_.SubItems[1].Text) - $($_.SubItems[2].Text)" }) -join "`r`n"
    if ($txt) { [System.Windows.Forms.Clipboard]::SetText($txt); Log 'System info copied.' } else { Log 'Nothing loaded yet - click Refresh.' }
} -Width 210 -Icon 'copy' | Out-Null
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
$sysList = New-DarkList $f @(@('Part', 110), @('Item', 260), @('Details', 500)) 880 470 $false
$sysList.ShowItemToolTips = $true; $f.SetFlowBreak($sysList, $true)
function Show-SystemInfo($Rows) {
    $sysList.BeginUpdate(); $sysList.Items.Clear(); $last = ''
    foreach ($r in @($Rows | Where-Object { $_.PSObject.Properties.Name -contains 'Group' })) {
        $li = New-Object System.Windows.Forms.ListViewItem($(if ($r.Group -ne $last) { $r.Group } else { '' })); $last = $r.Group
        [void]$li.SubItems.Add($r.Item); [void]$li.SubItems.Add($r.Value); $li.ToolTipText = "$($r.Item)`n$($r.Value)"
        if ($r.Value -match 'health: (Warning|Unhealthy)|[1-9]\d* uncorrected errors') { $li.ForeColor = $C.Bad }
        [void]$sysList.Items.Add($li)
    }
    $sysList.EndUpdate()
}
function Start-SystemInfo {
    if ($env:HALLOW_SNAP) { Show-SystemInfo (Get-SystemInfoRows); return }
    Start-Background 'System info' $CoreWork @($HallowRoot, 'Get-SystemInfoRows') { param($o) Show-SystemInfo $o }
}
$script:PageShowHooks['System'] = { Start-SystemInfo }

# ================================================================ TWEAKS: PRESETS (WinUtil style) - right under Apply / Undo all
$f = $script:PageFlows['Tweaks']
$undo = @($f.Controls | Where-Object { "$($_.Text)" -like 'Undo all*' })[0]
$n0 = $f.Controls.Count
foreach ($k in $TweakPresets.Keys) {
    $desc = @{ Minimal = 'Small, safe quality-of-life set'; Gamer = 'Lower lag, no recording, fewer pop-ups'; Privacy = 'Less tracking and fewer ads' }[$k]
    Add-Tool $f "$k preset" $desc ([scriptblock]::Create("Set-TweakPreset '$k'")) -Width 210 -Icon 'list-check' | Out-Null
}
function Set-TweakPreset([string]$Name) {
    $ids = @($TweakPresets[$Name]); $flipped = @()
    foreach ($cb in $script:TweakBoxes) { if ($ids -contains $cb.Tag.Id -and -not $cb.Checked) { $cb.Checked = $true; $cb.Invalidate(); $flipped += $cb.Tag.Name } }
    if (-not $flipped) { Log "$Name preset: everything in it is already on."; return }
    Log ("{0} preset switched on {1} setting(s) - NOT applied yet (yellow): {2}. Look them over, then click Apply changes. Undo all puts every switch back to the Windows default." -f $Name, $flipped.Count, ($flipped -join '; '))
}
if ($undo) {
    $new = @($f.Controls | Select-Object -Skip $n0); $at = $f.Controls.GetChildIndex($undo)
    $f.SetFlowBreak($undo, $true)
    for ($i = 0; $i -lt $new.Count; $i++) { $f.Controls.SetChildIndex($new[$i], $at + 1 + $i) }
    $f.SetFlowBreak($new[-1], $true)
}

# ================================================================ TWEAKS: BROWSER CLEAN-UP (opt-in, browser closed)
Add-Section $f 'Browser clean-up (cache and history - cookies, passwords and bookmarks are never touched)' 'globe'
(Add-Note $f 'Tick the browsers to clean. A browser that is open is skipped - close it first (Edge often keeps running in the background). Firefox: cache only, its history shares a file with your bookmarks.').Height = 36
$script:BrowserBoxes = @()
foreach ($t in @(Get-BrowserTargets)) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $t.Name; $cb.Tag = $t.Name; $cb.AutoSize = $false; $cb.Width = 140; $cb.Height = 24; $cb.ForeColor = $C.Text
    $cb.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 2); $f.Controls.Add($cb); $script:BrowserBoxes += $cb
}
if (-not $script:BrowserBoxes) { Add-Note $f 'No supported browser found (Chrome, Edge, Brave, Vivaldi, Opera, Firefox).' | Out-Null }
else { $f.SetFlowBreak($script:BrowserBoxes[-1], $true) }
$brCache = New-Object System.Windows.Forms.CheckBox; $brCache.Text = 'Cache (pages load a bit slower the first time)'; $brCache.Checked = $true
$brHist = New-Object System.Windows.Forms.CheckBox; $brHist.Text = 'History (sites you visited, address bar suggestions)'; $brHist.Checked = $false
foreach ($cb in $brCache, $brHist) { $cb.AutoSize = $false; $cb.Width = 400; $cb.Height = 24; $cb.ForeColor = $C.Text; $cb.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 2); $f.Controls.Add($cb) }
$f.SetFlowBreak($brHist, $true)
$BrowserCleanWork = { param($Root, $Names, $Cache, $History, $Dry) $script:LogBox = $null; . (Join-Path $Root 'HallowCore.ps1'); Invoke-BrowserClean @(Get-BrowserTargets | Where-Object { $Names -contains $_.Name }) $Cache $History -DryRun:$Dry }
function Start-BrowserClean([bool]$Dry) {
    $names = @($script:BrowserBoxes | Where-Object Checked | ForEach-Object Tag)
    if (-not $names) { Log 'Tick at least one browser.'; return }
    if (-not $brCache.Checked -and -not $brHist.Checked) { Log 'Tick Cache, History or both.'; return }
    $what = @(); if ($brCache.Checked) { $what += 'cache' }; if ($brHist.Checked) { $what += 'history' }
    if (-not $Dry -and -not (Confirm-Action "Clear $($what -join ' and ') for $($names -join ', ')?`n`nCookies, passwords and bookmarks are not touched. Open browsers are skipped. History can't be brought back.")) { return }
    Start-Background $(if ($Dry) { 'Browser clean-up preview' } else { 'Browser clean-up' }) $BrowserCleanWork @($HallowRoot, $names, $brCache.Checked, $brHist.Checked, $Dry) {
        param($o)
        $rows = @($o | Where-Object { $_.PSObject.Properties.Name -contains 'Bytes' })
        foreach ($r in $rows) { Log ("  {0}: {1}{2}" -f $r.Name, $r.Note, $(if ($r.Bytes -gt 0) { " - $(Format-Size $r.Bytes)" })) }
        Log ("Browsers: {0} {1} in total." -f $(if (@($rows | Where-Object { $_.Note -like 'would*' }).Count) { 'would free' } else { 'freed' }), (Format-Size (($rows | Measure-Object Bytes -Sum).Sum)))
    }
}
Add-Tool $f 'Preview' 'How much it would free' { Start-BrowserClean $true } -Width 210 -Icon 'magnifying-glass' | Out-Null
Add-Tool $f 'Clean ticked browsers' 'Only browsers that are closed' { Start-BrowserClean $false } -Primary -Width 210 -Icon 'broom' | Out-Null
