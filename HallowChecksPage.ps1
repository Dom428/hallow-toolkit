<#
  Hallow Toolkit - Health > Drives & drivers (v5.15): driver check and drive health as check rows, right under their
  buttons. Read-only: the only buttons on a row open a maker's driver page or the Storage tab. Dot-sourced by
  HallowToolkit.ps1 after HallowFamilyPage.ps1 (needs Show-CheckRows).
#>

$f = $script:PageFlows['Health']
$healthRows = New-Object System.Windows.Forms.FlowLayoutPanel
$healthRows.Text = 'Drive and driver results'   # not shown (lets snapshots scroll here)
$healthRows.FlowDirection = 'TopDown'; $healthRows.WrapContents = $false; $healthRows.AutoSize = $true; $healthRows.AutoSizeMode = 'GrowAndShrink'
$healthRows.MinimumSize = New-Object System.Drawing.Size(860, 0); $healthRows.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
$f.Controls.Add($healthRows); $f.SetFlowBreak($healthRows, $true)
# sit right under the Drives & drivers buttons (other files add sections to this page after them)
$anchor = @($f.Controls | Where-Object { "$($_.Text)" -like 'Optional driver updates*' })[0]
if ($anchor) { $f.Controls.SetChildIndex($healthRows, $f.Controls.GetChildIndex($anchor) + 1); $f.SetFlowBreak($anchor, $true) }

function Show-HealthRows($Lines) {
    $rows = foreach ($l in @($Lines | Where-Object { $_.Level })) {
        $title = $null; $code = $null; $icon = $null
        if ($l.Fix -eq 'open' -and $l.Arg) {
            $u = "$($l.Arg)" -replace "'", "''"
            $title = $(if ($u -match 'nvidia\.com') { 'NVIDIA drivers' } elseif ($u -match 'amd\.com') { 'AMD drivers' } elseif ($u -match 'intel\.com') { 'Intel drivers' } else { 'Board maker page' })
            $code = "Start-Process '$u'; Log 'Opened $title - nothing is downloaded until you choose to.'"; $icon = 'arrow-up-right-from-square'
        } elseif ($l.Fix -eq 'storage') { $title = 'Find what to remove'; $code = "Show-Page 'Storage'"; $icon = 'hard-drive' }
        [pscustomobject]@{ Title = $l.Text; Level = $l.Level; FixTitle = $title; FixIcon = $icon; FixCode = $code }
    }
    Show-CheckRows $healthRows @($rows)
}
function Write-CheckSummary([string]$Name, $Lines) {
    $l = @($Lines | Where-Object { $_.Level })
    Log ('{0}: {1} fine, {2} worth a look, {3} to act on - see the Health tab.' -f $Name, @($l | Where-Object Level -eq 'good').Count, @($l | Where-Object Level -eq 'warn').Count, @($l | Where-Object Level -eq 'bad').Count)
}
function Start-DriverAgeCheck {
    $url = ''; try { $url = Get-BoardSupportUrl (Get-BoardInfo) } catch { }
    Start-Background 'Driver check' $DriverAgeWork @(, @{ BoardUrl = $url }) {
        param($o)
        Show-HealthRows $o; Write-CheckSummary 'Driver check' $o
    }
}
function Start-DiskHealthCheck {
    $now = Get-DiskSpaceNow
    $hist = Update-DiskHistory -Now $now
    $script:LastTrend = @(Get-DiskTrendLines $hist $now)
    Start-Background 'Drive health' $DiskHealthWork @(, @{}) {
        param($o)
        $all = @($o) + @($script:LastTrend)
        Show-HealthRows $all; Write-CheckSummary 'Drive health' $all
    }
}
# one free-space reading a day for the trend (cheap: drive sizes only), whenever the toolkit opens
[void]$script:AfterShown.Add({ try { [void](Update-DiskHistory) } catch { } })
