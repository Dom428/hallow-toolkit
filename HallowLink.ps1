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

# ---- v4.8: what you're listening to and mic status, from Hallow Mixer (both off unless you turn them on)
# Called by the tray every 5 s with Hallow Mixer's /state. Songs: only from apps in the Music channel, only after
# 30 s of playing (skipped songs aren't posted), at most one post every 2 minutes. Mic: posts when a mute or unmute
# has lasted 10 s, at most once a minute.
$script:MixPost = @{ Song = $null; SongSince = $null; SongPosted = $false; LastSong = [datetime]::MinValue
                     Mic = $null; MicCand = $null; MicSince = $null; LastMic = [datetime]::MinValue }
function Update-MixerPosts($St, [datetime]$Now = (Get-Date)) {
    $p = $script:MixPost
    if (-not $St) { return }
    if (Get-LinkSetting 'DiscordNowPlaying' $false) {
        $n = $St.nowPlaying
        if ($n -and $n.playing -and $n.title -and ("$($n.channel)" -eq 'music')) {
            $key = "$($n.title)|$($n.artist)"
            if ($key -ne $p.Song) { $p.Song = $key; $p.SongSince = $Now; $p.SongPosted = $false }
            elseif (-not $p.SongPosted -and ($Now - $p.SongSince).TotalSeconds -ge 30 -and ($Now - $p.LastSong).TotalSeconds -ge 120) {
                $p.SongPosted = $true; $p.LastSong = $Now
                $text = "**$($n.title)**" + $(if ($n.artist) { " - $($n.artist)" } else { '' }) + " ($($n.app))"
                Send-DiscordPostAsync 'Listening to' $text 0x6ED28C
            }
        }
    }
    if (Get-LinkSetting 'DiscordMicStatus' $false) {
        $muted = [bool]$St.mic.muted
        if ($null -eq $p.Mic) { $p.Mic = $muted; $p.MicCand = $muted }   # first look: remember, don't post
        elseif ($muted -ne $p.MicCand) { $p.MicCand = $muted; $p.MicSince = $Now }
        elseif ($muted -ne $p.Mic -and $p.MicSince -and ($Now - $p.MicSince).TotalSeconds -ge 10 -and ($Now - $p.LastMic).TotalSeconds -ge 60) {
            $p.Mic = $muted; $p.LastMic = $Now
            if ($muted) { Send-DiscordPostAsync 'Mic muted' 'Probably away for a bit.' 0x8F88A0 } else { Send-DiscordPostAsync 'Mic back on' 'Back now.' 0xF07820 }
        }
    }
}

# ---- v5.6: saved Hallow Clips clips (off unless you turn it on). The tray calls this every 5 s with Clips' status.json.
# Only clips saved after it starts looking are posted (never your older ones), one post per save - the newest if several
# arrive at once. Under Discord's 10 MB limit the clip itself is uploaded, otherwise just "<game> - saved a clip".
# The upload runs in the background; the webhook link is never logged.
$ClipsStatusFile = Join-Path $env:LOCALAPPDATA 'HallowClips\status.json'
$DiscordFileLimit = 10MB
function Get-ClipsStatus { if (Test-Path $ClipsStatusFile) { try { Get-Content $ClipsStatusFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } } }
$script:ClipPost = @{ Since = $null; Job = $null }
function Get-ClipTime($Clip) {
    try { return [datetime]::Parse("$($Clip.time)") } catch { }
    try { (Get-Item -LiteralPath "$($Clip.file)" -ErrorAction Stop).LastWriteTime } catch { [datetime]::MinValue }
}
function Update-ClipPosts($St, [string]$Url, [datetime]$Now = (Get-Date)) {
    $p = $script:ClipPost
    Complete-ClipPost
    if (-not $St) { return }
    $clips = @($St.clips | Where-Object { $_ -and $_.file } | ForEach-Object { [pscustomobject]@{ Clip = $_; Time = (Get-ClipTime $_) } } | Sort-Object Time -Descending)
    if ($null -eq $p.Since) {   # first look: remember what's already there, don't post it
        $p.Since = $(if ($clips.Count -and $clips[0].Time -gt $Now) { $clips[0].Time } else { $Now }); return
    }
    $new = @($clips | Where-Object { $_.Time -gt $p.Since })
    if (-not $new.Count -or $p.Job) { return }   # nothing new, or still uploading the last one (try next time)
    $p.Since = $new[0].Time
    if (-not $Url) { $Url = Get-DiscordWebhook }
    if ($Url) { Send-DiscordClip $new[0].Clip $Url }
}
function Send-DiscordClip($Clip, [string]$Url) {
    Add-Type -AssemblyName System.Net.Http
    $game = "$($Clip.game)".Trim(); if (-not $game) { $game = 'A game' }
    $safe = $game -replace '([\\*_~`|>#\[\]()])', '\$1'
    $file = "$($Clip.file)"; $size = 0L
    try { $size = (Get-Item -LiteralPath $file -ErrorAction Stop).Length } catch { }
    $fits = $size -gt 0 -and $size -le ($DiscordFileLimit - 64KB)   # room for the rest of the upload
    $text = "**$safe** - saved a clip" + $(if ($size -gt 0 -and -not $fits) { " ({0:N0} MB - too big to upload to Discord)" -f ($size / 1MB) } else { '' })
    $json = @{ username = 'Hallow Toolkit'; content = $text; allowed_mentions = @{ parse = @() } } | ConvertTo-Json -Depth 4 -Compress
    $job = @{ Game = $game; Fits = $fits; Client = $null; Form = $null; Stream = $null; Task = $null; Url = $Url; Text = $json }
    try {
        $job.Client = New-Object System.Net.Http.HttpClient; $job.Client.Timeout = [TimeSpan]::FromMinutes(3)
        [void]$job.Client.DefaultRequestHeaders.UserAgent.TryParseAdd('HallowToolkit')
        $job.Form = New-Object System.Net.Http.MultipartFormDataContent
        $job.Form.Add((New-Object System.Net.Http.StringContent($json, [Text.Encoding]::UTF8, 'application/json')), 'payload_json')
        if ($fits) {
            $job.Stream = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite, Delete')
            $fc = New-Object System.Net.Http.StreamContent($job.Stream)
            $fc.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue('video/mp4')
            $name = [IO.Path]::GetFileName($file) -replace '[^\w\-. ]', '_'
            $job.Form.Add($fc, 'files[0]', $name)
        }
        $job.Task = $job.Client.PostAsync($Url, $job.Form)
        $script:ClipPost.Job = $job
    } catch { Close-ClipJob $job; Log "[tray] Clip post failed: $($_.Exception.Message -replace 'https?://\S+', '(webhook)')" }
}
function Close-ClipJob($Job) { foreach ($k in 'Stream', 'Form', 'Client') { if ($Job.$k) { try { $Job.$k.Dispose() } catch { } } } }
# Checks on the upload started by Send-DiscordClip. If Discord says the file is too big, posts the text instead.
function Complete-ClipPost {
    $j = $script:ClipPost.Job
    if (-not $j -or -not $j.Task.IsCompleted) { return }
    $script:ClipPost.Job = $null
    $code = 0; $err = $null
    if ($j.Task.IsFaulted -or $j.Task.IsCanceled) { $err = $(if ($j.Task.Exception) { $j.Task.Exception.GetBaseException().Message } else { 'timed out' }) }
    else { $code = [int]$j.Task.Result.StatusCode; $j.Task.Result.Dispose() }
    Close-ClipJob $j
    if ($code -ge 200 -and $code -lt 300) { Log "[tray] Posted a clip from $($j.Game) to Discord$(if (-not $j.Fits) { ' (text only - too big to upload)' })."; return }
    if ($code -eq 413 -and $j.Fits) {   # Discord's limit was lower than expected: post the text only
        $job = @{ Game = $j.Game; Fits = $false; Url = $j.Url; Text = $j.Text }
        try {
            $job.Client = New-Object System.Net.Http.HttpClient; $job.Client.Timeout = [TimeSpan]::FromSeconds(30)
            $job.Task = $job.Client.PostAsync($j.Url, (New-Object System.Net.Http.StringContent($j.Text, [Text.Encoding]::UTF8, 'application/json')))
            $script:ClipPost.Job = $job
        } catch { Close-ClipJob $job }
        return
    }
    Log "[tray] Clip post failed: $(if ($err) { $err -replace 'https?://\S+', '(webhook)' } else { "Discord answered $code" })"
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
# Sends a shared Hallow Mixer setup to the mixer (opens it first, as you, if it isn't running). Returns its message.
function Send-MixerShare($Mix) {
    if (-not (Get-MixerApi) -or -not (Invoke-Mixer '/state')) {
        if (-not (Test-Path $MixerExe)) { return 'Hallow Mixer is not installed - install it from the Hallow tab, then import again.' }
        Start-Process explorer.exe "`"$MixerExe`""
        $end = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $end -and -not (Invoke-Mixer '/state')) { Start-Sleep -Milliseconds 500 }
    }
    $a = Get-MixerApi; if (-not $a) { return 'Hallow Mixer did not answer (is "Let Hallow Toolkit control the mixer" on in its Settings?).' }
    $json = $Mix | ConvertTo-Json -Depth 10 -Compress
    try {
        $r = Invoke-RestMethod "http://127.0.0.1:$($a.port)/share-apply" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8' -Headers @{ 'X-Hallow-Key' = "$($a.key)" } -TimeoutSec 10 -UseBasicParsing
        "$($r.msg)"
    } catch { "Hallow Mixer did not take it: $($_.Exception.Message)" }
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
        $np = ''
        if ($mx.nowPlaying) {
            $n = $mx.nowPlaying
            $np = "<div class='np'><div class='nt'>$(& $e $n.title)</div><div class='m'>$(& $e (@($n.artist, $n.app) | Where-Object { $_ }) -join ' - ')$(if (-not $n.playing) { ' (paused)' })</div>" +
                  "<div class='nb'><a class='b' href='/$tok/media/prev'>&#9198;</a><a class='b w' href='/$tok/media/playpause'>$(if ($n.playing) { 'Pause' } else { 'Play' })</a><a class='b' href='/$tok/media/next'>&#9197;</a></div></div>"
        }
        $pf = ''
        if (@($mx.profiles).Count -gt 1) {
            $i = 0; $pfb = foreach ($p in @($mx.profiles)) { "<a class='b w $(if ($p -eq $mx.profile) { 'cur' })' href='/$tok/profile/$i'>$(& $e $p)</a>"; $i++ }
            $pf = "<div class='m pl'>Profile</div><div class='pf'>$($pfb -join '')</div>"
        }
        $mixHtml = "<h2>Mixer</h2>$np<table>$($mr -join '')</table><div class='ps'>$($pb -join '')</div>$pf"
    }
    $remoteHtml = ''
    if (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\Hallow Remote\HallowRemote.exe')) {
        $remoteHtml = "<div class='rm'><b>Try Hallow Remote</b> - it's installed on this PC and is the main phone app now: mixer, your Hub games with covers, game session and PC stats. " +
            "Open Hallow Remote on the PC and scan its QR code. This page keeps working too.</div>"
    }
    $gamesHtml = ''
    $hg = Get-HubGames
    if ($hg -and @($hg.games).Count) {
        $tok = Get-DashToken; $i = 0
        $gr = foreach ($g in @($hg.games)) {
            $act = if ($g.playing) { "<span class='good'>Playing</span>" } else { "<a class='b w' href='/$tok/game/$i'>Play</a>" }
            "<tr><td>$(& $e $g.name)</td><td class='mx'>$act</td></tr>"; $i++
        }
        $gamesHtml = "<h2>Games</h2><table>$($gr -join '')</table>"
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
.np{background:#241e2e;border-radius:6px;padding:10px 12px;margin-bottom:8px}.nt{font-weight:600;font-size:15px;overflow-wrap:anywhere}.nb{margin-top:8px}.nb .b{margin:0 6px 0 0}
.pl{margin-top:8px}.pf{margin-top:4px}.pf .b{margin:0 6px 6px 0}.b.cur{background:#a98be0;color:#16121c}
.rm{background:#241e2e;border-left:3px solid #f07820;border-radius:6px;padding:10px 12px;margin-top:12px;font-size:14px;line-height:1.4}.rm b{color:#f07820}
.b.w{min-width:64px}.b.on{background:#f05a5a;color:#16121c}.p{display:inline-block;width:46px;text-align:center}.ps{margin-top:10px}.ps .b{margin:0 6px 6px 0;background:#f07820;color:#16121c}
</style></head><body><h1>HALLOW</h1><div class='m'>$(& $e $env:COMPUTERNAME) - updated $(Get-Date -Format 'HH:mm:ss') - refreshes every 15 s</div>$remoteHtml
<h2>Now</h2><div class='g'>$($tiles -join '')</div>$mixHtml$gamesHtml<h2>Servers</h2><table>$($srv -join '')</table><h2>Drives</h2><table>$($rows -join '')</table>
</body></html>
"@
}

# Hallow Hub's recent games (Hub writes this list); only offered while Hub is running, so the game starts through Hub as you
function Get-HubGames {
    if (-not (Get-Process HallowHub -ErrorAction SilentlyContinue)) { return $null }
    $f = Join-Path $env:APPDATA 'HallowHub\recent.json'
    if (-not (Test-Path $f)) { return $null }
    try { Get-Content $f -Raw | ConvertFrom-Json } catch { $null }
}
# Mixer taps from the phone: /<key>/mix/<channel>/up|down|mute, /<key>/mic/mute, /<key>/preset/<n>, /<key>/media/playpause|next|prev. Returns what happened.
function Invoke-DashAction([string]$Action) {
    if ($Action -match '^/mix/(game|chat|music|media|other)/(up|down|mute)$') {
        $ch = $Matches[1]; $op = $Matches[2]
        $r = if ($op -eq 'mute') { Invoke-Mixer "/mute?ch=$ch&m=toggle" } else { Invoke-Mixer "/set?ch=$ch&d=$(if ($op -eq 'up') { 10 } else { -10 })" }
    } elseif ($Action -eq '/mic/mute') { $r = Invoke-Mixer '/mic?mute=toggle' }
    elseif ($Action -match '^/game/(\d{1,2})$') {
        $i = [int]$Matches[1]; $h = Get-HubGames
        if ($h -and $i -lt @($h.games).Count -and (Test-Path $h.exe)) {
            $g = @($h.games)[$i]
            Start-Process -FilePath $h.exe -ArgumentList @('--play', ('"' + $g.id + '"'))
            return "Starting $($g.name)"
        }
    }
    elseif ($Action -match '^/media/(playpause|next|prev)$') { $r = Invoke-Mixer "/media?do=$($Matches[1])" }
    elseif ($Action -match '^/profile/(\d{1,2})$') {
        $i = [int]$Matches[1]; $st = Invoke-Mixer '/state'
        if ($st -and $i -lt @($st.profiles).Count) { $r = Invoke-Mixer ('/profile?name=' + [uri]::EscapeDataString(@($st.profiles)[$i])) }
    }
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
