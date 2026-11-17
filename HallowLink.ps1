<#
  Hallow Toolkit - Discord posts (webhook) and the phone dashboard (read-only status page over Tailscale).
  No window code. Dot-sourced by HallowCore.ps1. Used by the tray app and the Server tab.
  The webhook link and the dashboard key are secrets: kept only in this PC's settings.json, never logged,
  never part of "Share your setup".
#>

# ================================================================ DISCORD POSTS
function Test-DiscordWebhookUrl([string]$Url) { $Url -match '^https://(canary\.|ptb\.)?discord(app)?\.com/api/webhooks/\d+/[\w-]+$' }
function Get-DiscordWebhook { $s = Get-Settings; if ($s.PSObject.Properties.Name -contains 'DiscordWebhook' -and (Test-DiscordWebhookUrl "$($s.DiscordWebhook)")) { "$($s.DiscordWebhook)" } }
function Get-LinkSetting([string]$Name, [bool]$Default) { $s = Get-Settings; if ($s.PSObject.Properties.Name -contains $Name) { [bool]$s.$Name } else { $Default } }
function Set-LinkSetting([string]$Name, $Value) { $s = Get-Settings; $s | Add-Member $Name $Value -Force; Save-Settings $s }

function New-DiscordBody([string]$Title, [string]$Text, [int]$Color) {
    @{ username = 'Hallow Toolkit'; embeds = @(@{ title = $Title; description = $Text; color = $Color; footer = @{ text = "$env:COMPUTERNAME - Hallow Toolkit v$AppVersion" } }) } | ConvertTo-Json -Depth 5 -Compress
}
# Waits for Discord's answer - for the "Send test post" button. Returns $true when Discord accepted it.
function Send-DiscordPost([string]$Title, [string]$Text, [int]$Color = 0xF07820, [string]$Url) {
    if (-not $Url) { $Url = Get-DiscordWebhook }
    if (-not $Url) { return $false }
    try {
        $body = [Text.Encoding]::UTF8.GetBytes((New-DiscordBody $Title $Text $Color))
        $rq = [System.Net.HttpWebRequest]::Create($Url)
        $rq.Method = 'POST'; $rq.ContentType = 'application/json; charset=utf-8'; $rq.Timeout = 10000; $rq.UserAgent = 'HallowToolkit'
        $st = $rq.GetRequestStream(); $st.Write($body, 0, $body.Length); $st.Close()
        $rq.GetResponse().Close()
        $true
    } catch { Log "Discord post failed: $($_.Exception.Message -replace 'https://\S+', '(webhook)')"; $false }
}
# Fire-and-forget for the tray app (never blocks the tray while Discord answers).
function Send-DiscordPostAsync([string]$Title, [string]$Text, [int]$Color = 0xF07820) {
    $url = Get-DiscordWebhook; if (-not $url) { return }
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers['Content-Type'] = 'application/json; charset=utf-8'; $wc.Encoding = [Text.Encoding]::UTF8
        $wc.UploadStringAsync([uri]$url, 'POST', (New-DiscordBody $Title $Text $Color))
    } catch { Log '[tray] Discord post failed to start.' }
}

# ================================================================ PHONE DASHBOARD
# A tiny read-only web page served by the tray app on this PC's Tailscale address only, behind a secret key in the link.
$DashPort = 5190
function Get-TailscaleIP {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -like '*Tailscale*' -or $_.IPAddress -like '100.*' } |
        Where-Object { $o = [int]($_.IPAddress -split '\.')[1]; ($_.IPAddress -like '100.*') -and $o -ge 64 -and $o -le 127 } | Select-Object -First 1
    if ($ip) { $ip.IPAddress }
}
function Get-DashToken {
    $s = Get-Settings
    if ($s.PSObject.Properties.Name -contains 'DashToken' -and "$($s.DashToken)".Length -ge 20) { return "$($s.DashToken)" }
    New-DashToken
}
function New-DashToken {
    $b = New-Object byte[] 18; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $t = ([Convert]::ToBase64String($b) -replace '\+', 'x' -replace '/', 'y' -replace '=', '')
    Set-LinkSetting 'DashToken' $t; $t
}
function Get-DashUrl { $ip = Get-TailscaleIP; if ($ip) { "http://${ip}:$DashPort/$(Get-DashToken)" } }

# ================================================================ HALLOW MIXER
# Hallow Mixer (github.com/Dom428/hallow-mixer) listens on 127.0.0.1 only; its port and key are in its api.json (your account only).
$MixerExe = Join-Path $env:LOCALAPPDATA 'Programs\Hallow Mixer\HallowMixer.exe'
function Get-MixerApi { $f = Join-Path $env:APPDATA 'HallowMixer\api.json'; if (Test-Path $f) { try { Get-Content $f -Raw | ConvertFrom-Json } catch { } } }
function Invoke-Mixer([string]$PathAndQuery) {
    $a = Get-MixerApi; if (-not $a) { return $null }
    try { Invoke-RestMethod "http://127.0.0.1:$($a.port)$PathAndQuery" -Headers @{ 'X-Hallow-Key' = "$($a.key)" } -TimeoutSec 2 -UseBasicParsing } catch { $null }
}
$MixerInstallWork = {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { $r = Invoke-RestMethod 'https://api.github.com/repos/Dom428/hallow-mixer/releases/latest' -Headers @{ 'User-Agent' = 'HallowToolkit'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20 }
    catch { return [pscustomobject]@{ Error = "Could not reach GitHub: $($_.Exception.Message)" } }
    $asset = @($r.assets | Where-Object { $_.name -like '*.zip' })[0]
    if (-not $asset) { return [pscustomobject]@{ Error = 'The latest Hallow Mixer release has no download.' } }
    $sha = ("$($asset.digest)" -replace '^sha256:', '')
    $tmp = Join-Path $env:TEMP ('hallow-mixer-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'mixer.zip'
    $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'HallowToolkit'; $wc.DownloadFile($asset.browser_download_url, $zip); $wc.Dispose()
    if ($sha -and (Get-FileHash $zip -Algorithm SHA256).Hash -ne $sha.ToUpper()) { Remove-Item $tmp -Recurse -Force; return [pscustomobject]@{ Error = 'Checksum mismatch - Hallow Mixer not installed.' } }
    Expand-Archive $zip (Join-Path $tmp 'x') -Force
    $inst = Get-ChildItem (Join-Path $tmp 'x') -Recurse -Filter 'Install.ps1' | Select-Object -First 1
    if (-not $inst) { return [pscustomobject]@{ Error = 'The download does not contain the installer.' } }
    Get-ChildItem $inst.DirectoryName | Unblock-File -ErrorAction SilentlyContinue
    [pscustomobject]@{ Error = $null; Installer = $inst.FullName; Version = ($r.tag_name -replace '^[vV]', ''); Verified = [bool]$sha }
}
# Runs Hallow Mixer's installer as you (not as admin) - it installs per user and opens the mixer.
function Start-MixerInstaller([string]$Installer) {
    $cmd = Join-Path $env:TEMP 'hallow-mixer-install.cmd'
    Set-Content $cmd @('@echo off', 'title Hallow Mixer - installing', "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Installer`"", 'timeout /t 3 >nul') -Encoding ASCII
    Start-Process explorer.exe "`"$cmd`""
}

# $State: hashtable the tray fills (InGame, GameStart, Servers, ...). Returns the HTML page.
function Get-DashboardHtml($State) {
    $e = { param($t) [System.Net.WebUtility]::HtmlEncode("$t") }
    $tiles = New-Object System.Collections.Generic.List[string]
    function Tile($label, $value, $cls = '') { $tiles.Add("<div class='t $cls'><div class='l'>$(& $e $label)</div><div class='v'>$(& $e $value)</div></div>") }
    try { $cpu = (Get-CimInstance Win32_Processor -Property LoadPercentage | Measure-Object LoadPercentage -Average).Average; Tile 'CPU' ('{0:N0}%' -f $cpu) } catch { }
    try { $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory; Tile 'RAM' ('{0:N1} / {1:N0} GB' -f (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB), ($os.TotalVisibleMemorySize / 1MB)) } catch { }
    if ($NvSmi) {
        $q = & $NvSmi '--query-gpu=utilization.gpu,temperature.gpu' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if ($q) { $v = $q -split ',\s*'; Tile 'GPU' ('{0}%' -f $v[0]); Tile 'GPU temp' ('{0} C' -f $v[1]) $(if ([int]$v[1] -ge 85) { 'bad' } elseif ([int]$v[1] -ge 75) { 'warn' } else { '' }) }
    }
    if ($State.InGame) { Tile 'Playing' ("{0} ({1:N0} min)" -f $State.InGame, ((Get-Date) - $State.GameStart).TotalMinutes) 'good' } else { Tile 'Playing' 'Nothing' }
    Tile 'Game session' $(if (Get-GameSession) { 'On' } else { 'Off' })
    if ($State.Timer) { Tile 'Timer' $State.Timer 'warn' }
    $mixHtml = ''
    $mx = Invoke-Mixer '/state'
    if ($mx) {
        $tok = Get-DashToken
        $mr = foreach ($c in @($mx.channels)) {
            "<tr><td>$(& $e $c.name)</td><td class='mx'><a class='b' href='/$tok/mix/$($c.id)/down'>&minus;</a><span class='p'>$($c.volume)%</span><a class='b' href='/$tok/mix/$($c.id)/up'>+</a>" +
            "<a class='b w $(if ($c.muted) { 'on' })' href='/$tok/mix/$($c.id)/mute'>$(if ($c.muted) { 'Muted' } else { 'Mute' })</a></td></tr>"
        }
        $mr += "<tr><td>Mic</td><td class='mx'><span class='p'>$(if ($mx.mic.level -ge 0) { "$($mx.mic.level)%" })</span><a class='b w $(if ($mx.mic.muted) { 'on' })' href='/$tok/mic/mute'>$(if ($mx.mic.muted) { 'Muted' } else { 'Mute' })</a></td></tr>"
        $i = 0; $pb = foreach ($p in @($mx.presets)) { "<a class='b w' href='/$tok/preset/$i'>$(& $e $p)</a>"; $i++ }
        $mixHtml = "<h2>Mixer</h2><table>$($mr -join '')</table><div class='ps'>$($pb -join '')</div>"
    }
    $rows = foreach ($d in @(Get-DriveSpace)) { "<tr><td>$(& $e $d.Drive) $(& $e $d.Label)</td><td class='$(if ($d.FreePct -lt 10) { 'bad' } else { '' })'>$($d.FreeGB) GB free ($($d.FreePct)%)</td></tr>" }
    $srv = foreach ($r in @($State.Servers | Where-Object { $_.Kind -ne 'Drive' })) { "<tr><td>$(& $e $r.Name)</td><td class='$(if ($r.Verdict -eq 'Good') { 'good' } else { 'bad' })'>$(& $e $r.Status)</td></tr>" }
    if (-not $srv) { $srv = "<tr><td colspan='2' class='m'>Checked every 5 minutes by the tray app (turn on Server alerts)</td></tr>" }
    @"
<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><meta http-equiv='refresh' content='15'>
<meta name='robots' content='noindex'><title>$(& $e $env:COMPUTERNAME) - Hallow</title><style>
body{background:#16121c;color:#ece8f4;font-family:Segoe UI,system-ui,sans-serif;margin:0;padding:16px}
h1{color:#f07820;font-size:22px;margin:0 0 2px}.m{color:#8f88a0;font-size:13px}h2{font-size:13px;color:#a98be0;text-transform:uppercase;margin:20px 0 8px}
*{box-sizing:border-box}.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(100px,1fr));gap:8px}.t{background:#241e2e;border-radius:6px;padding:10px;min-width:0}
.l{color:#8f88a0;font-size:12px}.v{font-size:18px;font-weight:600;margin-top:2px;overflow-wrap:anywhere}table{width:100%;border-collapse:collapse}
td{padding:7px 8px;border-bottom:1px solid #2c2538;font-size:14px}.good{color:#6ed28c}.warn{color:#f0be5a}.bad{color:#f05a5a}
.mx{text-align:right;white-space:nowrap}.b{display:inline-block;min-width:38px;padding:8px 10px;margin-left:6px;border-radius:6px;background:#2f2740;color:#ece8f4;text-decoration:none;text-align:center;font-weight:600}
.b.w{min-width:64px}.b.on{background:#f05a5a;color:#16121c}.p{display:inline-block;width:46px;text-align:center}.ps{margin-top:10px}.ps .b{margin:0 6px 6px 0;background:#f07820;color:#16121c}
</style></head><body><h1>HALLOW</h1><div class='m'>$(& $e $env:COMPUTERNAME) - updated $(Get-Date -Format 'HH:mm:ss') - refreshes every 15 s</div>
<h2>Now</h2><div class='g'>$($tiles -join '')</div>$mixHtml<h2>Servers</h2><table>$($srv -join '')</table><h2>Drives</h2><table>$($rows -join '')</table>
</body></html>
"@
}

# Mixer taps from the phone: /<key>/mix/<channel>/up|down|mute, /<key>/mic/mute, /<key>/preset/<n>. Returns what happened.
function Invoke-DashAction([string]$Action) {
    if ($Action -match '^/mix/(game|chat|music|media|other)/(up|down|mute)$') {
        $ch = $Matches[1]; $op = $Matches[2]
        $r = if ($op -eq 'mute') { Invoke-Mixer "/mute?ch=$ch&m=toggle" } else { Invoke-Mixer "/set?ch=$ch&d=$(if ($op -eq 'up') { 10 } else { -10 })" }
    } elseif ($Action -eq '/mic/mute') { $r = Invoke-Mixer '/mic?mute=toggle' }
    elseif ($Action -match '^/preset/(\d{1,2})$') {
        $i = [int]$Matches[1]; $st = Invoke-Mixer '/state'
        if ($st -and $i -lt @($st.presets).Count) { $r = Invoke-Mixer ('/preset?name=' + [uri]::EscapeDataString(@($st.presets)[$i])) }
    }
    if ($r) { "$($r.msg)" }
}
# Answers one waiting browser request (call often from a timer). Only GET /<key> gets the page; everything else is 404.
function Invoke-DashboardPoll($Listener, $State) {
    if (-not $Listener -or -not $Listener.Pending()) { return }
    $client = $Listener.AcceptTcpClient()
    try {
        $client.ReceiveTimeout = 2000; $client.SendTimeout = 2000
        $stream = $client.GetStream(); $buf = New-Object byte[] 4096
        $n = $stream.Read($buf, 0, $buf.Length)
        $line = ([Text.Encoding]::ASCII.GetString($buf, 0, [math]::Max(0, $n)) -split "`r?`n")[0]
        $ok = $line -match '^GET /([A-Za-z0-9]+)((?:/[a-z0-9]+){0,3})/? HTTP/1\.[01]$' -and $Matches[1] -ceq (Get-DashToken)
        $action = if ($ok) { $Matches[2] } else { '' }
        if ($ok -and $action) {
            [void](Invoke-DashAction $action)   # then send the phone back to the page (so a refresh never repeats the tap)
            $body = [Text.Encoding]::UTF8.GetBytes('OK'); $head = "HTTP/1.1 303 See Other`r`nLocation: /$(Get-DashToken)`r`nCache-Control: no-store`r`nReferrer-Policy: no-referrer`r`nContent-Type: text/plain`r`n"
        }
        elseif ($ok) { $body = [Text.Encoding]::UTF8.GetBytes((Get-DashboardHtml $State)); $head = "HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nCache-Control: no-store`r`nReferrer-Policy: no-referrer`r`n" }
        else { $body = [Text.Encoding]::UTF8.GetBytes('Not found'); $head = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain`r`n" }
        $h = [Text.Encoding]::ASCII.GetBytes("${head}Content-Length: $($body.Length)`r`nConnection: close`r`n`r`n")
        $stream.Write($h, 0, $h.Length); $stream.Write($body, 0, $body.Length); $stream.Flush()
    } catch { } finally { $client.Close() }
}
function Start-DashboardListener([string]$IP) {
    try { $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($IP), $DashPort); $l.Start(); $l } catch { $null }
}
