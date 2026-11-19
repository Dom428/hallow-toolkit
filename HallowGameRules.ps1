<#
  Hallow Toolkit - per-game rules (v5.10, Process Lasso style): priority, CPU cores and power plan while a game runs.
  The tray app applies a rule when the game starts (and to any process the game starts later) and puts the power plan
  back when it closes; priority and cores end with the game's processes. No window code. Dot-sourced by HallowCore.ps1.
#>
$RulePriorities = [ordered]@{ 'Normal' = 'Normal'; 'AboveNormal' = 'Above normal'; 'High' = 'High' }
$RuleAffinities = [ordered]@{ 'All' = 'All cores'; 'FirstHalf' = 'First half of the cores'; 'SecondHalf' = 'Second half of the cores'; 'NoFirst' = 'All but the first core' }

function Get-GameRules {
    $s = Get-Settings
    @($s.GameRules | Where-Object { $_ -and "$($_.Game)".Trim() } | ForEach-Object {
        [pscustomobject]@{ Game = "$($_.Game)".Trim(); Priority = $(if ($RulePriorities.Contains("$($_.Priority)")) { "$($_.Priority)" } else { 'High' })
            Affinity = $(if ($RuleAffinities.Contains("$($_.Affinity)")) { "$($_.Affinity)" } else { 'All' }); Power = "$($_.Power)" }
    })
}
function Save-GameRules($Rules) { $s = Get-Settings; $s | Add-Member GameRules @($Rules | ForEach-Object { [pscustomobject]@{ Game = $_.Game; Priority = $_.Priority; Affinity = $_.Affinity; Power = $_.Power } }) -Force; Save-Settings $s }
# the rule for a running game ($Game from the tray's game finder: Name = install folder, Process = exe name)
function Find-GameRule($Game) {
    if (-not $Game) { return $null }
    @(Get-GameRules | Where-Object { $_.Game -ieq "$($Game.Name)" -or $_.Game -ieq "$($Game.Process)" })[0]
}
# processor mask for a rule (logical processors; on CPUs with SMT the first core is logical 0 and 1)
function Get-RuleAffinityMask([string]$Mode, [int]$Count = [Environment]::ProcessorCount) {
    $Count = [math]::Max(1, [math]::Min($Count, 62))
    $bits = { param($n) ([int64]1 -shl $n) - 1 }
    $all = & $bits $Count; $half = [math]::Max(1, [int][math]::Floor($Count / 2))
    switch ($Mode) {
        'FirstHalf' { & $bits $half }
        'SecondHalf' { $all -bxor (& $bits $half) }
        'NoFirst' { $skip = $(if ($Count -ge 4) { 2 } else { 1 }); $all -bxor (& $bits $skip) }
        default { $all }
    }
}
# Applies priority + cores to every process with that exe name not handled yet. Returns the ids it changed.
function Set-GameRuleProcesses($Rule, [string]$ProcessName, $Done) {
    $ids = @()
    foreach ($p in @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) {
        if ($Done -and $Done.Contains($p.Id)) { continue }
        try {
            if ($Rule.Priority -ne 'Normal') { $p.PriorityClass = $Rule.Priority }
            if ($Rule.Affinity -ne 'All') { $p.ProcessorAffinity = [IntPtr](Get-RuleAffinityMask $Rule.Affinity) }
            $ids += $p.Id
        } catch { }   # anti-cheat protected games refuse - fine
        if ($Done) { [void]$Done.Add($p.Id) }
    }
    $ids
}
# power plans on this PC: Guid, Name, Active
function Get-PowerPlans {
    foreach ($l in @(powercfg /list 2>$null)) {
        if ($l -match '([0-9a-fA-F]{8}-[0-9a-fA-F\-]{27})\s+\((.+)\)(\s*\*)?') { [pscustomobject]@{ Guid = $Matches[1].ToLower(); Name = $Matches[2]; Active = [bool]$Matches[3] } }
    }
}
