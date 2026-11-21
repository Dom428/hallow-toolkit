<#
  Hallow Toolkit - the Hallow family apps (Mixer, Hub, Vault, Overlay, Remote, Clips, Keys, Guard, Assist, Shield):
  installed or not, running or not, newer release on GitHub, and installing / updating them. No window code.
  Dot-sourced by HallowCore.ps1. Each app installs per user (no admin) with its own installer from its own GitHub
  release; nothing is downloaded until you click Install or Update. Hallow Shield (v5.15) is a browser extension, not
  a program: the toolkit finds it in Chrome / Edge / Brave / Opera (read-only) and links to its release page and
  install steps.
#>

$FamilyApps = @(
    [pscustomobject]@{ Name = 'Mixer';   Icon = 'sliders';         Desc = 'Per-app volume mixer: game, chat, music and media faders' }
    [pscustomobject]@{ Name = 'Hub';     Icon = 'gamepad';         Desc = 'All your games in one place, with playtime, presets and game sessions' }
    [pscustomobject]@{ Name = 'Vault';   Icon = 'box-archive';     Desc = 'Backs up your game saves when a game closes and once a day' }
    [pscustomobject]@{ Name = 'Overlay'; Icon = 'window-maximize'; Desc = 'See-through stats panel over your games, anti-cheat safe' }
    [pscustomobject]@{ Name = 'Remote';  Icon = 'mobile-screen';   Desc = 'Your phone as a remote for Mixer, Hub and the toolkit' }
    [pscustomobject]@{ Name = 'Clips';   Icon = 'film';            Desc = 'Instant replay: Ctrl+Alt+S saves the last moments of your game' }
    [pscustomobject]@{ Name = 'Keys';    Icon = 'key';             Desc = 'Password manager that stays on your PC, with your phone as a key' }
    [pscustomobject]@{ Name = 'Guard';   Icon = 'shield-halved';   Desc = 'Safety center on top of Microsoft Defender: scans, score and tips' }
    [pscustomobject]@{ Name = 'Assist';  Icon = 'handshake-angle'; Desc = 'Remote help: let a friend see and fix your PC, only when you say so' }
    [pscustomobject]@{ Name = 'Shield';  Icon = 'puzzle-piece';    Desc = 'Browser extension: blocks ads, trackers, YouTube ads and cookie banners'; Kind = 'Extension' }
)
function Get-FamilyExe([string]$App) { Join-Path $env:LOCALAPPDATA "Programs\Hallow $App\Hallow$App.exe" }
function Get-FamilyRepo([string]$App) { "Dom428/hallow-$($App.ToLower())" }
function Test-FamilyExtension([string]$App) { [bool](@($FamilyApps | Where-Object { $_.Name -eq $App -and $_.Kind -eq 'Extension' }).Count) }
function Test-FamilyInstalled([string]$App) { if (Test-FamilyExtension $App) { return [bool](@(Find-ShieldInstall).Count) }; Test-Path (Get-FamilyExe $App) }
$ShieldReleaseUrl = 'https://github.com/Dom428/hallow-shield/releases/latest'
$ShieldStepsUrl = 'https://github.com/Dom428/hallow-shield#install'

# ---- Hallow Shield (v5.15): loaded as an unpacked extension in a Chromium browser? Reads each profile's
# (Secure) Preferences - extensions loaded from a folder (location 4 = unpacked, 8 = command line) whose manifest.json is
# named "Hallow Shield". Read-only; nothing else from the browser is looked at or kept. Firefox only loads it as a
# temporary add-on (gone after a restart), so it isn't looked for there. Self-contained (link check runspace).
$ShieldFindWork = {
    param([string]$Local, [string]$Roaming)
    if (-not $Roaming) { $Roaming = [Environment]::GetFolderPath('ApplicationData') }
    $roots = [ordered]@{ 'Chrome' = (Join-Path $Local 'Google\Chrome\User Data'); 'Edge' = (Join-Path $Local 'Microsoft\Edge\User Data')
        'Brave' = (Join-Path $Local 'BraveSoftware\Brave-Browser\User Data'); 'Opera' = (Join-Path $Roaming 'Opera Software\Opera Stable') }
    $found = @{}
    foreach ($b in @($roots.Keys)) {
        $root = $roots[$b]
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $profiles = if ($b -eq 'Opera') { @(Get-Item -LiteralPath $root) } else { @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) }
        foreach ($p in $profiles) {
            foreach ($fn in 'Secure Preferences', 'Preferences') {
                $file = Join-Path $p.FullName $fn
                if (-not (Test-Path -LiteralPath $file)) { continue }
                $j = $null; try { $j = [IO.File]::ReadAllText($file) | ConvertFrom-Json } catch { continue }
                $set = $null; try { $set = $j.extensions.settings } catch { }
                if (-not $set) { continue }
                foreach ($e in $set.PSObject.Properties) {
                    $v = $e.Value
                    if (-not $v -or ($v.location -ne 4 -and $v.location -ne 8) -or -not $v.path) { continue }
                    $mf = Join-Path "$($v.path)" 'manifest.json'
                    if (-not (Test-Path -LiteralPath $mf)) { continue }
                    $m = $null; try { $m = [IO.File]::ReadAllText($mf) | ConvertFrom-Json } catch { continue }
                    if ("$($m.name)" -ne 'Hallow Shield') { continue }
                    $key = "$b|$($p.Name)"; if ($found.ContainsKey($key)) { continue }
                    $off = $false
                    if ($v.PSObject.Properties.Name -contains 'disable_reasons' -and $v.disable_reasons) { $off = @($v.disable_reasons | Where-Object { $_ }).Count -gt 0 }
                    if ($v.PSObject.Properties.Name -contains 'state' -and $v.state -eq 0) { $off = $true }
                    $found[$key] = [pscustomobject]@{ Browser = $b; Profile = $p.Name; Path = "$($v.path)"; Version = "$($m.version)"; Enabled = -not $off }
                }
            }
        }
    }
    @($found.Values | Sort-Object Browser, Profile)
}
function Find-ShieldInstall([string]$Local = $env:LOCALAPPDATA, [string]$Roaming = $env:APPDATA) { @(& $ShieldFindWork $Local $Roaming) }
# what every link check (page, tray, snapshots) is given
function Get-LinkCheckOptions {
    $fc = Get-FamilyCache
    @{ ToolkitCrashDir = $CrashDir; ShieldFind = $ShieldFindWork.ToString(); ShieldLatest = $(if ($fc -and $fc.latest) { "$($fc.latest.Shield)" } else { '' }) }
}
# "v3.12", "3.12.0.0" -> [version] 3.12.0.0 (so tags and file versions compare); $null when there is no number
function ConvertTo-FamilyVersion([string]$Text) {
    $m = [regex]::Match("$Text", '\d+(\.\d+){0,3}')
    if (-not $m.Success) { return $null }
    $p = @($m.Value -split '\.'); while ($p.Count -lt 4) { $p += '0' }
    try { [version]($p -join '.') } catch { $null }
}
function Format-FamilyVersion($V) {
    if (-not $V) { return '' }
    $s = "$($V.Major).$($V.Minor)"
    if ($V.Build -gt 0 -or $V.Revision -gt 0) { $s += ".$($V.Build)" }
    if ($V.Revision -gt 0) { $s += ".$($V.Revision)" }
    $s
}
# Opens an app as you (Explorer starts it, so it never inherits the toolkit's admin rights).
function Open-FamilyApp([string]$App) {
    $exe = Get-FamilyExe $App
    if (-not (Test-Path $exe)) { return $false }
    Start-Process explorer.exe "`"$exe`""; $true
}

# ---- update check: newest release tag per app, cached in family-updates.json, asked at most every few hours.
# Failures are silent (the last known answer is kept).
$FamilyCacheFile = Join-Path $HallowRoot 'family-updates.json'
$FamilyCheckHours = 4
function Get-FamilyCache { if (Test-Path $FamilyCacheFile) { try { Get-Content $FamilyCacheFile -Raw | ConvertFrom-Json } catch { $null } } }
function Test-FamilyCheckDue {
    $fc = Get-FamilyCache
    if (-not $fc -or -not $fc.checked) { return $true }
    try { ((Get-Date) - [datetime]::Parse("$($fc.checked)")).TotalHours -ge $FamilyCheckHours } catch { $true }
}
$FamilyCheckWork = {
    param([string[]]$Apps, [string]$CacheFile)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $old = $null; if (Test-Path $CacheFile) { try { $old = Get-Content $CacheFile -Raw | ConvertFrom-Json } catch { } }
    $latest = [ordered]@{}
    foreach ($a in $Apps) {
        $tag = $null
        try {
            $r = Invoke-RestMethod "https://api.github.com/repos/Dom428/hallow-$($a.ToLower())/releases/latest" -Headers @{ 'User-Agent' = 'HallowToolkit'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 15
            $tag = "$($r.tag_name)" -replace '^[vV]', ''
        } catch { }
        if (-not $tag -and $old -and $old.latest -and $old.latest.$a) { $tag = "$($old.latest.$a)" }
        if ($tag) { $latest[$a] = $tag }
    }
    try { [ordered]@{ checked = (Get-Date).ToString('s'); latest = $latest } | ConvertTo-Json -Depth 4 | Set-Content $CacheFile -Encoding UTF8 } catch { }
    $true
}

# One row per app: installed, version, running, newest known version, update available.
function Get-FamilyStatus {
    $fc = Get-FamilyCache
    foreach ($a in $FamilyApps) {
        $exe = Get-FamilyExe $a.Name
        $where = $null
        if ($a.Kind -eq 'Extension') {
            $sh = @(Find-ShieldInstall); $installed = [bool]$sh.Count; $exe = $null; $ver = $null
            if ($installed) { $ver = @($sh | ForEach-Object { ConvertTo-FamilyVersion $_.Version } | Sort-Object -Descending)[0]; $where = (@($sh | ForEach-Object Browser | Select-Object -Unique) -join ', ') }
        } else {
            $installed = Test-Path $exe
            $ver = $null; if ($installed) { try { $ver = ConvertTo-FamilyVersion (Get-Item $exe).VersionInfo.FileVersion } catch { } }
        }
        $latest = $null; if ($fc -and $fc.latest) { $latest = ConvertTo-FamilyVersion "$($fc.latest.($a.Name))" }
        [pscustomobject]@{
            Name = $a.Name; Title = "Hallow $($a.Name)"; Icon = $a.Icon; Desc = $a.Desc; Exe = $exe; Kind = "$($a.Kind)"; Where = $where
            Installed = $installed; Version = $ver; Latest = $latest
            Running = [bool]($a.Kind -ne 'Extension' -and (Get-Process "Hallow$($a.Name)" -ErrorAction SilentlyContinue))
            Update = [bool]($installed -and $ver -and $latest -and $latest -gt $ver)
        }
    }
}

# ---- install / update (runs in the background when you click Install or Update). Downloads the app's newest
# release zip from its own GitHub repo, checks it against the SHA-256 GitHub reports for it, unpacks it to a temp
# folder and finds its installer. Start-FamilyInstaller then runs that installer as you.
$FamilyInstallWork = {
    param([string]$App)
    $repo = "Dom428/hallow-$($App.ToLower())"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { $r = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'HallowToolkit'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20 }
    catch { return [pscustomobject]@{ Error = "Could not reach GitHub: $($_.Exception.Message)" } }
    $asset = @($r.assets | Where-Object { $_.name -like '*.zip' })[0]
    if (-not $asset) { return [pscustomobject]@{ Error = "The latest Hallow $App release has no download." } }
    $sha = "$($asset.digest)" -replace '^sha256:', ''
    if ($sha -notmatch '^[0-9a-fA-F]{64}$') { return [pscustomobject]@{ Error = "GitHub did not give a checksum for the Hallow $App download - not installed." } }
    $tmp = Join-Path $env:TEMP ("hallow-$($App.ToLower())-" + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'download.zip'
    try { $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'HallowToolkit'; $wc.DownloadFile($asset.browser_download_url, $zip); $wc.Dispose() }
    catch { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; return [pscustomobject]@{ Error = "Download failed: $($_.Exception.Message)" } }
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $sha.ToUpper()) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; return [pscustomobject]@{ Error = "Checksum mismatch - Hallow $App not installed." } }
    try { Expand-Archive $zip (Join-Path $tmp 'x') -Force -ErrorAction Stop } catch { return [pscustomobject]@{ Error = "Could not unpack the download: $($_.Exception.Message)" } }
    $inst = Get-ChildItem (Join-Path $tmp 'x') -Recurse -Filter 'Install.ps1' | Select-Object -First 1
    if (-not $inst) { $inst = Get-ChildItem (Join-Path $tmp 'x') -Recurse -Filter 'INSTALL.bat' | Select-Object -First 1 }
    if (-not $inst) { return [pscustomobject]@{ Error = "The Hallow $App download does not contain an installer." } }
    Get-ChildItem $inst.DirectoryName | Unblock-File -ErrorAction SilentlyContinue
    [pscustomobject]@{ Error = $null; App = $App; Installer = $inst.FullName; Version = ("$($r.tag_name)" -replace '^[vV]', ''); Verified = $true }
}
# Runs the app's own installer as you, not as admin (Explorer starts it). It installs per user, closes the old copy
# if it's running and opens the app when done.
function Start-FamilyInstaller([string]$App, [string]$Installer) {
    $cmd = Join-Path $env:TEMP "hallow-$($App.ToLower())-install.cmd"
    $run = if ($Installer -like '*.ps1') { "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Installer`"" } else { "call `"$Installer`"" }
    Set-Content $cmd @('@echo off', "title Hallow $App - installing", $run, 'timeout /t 3 >nul') -Encoding ASCII
    Start-Process explorer.exe "`"$cmd`""
}

# ================================================================ CHECK LINKS (v5.7)
# One line per check for each installed app: running, its family pipe answers `ping` (and runs the installed version),
# status.json fresh, starts with Windows, Mixer's API answers with its key, Overlay can read FPS / server events,
# Hub hosts the one Hallow icon. Level: good / warn / bad. Fix: start / autostart / open (or none).
# Self-contained (runs in a background runspace). Secrets are never read into the output: the Mixer key is only sent
# to Mixer itself. Older app versions that don't know a command give amber, never red.
# $Opt (tests only): Local, Roaming, RunKey, PipeSuffix, Running (app names treated as running).
$FamilyLinkCheckWork = {
    param([string[]]$Apps, $Opt)
    if (-not $Opt) { $Opt = @{} }
    $local = $(if ($Opt.Local) { $Opt.Local } else { $env:LOCALAPPDATA })
    $roam = $(if ($Opt.Roaming) { $Opt.Roaming } else { $env:APPDATA })
    $runKey = $(if ($Opt.RunKey) { $Opt.RunKey } else { 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' })
    $suffix = "$($Opt.PipeSuffix)"
    $out = New-Object System.Collections.ArrayList
    function Add-Line($App, $Check, $Level, $Text, $Fix) { [void]$out.Add([pscustomobject]@{ App = $App; Check = $Check; Level = $Level; Text = $Text; Fix = $Fix }) }
    function Ver([string]$t) { $m = [regex]::Match("$t", '\d+(\.\d+){0,3}'); if (-not $m.Success) { return $null }; $p = @($m.Value -split '\.'); while ($p.Count -lt 4) { $p += '0' }; try { [version]($p -join '.') } catch { $null } }
    function Short($v) { if (-not $v) { return '?' }; $s = "$($v.Major).$($v.Minor)"; if ($v.Build -gt 0) { $s += ".$($v.Build)" }; $s }
    function Pipe-Name([string]$App) { "HallowFamily.$App.$([Environment]::UserName)$suffix" }
    $pipes = $null; try { $pipes = @([IO.Directory]::GetFiles('\\.\pipe\') | ForEach-Object { $_.Substring(9) }) } catch { }
    function Test-Pipe([string]$App) { if ($null -eq $pipes) { return $true }; $pipes -contains (Pipe-Name $App) }
    # one line out, one line back ($null when nothing came back)
    function Send-Pipe([string]$App, [string]$Line) {
        $pc = New-Object System.IO.Pipes.NamedPipeClientStream('.', (Pipe-Name $App), [System.IO.Pipes.PipeDirection]::InOut)
        try {
            $pc.Connect(1500)
            $b = [Text.Encoding]::UTF8.GetBytes("$Line`n"); $pc.Write($b, 0, $b.Length); $pc.Flush()
            $r = New-Object IO.StreamReader($pc, (New-Object Text.UTF8Encoding($false)))
            $t = $r.ReadLineAsync(); if (-not $t.Wait(3000)) { return $null }
            "$($t.Result)".Trim()
        } catch { $null } finally { try { $pc.Dispose() } catch { } }
    }
    function Is-Running([string]$App) { if ($Opt.Running) { return @($Opt.Running) -contains $App }; [bool](Get-Process "Hallow$App" -ErrorAction SilentlyContinue) }
    # v5.8: "lastCrash" (ISO) in an app's status - amber with Show when it's under 7 days old
    function Test-Crash([string]$App, $Status) {
        if (-not $Status -or $Status.PSObject.Properties.Name -notcontains 'lastCrash' -or -not $Status.lastCrash) { return }
        try { $lc = [datetime]::Parse("$($Status.lastCrash)") } catch { return }
        if (((Get-Date) - $lc).TotalDays -lt 7) { Add-Line $App 'Crash' 'warn' ("Crashed {0:ddd d MMM h:mm tt}" -f $lc) 'crash' }
    }
    # v5.15: Hallow Shield is a browser extension - found through the browsers' own extension list (read-only)
    if ($Apps -contains 'Shield' -and ($Opt.ShieldFind -or $Opt.Shield)) {
        $sh = @()
        if ($Opt.Shield) { $sh = @($Opt.Shield) }   # tests
        else { try { $sh = @(& ([scriptblock]::Create($Opt.ShieldFind)) $local $roam) } catch { } }
        if ($sh.Count) {
            $on = @($sh | Where-Object { $_.Enabled }); $offs = @($sh | Where-Object { -not $_.Enabled })
            if ($on.Count) { Add-Line 'Shield' 'Browser' 'good' ('Loaded in {0} (v{1})' -f (@($on | ForEach-Object { if ($_.Profile -and $_.Profile -ne 'Default' -and $_.Browser -ne 'Opera') { "$($_.Browser) ($($_.Profile))" } else { $_.Browser } } | Select-Object -Unique) -join ', '), (@($on | ForEach-Object Version | Sort-Object -Descending)[0])) $null }
            if ($offs.Count) { Add-Line 'Shield' 'Browser' 'warn' ('Turned off in {0} - switch it back on in the browser''s Extensions page' -f (@($offs | ForEach-Object Browser | Select-Object -Unique) -join ', ')) 'shieldsteps' }
            $lt = $null; if ($Opt.ShieldLatest) { $lt = Ver $Opt.ShieldLatest }
            $have = @($sh | ForEach-Object { Ver $_.Version } | Where-Object { $_ } | Sort-Object -Descending)[0]
            if ($lt -and $have -and $lt -gt $have) { Add-Line 'Shield' 'Update' 'warn' ("Version $(Short $lt) is out (you have $(Short $have)) - unzip it over the same folder, then click reload on Shield's card") 'shieldrelease' }
        }
    }
    if ($Opt.ToolkitCrashDir -and (Test-Path $Opt.ToolkitCrashDir)) {
        $tc = Get-ChildItem $Opt.ToolkitCrashDir -Filter '*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($tc) { Test-Crash 'Toolkit' ([pscustomobject]@{ lastCrash = $tc.LastWriteTime.ToString('s') }) }
    }
    $installed = @{}
    foreach ($a in $Apps) {
        $exe = Join-Path $local "Programs\Hallow $a\Hallow$a.exe"
        if (-not (Test-Path $exe)) { continue }
        $installed[$a] = $true
        $iv = $null; try { $iv = Ver (Get-Item $exe).VersionInfo.FileVersion } catch { }
        $run = Is-Running $a
        if ($run) { Add-Line $a 'Running' 'good' 'Running' $null } else { Add-Line $a 'Running' 'warn' 'Not running' 'start' }
        # starts with Windows: the app's own HKCU Run value "Hallow<App>" ("<exe>" --tray), the same one its Settings switch writes
        $rv = $null; try { $rv = (Get-ItemProperty -Path $runKey -Name "Hallow$a" -ErrorAction Stop)."Hallow$a" } catch { }
        if (-not $rv) { Add-Line $a 'Start with Windows' 'warn' "Doesn't start with Windows" 'autostart' }
        elseif ("$rv" -notlike "*$exe*") { Add-Line $a 'Start with Windows' 'warn' 'Starts with Windows from an old location' 'autostart' }
        else { Add-Line $a 'Start with Windows' 'good' 'Starts with Windows' $null }
        $sf = if ($a -eq 'Clips') { Join-Path $local 'HallowClips\status.json' } else { Join-Path $roam "Hallow$a\status.json" }
        $sj = $null
        if ($run -and (Test-Pipe $a)) { $r2 = Send-Pipe $a 'status'; if ($r2 -like 'ok*') { try { $sj = ($r2 -replace '^ok\s*', '') | ConvertFrom-Json } catch { } } }
        if (-not $sj -and (Test-Path $sf)) { try { $sj = Get-Content $sf -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { } }
        Test-Crash $a $sj
        if (-not $run) { continue }
        # the family pipe
        if (-not (Test-Pipe $a)) { Add-Line $a 'Link' 'warn' 'No link to the other Hallow apps - this version is too old, update it' $null }
        else {
            $r = Send-Pipe $a 'ping'
            if ($null -eq $r) { Add-Line $a 'Link' 'bad' "Its link doesn't answer - close and reopen it" $null }
            elseif ($r -like 'error unknown command*') { Add-Line $a 'Link' 'warn' "Its link doesn't know ping yet - update it" $null }
            elseif ($r -like 'ok*') {
                $pv = $null; try { $pv = Ver ((($r -replace '^ok\s*', '') | ConvertFrom-Json).version) } catch { }
                if ($pv -and $iv -and $pv -ne $iv) { Add-Line $a 'Link' 'warn' "Link answers, but the running copy is $(Short $pv) and $(Short $iv) is installed - close and reopen it" $null }
                else { Add-Line $a 'Link' 'good' "Link answers$(if ($pv) { " (v$(Short $pv))" })" $null }
            } else { Add-Line $a 'Link' 'warn' "Its link gave an odd answer - update it" $null }
        }
        # status.json: written when something changes and at least on start
        if (Test-Path $sf) {
            $t = (Get-Item $sf).LastWriteTime
            try { $u = [datetime]::Parse("$((Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json).updated)"); if ($u -gt $t) { $t = $u } } catch { }
            $age = [int]((Get-Date) - $t).TotalMinutes
            if ($age -le 10) { Add-Line $a 'Status' 'good' 'Status file is fresh' $null } else { Add-Line $a 'Status' 'warn' "Status file last updated $age min ago (fine if nothing changed since)" $null }
        } elseif ($a -ne 'Mixer') { Add-Line $a 'Status' 'warn' 'No status file - this version is too old, update it' $null }
        if ($a -eq 'Mixer') {
            $api = $null; try { $api = Get-Content (Join-Path $roam 'HallowMixer\api.json') -Raw | ConvertFrom-Json } catch { }
            if (-not $api -or -not $api.port) { Add-Line $a 'Mixer API' 'warn' 'Toolkit control is off - turn on "Let Hallow Toolkit control the mixer" in its Settings' 'open' }
            else {
                $code = 0
                try { $rq = [Net.HttpWebRequest]::Create("http://127.0.0.1:$([int]$api.port)/state"); $rq.Headers['X-Hallow-Key'] = "$($api.key)"; $rq.Timeout = 2500; $rs = $rq.GetResponse(); $code = [int]$rs.StatusCode; $rs.Close() }
                catch [Net.WebException] { if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } }
                catch { }
                if ($code -ge 200 -and $code -lt 300) { Add-Line $a 'Mixer API' 'good' 'Mixer API answers with its key' $null }
                elseif ($code -eq 401 -or $code -eq 403) { Add-Line $a 'Mixer API' 'bad' "Mixer API doesn't accept its key - close and reopen Hallow Mixer" $null }
                else { Add-Line $a 'Mixer API' 'warn' "Mixer API doesn't answer - check its Settings" 'open' }
            }
        }
        if ($a -eq 'Guard' -and $sj -and $sj.PSObject.Properties.Name -contains 'score' -and $null -ne $sj.score) {
            # v5.15: Guard's safety score (Guard itself works out what to fix; the toolkit only shows it)
            $sc = [int]$sj.score; $lab = "$($sj.scoreLabel)"
            $txt = "Safety score $sc$(if ($lab) { " - $lab" })$(if ($sj.threats) { ", $($sj.threats) threat(s) in Defender's history" })"
            if ($sc -ge 80) { Add-Line $a 'Safety' 'good' $txt $null } elseif ($sc -ge 50) { Add-Line $a 'Safety' 'warn' "$txt - open Guard to see what to fix" 'open' } else { Add-Line $a 'Safety' 'bad' "$txt - open Guard to see what to fix" 'open' }
        }
        if ($a -eq 'Assist' -and $sj) {
            # v5.15: only whether someone is connected and whether unattended access is on
            if ("$($sj.session)" -eq 'connected') { Add-Line $a 'Session' 'warn' $(if ($sj.helping) { 'You are helping someone right now' } else { 'Someone is connected to this PC right now - Disconnect in Assist if you did not expect it' }) 'open' }
            if ($sj.unattended) { Add-Line $a 'Unattended access' 'warn' 'Unattended access is on - fine on your own PCs, turn it off on anyone else''s' 'open' }
        }
        if ($a -eq 'Overlay') {
            # FPS and the game server come from Windows event tracing; a normal account needs the Performance Log Users group
            $st = $null; if (Test-Path $sf) { try { $st = Get-Content $sf -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { } }
            $etw = $null
            if ($st -and $st.PSObject.Properties.Name -contains 'etw') { $etw = [bool]$st.etw }
            elseif ($st -and $st.PSObject.Properties.Name -contains 'fpsDenied') { $etw = -not [bool]$st.fpsDenied }
            else { try { $etw = [bool](@([Security.Principal.WindowsIdentity]::GetCurrent().Groups | ForEach-Object Value) -contains 'S-1-5-32-559') } catch { } }
            if ($etw) { Add-Line $a 'FPS and server' 'good' 'FPS and game server can be read' $null }
            else { Add-Line $a 'FPS and server' 'warn' "FPS and game server may stay hidden - Windows only lets the Performance Log Users group read them (see Overlay's Settings)" 'open' }
        }
    }
    # one Hallow icon: Hub hosts the tray menu for the family
    if ($installed['Hub'] -and @($installed.Keys | Where-Object { $_ -ne 'Hub' }).Count) {
        if (-not (Is-Running 'Hub')) { Add-Line 'Hub' 'One Hallow icon' 'warn' "Hub isn't running, so each app shows its own tray icon" 'start' }
        else {
            $r = $(if (Test-Pipe 'Hub') { Send-Pipe 'Hub' 'tray-host' })
            if ($r -like 'ok*') {
                $on = $false; try { $on = [bool]((($r -replace '^ok\s*', '') | ConvertFrom-Json).on) } catch { }
                if ($on) { Add-Line 'Hub' 'One Hallow icon' 'good' 'Hub hosts the one Hallow icon' $null }
                else { Add-Line 'Hub' 'One Hallow icon' 'warn' 'One Hallow icon is off in Hub''s Settings' 'open' }
            } else { Add-Line 'Hub' 'One Hallow icon' 'warn' 'This Hub version doesn''t host the Hallow icon yet - update it' $null }
        }
    }
    $out
}
# Fixes for a check line, run as you: start the app, or turn on its own Start with Windows value.
function Invoke-FamilyFix([string]$App, [string]$Fix) {
    if ($Fix -eq 'shieldsteps') { Start-Process $ShieldStepsUrl; return 'Opened Hallow Shield''s install steps (Extensions page, Developer mode, Load unpacked).' }
    if ($Fix -eq 'shieldrelease') { Start-Process $ShieldReleaseUrl; return 'Opened the newest Hallow Shield release - download the zip for your browser and unzip it over the same folder.' }
    if ($Fix -eq 'crash') {   # open the newest crash report in Notepad
        $dir = if ($App -eq 'Toolkit') { $CrashDir } elseif ($App -eq 'Clips') { Join-Path $env:LOCALAPPDATA 'HallowClips\crashes' } else { Join-Path $env:APPDATA "Hallow$App\crashes" }
        $f = Get-ChildItem $dir -Filter '*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $f) { return "No crash report found for Hallow $App." }
        Start-Process notepad.exe "`"$($f.FullName)`""; return "Opened the newest Hallow $App crash report (kept on this PC only)."
    }
    $exe = Get-FamilyExe $App
    if (-not (Test-Path $exe)) { return "Hallow $App is not installed." }
    switch ($Fix) {
        'start' { [void](Open-FamilyApp $App); "Starting Hallow $App." }
        'open' { [void](Open-FamilyApp $App); "Opening Hallow $App - the setting is in its Settings." }
        'autostart' {
            Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name "Hallow$App" -Value "`"$exe`" --tray"
            "Hallow $App now starts with Windows (in the tray), the same as its own Settings switch."
        }
    }
}

# ================================================================ SHARED ACCENT (v5.8)
# %APPDATA%\Hallow\theme.json = {"accent":"#RRGGBB","updated":"..."} - every Hallow app with "Use the Hallow accent" on
# takes its accent colour from it. Written atomically. HALLOW_THEME_FILE points somewhere else (tests only).
$HallowThemeFile = $(if ($env:HALLOW_THEME_FILE) { $env:HALLOW_THEME_FILE } else { Join-Path $env:APPDATA 'Hallow\theme.json' })
$HallowAccents = [ordered]@{ 'Orange' = '#F07820'; 'Purple' = '#8B5CF6'; 'Blue' = '#3B82F6'; 'Cyan' = '#06B6D4'; 'Green' = '#22C55E'; 'Pink' = '#EC4899'; 'Red' = '#EF4444'; 'Gold' = '#EAB308' }
function Get-HallowAccentHex {
    try { $h = "$((Get-Content $HallowThemeFile -Raw -ErrorAction Stop | ConvertFrom-Json).accent)"; if ($h -match '^#[0-9A-Fa-f]{6}$') { return $h.ToUpper() } } catch { }
    $null
}
function ConvertFrom-HexColor([string]$Hex) { [System.Drawing.Color]::FromArgb([Convert]::ToInt32($Hex.Substring(1, 2), 16), [Convert]::ToInt32($Hex.Substring(3, 2), 16), [Convert]::ToInt32($Hex.Substring(5, 2), 16)) }
# v5.16: theme.json keeps every field it already has (other apps may add their own); only the ones given change.
function Get-HallowThemeData {
    $d = [ordered]@{}
    try {
        $j = Get-Content $HallowThemeFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($j) { foreach ($p in $j.PSObject.Properties) { $d[$p.Name] = $p.Value } }
    } catch { }
    $d
}
function Save-HallowThemeData([System.Collections.IDictionary]$Changes) {
    $d = Get-HallowThemeData
    foreach ($k in $Changes.Keys) { $d[$k] = $Changes[$k] }
    $d['updated'] = (Get-Date).ToString('s')
    New-Item -ItemType Directory -Force (Split-Path $HallowThemeFile) | Out-Null
    $json = [pscustomobject]$d | ConvertTo-Json -Compress -Depth 6
    $tmp = "$HallowThemeFile.tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path $HallowThemeFile) { [IO.File]::Replace($tmp, $HallowThemeFile, [NullString]::Value) } else { [IO.File]::Move($tmp, $HallowThemeFile) }
}
function Set-HallowAccent([string]$Hex) {
    if ($Hex -notmatch '^#[0-9A-Fa-f]{6}$') { throw "Not a colour: $Hex" }
    Save-HallowThemeData @{ accent = $Hex.ToUpper() }
}

# ================================================================ LIGHT / DARK MODE (v5.16)
# theme.json "mode": "dark" | "light" | "system" (missing or anything else = "dark", the look before 5.16).
# "system" follows Windows: HKCU\...\Themes\Personalize AppsUseLightTheme (1 = light). Each app can override it
# (the toolkit's own: Tools > Theme > Look). The toolkit owns the family switch (Hallow tab).
$HallowModes = [ordered]@{ 'light' = 'Light'; 'dark' = 'Dark'; 'system' = 'Same as Windows' }
function Get-HallowMode {
    $m = "$((Get-HallowThemeData)['mode'])".Trim().ToLower()
    if ($HallowModes.Contains($m)) { $m } else { 'dark' }
}
function Set-HallowMode([string]$Mode) {
    $Mode = "$Mode".Trim().ToLower()
    if (-not $HallowModes.Contains($Mode)) { throw "Not a mode: $Mode" }
    Save-HallowThemeData @{ mode = $Mode }
}
# Windows "apps use light theme" - read only, never changed. $null when it can't be read (treated as dark).
function Get-WindowsAppsLight([string]$Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') {
    try { $v = (Get-ItemProperty -LiteralPath $Key -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme; return ([int]$v -eq 1) } catch { $null }
}
# light or dark for one app: its own override (Light / Dark) wins, else the family mode; "system" asks $SystemLight
# (a scriptblock, so tests can pass a fake). Returns 'light' or 'dark'.
function Resolve-HallowLook([string]$Override, [string]$FamilyMode, [scriptblock]$SystemLight = { Get-WindowsAppsLight }) {
    $o = "$Override".Trim().ToLower()
    if ($o -eq 'light' -or $o -eq 'dark') { return $o }
    $m = "$FamilyMode".Trim().ToLower()
    if ($m -eq 'light') { return 'light' }
    if ($m -eq 'system') { if ([bool](& $SystemLight)) { return 'light' } else { return 'dark' } }
    'dark'
}
# WCAG contrast between two colours (1..21)
function Get-RelLuminance([System.Drawing.Color]$C) {
    $f = { param($v) $v = $v / 255.0; if ($v -le 0.03928) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) } }
    0.2126 * (& $f $C.R) + 0.7152 * (& $f $C.G) + 0.0722 * (& $f $C.B)
}
function Get-ContrastRatio([System.Drawing.Color]$A, [System.Drawing.Color]$B) {
    $la = Get-RelLuminance $A; $lb = Get-RelLuminance $B
    ([math]::Max($la, $lb) + 0.05) / ([math]::Min($la, $lb) + 0.05)
}
# the accent darkened in HSL (hue and saturation kept) until text in it reads on white (>= 4.5:1)
function Get-LightTextAccent([System.Drawing.Color]$Accent, [double]$Min = 4.5, [System.Drawing.Color]$On = [System.Drawing.Color]::White) {
    $white = $On   # the surface the text sits on (white unless given)
    if ((Get-ContrastRatio $Accent $white) -ge $Min) { return $Accent }
    $h = $Accent.GetHue() / 360.0; $s = [double]$Accent.GetSaturation(); $l = [double]$Accent.GetBrightness()
    $toRgb = {
        param($h, $s, $l)
        if ($s -eq 0) { $v = [int][math]::Round($l * 255); return [System.Drawing.Color]::FromArgb($v, $v, $v) }
        $q = if ($l -lt 0.5) { $l * (1 + $s) } else { $l + $s - $l * $s }; $p = 2 * $l - $q
        $hue = { param($p, $q, $t) if ($t -lt 0) { $t += 1 }; if ($t -gt 1) { $t -= 1 }
            if ($t -lt 1 / 6) { return $p + ($q - $p) * 6 * $t }; if ($t -lt 0.5) { return $q }; if ($t -lt 2 / 3) { return $p + ($q - $p) * (2 / 3 - $t) * 6 }; $p }
        [System.Drawing.Color]::FromArgb([int][math]::Round(255 * (& $hue $p $q ($h + 1 / 3))), [int][math]::Round(255 * (& $hue $p $q $h)), [int][math]::Round(255 * (& $hue $p $q ($h - 1 / 3))))
    }
    $c = $Accent
    while ($l -gt 0) {
        $l = [math]::Max(0.0, $l - 0.01); $c = & $toRgb $h $s $l
        if ((Get-ContrastRatio $c $white) -ge $Min) { break }
    }
    $c
}
# text on a filled accent button: whichever of dark text / white reads better
function Get-AccentFillText([System.Drawing.Color]$Accent) {
    $dark = [System.Drawing.Color]::FromArgb(0x1E, 0x1A, 0x26); $white = [System.Drawing.Color]::White
    if ((Get-ContrastRatio $Accent $dark) -ge (Get-ContrastRatio $Accent $white)) { $dark } else { $white }
}

# the fill for accent buttons in light mode: the real accent, unless neither text colour reaches 4.5:1 on it (e.g. violet
# #8B5CF6) - then the darkened text accent, with white text
function Get-LightAccentFill([System.Drawing.Color]$Accent) {
    if ((Get-ContrastRatio $Accent (Get-AccentFillText $Accent)) -ge 4.5) { $Accent } else { Get-LightTextAccent $Accent }
}
# ================================================================ CRASH REPORTS (v5.8)
# <toolkit folder>\crashes\<yyyy-MM-dd HH-mm-ss>.txt: version, Windows, time, the error and where it happened. Never settings,
# keys, links or file contents (web addresses in messages are blanked). Newest 20 kept. Nothing is sent anywhere.
$CrashDir = Join-Path $HallowRoot 'crashes'
function Write-HallowCrash($Err, [string]$Part = 'Hallow Toolkit') {
    try {
        New-Item -ItemType Directory -Force $CrashDir | Out-Null
        $ex = if ($Err -is [System.Management.Automation.ErrorRecord]) { $Err.Exception } else { $Err }
        $os = [Environment]::OSVersion.VersionString
        try { $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop; $os = "$($cv.ProductName) $($cv.DisplayVersion) (build $($cv.CurrentBuild))" } catch { }
        $L = New-Object System.Collections.Generic.List[string]
        $L.Add("App: $Part"); $L.Add("Version: $AppVersion"); $L.Add("Windows: $os"); $L.Add("Time: $((Get-Date).ToString('s'))"); $L.Add('')
        if ($Err -is [System.Management.Automation.ErrorRecord]) {
            if ($Err.InvocationInfo) { $L.Add("Where: $(Split-Path -Leaf "$($Err.InvocationInfo.ScriptName)") line $($Err.InvocationInfo.ScriptLineNumber)") }
            if ($Err.ScriptStackTrace) { $L.Add('Script stack:'); $L.Add("$($Err.ScriptStackTrace)"); $L.Add('') }
        }
        $e = $ex; $n = 0
        while ($e -and $n -lt 6) { $L.Add("$(if ($n) { 'Inner exception' } else { 'Exception' }): $($e.GetType().FullName)"); $L.Add("Message: $($e.Message)"); if ($e.StackTrace) { $L.Add("$($e.StackTrace)") }; $L.Add(''); $e = $e.InnerException; $n++ }
        $text = ($L -join "`r`n") -replace 'https?://\S+', '(link removed)'
        $file = Join-Path $CrashDir ((Get-Date -Format 'yyyy-MM-dd HH-mm-ss') + '.txt'); $i = 1
        while (Test-Path $file) { $file = Join-Path $CrashDir ((Get-Date -Format 'yyyy-MM-dd HH-mm-ss') + "-$i.txt"); $i++ }
        [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
        Get-ChildItem $CrashDir -Filter '*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 | Remove-Item -Force -ErrorAction SilentlyContinue
        Log "Crash report saved in $CrashDir"
        $file
    } catch { }
}
# the newest crash report not shown yet (shown once per file)
function Get-NewCrashReport {
    $f = Get-ChildItem $CrashDir -Filter '*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { return $null }
    if ("$((Get-Settings).LastCrashShown)" -eq $f.Name) { return $null }
    $f
}