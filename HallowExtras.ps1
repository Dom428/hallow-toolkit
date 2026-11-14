<#
  Hallow Toolkit v3 extras (no window code): game sessions, save backup, server ping, clips, debloat,
  tweaks, startup manager, services, dev toolbox, benchmark, disk map engine, sleep doctor, DNS test.
  Dot-sourced by HallowCore.ps1.
#>

$SessionDir = Join-Path $HallowRoot 'sessions'
$NvSmi = (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue).Source

# ================================================================ GAME SESSIONS
$script:SessCpu = $null
function Get-SessionSample {
    if (-not $script:SessCpu) {
        try { $script:SessCpu = New-Object System.Diagnostics.PerformanceCounter('Processor Information', '% Processor Utility', '_Total'); [void]$script:SessCpu.NextValue() } catch { }
    }
    $s = [ordered]@{ t = (Get-Date).ToString('o'); cpu = $null; ram = $null; gpu = $null; gtemp = $null; vram = $null; watts = $null; ctemp = $null }
    if ($script:SessCpu) { $s.cpu = [math]::Round([math]::Min(100, $script:SessCpu.NextValue()), 1) }
    $os = Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
    $s.ram = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
    if ($NvSmi) {
        $q = & $NvSmi '--query-gpu=utilization.gpu,temperature.gpu,memory.used,power.draw' '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1
        if ($q) { $v = $q -split ',\s*'; $s.gpu = [double]$v[0]; $s.gtemp = [double]$v[1]; $s.vram = [math]::Round([double]$v[2] / 1024, 2); $s.watts = [math]::Round([double]$v[3]) }
    }
    # CPU temp only if LibreHardwareMonitor answers (re-check once a minute so a missing sensor never slows sampling)
    if (-not $script:LhmNext -or (Get-Date) -ge $script:LhmNext) {
        $s.ctemp = Get-LhmCpuTemp
        $script:LhmNext = if ($null -eq $s.ctemp) { (Get-Date).AddMinutes(1) } else { $null }
    }
    [pscustomobject]$s
}

function Get-SessionSummary($S) {
    $sm = @($S.Samples)
    $num = { param($k, $op) $vals = @($sm | ForEach-Object { $_.$k } | Where-Object { $null -ne $_ }); if ($vals) { ($vals | Measure-Object -Average -Maximum).$op } else { $null } }
    $mins = ([datetime]$S.End - [datetime]$S.Start).TotalMinutes
    $gpuAvg = & $num 'gpu' 'Average'
    [pscustomobject]@{
        Game = $S.Game; Start = [datetime]$S.Start; Minutes = [math]::Round($mins)
        CpuAvg = & $num 'cpu' 'Average'; GpuAvg = $gpuAvg; GpuTempMax = & $num 'gtemp' 'Maximum'; CpuTempMax = & $num 'ctemp' 'Maximum'
        VramMax = & $num 'vram' 'Maximum'; RamMax = & $num 'ram' 'Maximum'; WattsMax = & $num 'watts' 'Maximum'
        Verdict = $(if ($null -eq $gpuAvg) { '' } elseif ($gpuAvg -ge 90) { 'GPU-bound (graphics card is the limit)' } elseif ($gpuAvg -lt 60) { 'GPU had headroom (CPU-limited or FPS cap)' } else { 'Balanced' })
    }
}

function Save-GameSession([string]$Game, [datetime]$Start, $Samples) {
    $arr = New-Object System.Collections.ArrayList
    foreach ($x in $Samples) { [void]$arr.Add($x) }
    if ($arr.Count -lt 2) { return $null }
    New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
    $s = [pscustomobject]@{ Game = $Game; Start = $Start.ToString('o'); End = (Get-Date).ToString('o'); Samples = $arr.ToArray() }
    $file = Join-Path $SessionDir ('{0:yyyy-MM-dd_HHmm}_{1}.json' -f $Start, ($Game -replace '[^\w\-]', '_'))
    $s | ConvertTo-Json -Depth 4 -Compress | Set-Content $file -Encoding UTF8
    Get-SessionSummary $s
}

function Get-GameSessions {
    foreach ($f in Get-ChildItem $SessionDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
        try { $s = Get-Content $f.FullName -Raw | ConvertFrom-Json; $sum = Get-SessionSummary $s; $sum | Add-Member File $f.FullName; $sum } catch { }
    }
}

# ================================================================ SAVE BACKUP
function Get-DefaultBackupDir {
    $s = Get-Settings
    if ($s.PSObject.Properties.Name -contains 'SaveBackupDir' -and $s.SaveBackupDir) { return $s.SaveBackupDir }
    $other = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ne "$env:SystemDrive\" -and $_.Free -gt 10GB } | Select-Object -First 1
    if ($other) { Join-Path $other.Root 'Hallow Backups\Game Saves' } else { Join-Path $HallowRoot 'save-backups' }
}

$SaveBackupWork = {
    param($Dest, $Keep, $EstimateOnly)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $sources = New-Object System.Collections.ArrayList
    function AddSrc($label, $path) { if ($path -and (Test-Path -LiteralPath $path)) { [void]$sources.Add([pscustomobject]@{ Label = $label; Path = $path }) } }
    AddSrc 'My Games' (Join-Path $docs 'My Games')
    AddSrc 'Saved Games' (Join-Path $env:USERPROFILE 'Saved Games')
    $skipLow = @('Unity', 'Microsoft', 'Temp', 'Sun', 'Intel', 'NVIDIA', 'Google', 'Mozilla', 'Adobe', 'Oracle', 'AMD')
    foreach ($d in Get-ChildItem (Join-Path $env:USERPROFILE 'AppData\LocalLow') -Directory -ErrorAction SilentlyContinue) {
        if ($skipLow -notcontains $d.Name) { AddSrc "LocalLow\$($d.Name)" $d.FullName }
    }
    foreach ($d in Get-ChildItem $env:LOCALAPPDATA -Directory -ErrorAction SilentlyContinue) {
        AddSrc "Local\$($d.Name)\SaveGames" (Join-Path $d.FullName 'Saved\SaveGames')
    }
    AddSrc 'Minecraft worlds' (Join-Path $env:APPDATA '.minecraft\saves')
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        foreach ($r in Get-ChildItem (Join-Path ($steam -replace '/', '\') 'userdata\*\*\remote') -Directory -ErrorAction SilentlyContinue) {
            $appid = Split-Path (Split-Path $r.FullName) -Leaf
            $uid = Split-Path (Split-Path (Split-Path $r.FullName)) -Leaf
            if ($appid -ne '760' -and $appid -ne '7') { AddSrc "Steam cloud\$uid\$appid" $r.FullName }
        }
    }
    $maxFile = 300MB
    $total = 0; $count = 0
    foreach ($s in $sources) {
        $files = @(Get-ChildItem -LiteralPath $s.Path -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -le $maxFile })
        $s | Add-Member Files $files
        $s | Add-Member Bytes ([double]($files | Measure-Object Length -Sum).Sum)
        $total += $s.Bytes; $count += $files.Count
    }
    $sources = @($sources | Where-Object { $_.Files.Count -gt 0 })
    if ($EstimateOnly) {
        foreach ($s in $sources | Sort-Object Bytes -Descending) { '{0,10:N1} MB  {1}' -f ($s.Bytes / 1MB), $s.Label }
        'Total: {0:N0} MB in {1} files from {2} places. Backups go to: {3}' -f ($total / 1MB), $count, $sources.Count, $Dest
        return
    }
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $zipPath = Join-Path $Dest ('GameSaves_{0:yyyy-MM-dd_HHmm}.zip' -f (Get-Date))
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    $ok = 0; $skipped = 0
    try {
        foreach ($s in $sources) {
            foreach ($f in $s.Files) {
                $rel = $f.FullName.Substring($s.Path.Length).TrimStart('\')
                try { [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, ($s.Label + '\' + $rel), 'Fastest'); $ok++ } catch { $skipped++ }
            }
        }
    } finally { $zip.Dispose() }
    $zi = Get-Item $zipPath
    'Saved {0} files from {1} places into {2} ({3:N0} MB){4}' -f $ok, $sources.Count, $zipPath, ($zi.Length / 1MB), $(if ($skipped) { " - $skipped in-use files skipped" } else { '' })
    $old = @(Get-ChildItem $Dest -Filter 'GameSaves_*.zip' | Sort-Object Name -Descending | Select-Object -Skip $Keep)
    foreach ($o in $old) { Remove-Item $o.FullName -Force; "Removed old backup $($o.Name) (keeping the newest $Keep)" }
    'To restore: open the zip, find the game, and copy its folder back to the same place.'
}

$SaveTaskName = 'Hallow Toolkit Weekly Save Backup'
function Invoke-ToggleSaveBackupTask {
    if (Get-ScheduledTask -TaskName $SaveTaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $SaveTaskName -Confirm:$false; Log 'Weekly game-save backup - OFF'; return
    }
    $main = Join-Path $HallowRoot 'HallowToolkit.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$main`" -Mode Backup"
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At '4:00 AM'
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $SaveTaskName -Action $action -Trigger $trigger -Settings $set -Force | Out-Null
    Log "Weekly game-save backup - ON (Saturdays 4 AM or next time the PC is on) to $(Get-DefaultBackupDir)"
}

# ================================================================ GAME SERVER PING
$ServerPingWork = {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    function PingMin($ip, $n = 4) {
        $p = New-Object System.Net.NetworkInformation.Ping; $best = $null
        for ($i = 0; $i -lt $n; $i++) { try { $r = $p.Send($ip, 1000); if ($r.Status -eq 'Success' -and ($null -eq $best -or $r.RoundtripTime -lt $best)) { $best = $r.RoundtripTime } } catch { } }
        $best
    }
    function TcpMin($hostName, $n = 3) {
        $best = $null
        for ($i = 0; $i -lt $n; $i++) {
            $c = New-Object System.Net.Sockets.TcpClient
            try {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                if ($c.ConnectAsync($hostName, 443).Wait(2000)) { $ms = $sw.Elapsed.TotalMilliseconds; if ($null -eq $best -or $ms -lt $best) { $best = $ms } }
            } catch { } finally { $c.Close() }
        }
        if ($null -ne $best) { [math]::Round($best) } else { $null }
    }
    $out = @()
    try {
        $cfg = Invoke-RestMethod 'https://api.steampowered.com/ISteamApps/GetSDRConfig/v1/?appid=730' -TimeoutSec 10
        $pops = foreach ($p in $cfg.pops.PSObject.Properties) {
            $relay = @($p.Value.relays) | Select-Object -First 1
            if ($relay -and $relay.ipv4) { [pscustomobject]@{ Code = $p.Name; Desc = $p.Value.desc; Ip = $relay.ipv4 } }
        }
        $res = foreach ($p in $pops) { $ms = PingMin $p.Ip 3; if ($null -ne $ms) { [pscustomobject]@{ Name = "$($p.Desc) ($($p.Code))"; Ms = $ms } } }
        $out += 'Valve servers (Deadlock, CS2, Dota 2) - your 8 closest:'
        $out += ($res | Sort-Object Ms | Select-Object -First 8 | ForEach-Object { '  {0,-38} {1,4} ms' -f $_.Name, $_.Ms })
    } catch { $out += "Valve server list unavailable ($($_.Exception.Message))" }
    $aws = [ordered]@{ 'us-east-1' = 'US East (Virginia)'; 'us-east-2' = 'US East (Ohio)'; 'us-west-1' = 'US West (California)'; 'us-west-2' = 'US West (Oregon)'
        'ca-central-1' = 'Canada (Montreal)'; 'sa-east-1' = 'Brazil (Sao Paulo)'; 'eu-west-2' = 'Europe (London)'; 'eu-central-1' = 'Europe (Frankfurt)'
        'ap-northeast-1' = 'Asia (Tokyo)'; 'ap-southeast-2' = 'Australia (Sydney)' }
    $out += 'Amazon AWS regions (many online games host here) - connection time:'
    $res = foreach ($k in $aws.Keys) { $ms = TcpMin "dynamodb.$k.amazonaws.com"; [pscustomobject]@{ Name = $aws[$k]; Ms = $ms } }
    $out += ($res | Sort-Object { if ($null -eq $_.Ms) { 99999 } else { $_.Ms } } | ForEach-Object { '  {0,-38} {1}' -f $_.Name, $(if ($null -ne $_.Ms) { '{0,4} ms' -f $_.Ms } else { 'no reply' }) })
    $out += 'In games with a region setting, pick the lowest number. AWS times include a connection handshake, so they read a bit higher than in-game ping.'
    $out
}

# ================================================================ CLIPS & SCREENSHOTS
function Get-ClipFolders {
    $vid = [Environment]::GetFolderPath('MyVideos'); $pic = [Environment]::GetFolderPath('MyPictures')
    $c = @($vid, (Join-Path $vid 'Captures'), (Join-Path $vid 'Medal'), (Join-Path $vid 'NVIDIA'), (Join-Path $pic 'Screenshots'))
    foreach ($d in Get-PSDrive -PSProvider FileSystem) { $c += (Join-Path $d.Root 'Medal'); $c += (Join-Path $d.Root 'Medal\Clips') }
    foreach ($f in Get-ChildItem "$env:APPDATA\Medal" -Recurse -Include *.json -ErrorAction SilentlyContinue | Where-Object Length -lt 2MB | Select-Object -First 40) {
        $m = Select-String -LiteralPath $f.FullName -Pattern '"(clipFolder|clipsFolder|ClipFolder|saveLocation)"\s*:\s*"([^"]+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { $c += ($m.Matches[0].Groups[2].Value -replace '\\\\', '\') }
    }
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) { $c += @(Get-ChildItem (Join-Path ($steam -replace '/', '\') 'userdata\*\760\remote') -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName) }
    $u = @(Get-UniquePaths ($c | Where-Object { $_ -and (Test-Path -LiteralPath $_) }))
    # drop folders that sit inside another listed folder (they are scanned already)
    $u | Where-Object { $p = $_; -not ($u | Where-Object { $_ -ne $p -and $p.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }) }
}
$ClipScanWork = {
    param($Folders, $Days)
    $ext = @('.mp4', '.mkv', '.mov', '.webm', '.avi', '.png', '.jpg', '.jpeg', '.gif', '.bmp')
    $cut = (Get-Date).AddDays(-$Days)
    foreach ($f in $Folders) {
        $files = @(Get-ChildItem -LiteralPath $f -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $ext -contains $_.Extension.ToLower() })
        "FOLDER|{0}|{1}|{2}" -f $f, ($files | Measure-Object Length -Sum).Sum, $files.Count
        foreach ($x in $files | Where-Object { $_.LastWriteTime -lt $cut }) {
            [pscustomobject]@{ Path = $x.FullName; Bytes = [double]$x.Length; Info = ('{0}, {1:yyyy-MM-dd}' -f $(if ($x.Extension -match 'mp4|mkv|mov|webm|avi') { 'clip' } else { 'screenshot' }), $x.LastWriteTime) }
        }
    }
}

# ================================================================ DEBLOAT
$BloatApps = @(
    @('Clipchamp.Clipchamp', 'Clipchamp video editor', $true),
    @('Microsoft.BingNews', 'Microsoft News', $true),
    @('Microsoft.BingWeather', 'Weather', $true),
    @('Microsoft.BingSearch', 'Bing Search app', $true),
    @('Microsoft.MicrosoftSolitaireCollection', 'Solitaire Collection', $true),
    @('Microsoft.GetHelp', 'Get Help', $true),
    @('Microsoft.Getstarted', 'Tips', $true),
    @('Microsoft.MicrosoftOfficeHub', 'Microsoft 365 (Office) hub', $true),
    @('Microsoft.People', 'People', $true),
    @('Microsoft.WindowsFeedbackHub', 'Feedback Hub', $true),
    @('Microsoft.WindowsMaps', 'Maps', $true),
    @('Microsoft.ZuneVideo', 'Movies & TV', $true),
    @('Microsoft.MixedReality.Portal', 'Mixed Reality Portal', $true),
    @('Microsoft.Todos', 'Microsoft To Do', $false),
    @('Microsoft.PowerAutomateDesktop', 'Power Automate', $true),
    @('Microsoft.549981C3F5F10', 'Cortana', $true),
    @('Microsoft.Windows.DevHome', 'Dev Home', $true),
    @('MicrosoftCorporationII.MicrosoftFamily', 'Microsoft Family', $true),
    @('Microsoft.WindowsAlarms', 'Alarms & Clock', $false),
    @('Microsoft.WindowsSoundRecorder', 'Sound Recorder', $false),
    @('Microsoft.OutlookForWindows', 'New Outlook', $false),
    @('MSTeams', 'Teams (personal)', $false),
    @('Microsoft.YourPhone', 'Phone Link', $false),
    @('Microsoft.Copilot', 'Copilot app', $false),
    @('Microsoft.MicrosoftJournal', 'Journal', $true),
    @('Microsoft.Wallet', 'Wallet', $true),
    @('Microsoft.3DBuilder', '3D Builder', $true),
    @('Microsoft.Microsoft3DViewer', '3D Viewer', $true),
    @('Microsoft.SkypeApp', 'Skype', $true),
    @('Disney.37853FA22FAF4', 'Disney+', $true),
    @('SpotifyAB.SpotifyMusic', 'Spotify (Store version)', $false),
    @('king.com.CandyCrushSaga', 'Candy Crush Saga', $true),
    @('king.com.CandyCrushSodaSaga', 'Candy Crush Soda', $true),
    @('Facebook.Facebook', 'Facebook', $true),
    @('BytedancePte.Ltd.TikTok', 'TikTok', $true),
    @('Facebook.InstagramBeta', 'Instagram', $true),
    @('AmazonVideo.PrimeVideo', 'Prime Video', $true),
    @('7EE7776C.LinkedInforWindows', 'LinkedIn', $true)
)
function Get-InstalledBloat {
    $pk = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    foreach ($b in $BloatApps) {
        $hit = $pk | Where-Object Name -eq $b[0] | Select-Object -First 1
        if ($hit) { [pscustomobject]@{ Id = $b[0]; Name = $b[1]; Recommended = $b[2]; Package = $hit.PackageFullName } }
    }
}
function Remove-Bloat($Items) {
    foreach ($i in $Items) {
        try { Remove-AppxPackage -Package $i.Package -ErrorAction Stop; Log "Removed $($i.Name)" } catch { Log "Could not remove $($i.Name): $($_.Exception.Message)" }
    }
    Log 'Removed apps can be reinstalled any time from the Microsoft Store.'
}

# ================================================================ PRIVACY & QUALITY-OF-LIFE TWEAKS
# Each op: Path, Name, On value, Off value ($null = delete value; for Type Key: delete key when off)
$Tweaks = @(
    @{ Id = 'adid'; Group = 'Privacy'; Name = 'Turn off advertising ID'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 0, 1)) },
    @{ Id = 'tips'; Group = 'Privacy'; Name = 'Turn off tips, suggestions and "fun facts"'; Admin = $false; Ops = @(
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338389Enabled', 0, 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-310093Enabled', 0, 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338388Enabled', 0, 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SoftLandingEnabled', 0, 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SystemPaneSuggestionsEnabled', 0, 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'RotatingLockScreenOverlayEnabled', 0, 1)) },
    @{ Id = 'startrec'; Group = 'Privacy'; Name = 'Turn off Start menu recommendations/promos'; Admin = $false; Ops = @(
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_IrisRecommendations', 0, 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_AccountNotifications', 0, 1)) },
    @{ Id = 'bing'; Group = 'Privacy'; Name = 'No Bing web results in Start search'; Admin = $false; Ops = @(@('HKCU:\Software\Policies\Microsoft\Windows\Explorer', 'DisableSearchBoxSuggestions', 1, $null)) },
    @{ Id = 'tailored'; Group = 'Privacy'; Name = 'Turn off tailored experiences'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled', 0, 1)) },
    @{ Id = 'copilot'; Group = 'Privacy'; Name = 'Hide Copilot'; Admin = $false; Ops = @(
            @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1, $null),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowCopilotButton', 0, $null)) },
    @{ Id = 'recall'; Group = 'Privacy'; Name = 'Turn off Recall snapshots'; Admin = $false; Ops = @(@('HKCU:\Software\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1, $null)) },
    @{ Id = 'activity'; Group = 'Privacy'; Name = 'Turn off activity history (admin)'; Admin = $true; Ops = @(@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'PublishUserActivities', 0, $null)) },
    @{ Id = 'telemetry'; Group = 'Privacy'; Name = 'Minimum diagnostic data (admin)'; Admin = $true; Ops = @(@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry', 1, $null)) },
    @{ Id = 'location'; Group = 'Privacy'; Name = 'Location off for your apps'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location', 'Value', 'Deny', 'Allow')) },
    @{ Id = 'speech'; Group = 'Privacy'; Name = 'Online speech recognition off'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy', 'HasAccepted', 0, 1)) },
    @{ Id = 'inking'; Group = 'Privacy'; Name = 'Typing & inking personalization off'; Admin = $false; Ops = @(
            @('HKCU:\Software\Microsoft\InputPersonalization', 'RestrictImplicitTextCollection', 1, 0),
            @('HKCU:\Software\Microsoft\InputPersonalization', 'RestrictImplicitInkCollection', 1, 0),
            @('HKCU:\Software\Microsoft\Personalization\Settings', 'AcceptedPrivacyPolicy', 0, 1)) },
    @{ Id = 'ext'; Group = 'Quality of life'; Name = 'Show file extensions (.exe, .zip...)'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'HideFileExt', 0, 1)) },
    @{ Id = 'hidden'; Group = 'Quality of life'; Name = 'Show hidden files'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Hidden', 1, 2)) },
    @{ Id = 'classicmenu'; Group = 'Quality of life'; Name = 'Classic right-click menu (no "Show more options")'; Admin = $false; Ops = @(@('HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32', '(default)', '', 'KEY')) },
    @{ Id = 'endtask'; Group = 'Quality of life'; Name = 'Add "End task" to taskbar right-click'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings', 'TaskbarEndTask', 1, 0)) },
    @{ Id = 'thispc'; Group = 'Quality of life'; Name = 'File Explorer opens to "This PC"'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'LaunchTo', 1, $null)) },
    @{ Id = 'dark'; Group = 'Quality of life'; Name = 'Dark mode for Windows and apps'; Admin = $false; Ops = @(
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 0, 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'SystemUsesLightTheme', 0, 1)) },
    @{ Id = 'clipboard'; Group = 'Quality of life'; Name = 'Clipboard history (Win+V)'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Clipboard', 'EnableClipboardHistory', 1, 0)) },
    @{ Id = 'seconds'; Group = 'Quality of life'; Name = 'Seconds on the taskbar clock'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowSecondsInSystemClock', 1, 0)) },
    @{ Id = 'taskview'; Group = 'Taskbar'; Name = 'Hide the Task View button'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowTaskViewButton', 0, 1)) },
    @{ Id = 'searchicon'; Group = 'Taskbar'; Name = 'Search as a small icon (not a big box)'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search', 'SearchboxTaskbarMode', 1, 2)) },
    @{ Id = 'startleft'; Group = 'Taskbar'; Name = 'Start button on the left'; Admin = $false; Ops = @(@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarAl', 0, 1)) },
    @{ Id = 'widgets'; Group = 'Taskbar'; Name = 'Remove Widgets / news (admin)'; Admin = $true; Ops = @(@('HKLM:\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests', 0, $null)) },
    @{ Id = 'edgebg'; Group = 'Performance'; Name = 'Edge stops running after you close it (admin)'; Admin = $true; Ops = @(
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'BackgroundModeEnabled', 0, $null),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'StartupBoostEnabled', 0, $null)) },
    @{ Id = 'faststart'; Group = 'Performance'; Name = 'Fast Startup off - shut down = real fresh start (admin)'; Admin = $true; Ops = @(@('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power', 'HiberbootEnabled', 0, 1)) },
    @{ Id = 'hiber'; Group = 'Performance'; Name = 'Hibernation off - frees the hiberfil.sys space on C: (admin)'; Admin = $true; Ops = @()
        Test = { (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled') -eq 0 }
        Apply = { param($On) powercfg /hibernate $(if ($On) { 'off' } else { 'on' }) | Out-Null } },
    @{ Id = 'sticky'; Group = 'Gaming'; Name = 'No Sticky Keys pop-up when pressing Shift 5 times'; Admin = $false; Ops = @(@('HKCU:\Control Panel\Accessibility\StickyKeys', 'Flags', '506', '510')) },
    @{ Id = 'gamedvr'; Group = 'Gaming'; Name = 'Turn off Game Bar background recording'; Admin = $false; Ops = @(
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR', 'AppCaptureEnabled', 0, 1),
            @('HKCU:\System\GameConfigStore', 'GameDVR_Enabled', 0, 1)) }
)
function Get-RegValue([string]$Path, [string]$Name) {
    if (-not (Test-Path $Path)) { return $null }
    if ($Name -eq '(default)') { return (Get-Item $Path).GetValue('') }
    $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($p) { $p.$Name } else { $null }
}
function Test-Tweak($T) {
    if ($T.Test) { return [bool](& $T.Test) }
    foreach ($op in $T.Ops) {
        $v = Get-RegValue $op[0] $op[1]
        if ($null -eq $v -or "$v" -ne "$($op[2])") { return $false }
    }
    $true
}
function Set-Tweak($T, [bool]$On) {
    if ($T.Admin -and -not $IsAdmin) { Log "Skipped '$($T.Name)' (needs admin)"; return }
    if ($T.Apply) { & $T.Apply $On; Log ("{0} - {1}" -f $T.Name, $(if ($On) { 'ON' } else { 'back to Windows default' })); return }
    foreach ($op in $T.Ops) {
        $path, $name, $onV, $offV = $op
        if ($On) {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            if ($name -eq '(default)') { Set-Item -Path $path -Value $onV }
            elseif ($onV -is [string]) { Set-ItemProperty -Path $path -Name $name -Value $onV -Type String }
            else { Set-ItemProperty -Path $path -Name $name -Value $onV -Type DWord }
        } else {
            if ($offV -eq 'KEY') { Remove-Item -Path (Split-Path $path) -Recurse -Force -ErrorAction SilentlyContinue }
            elseif ($null -eq $offV) { Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue }
            else {
                if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                if ($offV -is [string]) { Set-ItemProperty -Path $path -Name $name -Value $offV -Type String } else { Set-ItemProperty -Path $path -Name $name -Value $offV -Type DWord }
            }
        }
    }
    Log ("{0} - {1}" -f $T.Name, $(if ($On) { 'ON' } else { 'back to Windows default' }))
}

# ================================================================ STARTUP MANAGER
$ApprovedRoots = @{ HKCU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'; HKLM = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved' }
function Get-StartupItems {
    $procs = Get-Process | Group-Object ProcessName -AsHashTable -AsString
    $mem = { param($cmd) $exe = if ($cmd -match '([^\\/"]+)\.exe') { $Matches[1] } else { $null }; if ($exe -and $procs -and $procs.ContainsKey($exe)) { [math]::Round(($procs[$exe] | Measure-Object WorkingSet64 -Sum).Sum / 1MB) } else { $null } }
    $sources = @(
        @('HKCU', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'Run', 'Registry (you)'),
        @('HKLM', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'Run', 'Registry (all users)'),
        @('HKLM', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'Run32', 'Registry (all users, 32-bit)'))
    foreach ($s in $sources) {
        $props = Get-ItemProperty $s[1] -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            $ap = Get-ItemProperty (Join-Path $ApprovedRoots[$s[0]] $s[2]) -Name $p.Name -ErrorAction SilentlyContinue
            $on = -not $ap -or (($ap.($p.Name))[0] % 2 -eq 0)
            [pscustomobject]@{ Name = $p.Name; Command = [string]$p.Value; Source = $s[3]; Kind = 'Run'; Hive = $s[0]; Approved = $s[2]; Key = $s[1]; Enabled = $on; MB = (& $mem $p.Value) }
        }
    }
    foreach ($s in @(@('HKCU', [Environment]::GetFolderPath('Startup'), 'Startup folder (you)'), @('HKLM', [Environment]::GetFolderPath('CommonStartup'), 'Startup folder (all users)'))) {
        foreach ($f in Get-ChildItem $s[1] -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini') {
            $ap = Get-ItemProperty (Join-Path $ApprovedRoots[$s[0]] 'StartupFolder') -Name $f.Name -ErrorAction SilentlyContinue
            $on = -not $ap -or (($ap.($f.Name))[0] % 2 -eq 0)
            [pscustomobject]@{ Name = $f.BaseName; Command = $f.FullName; Source = $s[2]; Kind = 'Folder'; Hive = $s[0]; Approved = 'StartupFolder'; Key = $f.Name; Enabled = $on; MB = (& $mem $f.Name) }
        }
    }
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and ($_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }) }) {
        $cmd = (@($t.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join ' ; '
        [pscustomobject]@{ Name = $t.TaskName; Command = $cmd; Source = $(if ($t.TaskPath -eq '\Hallow\') { 'Delayed by Hallow' } else { 'Scheduled task at sign-in' }); Kind = 'Task'; Hive = $null; Approved = $null; Key = $t.TaskPath; Enabled = ($t.State -ne 'Disabled'); MB = (& $mem $cmd) }
    }
}
function Set-StartupItem($I, [bool]$Enabled) {
    if (($I.Hive -eq 'HKLM' -or $I.Kind -eq 'Task') -and -not $IsAdmin -and $I.Source -ne 'Delayed by Hallow') { Log "Skipped $($I.Name) (needs admin)"; return }
    if ($I.Kind -eq 'Task') {
        if ($Enabled) { Enable-ScheduledTask -TaskPath $I.Key -TaskName $I.Name | Out-Null } else { Disable-ScheduledTask -TaskPath $I.Key -TaskName $I.Name | Out-Null }
    } else {
        $k = Join-Path $ApprovedRoots[$I.Hive] $I.Approved
        if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
        $val = if ($I.Kind -eq 'Folder') { $I.Key } else { $I.Name }
        $bytes = if ($Enabled) { [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) } else { [byte[]](3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()) }
        Set-ItemProperty -Path $k -Name $val -Value $bytes -Type Binary
    }
    Log ("Startup: {0} - {1}" -f $I.Name, $(if ($Enabled) { 'ON' } else { 'OFF' }))
}
function Split-Command([string]$Cmd) {
    $Cmd = $Cmd.Trim()
    if ($Cmd.StartsWith('"')) { $e = $Cmd.IndexOf('"', 1); return @($Cmd.Substring(1, $e - 1), $Cmd.Substring($e + 1).Trim()) }
    $m = [regex]::Match($Cmd, '^(.+?\.exe)\s*(.*)$', 'IgnoreCase')
    if ($m.Success) { return @($m.Groups[1].Value, $m.Groups[2].Value) }
    @($Cmd, '')
}
function Set-StartupDelayed($I) {
    if ($I.Kind -ne 'Run') { Log 'Only registry startup entries can be delayed.'; return }
    $exe, $args2 = Split-Command $I.Command
    $act = if ($args2) { New-ScheduledTaskAction -Execute $exe -Argument $args2 } else { New-ScheduledTaskAction -Execute $exe }
    $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $trg.Delay = 'PT1M'
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
    Register-ScheduledTask -TaskPath '\Hallow\' -TaskName $I.Name -Action $act -Trigger $trg -Settings $set -Force | Out-Null
    Set-StartupItem $I $false
    Log "$($I.Name) now starts 1 minute after you sign in (faster boot). Undo: tick it again and remove the 'Delayed by Hallow' entry."
}
function Remove-StartupDelay($I) {
    Unregister-ScheduledTask -TaskPath '\Hallow\' -TaskName $I.Name -Confirm:$false -ErrorAction SilentlyContinue
    Log "Removed the delayed start for $($I.Name) - turn its normal entry back on in the list if you want it at boot."
}

# ================================================================ SERVICES HELPER
$ServiceUndoFile = Join-Path $HallowRoot 'services-undo.json'
function Get-ThirdPartyServices {
    foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
        $path = [string]$s.PathName
        $exe = if ($path -match '^"([^"]+)"') { $Matches[1] } elseif ($path -match '^(\S+\.exe)') { $Matches[1] } else { $null }
        if (-not $exe -or $exe -match '(?i)\\Windows\\') { continue }
        $co = ''; try { $co = (Get-Item -LiteralPath $exe -ErrorAction Stop).VersionInfo.CompanyName } catch { }
        if ($co -match 'Microsoft') { continue }
        $sugg = ''
        if ($s.StartMode -eq 'Auto' -and ("$($s.Name) $($s.DisplayName)" -match '(?i)update|updater|telemetry|crash\s?handler|maintenance')) { $sugg = 'Manual - only needed for updates' }
        [pscustomobject]@{ Name = $s.Name; Display = $s.DisplayName; Company = [string]$co; Start = $s.StartMode; State = $s.State; Suggest = $sugg }
    }
}
function Set-ServiceStart([string]$Name, [string]$Mode) {
    if (-not (Need-Admin 'Changing services')) { return }
    $undo = @{}
    if (Test-Path $ServiceUndoFile) { (Get-Content $ServiceUndoFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $undo[$_.Name] = $_.Value } }
    $cur = (Get-CimInstance Win32_Service -Filter "Name='$Name'").StartMode
    if (-not $undo.ContainsKey($Name)) { $undo[$Name] = $cur }
    $undo | ConvertTo-Json | Set-Content $ServiceUndoFile -Encoding UTF8
    $type = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }[$Mode]
    Set-Service -Name $Name -StartupType $type -ErrorAction Stop
    Log "Service $Name - start type $cur -> $type"
}
function Restore-Services {
    if (-not (Need-Admin 'Restoring services')) { return }
    if (-not (Test-Path $ServiceUndoFile)) { Log 'Nothing to restore - no services were changed by the toolkit.'; return }
    $undo = Get-Content $ServiceUndoFile -Raw | ConvertFrom-Json
    foreach ($p in $undo.PSObject.Properties) {
        $type = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }[[string]$p.Value]
        try { Set-Service -Name $p.Name -StartupType $type -ErrorAction Stop; Log "Restored $($p.Name) to $type" } catch { Log "Could not restore $($p.Name): $($_.Exception.Message)" }
    }
    Remove-Item $ServiceUndoFile -Force
}

# ================================================================ DEV TOOLBOX
function Get-ListeningPorts {
    $tcp = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, OwningProcess, @{ n = 'Proto'; e = { 'TCP' } }
    $udp = Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -lt 49152 } | Select-Object LocalAddress, LocalPort, OwningProcess, @{ n = 'Proto'; e = { 'UDP' } }
    foreach ($c in @($tcp) + @($udp) | Sort-Object LocalPort -Unique) {
        $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        [pscustomobject]@{ Port = $c.LocalPort; Proto = $c.Proto; Address = $c.LocalAddress; Pid = $c.OwningProcess; Process = $(if ($p) { $p.ProcessName } else { '?' }); Path = $(if ($p) { try { $p.Path } catch { '' } }) }
    }
}
function Show-PortOwner([int]$Port) {
    $hits = @(Get-ListeningPorts | Where-Object Port -eq $Port)
    if (-not $hits) { Log "Nothing is listening on port $Port - it's free."; return @() }
    foreach ($h in $hits) { Log ("Port {0} ({1}) is used by {2} (PID {3}) {4}" -f $h.Port, $h.Proto, $h.Process, $h.Pid, $h.Path) }
    $hits
}
function Stop-PortOwner([int]$Port) {
    $hits = @(Get-ListeningPorts | Where-Object { $_.Port -eq $Port -and $_.Pid -gt 4 })
    if (-not $hits) { Log "Nothing to stop on port $Port."; return }
    $names = ($hits | ForEach-Object { "$($_.Process) (PID $($_.Pid))" } | Select-Object -Unique) -join ', '
    if (-not (Confirm-Action "Stop $names to free port $Port?")) { return }
    foreach ($h in $hits | Select-Object Pid -Unique) { Stop-Process -Id $h.Pid -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    if (Get-ListeningPorts | Where-Object Port -eq $Port) { Log "Port $Port is still in use (it may need admin)." } else { Log "Port $Port is free now." }
}

$DevCacheList = @(
    @('npm cache', '%LOCALAPPDATA%\npm-cache'),
    @('Yarn cache', '%LOCALAPPDATA%\Yarn\Cache'),
    @('pnpm store', '%LOCALAPPDATA%\pnpm\store'),
    @('pip cache', '%LOCALAPPDATA%\pip\Cache'),
    @('uv cache', '%LOCALAPPDATA%\uv\cache'),
    @('NuGet packages', '%USERPROFILE%\.nuget\packages'),
    @('NuGet HTTP cache', '%LOCALAPPDATA%\NuGet\v3-cache'),
    @('Gradle caches', '%USERPROFILE%\.gradle\caches'),
    @('Cargo registry', '%USERPROFILE%\.cargo\registry'),
    @('Go build cache', '%LOCALAPPDATA%\go-build'),
    @('Unity cache', '%LOCALAPPDATA%\Unity\cache'),
    @('Unity Asset Store downloads', '%APPDATA%\Unity\Asset Store-5.x'),
    @('Electron cache', '%LOCALAPPDATA%\electron\Cache'),
    @('electron-builder cache', '%LOCALAPPDATA%\electron-builder\Cache'),
    @('node-gyp headers', '%LOCALAPPDATA%\node-gyp\Cache'),
    @('TypeScript cache', '%LOCALAPPDATA%\Microsoft\TypeScript'),
    @('Playwright browsers', '%LOCALAPPDATA%\ms-playwright'),
    @('Puppeteer browsers', '%USERPROFILE%\.cache\puppeteer'),
    @('Hugging Face models', '%USERPROFILE%\.cache\huggingface')
)
$DevCacheWork = [scriptblock]::Create('param($List)' + "`n" + $TreeSizeFn + @'
foreach ($c in $List) {
    $p = [Environment]::ExpandEnvironmentVariables($c[1])
    if (Test-Path -LiteralPath $p) { $b = Get-TreeSize $p; if ($b -gt 1MB) { [pscustomobject]@{ Path = $p; Bytes = $b; Info = $c[0] } } }
}
'@)

$GitScanWork = {
    param($Root)
    $git = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
    if (-not $git) { 'Git is not installed.'; return }
    $skip = @('AppData', 'node_modules', 'Library', '.git', '$Recycle.Bin', 'OneDrive', 'Temp', '.cache', '.nuget', '.gradle', '.cargo')
    $repos = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Stack; $stack.Push(@($Root, 0))
    while ($stack.Count -gt 0) {
        $it = $stack.Pop(); $p = $it[0]; $d = $it[1]
        try { $subs = @((New-Object System.IO.DirectoryInfo $p).EnumerateDirectories()) } catch { continue }
        if ($subs | Where-Object Name -eq '.git') { $repos.Add($p); continue }
        if ($d -ge 4) { continue }
        foreach ($s in $subs) { if ($skip -notcontains $s.Name -and -not ($s.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push(@($s.FullName, $d + 1)) } }
    }
    foreach ($r in $repos) {
        $st = @(& $git -C $r status --porcelain=v1 -b 2>$null)
        $head = if ($st) { $st[0] } else { '' }
        $branch = if ($head -match '^## (?:No commits yet on )?([^\.\s]+)') { $Matches[1] } else { '?' }
        $ahead = if ($head -match 'ahead (\d+)') { [int]$Matches[1] } else { 0 }
        $behind = if ($head -match 'behind (\d+)') { [int]$Matches[1] } else { 0 }
        $upstream = $head -match '\.\.\.'
        $changes = [math]::Max(0, $st.Count - 1)
        $last = (& $git -C $r log -1 --format=%cr 2>$null) | Select-Object -First 1
        $state = @()
        if ($changes) { $state += "$changes uncommitted" }
        if ($ahead) { $state += "$ahead not pushed" }
        if ($behind) { $state += "$behind to pull" }
        if (-not $upstream) { $state += 'no remote branch' }
        if (-not $state) { $state = @('clean') }
        [pscustomobject]@{ Path = $r; Branch = $branch; Changes = $changes; Ahead = $ahead; Behind = $behind; Last = [string]$last; State = ($state -join ', ') }
    }
}

# ================================================================ BENCHMARK
$BenchFile = Join-Path $HallowRoot 'benchmarks.json'
$BenchmarkWork = {
    param($IsAdmin)
    if (-not ('HallowBench' -as [type])) {
        Add-Type @'
using System; using System.Diagnostics; using System.Threading; using System.Threading.Tasks; using System.Security.Cryptography;
public static class HallowBench {
    public static double Hash(double seconds, int threads) {
        byte[] buf = new byte[1 << 20]; new Random(1).NextBytes(buf); long count = 0;
        var sw = Stopwatch.StartNew();
        Parallel.For(0, threads, new ParallelOptions { MaxDegreeOfParallelism = threads }, i => {
            using (var sha = SHA256.Create()) { long local = 0; while (sw.Elapsed.TotalSeconds < seconds) { sha.ComputeHash(buf); local++; } Interlocked.Add(ref count, local); }
        });
        return count / sw.Elapsed.TotalSeconds;   // MB/s hashed
    }
    public static double Mem() {
        int n = 256 << 20; var a = new byte[n]; var b = new byte[n]; new Random(2).NextBytes(a);
        Buffer.BlockCopy(a, 0, b, 0, n);
        var sw = Stopwatch.StartNew(); int reps = 10;
        for (int i = 0; i < reps; i++) Buffer.BlockCopy(i % 2 == 0 ? a : b, 0, i % 2 == 0 ? b : a, 0, n);
        return (double)reps * n / (1 << 30) / sw.Elapsed.TotalSeconds;   // GB/s copied
    }
}
'@
    }
    $r = [ordered]@{ Date = (Get-Date).ToString('o') }
    $r.CpuSingle = [math]::Round([HallowBench]::Hash(4, 1))
    $r.CpuMulti = [math]::Round([HallowBench]::Hash(4, [Environment]::ProcessorCount))
    $r.MemGBs = [math]::Round([HallowBench]::Mem(), 1)
    $r.Disks = [ordered]@{}
    if ($IsAdmin) {
        foreach ($d in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 50GB }) {
            $l = $d.DriveLetter
            $read = (winsat disk -seq -read -drive $l 2>$null | Select-String 'MB/s' | Select-Object -First 1) -replace '.*?([\d\.]+)\s*MB/s.*', '$1'
            $write = (winsat disk -seq -write -drive $l 2>$null | Select-String 'MB/s' | Select-Object -First 1) -replace '.*?([\d\.]+)\s*MB/s.*', '$1'
            $r.Disks["$l"] = [ordered]@{ Read = [double]$read; Write = [double]$write }
        }
    }
    [pscustomobject]$r
}
function Save-Benchmark($R) {
    $all = @(Get-Benchmarks) + @($R)
    ConvertTo-Json -InputObject @($all) -Depth 5 | Set-Content $BenchFile -Encoding UTF8
}
function Get-Benchmarks { if (Test-Path $BenchFile) { $j = Get-Content $BenchFile -Raw | ConvertFrom-Json; @($j) } else { @() } }

# ================================================================ SLEEP & WAKE DOCTOR
function Get-WakeDevices { @(powercfg /devicequery wake_armed 2>$null | Where-Object { $_ -and $_ -notmatch '^NONE$' } | ForEach-Object { $_.Trim() }) }
function Invoke-SleepDoctor {
    Log '===== SLEEP & WAKE DOCTOR ====='
    Log 'Last thing that woke the PC:'
    (powercfg /lastwake 2>$null) | Where-Object { $_ -match '\S' } | Select-Object -Skip 1 -First 6 | ForEach-Object { Log "  $($_.Trim())" }
    $wakes = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1 } -MaxEvents 8 -ErrorAction SilentlyContinue
    if ($wakes) {
        Log 'Recent wake-ups:'
        foreach ($w in $wakes) { $src = (($w.Message -split "`n") | Where-Object { $_ -match 'Wake Source' } | Select-Object -First 1); Log ("  {0:yyyy-MM-dd HH:mm}  {1}" -f $w.TimeCreated, ([string]$src).Trim()) }
    } else { Log 'Recent wake-ups: none recorded (since the logs were last cleared).' }
    $dev = Get-WakeDevices
    Log ("Devices allowed to wake the PC: {0}" -f $(if ($dev) { $dev -join '; ' } else { 'none' }))
    if ($IsAdmin) {
        $timers = (powercfg /waketimers 2>$null) -join ' '
        Log ("Wake timers: {0}" -f $(if ($timers -match 'no active wake timers|There are no') { 'none' } else { ($timers -replace '\s+', ' ').Substring(0, [math]::Min(300, $timers.Length)) }))
        Log 'Things keeping the PC awake right now:'
        $req = powercfg /requests 2>$null
        $cur = ''
        foreach ($l in $req) { if ($l -match '^(DISPLAY|SYSTEM|AWAYMODE|EXECUTION|PERFBOOST|ACTIVELOCKSCREEN):') { $cur = $Matches[1] } elseif ($l -match '\S' -and $l -notmatch '^None\.') { Log "  [$cur] $($l.Trim())" } }
    } else { Log '(Open the toolkit as admin to also see wake timers and what blocks sleep.)' }
    Log 'Tip: if the mouse wakes the PC when bumped, use "Stop a device waking the PC".'
}
function Disable-DeviceWake([string]$Device) {
    if (-not (Need-Admin 'Changing wake devices')) { return }
    powercfg /devicedisablewake "$Device" | Out-Null
    Log "$Device can no longer wake the PC. (Undo: Device Manager > device > Power Management.)"
}

# ================================================================ DNS SPEED TEST
$DnsTestWork = {
    param($Servers)
    $domains = 'google.com', 'youtube.com', 'discord.com', 'steampowered.com', 'riotgames.com', 'twitch.tv', 'reddit.com', 'amazon.com', 'github.com', 'epicgames.com', 'battle.net', 'ea.com'
    foreach ($s in $Servers) {
        $times = New-Object System.Collections.Generic.List[double]; $fail = 0
        foreach ($pass in 1, 2) {
            foreach ($d in $domains) {
                $sw = [Diagnostics.Stopwatch]::StartNew()
                try { Resolve-DnsName -Name $d -Server $s.Ip -Type A -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop | Out-Null; $times.Add($sw.Elapsed.TotalMilliseconds) } catch { $fail++ }
            }
        }
        $sorted = @($times | Sort-Object)
        [pscustomobject]@{ Name = $s.Name; Ip = $s.Ip; Median = $(if ($sorted) { [math]::Round($sorted[[int]($sorted.Count / 2)], 1) } else { $null }); Avg = $(if ($sorted) { [math]::Round(($sorted | Measure-Object -Average).Average, 1) } else { $null }); Fails = $fail }
    }
}
$DnsPresets = [ordered]@{ Cloudflare = @('1.1.1.1', '1.0.0.1'); Google = @('8.8.8.8', '8.8.4.4'); Quad9 = @('9.9.9.9', '149.112.112.112'); OpenDNS = @('208.67.222.222', '208.67.220.220') }
function Set-DnsPreset([string]$Name) {
    if (-not (Need-Admin 'Changing DNS')) { return }
    $a = Get-MainAdapter; if (-not $a) { Log 'No connected network adapter found.'; return }
    if ($Name -eq 'Automatic' -or -not $DnsPresets.Contains($Name)) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses; Log "DNS on $($a.Name) reset to automatic." }
    else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $DnsPresets[$Name]; Log "DNS on $($a.Name) set to $Name ($($DnsPresets[$Name] -join ', '))." }
    Clear-DnsClientCache
}

# ================================================================ DISK MAP ENGINE (C# for speed)
Import-HallowType 'HallowDiskMap' @'
using System; using System.Collections.Generic; using System.IO; using System.Drawing;
public class HallowDiskMap {
    public Dictionary<string, long> Size = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, long> OwnFiles = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, List<string>> Kids = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
    public long Files;
    public long Scan(string path) {
        long own = 0; var kids = new List<string>();
        try {
            var di = new DirectoryInfo(path);
            foreach (var f in di.EnumerateFiles()) { try { own += f.Length; Files++; } catch { } }
            foreach (var d in di.EnumerateDirectories()) { if ((d.Attributes & FileAttributes.ReparsePoint) == 0) kids.Add(d.FullName); }
        } catch { }
        long total = own;
        foreach (var k in kids) total += Scan(k);
        Size[path] = total; OwnFiles[path] = own; Kids[path] = kids;
        return total;
    }
    // Squarified treemap: values sorted descending, returns one rectangle per value.
    public static RectangleF[] Layout(double[] values, RectangleF r) {
        var res = new RectangleF[values.Length]; double sum = 0; foreach (var v in values) sum += v;
        if (sum <= 0) return res;
        double scale = r.Width * r.Height / sum; int i = 0; var rect = r;
        while (i < values.Length) {
            double side = Math.Min(rect.Width, rect.Height); int j = i; double rowSum = 0, best = double.MaxValue;
            while (j < values.Length) {
                double s2 = rowSum + values[j] * scale, mn = double.MaxValue, mx = 0;
                for (int k = i; k <= j; k++) { double a = values[k] * scale; mn = Math.Min(mn, a); mx = Math.Max(mx, a); }
                double worst = Math.Max(side * side * mx / (s2 * s2), (s2 * s2) / (side * side * Math.Max(mn, 1e-9)));
                if (worst > best) break; best = worst; rowSum = s2; j++;
            }
            if (j == i) { rowSum = values[i] * scale; j = i + 1; }
            bool horiz = rect.Width >= rect.Height; double thick = rowSum / side; double pos = 0;
            for (int k = i; k < j; k++) {
                double len = values[k] * scale / thick;
                res[k] = horiz ? new RectangleF(rect.X, (float)(rect.Y + pos), (float)thick, (float)len) : new RectangleF((float)(rect.X + pos), rect.Y, (float)len, (float)thick);
                pos += len;
            }
            rect = horiz ? new RectangleF((float)(rect.X + thick), rect.Y, (float)(rect.Width - thick), rect.Height) : new RectangleF(rect.X, (float)(rect.Y + thick), rect.Width, (float)(rect.Height - thick));
            i = j;
        }
        return res;
    }
}
'@ @('System.Drawing')
