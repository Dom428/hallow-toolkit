<#
  Hallow Toolkit - the Hallow family apps (Mixer, Hub, Vault, Overlay, Remote, Clips): installed or not, running or
  not, newer release on GitHub, and installing / updating them. No window code. Dot-sourced by HallowCore.ps1.
  Each app installs per user (no admin) with its own installer from its own GitHub release; nothing is downloaded
  until you click Install or Update.
#>

$FamilyApps = @(
    [pscustomobject]@{ Name = 'Mixer';   Icon = 'sliders';         Desc = 'Per-app volume mixer: game, chat, music and media faders' }
    [pscustomobject]@{ Name = 'Hub';     Icon = 'gamepad';         Desc = 'All your games in one place, with playtime, presets and game sessions' }
    [pscustomobject]@{ Name = 'Vault';   Icon = 'box-archive';     Desc = 'Backs up your game saves when a game closes and once a day' }
    [pscustomobject]@{ Name = 'Overlay'; Icon = 'window-maximize'; Desc = 'See-through stats panel over your games, anti-cheat safe' }
    [pscustomobject]@{ Name = 'Remote';  Icon = 'mobile-screen';   Desc = 'Your phone as a remote for Mixer, Hub and the toolkit' }
    [pscustomobject]@{ Name = 'Clips';   Icon = 'film';            Desc = 'Instant replay: Ctrl+Alt+S saves the last moments of your game' }
)
function Get-FamilyExe([string]$App) { Join-Path $env:LOCALAPPDATA "Programs\Hallow $App\Hallow$App.exe" }
function Get-FamilyRepo([string]$App) { "Dom428/hallow-$($App.ToLower())" }
function Test-FamilyInstalled([string]$App) { Test-Path (Get-FamilyExe $App) }
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
        $installed = Test-Path $exe
        $ver = $null; if ($installed) { try { $ver = ConvertTo-FamilyVersion (Get-Item $exe).VersionInfo.FileVersion } catch { } }
        $latest = $null; if ($fc -and $fc.latest) { $latest = ConvertTo-FamilyVersion "$($fc.latest.($a.Name))" }
        [pscustomobject]@{
            Name = $a.Name; Title = "Hallow $($a.Name)"; Icon = $a.Icon; Desc = $a.Desc; Exe = $exe
            Installed = $installed; Version = $ver; Latest = $latest
            Running = [bool](Get-Process "Hallow$($a.Name)" -ErrorAction SilentlyContinue)
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
