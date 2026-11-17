<#
  Hallow Toolkit v3 - extra pages and sections. Dot-sourced by HallowToolkit.ps1 after the main pages are built.
#>
if (-not $script:PageShowHooks) { $script:PageShowHooks = @{} }
$ChartBlue = RGB 57 135 229     # #3987e5  (GPU)   - validated dark categorical slot 1
$ChartOrange = RGB 217 89 38    # #d95926  (CPU)   - validated dark categorical slot 2
$GridInk = $C.Grid

# ---------------------------------------------------------------- small helpers
function Show-Chooser([string]$Title, [string[]]$Items, [string]$Button = 'OK') {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $Title; $d.Size = New-Object System.Drawing.Size(560, 420); $d.StartPosition = 'CenterParent'
    $d.BackColor = $C.Bg; $d.ForeColor = $C.Text; $d.Font = New-Font 10; $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $lb = New-Object System.Windows.Forms.CheckedListBox
    $lb.Dock = 'Fill'; $lb.BackColor = $C.Panel; $lb.ForeColor = $C.Text; $lb.BorderStyle = 'None'; $lb.CheckOnClick = $true
    foreach ($i in $Items) { [void]$lb.Items.Add($i) }
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = $Button; $ok.Dock = 'Bottom'; $ok.Height = 40; $ok.FlatStyle = 'Flat'; $ok.BackColor = $C.Accent; $ok.ForeColor = $C.AccentText
    $ok.DialogResult = 'OK'
    $d.Controls.Add($lb); $d.Controls.Add($ok); $d.AcceptButton = $ok
    if ($d.ShowDialog($form) -eq 'OK') { @($lb.CheckedItems | ForEach-Object { [string]$_ }) } else { @() }
}

function New-DarkChart([string]$Title, [string]$Unit) {
    $ch = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    $ch.Dock = 'Fill'; $ch.BackColor = $C.Bg
    $ar = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea 'a'
    $ar.BackColor = $C.Bg
    foreach ($ax in $ar.AxisX, $ar.AxisY) {
        $ax.LineColor = $GridInk; $ax.MajorGrid.LineColor = $GridInk; $ax.MajorTickMark.LineColor = $GridInk
        $ax.LabelStyle.ForeColor = $C.Muted; $ax.LabelStyle.Font = New-Font 8.5; $ax.TitleForeColor = $C.Muted; $ax.TitleFont = New-Font 8.5
    }
    $ar.AxisX.MajorGrid.Enabled = $false; $ar.AxisX.Title = 'Minutes into the session'; $ar.AxisX.LabelStyle.Format = '0'
    $ar.AxisY.Title = $Unit; $ar.AxisY.Minimum = 0
    $ch.ChartAreas.Add($ar)
    $lg = New-Object System.Windows.Forms.DataVisualization.Charting.Legend 'l'
    $lg.Docking = 'Top'; $lg.Alignment = 'Near'; $lg.BackColor = $C.Bg; $lg.ForeColor = $C.Text; $lg.Font = New-Font 9
    $ch.Legends.Add($lg)
    $t = New-Object System.Windows.Forms.DataVisualization.Charting.Title $Title
    $t.ForeColor = $C.Text; $t.Font = New-Font 11 'Bold'; $t.Alignment = 'TopLeft'
    $ch.Titles.Add($t)
    $ch
}
function Add-ChartLine($Chart, [string]$Name, $Color, $Xs, $Ys, [string]$Unit) {
    $s = New-Object System.Windows.Forms.DataVisualization.Charting.Series $Name
    $s.ChartType = 'Line'; $s.BorderWidth = 2; $s.Color = $Color; $s.Legend = 'l'
    $s.ToolTip = "#SERIESNAME: #VALY{0}$Unit at #VALX{0.0} min"
    for ($i = 0; $i -lt $Xs.Count; $i++) { if ($null -ne $Ys[$i]) { [void]$s.Points.AddXY([double]$Xs[$i], [double]$Ys[$i]) } }
    if ($s.Points.Count) { $Chart.Series.Add($s) }
}

# ================================================================ GAMES: sessions, save backup, clips
$f = $script:PageFlows['Games']
Add-Section $f 'Game sessions (recorded by the tray app while you play)'
$sessList = New-DarkList $f @(@('Game', 210), @('Date', 125), @('Length', 65), @('GPU avg', 70), @('GPU max', 70), @('VRAM max', 75), @('Verdict', 255)) 880 190 $false
$sessNote = Add-Note $f ''
function Update-SessionList {
    $sessList.BeginUpdate(); $sessList.Items.Clear()
    $all = @(Get-GameSessions)
    foreach ($s in $all) {
        $it = New-Object System.Windows.Forms.ListViewItem($s.Game)
        [void]$it.SubItems.Add(('{0:yyyy-MM-dd HH:mm}' -f $s.Start))
        [void]$it.SubItems.Add(('{0} min' -f $s.Minutes))
        [void]$it.SubItems.Add($(if ($null -ne $s.GpuAvg) { '{0:N0}%' -f $s.GpuAvg } else { '-' }))
        [void]$it.SubItems.Add($(if ($null -ne $s.GpuTempMax) { '{0:N0} C' -f $s.GpuTempMax } else { '-' }))
        [void]$it.SubItems.Add($(if ($null -ne $s.VramMax) { '{0:N1} GB' -f $s.VramMax } else { '-' }))
        [void]$it.SubItems.Add($s.Verdict)
        $it.Tag = $s; [void]$sessList.Items.Add($it)
    }
    $sessList.EndUpdate()
    $sessNote.Text = $(if ($all) { "$($all.Count) recorded session(s). Select one and click Show chart." } else { 'No sessions yet - start the tray app (Gaming tab) and play a game; it records automatically.' })
}
function Show-SessionChart($Sum) {
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization
    $s = Get-Content $Sum.File -Raw | ConvertFrom-Json
    $t0 = [datetime]$s.Start
    $xs = @($s.Samples | ForEach-Object { ([datetime]$_.t - $t0).TotalMinutes })
    $w = New-Object System.Windows.Forms.Form
    $w.Text = "$($s.Game) - session $('{0:yyyy-MM-dd HH:mm}' -f $t0)"; $w.Size = New-Object System.Drawing.Size(1000, 700)
    $w.StartPosition = 'CenterParent'; $w.BackColor = $C.Bg; $w.ForeColor = $C.Text; $w.Font = New-Font 10
    if ($form.Icon) { $w.Icon = $form.Icon }
    $tl = New-Object System.Windows.Forms.TableLayoutPanel
    $tl.Dock = 'Fill'; $tl.RowCount = 3; $tl.ColumnCount = 1; $tl.Padding = New-Object System.Windows.Forms.Padding(12)
    [void]$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 54)))
    [void]$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 50)))
    [void]$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 50)))
    $hd = New-Object System.Windows.Forms.Label
    $hd.Dock = 'Fill'; $hd.Font = New-Font 10.5
    $hd.Text = ("{0}  |  {1} min  |  GPU avg {2}  |  GPU max {3}  |  VRAM max {4}  |  {5}" -f $s.Game, $Sum.Minutes,
        $(if ($null -ne $Sum.GpuAvg) { '{0:N0}%' -f $Sum.GpuAvg } else { '-' }), $(if ($null -ne $Sum.GpuTempMax) { '{0:N0} C' -f $Sum.GpuTempMax } else { '-' }),
        $(if ($null -ne $Sum.VramMax) { '{0:N1} GB' -f $Sum.VramMax } else { '-' }), $Sum.Verdict)
    $tl.Controls.Add($hd, 0, 0)
    $load = New-DarkChart 'Load' '%'
    $load.ChartAreas[0].AxisY.Maximum = 100
    Add-ChartLine $load 'GPU load' $ChartBlue $xs @($s.Samples | ForEach-Object { $_.gpu }) '%'
    Add-ChartLine $load 'CPU load' $ChartOrange $xs @($s.Samples | ForEach-Object { $_.cpu }) '%'
    $tl.Controls.Add($load, 0, 1)
    $temp = New-DarkChart 'Temperature' 'Degrees C'
    Add-ChartLine $temp 'GPU temp' $ChartBlue $xs @($s.Samples | ForEach-Object { $_.gtemp }) ' C'
    Add-ChartLine $temp 'CPU temp' $ChartOrange $xs @($s.Samples | ForEach-Object { $_.ctemp }) ' C'
    $tl.Controls.Add($temp, 0, 2)
    $w.Controls.Add($tl)
    [void]$w.Show($form)
}
Add-Tool $f 'Show chart' 'Load + temperature over time' {
    if (-not $sessList.SelectedItems.Count) { Log 'Click a session first.'; return }
    Show-SessionChart $sessList.SelectedItems[0].Tag
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Refresh sessions' 'Reload recorded sessions' { Update-SessionList } -Width 210 | Out-Null
Add-Tool $f 'Sessions folder' 'Raw data (JSON)' { New-Item -ItemType Directory -Force $SessionDir | Out-Null; Start-Process explorer.exe $SessionDir } -Width 210 | Out-Null
[void]$script:AfterShown.Add({ Update-SessionList })

Add-Section $f 'Game save backup'
$saveNote = Add-Note $f ("Backups go to: " + (Get-DefaultBackupDir) + "  (newest 5 kept)")
Add-Tool $f 'Back up saves now' 'Zip all game saves' {
    $dest = Get-DefaultBackupDir
    Start-Background 'Game save backup' $SaveBackupWork @($dest, 5, $false)
} -Primary -Width 210 | Out-Null
Add-Tool $f 'What gets backed up' 'List save folders + sizes' { Start-Background 'Save backup preview' $SaveBackupWork @((Get-DefaultBackupDir), 5, $true) } -Width 210 | Out-Null
Add-Tool $f 'Change backup folder' 'Pick where zips go' {
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Where should game-save backups go? (another drive is safest)'
    if ($fb.ShowDialog($form) -eq 'OK') {
        $st = Get-Settings; $st | Add-Member SaveBackupDir $fb.SelectedPath -Force; Save-Settings $st
        $saveNote.Text = "Backups go to: $($fb.SelectedPath)  (newest 5 kept)"; Log "Game-save backups will go to $($fb.SelectedPath)"
    }
} -Width 210 | Out-Null
Add-Tool $f 'Weekly auto backup' 'Saturdays 4 AM' { Invoke-ToggleSaveBackupTask } -Width 210 -State { [bool](Get-ScheduledTask -TaskName $SaveTaskName -ErrorAction SilentlyContinue) } | Out-Null
Add-Tool $f 'Open backups' 'Browse backup zips' { $d = Get-DefaultBackupDir; New-Item -ItemType Directory -Force $d | Out-Null; Start-Process explorer.exe $d } -Width 210 | Out-Null

Add-Section $f 'Clips & screenshots'
$clipAge = New-Object System.Windows.Forms.ComboBox
$clipAge.DropDownStyle = 'DropDownList'; $clipAge.Width = 210; $clipAge.Font = New-Font 10.5
$clipAge.BackColor = $C.Panel; $clipAge.ForeColor = $C.Text; $clipAge.FlatStyle = 'Flat'
$clipAge.Margin = New-Object System.Windows.Forms.Padding(0, 18, 10, 10)
foreach ($o in 'Older than 30 days', 'Older than 90 days', 'Older than 180 days', 'Older than 1 year') { [void]$clipAge.Items.Add($o) }
$clipAge.SelectedIndex = 1
$f.Controls.Add($clipAge)
Add-Tool $f 'Find old clips' 'Medal, NVIDIA, Steam...' {
    $days = @(30, 90, 180, 365)[$clipAge.SelectedIndex]
    $folders = @(Get-ClipFolders)
    if (-not $folders) { Log 'No clip or screenshot folders found.'; return }
    Start-Background 'Clip scan' $ClipScanWork (@(, $folders) + @($days)) {
        param($o)
        foreach ($l in $o | Where-Object { $_ -is [string] }) { $p = $l -split '\|'; Log ("  {0}: {1} files, {2}" -f $p[1], $p[3], (Format-Size ([double]$p[2]))) }
        Show-Results "Clips & screenshots $($clipAge.SelectedItem.ToLower())" @($o | Where-Object { $_ -isnot [string] }) $true $false
        Show-Page 'Storage'
    }
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Open Videos folder' 'Where most clips live' { Start-Process explorer.exe ([Environment]::GetFolderPath('MyVideos')) } -Width 210 | Out-Null

# ================================================================ NETWORK: game servers + DNS speed
$f = $script:PageFlows['Network']
Add-Section $f 'Game servers & DNS'
Add-Tool $f 'Game server ping' 'Valve + AWS regions near you' { Start-Background 'Game server ping' $ServerPingWork @() } -Primary | Out-Null
Add-Tool $f 'DNS speed test' 'Your ISP vs Cloudflare, Google, Quad9' {
    $a = Get-MainAdapter
    $servers = @()
    if ($a) {
        foreach ($ip in (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses | Select-Object -First 1) { $servers += [pscustomobject]@{ Name = 'Current (your provider)'; Ip = $ip } }
    }
    foreach ($k in $DnsPresets.Keys) { $servers += [pscustomobject]@{ Name = $k; Ip = $DnsPresets[$k][0] } }
    Start-Background 'DNS speed test' $DnsTestWork (, $servers) {
        param($o)
        $rank = @($o | Where-Object { $null -ne $_.Median } | Sort-Object Median)
        Log 'DNS lookup speed (lower is better):'
        foreach ($r in $rank) { Log ('  {0,-26} {1,-16} median {2,5:N1} ms   avg {3,5:N1} ms{4}' -f $r.Name, $r.Ip, $r.Median, $r.Avg, $(if ($r.Fails) { "   ($($r.Fails) failed)" } else { '' })) }
        $best = $rank | Select-Object -First 1
        if ($best) {
            $script:FastestDns = if ($DnsPresets.Contains($best.Name)) { $best.Name } else { $null }
            if ($script:FastestDns) { Log "Fastest: $($best.Name). Click 'Use fastest DNS' to switch." } else { Log 'Your current DNS is already the fastest - no change needed.' }
        }
    }
} | Out-Null
Add-Tool $f 'Use fastest DNS' 'Apply the DNS speed test winner' {
    if (-not $script:FastestDns) { Log 'Run the DNS speed test first (or your current DNS is already fastest).'; return }
    Set-DnsPreset $script:FastestDns
} | Out-Null

# ================================================================ HEALTH: benchmark + sleep doctor
$f = $script:PageFlows['Health']
Add-Section $f 'Benchmark (higher is better - compare before/after BIOS or driver changes)'
$benchList = New-DarkList $f @(@('Date', 140), @('CPU 1 core', 105), @('CPU all cores', 115), @('Memory', 95), @('Drive C: read / write', 200), @('Drive G: read / write', 200)) 880 150 $false
function Update-BenchList {
    $benchList.BeginUpdate(); $benchList.Items.Clear()
    foreach ($b in @(Get-Benchmarks) | Sort-Object Date -Descending) {
        $it = New-Object System.Windows.Forms.ListViewItem(('{0:yyyy-MM-dd HH:mm}' -f [datetime]$b.Date))
        [void]$it.SubItems.Add(('{0:N0} MB/s' -f $b.CpuSingle)); [void]$it.SubItems.Add(('{0:N0} MB/s' -f $b.CpuMulti)); [void]$it.SubItems.Add(('{0:N1} GB/s' -f $b.MemGBs))
        foreach ($l in 'C', 'G') {
            $d = if ($b.Disks) { $b.Disks.$l } else { $null }
            [void]$it.SubItems.Add($(if ($d) { '{0:N0} / {1:N0} MB/s' -f $d.Read, $d.Write } else { '-' }))
        }
        [void]$benchList.Items.Add($it)
    }
    $benchList.EndUpdate()
}
Add-Tool $f 'Run benchmark' 'CPU, memory, drives (~30 s)' {
    if (-not $IsAdmin) { Log 'Drive speeds need admin - this run measures CPU and memory only.' }
    $prev = @(Get-Benchmarks) | Select-Object -Last 1
    Start-Background 'Benchmark (keep the PC idle)' $BenchmarkWork @($IsAdmin) {
        param($o)
        $r = $o | Where-Object { $_ -isnot [string] } | Select-Object -Last 1
        if (-not $r) { Log 'Benchmark failed.'; return }
        Save-Benchmark $r
        Log ('CPU 1 core: {0:N0} MB/s   CPU all cores: {1:N0} MB/s   Memory: {2:N1} GB/s' -f $r.CpuSingle, $r.CpuMulti, $r.MemGBs)
        foreach ($k in $r.Disks.Keys) { Log ('Drive {0}: read {1:N0} MB/s, write {2:N0} MB/s' -f $k, $r.Disks[$k].Read, $r.Disks[$k].Write) }
        if ($prev) { Log ('Compared with last run: CPU all cores {0:+0;-0}%, memory {1:+0;-0}%' -f (100 * ($r.CpuMulti / $prev.CpuMulti - 1)), (100 * ($r.MemGBs / $prev.MemGBs - 1))) }
        Update-BenchList
    }
} -Primary -Width 210 | Out-Null
[void]$script:AfterShown.Add({ Update-BenchList })
Add-Section $f 'Sleep & wake'
Add-Tool $f 'Sleep & wake doctor' 'What wakes the PC / blocks sleep' { Invoke-SleepDoctor } | Out-Null
Add-Tool $f 'Stop a device waking the PC' 'e.g. a mouse that wakes it' {
    $dev = Get-WakeDevices
    if (-not $dev) { Log 'No devices are allowed to wake the PC.'; return }
    foreach ($d in Show-Chooser 'Tick devices that should NOT wake the PC' $dev 'Stop these waking the PC') { Disable-DeviceWake $d }
} | Out-Null

# ================================================================ STORAGE: disk map
$f = $script:PageFlows['Storage']
Add-Section $f 'Visual'
function Show-DiskMap([string]$Root) {
    $w = New-Object System.Windows.Forms.Form
    $w.Text = "Disk map - $Root"; $w.Size = New-Object System.Drawing.Size(1150, 780); $w.StartPosition = 'CenterParent'
    $w.BackColor = $C.Bg; $w.ForeColor = $C.Text; $w.Font = New-Font 10
    if ($form.Icon) { $w.Icon = $form.Icon }
    $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 46
    $up = New-Object System.Windows.Forms.Button
    $up.Text = 'Up'; $up.Size = New-Object System.Drawing.Size(70, 32); $up.Location = New-Object System.Drawing.Point(10, 7)
    $up.FlatStyle = 'Flat'; $up.BackColor = $C.Panel; $up.ForeColor = $C.Text; $up.FlatAppearance.BorderSize = 0
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $true; $lbl.Location = New-Object System.Drawing.Point(92, 13); $lbl.Text = "Scanning $Root ... (big drives take a minute)"; $lbl.UseMnemonic = $false
    $top.Controls.AddRange(@($up, $lbl))
    $canvas = New-Object System.Windows.Forms.PictureBox; $canvas.Dock = 'Fill'; $canvas.BackColor = $C.Bg
    $w.Controls.Add($canvas); $w.Controls.Add($top)
    $tip = New-Object System.Windows.Forms.ToolTip
    $st = @{ Map = $null; Node = $Root; Rects = @(); Hover = -1; Win = $w; Canvas = $canvas; Label = $lbl; Tip = $tip; LastTip = '' }
    $w.Tag = $st

    $draw = {
        param($st)
        $cv = $st.Canvas; if (-not $st.Map -or $cv.Width -lt 50 -or $cv.Height -lt 50) { return }
        $m = $st.Map; $node = $st.Node
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($k in $m.Kids[$node]) { $items.Add([pscustomobject]@{ Name = (Split-Path $k -Leaf); Path = $k; Bytes = [double]$m.Size[$k]; Dir = $true }) }
        if ($m.OwnFiles[$node] -gt 0) { $items.Add([pscustomobject]@{ Name = '(files in this folder)'; Path = $node; Bytes = [double]$m.OwnFiles[$node]; Dir = $false }) }
        $sorted = @($items | Where-Object Bytes -gt 0 | Sort-Object Bytes -Descending)
        if ($sorted.Count -gt 60) {
            $rest = $sorted[60..($sorted.Count - 1)]
            $sorted = @($sorted[0..59]) + [pscustomobject]@{ Name = "($($rest.Count) smaller items)"; Path = $node; Bytes = [double](($rest | Measure-Object Bytes -Sum).Sum); Dir = $false }
        }
        $bmp = New-Object System.Drawing.Bitmap $cv.Width, $cv.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear($C.Bg); $g.TextRenderingHint = 'ClearTypeGridFit'
        $area = New-Object System.Drawing.RectangleF(8, 4, ($cv.Width - 16), ($cv.Height - 12))
        $rects = [HallowDiskMap]::Layout([double[]]@($sorted | ForEach-Object Bytes), $area)
        $font = New-Font 9; $fontB = New-Font 9.5 'Bold'
        $sf = New-Object System.Drawing.StringFormat; $sf.FormatFlags = 'NoWrap'; $sf.Trimming = 'EllipsisCharacter'
        $st.Rects = @()
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $r = $rects[$i]; $it = $sorted[$i]
            $inner = New-Object System.Drawing.RectangleF(($r.X + 1), ($r.Y + 1), [math]::Max(0.0, $r.Width - 2), [math]::Max(0.0, $r.Height - 2))   # 2px surface gap between tiles
            $fill = if (-not $it.Dir) { $C.PanelHi } elseif ($i -eq $st.Hover) { RGB 92 158 236 } else { $ChartBlue }
            $g.FillRectangle((New-Object System.Drawing.SolidBrush $fill), $inner)
            if ($inner.Width -gt 70 -and $inner.Height -gt 34) {
                $tr = New-Object System.Drawing.RectangleF(($inner.X + 6), ($inner.Y + 4), ($inner.Width - 10), 18)
                $g.DrawString($it.Name, $fontB, [System.Drawing.Brushes]::White, $tr, $sf)
                $tr2 = New-Object System.Drawing.RectangleF(($inner.X + 6), ($inner.Y + 20), ($inner.Width - 10), 16)
                if ($inner.Height -gt 40) { $g.DrawString((Format-Size $it.Bytes), $font, (New-Object System.Drawing.SolidBrush (RGB 230 236 248)), $tr2, $sf) }
            }
            $st.Rects += [pscustomobject]@{ R = $r; Item = $it }
        }
        $g.Dispose()
        if ($cv.Image) { $cv.Image.Dispose() }
        $cv.Image = $bmp
        $st.Label.Text = "{0}   -   {1}   (click a blue box to open it, right-click to show in Explorer)" -f $node, (Format-Size $m.Size[$node])
    }
    $st.Draw = $draw
    $canvas.Add_Resize({ $s2 = $this.FindForm().Tag; & $s2.Draw $s2 })
    $canvas.Add_MouseMove({
        param($s, $e); $s2 = $this.FindForm().Tag; $hit = -1
        for ($i = 0; $i -lt $s2.Rects.Count; $i++) { if ($s2.Rects[$i].R.Contains($e.X, $e.Y)) { $hit = $i; break } }
        if ($hit -ne $s2.Hover) {
            $s2.Hover = $hit; & $s2.Draw $s2
            if ($hit -ge 0) { $it = $s2.Rects[$hit].Item; $s2.Tip.SetToolTip($this, ("{0}`n{1}" -f $it.Path, (Format-Size $it.Bytes))) }
        }
    })
    $canvas.Add_MouseClick({
        param($s, $e); $s2 = $this.FindForm().Tag
        $hit = $s2.Rects | Where-Object { $_.R.Contains($e.X, $e.Y) } | Select-Object -First 1
        if (-not $hit) { return }
        if ($e.Button -eq 'Right') { Start-Process explorer.exe "/select,`"$($hit.Item.Path)`""; return }
        if ($hit.Item.Dir -and $s2.Map.Kids.ContainsKey($hit.Item.Path)) { $s2.Node = $hit.Item.Path; $s2.Hover = -1; & $s2.Draw $s2 }
    })
    $up.Add_Click({
        $s2 = $this.FindForm().Tag
        $parent = Split-Path $s2.Node
        if ($parent -and $s2.Map -and $s2.Map.Size.ContainsKey($parent)) { $s2.Node = $parent; $s2.Hover = -1; & $s2.Draw $s2 }
    })
    [void]$w.Show($form)
    $script:DiskMapWindow = $st
    Start-Background "Disk map scan of $Root" { param($r) $m = New-Object HallowDiskMap; [void]$m.Scan($r); $m } @($Root) {
        param($o)
        $st2 = $script:DiskMapWindow
        $st2.Map = $o | Where-Object { $_ -is [HallowDiskMap] } | Select-Object -First 1
        if ($st2.Map) { & $st2.Draw $st2; Log ("Disk map: {0:N0} files, {1}" -f $st2.Map.Files, (Format-Size $st2.Map.Size[$st2.Node])) }
    }
}
Add-Tool $f 'Disk map' 'See what fills the drive, visually' {
    $root = [string]$where.SelectedItem
    if ($root.Length -eq 3) { Log "Mapping a whole drive takes 1-3 minutes - the window fills in when it's done." }
    Show-DiskMap $root
} -Primary | Out-Null

# ================================================================ PAGE: TWEAKS
$f = Add-Page 'Tweaks' ([char]0x2699) 'Privacy, quality-of-life, debloat, startup apps and background services'
$script:TweakBoxes = @()
$script:TweakNow = @{}      # checkbox -> what the PC is actually set to
$script:TweakFont = New-Font 9.5
# Each tweak is a checkbox drawn as a toggle switch: green = on, grey = off.
# A yellow ring + "not applied" means the switch was flipped but Apply hasn't been clicked yet.
$script:TweakPaint = {
    param($s, $e)
    $g = $e.Graphics; $g.Clear($s.Parent.BackColor)
    $pending = $script:TweakNow.ContainsKey($s) -and ($s.Checked -ne $script:TweakNow[$s])
    Draw-Switch $g 2 ([int](($s.Height - 22) / 2)) $s.Checked -Pending:$pending -Enabled:$s.Enabled
    $tx = 52; $tw = $s.Width - $tx - $(if ($pending) { 78 } else { 4 })
    $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis, NoPrefix'
    $tc = $(if ($s.Tag.Admin -and -not $IsAdmin) { $C.Muted } else { $C.Text })
    [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $script:TweakFont, (New-Object System.Drawing.Rectangle($tx, 0, $tw, $s.Height)), $tc, $flags)
    if ($pending) { [System.Windows.Forms.TextRenderer]::DrawText($g, 'not applied', $script:TweakFont, (New-Object System.Drawing.Rectangle(($s.Width - 76), 0, 76, $s.Height)), $C.Warn, $flags) }
    if ($s.Focused -and $s.ShowFocusCues) { [System.Windows.Forms.ControlPaint]::DrawFocusRectangle($g, (New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height))) }
}
$lastGroup = ''
foreach ($t in $Tweaks) {
    if ($t.Group -ne $lastGroup) { Add-Section $f $t.Group; $lastGroup = $t.Group }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $t.Name; $cb.Tag = $t; $cb.Width = 430; $cb.Height = 32; $cb.ForeColor = $C.Text; $cb.UseMnemonic = $false
    $cb.Margin = New-Object System.Windows.Forms.Padding(2, 0, 10, 0); $cb.Cursor = [System.Windows.Forms.Cursors]::Hand
    $cb.Add_Paint($script:TweakPaint)
    $tips.SetToolTip($cb, "$($t.Name)`nGreen = on, grey = off. Flip it, then click Apply changes.")
    $f.Controls.Add($cb); $script:TweakBoxes += $cb
}
function Update-TweakBoxes {
    foreach ($cb in $script:TweakBoxes) { $on = [bool](Test-Tweak $cb.Tag); $script:TweakNow[$cb] = $on; $cb.Checked = $on; $cb.Invalidate() }
}
Add-Note $f 'Green = on right now, grey = off. Flip switches, then click Apply changes (yellow = not applied yet). Undo = Windows defaults.' | Out-Null
Add-Tool $f 'Apply changes' 'Apply the switches above' {
    $changed = 0; $explorer = $false
    foreach ($cb in $script:TweakBoxes) {
        $on = Test-Tweak $cb.Tag
        if ($cb.Checked -ne $on) { Set-Tweak $cb.Tag $cb.Checked; $changed++; if ($cb.Tag.Id -in 'ext', 'hidden', 'classicmenu', 'endtask', 'thispc', 'startrec', 'copilot', 'bing', 'taskview', 'searchicon', 'startleft', 'seconds', 'widgets') { $explorer = $true } }
    }
    if (-not $changed) { Log 'Nothing changed.'; return }
    Update-TweakBoxes
    if ($explorer -and (Confirm-Action 'Restart Explorer now so the changes show? (Your taskbar blinks for a second.)')) { Restart-Explorer }
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Undo all' 'Back to Windows defaults' {
    if (-not (Confirm-Action 'Put every switch on this page back to the Windows default?')) { return }
    foreach ($cb in $script:TweakBoxes) { if (Test-Tweak $cb.Tag) { Set-Tweak $cb.Tag $false } }
    Update-TweakBoxes
} -Width 210 | Out-Null
[void]$script:AfterShown.Add({ Update-TweakBoxes })

Add-Section $f 'Who used your camera, microphone or location'
Add-Tool $f 'Show history' 'Which apps, and when (read-only)' {
    $camList.Items.Clear()
    $rows = @(Get-DeviceAccessHistory | Sort-Object Last -Descending | Group-Object Device, App | ForEach-Object { $_.Group[0] } | Sort-Object Last -Descending)
    foreach ($r in $rows) {
        $li = New-Object System.Windows.Forms.ListViewItem($r.Device)
        [void]$li.SubItems.Add($r.App)
        [void]$li.SubItems.Add($(if ($r.InUse) { 'IN USE NOW' } else { '{0:yyyy-MM-dd HH:mm}' -f $r.Last }))
        [void]$li.SubItems.Add($(if ($r.Seconds -ge 60) { '{0:N0} min' -f ($r.Seconds / 60) } elseif ($r.Seconds) { "$($r.Seconds) s" } else { '' }))
        [void]$li.SubItems.Add($r.Path)
        $li.ToolTipText = $r.Path
        $li.ForeColor = $(if ($r.InUse) { $C.Bad } elseif ($r.Last -gt (Get-Date).AddDays(-1)) { $C.Warn } else { $C.Text })
        [void]$camList.Items.Add($li)
    }
    $now = @($rows | Where-Object InUse)
    Log ("{0} app(s) have used your camera, mic or location.{1}" -f @($rows.App | Select-Object -Unique).Count, $(if ($now) { " In use right now: $(($now | ForEach-Object { "$($_.App) ($($_.Device))" }) -join ', ')" } else { ' Nothing is using them right now.' }))
} -Primary | Out-Null
Add-Tool $f 'Camera & mic permissions' 'Windows settings to block apps' { Start-Process 'ms-settings:privacy-webcam'; Log 'Opened camera permissions (Microphone and Location are in the same list on the left).' } | Out-Null
$camList = New-DarkList $f @(@('Device', 90), @('App', 190), @('Last used', 130), @('For', 70), @('Where', 370)) 860 170 $false
$camList.ShowItemToolTips = $true; $f.SetFlowBreak($camList, $true)

Add-Section $f 'Privacy clean - wipe your activity traces'
Add-Note $f 'Clears recent files, jump lists, Explorer search/address history, the Run box and clipboard history. Your actual files are not touched.' | Out-Null
Add-Tool $f 'Privacy clean' 'Clear recent-activity traces' {
    if (-not (Confirm-Action "Clear these traces?`n`n  - Recent files list and Quick Access recents`n  - Jump lists (includes items you pinned in them)`n  - File Explorer search, address bar and Run box history`n  - Clipboard history (pinned clips are kept)`n`nYour actual files are not touched. This can't be undone.")) { return }
    Invoke-PrivacyClean
} -Primary | Out-Null

Add-Section $f 'Debloat - remove preinstalled apps (reinstallable from the Store)'
$bloatList = New-Object System.Windows.Forms.CheckedListBox
$bloatList.Size = New-Object System.Drawing.Size(566, 200); $bloatList.CheckOnClick = $true
$bloatList.BackColor = $C.Panel; $bloatList.ForeColor = $C.Text; $bloatList.BorderStyle = 'None'
$bloatList.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 10)
$f.Controls.Add($bloatList)
$script:BloatItems = @()
function Update-BloatList {
    $bloatList.Items.Clear(); $script:BloatItems = @(Get-InstalledBloat)
    foreach ($b in $script:BloatItems) { [void]$bloatList.Items.Add(("{0}{1}" -f $b.Name, $(if ($b.Recommended) { '   (safe to remove)' } else { '   (you may use this)' })), $false) }
    if (-not $script:BloatItems) { [void]$bloatList.Items.Add('Nothing to remove - no known bloat apps installed.') }
}
$bside = New-Object System.Windows.Forms.FlowLayoutPanel
$bside.FlowDirection = 'TopDown'; $bside.Size = New-Object System.Drawing.Size(290, 222); $bside.WrapContents = $false
$f.Controls.Add($bside)
Add-Tool $bside 'Tick the safe ones' 'Select apps marked safe to remove' {
    for ($i = 0; $i -lt $script:BloatItems.Count; $i++) { $bloatList.SetItemChecked($i, [bool]$script:BloatItems[$i].Recommended) }
} | Out-Null
Add-Tool $bside 'Remove ticked apps' 'Uninstall for your account' {
    $sel = @(); foreach ($i in $bloatList.CheckedIndices) { if ($i -lt $script:BloatItems.Count) { $sel += $script:BloatItems[$i] } }
    if (-not $sel) { Log 'Tick some apps first.'; return }
    if (Confirm-Action ("Remove these apps?`n`n" + (($sel | ForEach-Object Name) -join "`n") + "`n`nYou can reinstall any of them from the Microsoft Store.")) { Remove-Bloat $sel; Update-BloatList }
} -Primary | Out-Null
Add-Tool $bside 'Refresh' 'Re-check installed apps' { Update-BloatList } | Out-Null

Add-Section $f 'Startup apps (ticked = starts with Windows)'
$startList = New-DarkList $f @(@('Name', 190), @('Where', 180), @('RAM now', 70), @('Command', 430)) 880 220 $true
function Update-StartList {
    $startList.BeginUpdate(); $startList.Items.Clear()
    foreach ($s in Get-StartupItems | Sort-Object Source, Name) {
        $it = New-Object System.Windows.Forms.ListViewItem($s.Name)
        [void]$it.SubItems.Add($s.Source); [void]$it.SubItems.Add($(if ($s.MB) { "$($s.MB) MB" } else { '' })); [void]$it.SubItems.Add($s.Command)
        $it.Tag = $s; $it.Checked = [bool]$s.Enabled
        [void]$startList.Items.Add($it)
    }
    $startList.EndUpdate()
}
Add-Tool $f 'Apply ticks' 'Turn startup apps on/off' {
    $n = 0
    foreach ($it in $startList.Items) { if ($it.Checked -ne [bool]$it.Tag.Enabled) { Set-StartupItem $it.Tag $it.Checked; $n++ } }
    if (-not $n) { Log 'No startup changes.' } else { Log "$n startup change(s) applied - they take effect next time you sign in." }
    Update-StartList
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Start 1 min after boot' 'Delay the selected app' {
    if (-not $startList.SelectedItems.Count) { Log 'Click a startup app first.'; return }
    Set-StartupDelayed $startList.SelectedItems[0].Tag; Update-StartList
} -Width 210 | Out-Null
Add-Tool $f 'Remove delay' 'Undo a Hallow delayed start' {
    if (-not $startList.SelectedItems.Count -or $startList.SelectedItems[0].Tag.Source -ne 'Delayed by Hallow') { Log "Click a 'Delayed by Hallow' entry first."; return }
    Remove-StartupDelay $startList.SelectedItems[0].Tag; Update-StartList
} -Width 210 | Out-Null
Add-Tool $f 'Refresh' 'Re-read startup apps' { Update-StartList } -Width 210 | Out-Null

Add-Section $f 'Background services (not from Microsoft)'
$svcList = New-DarkList $f @(@('Service', 250), @('Company', 170), @('Starts', 70), @('Now', 70), @('Suggestion', 300)) 880 220 $false
function Update-SvcList {
    $svcList.BeginUpdate(); $svcList.Items.Clear()
    foreach ($s in Get-ThirdPartyServices | Sort-Object @{ e = { -not $_.Suggest } }, Display) {
        $it = New-Object System.Windows.Forms.ListViewItem($s.Display)
        [void]$it.SubItems.Add($s.Company); [void]$it.SubItems.Add($s.Start); [void]$it.SubItems.Add($s.State); [void]$it.SubItems.Add($s.Suggest)
        if ($s.Suggest) { $it.ForeColor = $C.Warn }
        $it.Tag = $s; [void]$svcList.Items.Add($it)
    }
    $svcList.EndUpdate()
}
function Get-SelectedSvc { if ($svcList.SelectedItems.Count) { $svcList.SelectedItems[0].Tag } else { Log 'Click a service first.'; $null } }
Add-Tool $f 'Set to Manual' 'Starts only when needed' { $s = Get-SelectedSvc; if ($s) { Set-ServiceStart $s.Name 'Manual'; Update-SvcList } } -Primary -Width 210 | Out-Null
Add-Tool $f 'Set to Automatic' 'Starts with Windows' { $s = Get-SelectedSvc; if ($s) { Set-ServiceStart $s.Name 'Auto'; Update-SvcList } } -Width 210 | Out-Null
Add-Tool $f 'Disable' 'Never starts (careful)' {
    $s = Get-SelectedSvc; if (-not $s) { return }
    if (Confirm-Action "Disable $($s.Display)?`n`nThe app that owns it may stop working until you set it back (Restore originals).") { Set-ServiceStart $s.Name 'Disabled'; Update-SvcList }
} -Width 210 | Out-Null
Add-Tool $f 'Restore originals' 'Undo all service changes' { Restore-Services; Update-SvcList } -Width 210 | Out-Null
$script:PageShowHooks['Tweaks'] = { Update-BloatList; Update-StartList; Update-SvcList }

# ================================================================ PAGE: DEV
$f = Add-Page 'Dev' ([char]0x2328) 'Ports, dev caches and the state of your git projects'
Add-Section $f 'Ports'
$portBox = New-Object System.Windows.Forms.TextBox
$portBox.Width = 120; $portBox.Font = New-Font 14; $portBox.Text = '3000'; $portBox.BackColor = $C.Panel; $portBox.ForeColor = $C.Text; $portBox.BorderStyle = 'FixedSingle'
$portBox.Margin = New-Object System.Windows.Forms.Padding(0, 16, 10, 10)
$f.Controls.Add($portBox)
function Get-PortNumber { $n = 0; if ([int]::TryParse($portBox.Text.Trim(), [ref]$n) -and $n -gt 0 -and $n -lt 65536) { $n } else { Log 'Type a port number (1-65535).'; $null } }
Add-Tool $f 'Who is using it?' 'Find the app on this port' { $p = Get-PortNumber; if ($p) { Show-PortOwner $p | Out-Null } } -Width 210 | Out-Null
Add-Tool $f 'Free the port' 'Stop the app holding it' { $p = Get-PortNumber; if ($p) { Stop-PortOwner $p } } -Primary -Width 210 | Out-Null
Add-Tool $f 'All listening ports' 'Every server running locally' {
    Log '===== LISTENING PORTS ====='
    foreach ($l in Get-ListeningPorts | Where-Object { $_.Pid -gt 4 }) { Log ('  {0,5} {1}  {2,-26} PID {3}' -f $l.Port, $l.Proto, $l.Process, $l.Pid) }
} -Width 210 | Out-Null

Add-Section $f 'Dev caches (safe to clear - tools re-download what they need)'
$cacheList = New-DarkList $f @(@('Size', 90), @('Cache', 220), @('Path', 560)) 880 200 $true
Add-Tool $f 'Scan caches' 'npm, Gradle, Unity, pip...' {
    Start-Background 'Dev cache scan' $DevCacheWork (, $DevCacheList) {
        param($o)
        $cacheList.BeginUpdate(); $cacheList.Items.Clear(); $tot = 0
        foreach ($r in $o | Where-Object { $_ -isnot [string] } | Sort-Object Bytes -Descending) {
            $it = New-Object System.Windows.Forms.ListViewItem((Format-Size $r.Bytes)); [void]$it.SubItems.Add($r.Info); [void]$it.SubItems.Add($r.Path)
            $it.Tag = $r.Path; [void]$cacheList.Items.Add($it); $tot += $r.Bytes
        }
        $cacheList.EndUpdate(); Log ("Dev caches: {0} found, {1} total. Tick the ones to clear." -f $cacheList.Items.Count, (Format-Size $tot))
    }
} -Primary -Width 210 | Out-Null
Add-Tool $f 'Clear ticked caches' 'Delete the ticked caches' {
    $paths = @($cacheList.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $paths) { Log 'Tick some caches first.'; return }
    if (-not (Confirm-Action ("Clear these caches?`n`n" + ($paths -join "`n") + "`n`nTools download what they need again next time (first build may be slower)."))) { return }
    foreach ($p in $paths) { Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object { if ($_.PSIsContainer) { cmd.exe /c "rd /s /q `"\\?\$($_.FullName)`"" 2>$null | Out-Null } else { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } } }
    Log "Cleared $($paths.Count) cache(s)."
    foreach ($i in @($cacheList.CheckedItems)) { $cacheList.Items.Remove($i) }
} -Width 210 | Out-Null
Add-Tool $f 'Docker clean-up' 'docker system prune' {
    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) { Log 'Docker is not installed.'; return }
    Start-InNewWindow 'Docker clean-up' 'docker system prune'
} -Width 210 | Out-Null

Add-Section $f 'Git projects'
$gitList = New-DarkList $f @(@('Project', 330), @('Branch', 110), @('Status', 290), @('Last commit', 140)) 880 220 $false
Add-Tool $f 'Scan projects' 'Uncommitted / unpushed work' {
    Start-Background 'Git project scan' $GitScanWork @($env:USERPROFILE) {
        param($o)
        $gitList.BeginUpdate(); $gitList.Items.Clear(); $dirty = 0
        foreach ($l in $o | Where-Object { $_ -is [string] }) { Log $l }
        foreach ($r in $o | Where-Object { $_ -isnot [string] } | Sort-Object @{ e = { $_.State -eq 'clean' } }, Path) {
            $it = New-Object System.Windows.Forms.ListViewItem(($r.Path -replace [regex]::Escape($env:USERPROFILE + '\'), ''))
            [void]$it.SubItems.Add($r.Branch); [void]$it.SubItems.Add($r.State); [void]$it.SubItems.Add($r.Last)
            if ($r.State -ne 'clean') { $it.ForeColor = $C.Warn; $dirty++ }
            $it.Tag = $r; [void]$gitList.Items.Add($it)
        }
        $gitList.EndUpdate(); Log ("Git: {0} projects, {1} need attention (yellow)." -f $gitList.Items.Count, $dirty)
    }
} -Primary -Width 210 | Out-Null
function Get-SelectedRepo { if ($gitList.SelectedItems.Count) { $gitList.SelectedItems[0].Tag.Path } else { Log 'Click a project first.'; $null } }
Add-Tool $f 'Open folder' 'In Explorer' { $p = Get-SelectedRepo; if ($p) { Start-Process explorer.exe $p } } -Width 210 | Out-Null
Add-Tool $f 'Open terminal' 'Terminal in that folder' {
    $p = Get-SelectedRepo; if (-not $p) { return }
    if (Get-Command wt.exe -ErrorAction SilentlyContinue) { Start-Process wt.exe -ArgumentList @('-d', "`"$p`"") } else { Start-Process powershell.exe -WorkingDirectory $p }
} -Width 210 | Out-Null
Add-Tool $f 'Open in VS Code' 'code .' {
    $p = Get-SelectedRepo; if (-not $p) { return }
    if (Get-Command code -ErrorAction SilentlyContinue) { Start-Process code -ArgumentList "`"$p`"" -WindowStyle Hidden } else { Log 'VS Code (code) is not on this PC.' }
} -Width 210 | Out-Null
