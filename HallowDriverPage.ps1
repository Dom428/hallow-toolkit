<#
  Hallow Toolkit - Drivers page + toolkit self-update (window code). Dot-sourced by HallowToolkit.ps1.
#>

if (-not $script:PageShowHooks) { $script:PageShowHooks = @{} }

# ================================================================ PAGE: DRIVERS
$f = Add-Page 'Drivers' ([char]0x2699) 'Motherboard drivers, BIOS and Windows Update drivers'
Add-Section $f 'Your motherboard'
$script:BoardNote = Add-Note $f 'Reading motherboard...'
$script:Board = $null
function Get-Board {
    if (-not $script:Board) {
        $script:Board = Get-BoardInfo
        $b = $script:Board
        $api = if ($b.Vendor -eq 'ASUS') { 'automatic download list available' } else { "$($b.Vendor): opens the support page + Windows Update drivers" }
        $script:BoardNote.Text = "{0}  {1}   |   BIOS {2} ({3:yyyy-MM-dd})   |   {4}" -f $b.Maker, $b.Model, $b.Bios, $b.BiosDate, $api
    }
    $script:Board
}
$script:PageShowHooks['Drivers'] = { [void](Get-Board) }

Add-Tool $f 'Check for updates' 'Newest drivers + BIOS from the maker' { Start-DriverScan } -Primary | Out-Null
Add-Tool $f 'Maker support page' 'Your board on the maker''s site' { Start-Process (Get-BoardSupportUrl (Get-Board)); Log 'Opened the support page.' } | Out-Null
Add-Tool $f 'Open downloads' 'Where drivers and BIOS files go' {
    New-Item -ItemType Directory -Force $DriverDownloadRoot | Out-Null; Start-Process explorer.exe "`"$DriverDownloadRoot`""
} | Out-Null

$drvList = New-DarkList $f @(@('Type', 78), @('Name', 318), @('Version', 100), @('Released', 82), @('Size', 72), @('Status', 186)) 860 230 $true
$f.SetFlowBreak($drvList, $true); $drvList.ShowItemToolTips = $true
Add-Tool $f 'Download & install ticked' 'Checksum-verified, signed installers only' { Install-PickedDrivers } -Primary | Out-Null
Add-Tool $f 'Tick recommended' 'Everything marked Newer (not BIOS)' {
    foreach ($i in $drvList.Items) { $i.Checked = ($i.Tag.Kind -ne 'BIOS' -and $i.Tag.Status -match '^(Newer|Recommended)') }
} -Width 210 | Out-Null
Add-Tool $f 'Untick all' 'Clear selection' { foreach ($i in $drvList.Items) { $i.Checked = $false } } -Width 160 | Out-Null

function Start-DriverScan {
    $b = Get-Board
    $drvList.Items.Clear()
    Start-Background "Driver check ($($b.Model))" $BoardScanWork @($b.Vendor, $b.Model, $b.Bios) {
        param($out)
        $first = @($out)[0]
        if ($first.Error -eq 'NOAPI') {
            Log "$($script:Board.Vendor) has no automatic download list, so I opened their support page for $($script:Board.Model)."
            Log "Also click 'Scan Windows Update' below - it finds driver updates for any brand."
            Start-Process (Get-BoardSupportUrl $script:Board); return
        }
        if ($first.Error) { Log $first.Error; return }
        $new = 0
        foreach ($it in $out) {
            $li = New-Object System.Windows.Forms.ListViewItem($it.Category)
            foreach ($v in $it.Title, $it.Version, $it.Date, $it.Size, $it.Status) { [void]$li.SubItems.Add("$v") }
            $li.Tag = $it; $li.ToolTipText = $it.Notes
            if ($it.Status -match '^(Newer|Recommended)') { $li.ForeColor = $C.Accent; $li.Checked = ($it.Kind -ne 'BIOS'); $new++ }
            elseif ($it.Status -eq 'Up to date') { $li.ForeColor = $C.Good }
            else { $li.ForeColor = $C.Muted }
            [void]$drvList.Items.Add($li)
        }
        Log "Found $new update(s) for your $($script:Board.Model). Recommended drivers are ticked - the BIOS is never ticked for you."
        $bios = @($out | Where-Object { $_.Kind -eq 'BIOS' -and $_.Status -like 'Newer*' })[0]
        if ($bios) { Log "BIOS $($bios.Version) is out ($($bios.Date)). Tick it to download + verify it, then flash it with EZ Flash. $($bios.Notes)" }
    }
}

function Install-PickedDrivers {
    $items = @($drvList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $items) { Log 'Tick at least one item first (or click Check for updates).'; return }
    if (-not (Need-Admin 'Installing drivers')) { return }
    $list = ($items | ForEach-Object { "  - $($_.Title)  ($($_.Size))" }) -join "`n"
    $msg = "Download and install these from $($script:Board.Vendor)?`n`n$list`n`nEach file is checked against the maker's checksum and only signed installers are run. Installer windows will open - follow them."
    if ($items | Where-Object Kind -eq 'BIOS') { $msg += "`n`nThe BIOS is only downloaded, verified and unpacked. You flash it yourself from the BIOS screen (EZ Flash)." }
    $msg += "`n`nTip: make a restore point first (Tools tab)."
    if (-not (Confirm-Action $msg)) { return }
    Start-Background 'Driver download + install' $DriverInstallWork @($items, $DriverDownloadRoot) $null
}

Add-Section $f 'Windows Update drivers (works for any brand)'
Add-Tool $f 'Scan Windows Update' 'Driver updates Microsoft has for this PC' { Start-WuDriverScan } -Primary | Out-Null
Add-Tool $f 'Install ticked' 'Download + install from Windows Update' { Install-WuDrivers } | Out-Null
$wuList = New-DarkList $f @(@('Driver', 520), @('Type', 130), @('Driver date', 105), @('Size', 85)) 860 150 $true

function Start-WuDriverScan {
    $wuList.Items.Clear()
    Start-Background 'Windows Update driver scan' $WuDriverScanWork @() {
        param($out)
        $n = 0
        foreach ($u in $out) {
            if (-not $u.Id) { continue }
            $li = New-Object System.Windows.Forms.ListViewItem("$($u.Title)")
            [void]$li.SubItems.Add($u.Class); [void]$li.SubItems.Add($(if ($u.Date) { '{0:yyyy-MM-dd}' -f $u.Date } else { '' })); [void]$li.SubItems.Add("$($u.MB) MB")
            $li.Tag = $u; [void]$wuList.Items.Add($li); $n++
        }
        if ($n) { Log "Windows Update has $n driver update(s). Tick the ones you want and click Install ticked." } else { Log 'Windows Update has no driver updates for this PC right now.' }
    }
}

function Install-WuDrivers {
    $ids = @($wuList.CheckedItems | ForEach-Object { $_.Tag.Id })
    if (-not $ids) { Log 'Tick at least one driver first (Scan Windows Update).'; return }
    if (-not (Need-Admin 'Installing Windows Update drivers')) { return }
    if (-not (Confirm-Action "Install $($ids.Count) driver update(s) from Windows Update?")) { return }
    Start-Background 'Windows Update driver install' $WuDriverInstallWork @(, [string[]]$ids) $null
}

Add-Section $f 'Driver backup & old driver cleanup'
Add-Tool $f 'Back up all drivers' 'Before a BIOS or driver change' {
    if (-not (Need-Admin 'Backing up drivers')) { return }
    New-Item -ItemType Directory -Force $DriverBackupRoot | Out-Null
    Start-Background 'Driver backup' $DriverBackupWork @($DriverBackupRoot) $null
} -Primary | Out-Null
Add-Tool $f 'Open backups' 'Documents > Hallow Driver Backups' {
    New-Item -ItemType Directory -Force $DriverBackupRoot | Out-Null; Start-Process explorer.exe "`"$DriverBackupRoot`""
} | Out-Null
Add-Tool $f 'Find old drivers' 'Old versions Windows keeps around' {
    $oldList.Items.Clear()
    $items = @(Get-OldDriverPackages | Sort-Object Bytes -Descending)
    foreach ($it in $items) {
        $li = New-Object System.Windows.Forms.ListViewItem((Format-Size $it.Bytes))
        foreach ($v in $it.Inf, $it.Provider, $it.Version, $it.Newer) { [void]$li.SubItems.Add("$v") }
        $li.Tag = $it; $li.Checked = $true; $li.ToolTipText = $it.Folder
        [void]$oldList.Items.Add($li)
    }
    Log ("Found {0} old driver package(s) using {1}. A newer version of each is installed; ticked ones can go." -f $items.Count, (Format-Size (($items | Measure-Object Bytes -Sum).Sum)))
} | Out-Null
$oldList = New-DarkList $f @(@('Size', 80), @('Driver file', 250), @('Maker', 220), @('Old version', 140), @('Newer one', 140)) 860 180 $true
$oldList.ShowItemToolTips = $true; $f.SetFlowBreak($oldList, $true)
Add-Tool $f 'Remove ticked old drivers' 'Drivers still in use are kept' {
    $items = @($oldList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $items) { Log 'Click Find old drivers first.'; return }
    $total = Format-Size (($items | Measure-Object Bytes -Sum).Sum)
    if (-not (Confirm-Action "Remove $($items.Count) old driver package(s) ($total)?`n`nA newer version of each stays installed, and Windows refuses to remove any that a device still uses. Tip: click Back up all drivers first.`n`nThis can't be undone (except from a backup).")) { return }
    Remove-OldDriverPackages $items
    foreach ($i in @($oldList.CheckedItems)) { if (-not (pnputil /enum-drivers 2>$null | Select-String -SimpleMatch "Published Name:     $($i.Tag.Oem)")) { $oldList.Items.Remove($i) } }
} | Out-Null
# ================================================================ TOOLKIT SELF-UPDATE
$script:QuietCheck = $false
function Start-SelfUpdateCheck([switch]$Quiet) {
    $script:QuietCheck = [bool]$Quiet
    Start-Background 'Toolkit update check' $SelfUpdateCheckWork @($UpdateRepo) {
        param($out)
        $r = @($out)[0]
        $s = Get-Settings; $s.LastUpdateCheck = (Get-Date).ToString('o'); Save-Settings $s
        if ($r.Error) { if (-not $script:QuietCheck) { Log "Update check: $($r.Error)" }; return }
        if (Test-NewerVersion $r.Version $AppVersion) {
            $brand2.Text = "TOOLKIT  v$AppVersion  >  v$($r.Version)"; $brand2.ForeColor = $C.Accent
            Log "Hallow Toolkit v$($r.Version) is available (you have v$AppVersion)."
            $notes = "$($r.Notes)"; if ($notes.Length -gt 600) { $notes = $notes.Substring(0, 600) + '...' }
            if (Confirm-Action "Hallow Toolkit v$($r.Version) is available (you have v$AppVersion).`n`n$notes`n`nUpdate now? The toolkit restarts; your settings and logs are kept.") { Start-SelfUpdateInstall $r }
            else { Log 'Update skipped - Tools tab > Check for toolkit updates when you are ready.' }
        } elseif (-not $script:QuietCheck) { Log "You have the latest version (v$AppVersion)." }
    }
}

function Start-SelfUpdateInstall($Release) {
    if (-not $Release.Url) { Log 'That release has no zip attached - nothing to install.'; return }
    $script:PendingRelease = $Release
    Start-Background "Downloading v$($Release.Version)" $SelfUpdateDownloadWork @($Release.Url, $Release.Sha256) {
        param($out)
        $d = @($out)[0]
        if ($d.Error) { Log "Update failed: $($d.Error)"; return }
        $n = Install-SelfUpdateFiles $d.Folder $d.Temp
        $s = Get-Settings; $s | Add-Member PendingNotes ("v{0}`n`n{1}" -f $script:PendingRelease.Version, "$($script:PendingRelease.Notes)") -Force; Save-Settings $s
        Log ("Updated {0} files{1}. Restarting..." -f $n, $(if ($d.Verified) { ' (checksum verified)' } else { '' }))
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $HallowRoot 'HallowToolkit.ps1')`"")
        $form.Close()
    }
}

function Switch-AutoUpdate {
    $s = Get-Settings; $s.AutoUpdate = -not $s.AutoUpdate; Save-Settings $s
    Log "Automatic update check is now $(if ($s.AutoUpdate) { 'ON - checks when the toolkit opens (at most every 12 hours)' } else { 'OFF' })."
}

# First start after a self-update: show what changed.
[void]$script:AfterShown.Add({
    $s = Get-Settings
    if ($s.PSObject.Properties.Name -contains 'PendingNotes' -and $s.PendingNotes) {
        $txt = ("$($s.PendingNotes)" -replace '\*\*', '' -replace '(?m)^- ', '  - ')
        if ($txt.Length -gt 1500) { $txt = $txt.Substring(0, 1500) + '...' }
        $s.PendingNotes = ''; Save-Settings $s
        Log "Updated to $AppVersion."
        [void][System.Windows.Forms.MessageBox]::Show("Hallow Toolkit was updated - here's what's new in $txt", $AppName, 'OK', 'Information')
    }
})
[void]$script:AfterShown.Add({
    $s = Get-Settings; $last = [datetime]::MinValue
    [void][datetime]::TryParse("$($s.LastUpdateCheck)", [ref]$last)
    if ($s.AutoUpdate -and ((Get-Date) - $last).TotalHours -ge 12) { Start-SelfUpdateCheck -Quiet }
})
