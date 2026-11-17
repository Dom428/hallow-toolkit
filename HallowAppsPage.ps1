<#
  Hallow Toolkit - Apps tab (window code). Dot-sourced by HallowToolkit.ps1 after the other pages.
#>
if (-not $script:PageShowHooks) { $script:PageShowHooks = @{} }

$f = Add-Page 'Apps' ([char]0x2B07) 'Install your apps in one go - like Ninite, built in. Official installers, no toolbars.'
$script:AppRows = @(Get-AppCatalogRows)
$script:AppTicked = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:AppState = $null; $script:AppFilling = $false

Add-Section $f 'Pick apps, then Install ticked' 'download'
$appFilter = New-Object System.Windows.Forms.ComboBox
$appFilter.DropDownStyle = 'DropDownList'; $appFilter.Width = 300; $appFilter.Font = New-Font 10.5
$appFilter.BackColor = $C.Panel; $appFilter.ForeColor = $C.Text; $appFilter.FlatStyle = 'Flat'
$appFilter.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
foreach ($x in @('All apps') + @($AppCatalog.Keys) + @('Not installed yet', 'Updates available', 'My apps')) { [void]$appFilter.Items.Add($x) }
$appFilter.SelectedIndex = 0
$f.Controls.Add($appFilter)
$appCount = New-Object System.Windows.Forms.Label
$appCount.AutoSize = $false; $appCount.Width = 540; $appCount.Height = 30; $appCount.TextAlign = 'MiddleLeft'
$appCount.ForeColor = $C.Muted; $appCount.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$f.Controls.Add($appCount); $f.SetFlowBreak($appCount, $true)

$appList = New-DarkList $f @(@('App', 230), @('Group', 120), @('Status', 130), @('What it is', 360)) 860 330 $true
$appList.ShowItemToolTips = $true; $f.SetFlowBreak($appList, $true)

function Get-AppStatus($r) {
    $st = $script:AppState
    if (-not $st) { return '...' }
    if ($st.Updates -contains $r.Id) { return 'Update available' }
    if ($st.Installed -contains $r.Id) { return 'Installed' }
    $rx = '^' + [regex]::Escape($r.Name) + '(\s|$|\.|\d|\()'
    if (@($st.Names | Where-Object { $_ -match $rx }).Count) { return 'Installed' }
    ''
}
function Update-AppTickCount {
    $n = $script:AppTicked.Count
    $appCount.Text = $(if ($n) { "$n ticked: " + ((@($script:AppRows | Where-Object { $script:AppTicked.Contains($_.Id) }) | ForEach-Object Name) -join ', ') } else { 'Nothing ticked yet.' })
}
function Show-AppList {
    $script:AppFilling = $true
    $appList.BeginUpdate(); $appList.Items.Clear()
    $mine = Get-MyApps; $sel = "$($appFilter.SelectedItem)"
    foreach ($r in $script:AppRows) {
        $status = Get-AppStatus $r
        $show = switch ($sel) {
            'All apps' { $true }
            'Not installed yet' { -not $status }
            'Updates available' { $status -eq 'Update available' }
            'My apps' { $mine -contains $r.Id }
            default { $r.Category -eq $sel }
        }
        if (-not $show) { continue }
        $li = New-Object System.Windows.Forms.ListViewItem($r.Name)
        foreach ($v in $r.Category, $status, $r.Note) { [void]$li.SubItems.Add("$v") }
        $li.Tag = $r; $li.ToolTipText = "winget id: $($r.Id)$(if ($r.Ninite) { '  |  also on Ninite' })"
        $li.ForeColor = switch ($status) { 'Installed' { $C.Good } 'Update available' { $C.Warn } default { $C.Text } }
        $li.Checked = $script:AppTicked.Contains($r.Id)
        [void]$appList.Items.Add($li)
    }
    $appList.EndUpdate()
    $script:AppFilling = $false
    Update-AppTickCount
}
$appList.Add_ItemChecked({
    param($s, $e)
    if ($script:AppFilling) { return }
    $id = $e.Item.Tag.Id
    if ($e.Item.Checked) { [void]$script:AppTicked.Add($id) } else { [void]$script:AppTicked.Remove($id) }
    Update-AppTickCount
})
$appFilter.Add_SelectedIndexChanged({ Show-AppList })

function Update-AppState([switch]$Quiet) {
    Start-Background 'Checking installed apps' $AppStateWork @() {
        param($out)
        $r = @($out)[0]
        if ($r.Error) { Log $r.Error; return }
        $script:AppState = $r
        Show-AppList
        $inst = @($script:AppRows | Where-Object { (Get-AppStatus $_) -eq 'Installed' }).Count
        $upd = @($script:AppRows | Where-Object { (Get-AppStatus $_) -eq 'Update available' }).Count
        Log ("Apps: {0} of {1} in the list are installed{2}." -f $inst, $script:AppRows.Count, $(if ($upd) { ", $upd with an update (pick 'Updates available' to see them)" } else { '' }))
    }
}

function Install-AppRows($Rows, [string]$What) {
    $Rows = @($Rows)
    if (-not $Rows) { Log 'Tick some apps first.'; return }
    $todo = @(); $skip = @()
    foreach ($r in $Rows) {
        $st = if ($r.PSObject.Properties.Name -contains 'Category') { Get-AppStatus $r } else { '' }
        if ($st -eq 'Installed') { $skip += $r.Name; continue }
        $todo += [pscustomobject]@{ Name = $r.Name; Id = $r.Id; Update = ($st -eq 'Update available'); User = [bool]$r.User }
    }
    if ($skip) { Log "Already installed, skipped: $($skip -join ', ')" }
    if (-not $todo) { return }
    $names = ($todo | ForEach-Object Name) -join ', '
    if (-not (Confirm-Action "Install or update $($todo.Count) app(s)?`n`n$names`n`nEach one downloads from its maker's official installer and installs silently, one after another.")) { return }
    $user = @($todo | Where-Object User); $main = @($todo | Where-Object { -not $_.User })
    if ($user -and $IsAdmin) { Start-UserAppInstall $user } elseif ($user) { $main += $user }
    if ($main) {
        Log "Installing $($main.Count) app(s) - this can take a few minutes. You can keep using the toolkit; the results show here when done."
        Start-Background "Installing $($main.Count) app(s)" $AppInstallWork @(, [object[]]$main) {
            param($out)
            foreach ($l in $out) { Log "$l" }
            if ($script:AppState) { Update-AppState }
        }
    }
}

Add-Tool $f 'Install ticked' 'Silent, one after another' { Install-AppRows @($script:AppRows | Where-Object { $script:AppTicked.Contains($_.Id) }) } -Primary -Width 210 -Icon 'download' | Out-Null
Add-Tool $f 'Open on Ninite' 'Same apps as a Ninite installer' {
    $rows = @($script:AppRows | Where-Object { $script:AppTicked.Contains($_.Id) })
    if (-not $rows) { Log 'Tick some apps first.'; return }
    $url = Get-NiniteUrl $rows
    $missing = @($rows | Where-Object { -not $_.Ninite } | ForEach-Object Name)
    if ($url) { Start-Process $url; Log "Opened Ninite with your apps: $url" } else { Log 'None of the ticked apps are on Ninite.' }
    if ($missing) { Log "Not on Ninite (use Install ticked for these): $($missing -join ', ')" }
} -Width 210 -Icon 'arrow-up-right-from-square' | Out-Null
Add-Tool $f 'Refresh' 'Re-check what is installed' { Update-AppState } -Width 210 -Icon 'arrows-rotate' | Out-Null
Add-Tool $f 'Untick all' 'Clear your picks' { $script:AppTicked.Clear(); Show-AppList } -Width 210 -Icon 'list-check' | Out-Null

Add-Section $f 'My apps (set up a new PC in one click)' 'star'
Add-Tool $f 'Save ticked as my apps' 'Remember this set' {
    if (-not $script:AppTicked.Count) { Log 'Tick the apps you always want first.'; return }
    Save-MyApps @($script:AppTicked); Log "Saved $($script:AppTicked.Count) app(s) as your apps. Tools > Export my setup takes them to a friend or a new PC."
} -Width 210 -Icon 'floppy-disk' | Out-Null
Add-Tool $f 'Tick my apps' 'Ready to install on a new PC' {
    $mine = Get-MyApps
    if (-not $mine) { Log 'No saved apps yet - tick some and click Save ticked as my apps.'; return }
    foreach ($id in $mine) { [void]$script:AppTicked.Add($id) }
    $appFilter.SelectedItem = 'My apps'; Show-AppList; Log "Ticked your $($mine.Count) app(s). Click Install ticked."
} -Width 210 -Icon 'list-check' | Out-Null

Add-Section $f 'Search every app in winget' 'magnifying-glass'
$appSearch = New-Object System.Windows.Forms.TextBox
$appSearch.Width = 430; $appSearch.Font = New-Font 11; $appSearch.BackColor = $C.Panel; $appSearch.ForeColor = $C.Text; $appSearch.BorderStyle = 'FixedSingle'
$appSearch.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 10)
$f.Controls.Add($appSearch)
function Start-AppSearch {
    $q = $appSearch.Text.Trim()
    if ($q.Length -lt 2) { Log 'Type at least 2 letters to search.'; return }
    $srchList.Items.Clear()
    Start-Background "Searching for '$q'" $AppSearchWork @($q) {
        param($out)
        $rows = @($out | Where-Object { $_.Id })
        foreach ($r in $rows) {
            $li = New-Object System.Windows.Forms.ListViewItem($r.Name)
            [void]$li.SubItems.Add($r.Id); [void]$li.SubItems.Add($r.Version); $li.Tag = $r
            [void]$srchList.Items.Add($li)
        }
        Log $(if ($rows) { "Found $($rows.Count) app(s) - tick and click Install ticked results." } else { 'Nothing found - try another word.' })
    }
}
$appSearch.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Return') { $e.SuppressKeyPress = $true; Start-AppSearch } })
Add-Tool $f 'Search' 'Or press Enter' { Start-AppSearch } -Width 160 -Icon 'magnifying-glass' | Out-Null
Add-Tool $f 'Install ticked results' 'From the search list' {
    Install-AppRows @($srchList.CheckedItems | ForEach-Object { $_.Tag })
} -Width 230 -Icon 'download' | Out-Null
$srchList = New-DarkList $f @(@('App', 340), @('winget id', 360), @('Version', 140)) 860 220 $true
$f.SetFlowBreak($srchList, $true)
Add-Note $f 'Apps come from winget, the app installer built into Windows. Hover an app to see its winget id and whether Ninite has it too.' | Out-Null

Show-AppList
$script:PageShowHooks['Apps'] = { Update-AppState }
