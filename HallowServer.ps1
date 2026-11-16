<#
  Hallow Toolkit - home server status: media apps (Radarr, Sonarr, Jellyfin, Plex, qBittorrent...), your own
  servers/websites, and drive space. No window code. Dot-sourced by HallowCore.ps1.
  Your own servers live in settings.json (ServerChecks) and are never part of "Share your setup".
#>

# Known apps. Proc = process name regex, Service = Windows service name, Url = health check, Web = page to open.
$ServerCatalog = @(
    @{ Name = 'Radarr';      Proc = '^Radarr(\.Console)?$';   Service = 'Radarr';         Url = 'http://localhost:7878/ping';  Web = 'http://localhost:7878' }
    @{ Name = 'Sonarr';      Proc = '^Sonarr(\.Console)?$';   Service = 'Sonarr';         Url = 'http://localhost:8989/ping';  Web = 'http://localhost:8989' }
    @{ Name = 'Prowlarr';    Proc = '^Prowlarr(\.Console)?$'; Service = 'Prowlarr';       Url = 'http://localhost:9696/ping';  Web = 'http://localhost:9696' }
    @{ Name = 'Lidarr';      Proc = '^Lidarr(\.Console)?$';   Service = 'Lidarr';         Url = 'http://localhost:8686/ping';  Web = 'http://localhost:8686' }
    @{ Name = 'Bazarr';      Proc = '^bazarr';                Service = 'bazarr';         Url = 'http://localhost:6767';       Web = 'http://localhost:6767' }
    @{ Name = 'Jellyfin';    Proc = '^jellyfin$';             Service = 'JellyfinServer'; Url = 'http://localhost:8096/health'; Web = 'http://localhost:8096'; Dir = "$env:ProgramData\Jellyfin\Server" }
    @{ Name = 'Emby';        Proc = '^EmbyServer$';           Service = 'Emby Server';    Url = 'http://localhost:8096/emby/System/Ping'; Web = 'http://localhost:8096' }
    @{ Name = 'Plex';        Proc = '^Plex Media Server$';    Service = '';               Url = 'http://localhost:32400/identity'; Web = 'http://localhost:32400/web'; Dir = "${env:ProgramFiles}\Plex\Plex Media Server" }
    @{ Name = 'qBittorrent'; Proc = '^qbittorrent$';          Service = '';               Url = '';                            Web = '';  Exe = "${env:ProgramFiles}\qBittorrent\qbittorrent.exe" }
    @{ Name = 'SABnzbd';     Proc = '^SABnzbd';               Service = 'SABnzbd';        Url = 'http://localhost:8080';       Web = 'http://localhost:8080' }
    @{ Name = 'Tailscale';   Proc = '^tailscaled$';           Service = 'Tailscale';      Url = '';                            Web = '' }
    @{ Name = 'Cloudflare tunnel'; Proc = '^cloudflared$';    Service = 'Cloudflared';    Url = '';                            Web = '' }
)

# Runs in a background runspace - self-contained. Returns one row per app, server and drive.
$ServerCheckWork = {
    param($Catalog, $Custom, $Hidden)
    function Test-Url([string]$Url) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $rq = [Net.HttpWebRequest]::Create($Url); $rq.Timeout = 6000; $rq.AllowAutoRedirect = $false; $rq.UserAgent = 'HallowToolkit'
            $rs = $rq.GetResponse(); $code = [int]$rs.StatusCode; $rs.Close()
        } catch [Net.WebException] {
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode; $_.Exception.Response.Close() }
            else { return @{ Up = $false; Ms = 0; Why = ($_.Exception.Message -replace '^.*?:\s*', '' -replace '\.$', '') } }
        } catch { return @{ Up = $false; Ms = 0; Why = $_.Exception.Message } }
        @{ Up = ($code -lt 500); Ms = $sw.ElapsedMilliseconds; Why = "HTTP $code" }
    }
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($a in $Catalog) {
        if ($Hidden -contains $a.Name) { continue }
        $svc = if ($a.Service) { Get-Service -Name $a.Service -ErrorAction SilentlyContinue } else { $null }
        $p = @($procs | Where-Object { $_.ProcessName -match $a.Proc }) | Select-Object -First 1
        $installed = $svc -or $p -or ($a.Dir -and (Test-Path $a.Dir)) -or ($a.Exe -and (Test-Path $a.Exe))
        if (-not $installed) { continue }
        $path = $null; if ($p) { try { $path = $p.Path } catch { } }
        if (-not $path -and $a.Exe -and (Test-Path $a.Exe)) { $path = $a.Exe }
        $running = [bool]$p -or ($svc -and $svc.Status -eq 'Running')
        if (-not $running) { $status = 'Stopped'; $detail = $(if ($svc) { "Windows service is $($svc.Status)" } else { 'Not running' }); $verdict = 'Bad' }
        elseif ($a.Url) {
            $t = Test-Url $a.Url
            if ($t.Up) { $status = 'Running'; $detail = "Web page answers in $($t.Ms) ms"; $verdict = 'Good' }
            else { $status = 'Not answering'; $detail = "Running, but the web page does not answer ($($t.Why))"; $verdict = 'Warn' }
        } else { $status = 'Running'; $detail = $(if ($p) { 'Process is running' } else { 'Service is running' }); $verdict = 'Good' }
        [pscustomobject]@{ Kind = 'App'; Name = $a.Name; Status = $status; Detail = $detail; Verdict = $verdict
            Web = $a.Web; Service = $(if ($svc) { $svc.Name } else { '' }); Path = $path; Key = "app:$($a.Name)" }
    }
    foreach ($c in @($Custom)) {
        if (-not $c -or -not $c.Url) { continue }
        $t = Test-Url $c.Url
        [pscustomobject]@{ Kind = 'Server'; Name = $c.Name; Status = $(if ($t.Up) { 'Up' } else { 'Down' })
            Detail = $(if ($t.Up) { "Answers in $($t.Ms) ms - $($c.Url)" } else { "$($t.Why) - $($c.Url)" })
            Verdict = $(if ($t.Up) { 'Good' } else { 'Bad' }); Web = $c.Url; Service = ''; Path = ''; Key = "url:$($c.Url)" }
    }
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady -or $d.TotalSize -le 0) { continue }
        $pct = $d.AvailableFreeSpace / $d.TotalSize * 100; $gb = $d.AvailableFreeSpace / 1GB
        $v = if ($pct -lt 5 -or $gb -lt 15) { 'Bad' } elseif ($pct -lt 10 -or $gb -lt 50) { 'Warn' } else { 'Good' }
        $label = if ($d.VolumeLabel) { "$($d.Name.TrimEnd('\')) $($d.VolumeLabel)" } else { $d.Name.TrimEnd('\') }
        [pscustomobject]@{ Kind = 'Drive'; Name = "Drive $label"; Status = ('{0:N0}% free' -f $pct)
            Detail = ('{0:N0} GB free of {1:N0} GB' -f $gb, ($d.TotalSize / 1GB)); Verdict = $v; Web = ''; Service = ''; Path = $d.Name; Key = "drive:$($d.Name)" }
    }
}

function Get-ServerChecks { @((Get-Settings).ServerChecks | Where-Object { $_ -and $_.Url }) }
function Get-ServerHidden { @((Get-Settings).ServerHidden | Where-Object { $_ }) }

function Add-ServerCheck([string]$Name, [string]$Url) {
    if ($Url -notmatch '^https?://') { $Url = "http://$Url" }
    $s = Get-Settings
    $list = @($s.ServerChecks | Where-Object { $_ -and $_.Url -ne $Url }) + @([pscustomobject]@{ Name = $Name; Url = $Url })
    $s | Add-Member -NotePropertyName ServerChecks -NotePropertyValue $list -Force; Save-Settings $s
    Log "Added $Name ($Url) to the server checks."
}

function Remove-ServerRow($Row) {
    $s = Get-Settings
    if ($Row.Kind -eq 'Server') {
        $s | Add-Member -NotePropertyName ServerChecks -NotePropertyValue @($s.ServerChecks | Where-Object { $_ -and $_.Url -ne $Row.Web }) -Force
        Log "Removed $($Row.Name) from the server checks."
    } elseif ($Row.Kind -eq 'App') {
        $s | Add-Member -NotePropertyName ServerHidden -NotePropertyValue (@($s.ServerHidden | Where-Object { $_ }) + $Row.Name | Select-Object -Unique) -Force
        Log "Hid $($Row.Name). Show hidden apps again with the Show hidden apps button."
    } else { Log 'Drives always show here.'; return }
    Save-Settings $s
}

function Show-HiddenServerApps {
    $s = Get-Settings; $s | Add-Member -NotePropertyName ServerHidden -NotePropertyValue @() -Force; Save-Settings $s
}

function Start-ServerApp($Row) {
    if ($Row.Kind -ne 'App') { Log "$($Row.Name) is not on this PC - start it where it runs."; return }
    if ($Row.Service) {
        if (-not (Need-Admin "Starting the $($Row.Name) service")) { return }
        try { Restart-Service -Name $Row.Service -Force -ErrorAction Stop; Log "Restarted the $($Row.Name) service." }
        catch { Log "Could not start $($Row.Name): $($_.Exception.Message)" }
    } elseif ($Row.Path -and (Test-Path $Row.Path)) {
        if ($Row.Status -ne 'Stopped') { Log "$($Row.Name) is already running." ; return }
        Start-Process -FilePath $Row.Path -WindowStyle Minimized; Log "Started $($Row.Name)."
    } else { Log "Don't know where $($Row.Name) is installed - start it from the Start menu." }
}
