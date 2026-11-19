<#
  Hallow Toolkit - Gaming > Per-game rules (v5.10). Dot-sourced by HallowToolkit.ps1 after the pages are built.
#>
$f = $script:PageFlows['Gaming']
Add-Section $f 'Per-game rules (priority, CPU cores and power plan while a game runs)' 'sliders'
(Add-Note $f 'The tray app applies a rule when that game starts - also to anything the game starts later - and puts your power plan back when it closes. Priority and cores end with the game. A rule''s priority replaces the tray''s "High priority for games" for that game.').Height = 36
(New-RowLabel $f 'Game' 44).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$ruleGame = New-DarkCombo $f 230; $ruleGame.DropDownStyle = 'DropDown'
(New-RowLabel $f 'Priority' 56).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$rulePrio = New-DarkCombo $f 120; foreach ($v in $RulePriorities.Values) { [void]$rulePrio.Items.Add($v) }; $rulePrio.SelectedItem = 'High'
(New-RowLabel $f 'Cores' 42).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$ruleAff = New-DarkCombo $f 200; foreach ($v in $RuleAffinities.Values) { [void]$ruleAff.Items.Add($v) }; $ruleAff.SelectedIndex = 0
$f.SetFlowBreak($ruleAff, $true)
(New-RowLabel $f 'Power plan' 76).Margin = New-Object System.Windows.Forms.Padding(2, 8, 6, 6)
$rulePower = New-DarkCombo $f 230
$script:RulePlans = @(Get-PowerPlans)
[void]$rulePower.Items.Add("Don't change"); foreach ($p in $script:RulePlans) { [void]$rulePower.Items.Add($p.Name) }; $rulePower.SelectedIndex = 0
$f.SetFlowBreak($rulePower, $true)
# game names: the install folders the tray recognises games by
try { foreach ($n in @(Get-GameRoots | ForEach-Object { Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue } | ForEach-Object Name | Where-Object { $IgnoreFolders -notcontains $_ } | Sort-Object -Unique)) { [void]$ruleGame.Items.Add($n) } } catch { }
$tips.SetToolTip($ruleGame, 'The game''s install folder (as on the Games tab) or its .exe name without .exe')
$tips.SetToolTip($ruleAff, 'First half = the first CCD on two-CCD Ryzen chips (the 3D V-Cache cores on most X3D chips). All but the first core keeps the game off core 0, where Windows handles a lot of interrupts.')

$ruleList = New-DarkList $f @(@('Game', 260), @('Priority', 120), @('Cores', 220), @('Power plan', 240)) 880 130 $false
function Update-RuleList {
    $ruleList.Items.Clear()
    foreach ($r in @(Get-GameRules)) {
        $li = New-Object System.Windows.Forms.ListViewItem($r.Game)
        [void]$li.SubItems.Add($RulePriorities[$r.Priority]); [void]$li.SubItems.Add($RuleAffinities[$r.Affinity])
        [void]$li.SubItems.Add($(if ($r.Power) { $pp = @($script:RulePlans | Where-Object Guid -eq $r.Power)[0]; if ($pp) { $pp.Name } else { 'a plan no longer on this PC' } } else { "Don't change" }))
        $li.Tag = $r; [void]$ruleList.Items.Add($li)
    }
}
$ruleList.Add_SelectedIndexChanged({
    if (-not $ruleList.SelectedItems.Count) { return }
    $r = $ruleList.SelectedItems[0].Tag
    $ruleGame.Text = $r.Game; $rulePrio.SelectedItem = $RulePriorities[$r.Priority]; $ruleAff.SelectedItem = $RuleAffinities[$r.Affinity]
    $pp = @($script:RulePlans | Where-Object Guid -eq $r.Power)[0]; $rulePower.SelectedItem = $(if ($pp) { $pp.Name } else { "Don't change" })
})
$f.SetFlowBreak($ruleList, $true)
Add-Tool $f 'Save rule' 'Add or change the rule for this game' {
    $game = "$($ruleGame.Text)".Trim() -replace '\.exe$', ''
    if (-not $game) { Log 'Pick or type a game first.'; return }
    $prio = @($RulePriorities.Keys | Where-Object { $RulePriorities[$_] -eq $rulePrio.SelectedItem })[0]
    $aff = @($RuleAffinities.Keys | Where-Object { $RuleAffinities[$_] -eq $ruleAff.SelectedItem })[0]
    $pw = @($script:RulePlans | Where-Object Name -eq $rulePower.SelectedItem)[0]
    $rules = @(Get-GameRules | Where-Object { $_.Game -ine $game }) + [pscustomobject]@{ Game = $game; Priority = $prio; Affinity = $aff; Power = $(if ($pw) { $pw.Guid } else { '' }) }
    Save-GameRules $rules; Update-RuleList
    Log "Rule saved for $game - the tray app applies it the next time $game starts."
} -Primary -Width 210 -Icon 'floppy-disk' | Out-Null
Add-Tool $f 'Remove rule' 'Delete the selected rule' {
    if (-not $ruleList.SelectedItems.Count) { Log 'Click a rule first.'; return }
    $game = $ruleList.SelectedItems[0].Tag.Game
    Save-GameRules @(Get-GameRules | Where-Object { $_.Game -ine $game }); Update-RuleList; Log "Rule for $game removed."
} -Width 210 -Icon 'trash-can' | Out-Null
Update-RuleList
