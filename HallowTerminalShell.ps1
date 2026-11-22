<#
  Hallow Terminal (Hallow Toolkit 5.18) - the prompt and the `hallow` command of the "Hallow PowerShell" profile in
  Windows Terminal. Hallow Toolkit copies this file to <toolkit>\terminal\hallow-prompt.ps1 when you click Install on the
  Hallow tab, and the profile starts it with:
      powershell.exe -NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "<toolkit>\terminal\hallow-prompt.ps1"
  so your own PowerShell profile ($PROFILE) is never touched. "Hallow Command Prompt" calls it for `hallow` too:
      powershell.exe ... -File "<toolkit>\terminal\hallow-prompt.ps1" -Cli <words>
  It only reads the Hallow apps' status.json files and sends their documented pipe commands (HALLOW-FAMILY.md); it never
  prints keys, tokens, addresses or anything private.
  Speed: every prompt stays far under 30 ms - files are re-read only when they change, games are looked up every 5 s,
  `git status` runs on a background thread (the prompt redraws itself when the answer differs) and is skipped in huge repos.
  Tests only: HALLOW_TERMINAL_APPDATA / HALLOW_TERMINAL_LOCALAPPDATA (data and Programs folders), HALLOW_TERMINAL_PIPE
  (pipe prefix), HALLOW_PROMPT_GIT (git to run), HALLOW_TERMINAL_GAMES (process names), HALLOW_TERMINAL_LOOK (light|dark).
#>
param([switch]$Cli, [Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)

$global:HallowTerm = @{
    Version      = '1.0'
    Root         = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)   # the toolkit folder (terminal\..)
    AppData      = $(if ($env:HALLOW_TERMINAL_APPDATA) { $env:HALLOW_TERMINAL_APPDATA } else { $env:APPDATA })
    LocalAppData = $(if ($env:HALLOW_TERMINAL_LOCALAPPDATA) { $env:HALLOW_TERMINAL_LOCALAPPDATA } else { $env:LOCALAPPDATA })
    PipePrefix   = $(if ($env:HALLOW_TERMINAL_PIPE) { $env:HALLOW_TERMINAL_PIPE } else { 'HallowFamily' })
    Apps         = @('Hub', 'Mixer', 'Vault', 'Overlay', 'Clips', 'Remote', 'Keys', 'Guard', 'Assist', 'Tasks', 'Browser', 'VPN', 'Torrents', 'Gear', 'Financials', 'Home', 'Email', 'Setup')
    Games        = [ordered]@{ 'DeltaForceClient-Win64-Shipping' = 'Delta Force'; 'Discovery-d' = 'Discovery' }
    Files        = @{}          # path -> @{ Time = last write; Data = parsed JSON }
    Esc          = [char]27
    Color        = $true
    GameAt       = [datetime]::MinValue; Game = $null
    LookAt       = [datetime]::MinValue; LookKey = ''; Accent = '38;2;240;120;32'; Light = $false
    Git          = $null; GitState = @{}; GitJob = $null; GitRunspace = $null; Shown = @{}
    LastHistory  = -1; LastExit = 0
    BigIndexBytes = 5MB         # repos with a bigger .git\index (~50k+ files) show the branch only, no `git status`
}
if ($env:HALLOW_TERMINAL_GAMES) { $global:HallowTerm.Games = [ordered]@{}; foreach ($g in ($env:HALLOW_TERMINAL_GAMES -split ',')) { if ($g.Trim()) { $global:HallowTerm.Games[$g.Trim()] = $g.Trim() } } }
try { if (([Console]::IsOutputRedirected -or $env:NO_COLOR) -and -not $env:HALLOW_TERMINAL_COLOR) { $global:HallowTerm.Color = $false } } catch { }

# ---------------------------------------------------------------- small helpers
function global:Get-HallowAnsi([string]$Code) { if ($global:HallowTerm.Color) { "$($global:HallowTerm.Esc)[$($Code)m" } else { '' } }
# a JSON file, parsed again only when its last-write time changes (a half-written file keeps the last good answer)
function global:Read-HallowJsonCached([string]$Path) {
    $c = $global:HallowTerm.Files[$Path]
    $t = [IO.File]::GetLastWriteTimeUtc($Path)   # missing file: 1601-01-01, no exception
    if ($c -and $c.Time -eq $t) { return $c.Data }
    if ($t.Year -lt 1700) { $global:HallowTerm.Files[$Path] = @{ Time = $t; Data = $null }; return $null }
    try { $d = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop } catch { if ($c) { return $c.Data }; return $null }
    $global:HallowTerm.Files[$Path] = @{ Time = $t; Data = $d }
    $d
}
function global:Get-HallowDataDir([string]$App) {
    if ($App -eq 'Clips') { Join-Path $global:HallowTerm.LocalAppData 'HallowClips' } else { Join-Path $global:HallowTerm.AppData "Hallow$App" }
}
function global:Read-HallowStatus([string]$App) { Read-HallowJsonCached (Join-Path (Get-HallowDataDir $App) 'status.json') }
function global:Get-HallowExe([string]$App) { Join-Path $global:HallowTerm.LocalAppData "Programs\Hallow $App\Hallow$App.exe" }
function global:Get-HallowRelLum([int]$R, [int]$G, [int]$B) {
    $f = { param($v) $v = $v / 255.0; if ($v -le 0.03928) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) } }
    0.2126 * (& $f $R) + 0.7152 * (& $f $G) + 0.0722 * (& $f $B)
}
function global:Get-HallowContrast([int[]]$A, [int[]]$B) {
    $la = Get-HallowRelLum $A[0] $A[1] $A[2]; $lb = Get-HallowRelLum $B[0] $B[1] $B[2]
    ([math]::Max($la, $lb) + 0.05) / ([math]::Min($la, $lb) + 0.05)
}

# ---------------------------------------------------------------- the look: accent from theme.json, light or dark
# The prompt's accent is the Hallow accent, darkened (light) or lightened (dark) until it reads on the scheme's background.
function global:Update-HallowLook {
    $T = $global:HallowTerm
    $tj = Read-HallowJsonCached (Join-Path $T.AppData 'Hallow\theme.json')
    $hex = '#F07820'; if ($tj -and "$($tj.accent)" -match '^#[0-9A-Fa-f]{6}$') { $hex = "$($tj.accent)" }
    $mode = if ($tj) { "$($tj.mode)".Trim().ToLower() } else { '' }
    $light = $false
    if ($env:HALLOW_TERMINAL_LOOK -in 'light', 'dark') { $light = ($env:HALLOW_TERMINAL_LOOK -eq 'light') }
    elseif ($mode -eq 'light') { $light = $true }
    elseif ($mode -eq 'system') {
        if (((Get-Date) - $T.LookAt).TotalSeconds -ge 10 -or $T.SysLight -eq $null) {
            $T.LookAt = Get-Date
            try { $T.SysLight = ([int]([Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'AppsUseLightTheme', 0)) -eq 1) } catch { $T.SysLight = $false }
        }
        $light = [bool]$T.SysLight
    }
    $key = "$hex|$light"
    if ($key -eq $T.LookKey) { return }
    $T.LookKey = $key; $T.Light = $light
    $rgb = @([Convert]::ToInt32($hex.Substring(1, 2), 16), [Convert]::ToInt32($hex.Substring(3, 2), 16), [Convert]::ToInt32($hex.Substring(5, 2), 16))
    $bg = if ($light) { @(0xF6, 0xF4, 0xFA) } else { @(0x12, 0x10, 0x18) }
    $to = if ($light) { 0 } else { 255 }
    for ($i = 0; $i -lt 40 -and (Get-HallowContrast $rgb $bg) -lt 4.5; $i++) { $rgb = @($rgb | ForEach-Object { [int][math]::Round($_ + ($to - $_) * 0.06) }) }
    $T.Accent = "38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
}

# ---------------------------------------------------------------- prompt parts
function global:Get-HallowShortPath {
    $loc = $ExecutionContext.SessionState.Path.CurrentLocation
    $p = if ($loc.Provider.Name -eq 'FileSystem') { $loc.ProviderPath } else { $loc.Path }
    $h = $env:USERPROFILE
    if ($h -and $p.StartsWith($h, [StringComparison]::OrdinalIgnoreCase) -and ($p.Length -eq $h.Length -or $p[$h.Length] -eq '\')) { $p = '~' + $p.Substring($h.Length) }
    $parts = $p.TrimEnd('\') -split '\\'
    if ($parts.Count -gt 4) { $p = ($parts[0], [string][char]0x2026, $parts[-2], $parts[-1]) -join '\' }
    if ($p -match '^[A-Za-z]:$') { $p += '\' }
    $p
}
# the game running now: Hub's status.json "playing" (only while Hub runs), else the family game list (checked every 5 s)
function global:Get-HallowGame {
    $T = $global:HallowTerm
    $hub = Read-HallowStatus 'Hub'
    if ($hub -and $hub.running -eq $true -and $hub.playing) {
        foreach ($x in @($hub.playing)) { if ($x -is [string] -and $x) { return $x }; if ($x.name) { return "$($x.name)" } }
    }
    if (((Get-Date) - $T.GameAt).TotalSeconds -ge 5) {
        $T.GameAt = Get-Date; $T.Game = $null
        try {
            $names = @{}; foreach ($p in [Diagnostics.Process]::GetProcesses()) { $names[$p.ProcessName] = 1; $p.Dispose() }
            foreach ($g in $T.Games.Keys) { if ($names.ContainsKey($g)) { $T.Game = $T.Games[$g]; break } }
        } catch { }
    }
    $T.Game
}
function global:Get-HallowVpnBadge {
    $v = Read-HallowStatus 'VPN'
    if (-not $v) { return $null }
    if ($v.connected -eq $true) { return @('32', "VPN $(if ($v.server) { $v.server } elseif ($v.country) { $v.country } else { 'on' })") }
    if ($v.connecting -eq $true) { return @('33', 'VPN connecting') }
    if ($v.paused -eq $true) { return @('33', 'VPN paused for a game') }
    $null
}
# git: branch from .git\HEAD (no process); dirty from `git status` on a background thread
function global:Find-HallowGitDir([string]$Dir) {
    $d = $Dir
    for ($i = 0; $i -lt 40 -and $d; $i++) {
        $g = Join-Path $d '.git'
        if ([IO.Directory]::Exists($g)) { return @($d, $g) }
        if ([IO.File]::Exists($g)) {
            try { $l = [IO.File]::ReadAllText($g).Trim(); if ($l -match '^gitdir:\s*(.+)$') { $gd = $Matches[1].Trim(); if (-not [IO.Path]::IsPathRooted($gd)) { $gd = [IO.Path]::GetFullPath((Join-Path $d $gd)) }; return @($d, $gd) } } catch { }
            return $null
        }
        $d = [IO.Path]::GetDirectoryName($d)
    }
    $null
}
function global:Receive-HallowGitJob {
    $T = $global:HallowTerm; $j = $T.GitJob
    if (-not $j -or -not $j.Handle.IsCompleted) { return $false }
    $T.GitJob = $null
    try { $r = "$(@($j.PS.EndInvoke($j.Handle))[0])" } catch { $r = 'error' }
    try { $j.PS.Dispose() } catch { }
    $T.GitState[$j.Key] = @{ Dirty = $(if ($r -eq 'dirty') { $true } elseif ($r -eq 'clean') { $false } else { $null }); Time = Get-Date }
    $true
}
function global:Start-HallowGitJob([string]$Root, [string]$Key) {
    $T = $global:HallowTerm
    if ($T.GitJob) { return }
    if (-not $T.GitRunspace) {
        $T.GitRunspace = [runspacefactory]::CreateRunspace(); $T.GitRunspace.Open()
    }
    $ps = [powershell]::Create(); $ps.Runspace = $T.GitRunspace
    [void]$ps.AddScript({
        param($git, $root)
        $o = & $git -C $root --no-optional-locks status --porcelain=v1 --untracked-files=normal --ignore-submodules=dirty 2>$null
        if ($LASTEXITCODE -ne 0) { 'error' } elseif ($o) { 'dirty' } else { 'clean' }
    }).AddArgument($T.Git).AddArgument($Root)
    $T.GitJob = @{ PS = $ps; Handle = $ps.BeginInvoke(); Key = $Key }
}
function global:Get-HallowGitInfo {
    $T = $global:HallowTerm
    if (-not $T.Git) { return $null }
    $loc = $ExecutionContext.SessionState.Path.CurrentLocation
    if ($loc.Provider.Name -ne 'FileSystem') { return $null }
    $f = Find-HallowGitDir $loc.ProviderPath
    if (-not $f) { return $null }
    $branch = $null
    try {
        $head = [IO.File]::ReadAllText((Join-Path $f[1] 'HEAD')).Trim()
        if ($head -match '^ref:\s*refs/heads/(.+)$') { $branch = $Matches[1] } elseif ($head.Length -ge 7) { $branch = $head.Substring(0, 7) }
    } catch { return $null }
    $key = $f[1]
    [void](Receive-HallowGitJob)
    $big = $false
    try { $ix = New-Object IO.FileInfo (Join-Path $f[1] 'index'); $big = $ix.Exists -and $ix.Length -gt $T.BigIndexBytes } catch { }
    $st = $T.GitState[$key]
    if (-not $big -and (-not $st -or ((Get-Date) - $st.Time).TotalMilliseconds -gt 1500)) { Start-HallowGitJob $f[0] $key }
    @{ Branch = $branch; Dirty = $(if ($st) { $st.Dirty } else { $null }); Big = $big; Key = $key }
}

# ---------------------------------------------------------------- the prompt
function global:Get-HallowLastCommand { Get-History -Count 1 }   # (tests put a stand-in here)
function global:Get-HallowPromptText([bool]$Ok, $Code) {
    $T = $global:HallowTerm
    Update-HallowLook
    $rs = Get-HallowAnsi '0'
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append((Get-HallowAnsi "1;$($T.Accent)")).Append((Get-HallowShortPath)).Append($rs)
    $gi = Get-HallowGitInfo
    if ($gi) {
        [void]$sb.Append('  ').Append((Get-HallowAnsi '35')).Append($gi.Branch)
        if ($gi.Dirty -eq $true) { [void]$sb.Append(' ').Append((Get-HallowAnsi '33')).Append([char]0x25CF) }
        [void]$sb.Append($rs)
        $T.Shown = @{ Key = $gi.Key; Dirty = $gi.Dirty }
    } else { $T.Shown = @{} }
    $vpn = Get-HallowVpnBadge
    if ($vpn) { [void]$sb.Append('  ').Append((Get-HallowAnsi $vpn[0])).Append([char]0x25C6).Append(' ').Append($vpn[1]).Append($rs) }
    $game = Get-HallowGame
    if ($game) { [void]$sb.Append('  ').Append((Get-HallowAnsi '36')).Append([char]0x25B6).Append(' ').Append($game).Append($rs) }
    # last command: how long (over 2 s) and whether it failed - once per command
    $h = Get-HallowLastCommand
    if ($h -and $h.Id -ne $T.LastHistory) {
        $T.LastHistory = $h.Id
        $sec = ($h.EndExecutionTime - $h.StartExecutionTime).TotalSeconds
        if ($sec -ge 2) { [void]$sb.Append('  ').Append((Get-HallowAnsi '90')).Append($(if ($sec -ge 60) { '{0}m {1}s' -f [int][math]::Floor($sec / 60), [int]($sec % 60) } else { '{0:0.0}s' -f $sec })).Append($rs) }
        if (-not $Ok) { [void]$sb.Append('  ').Append((Get-HallowAnsi '31')).Append([char]0x00D7).Append($(if ($Code -is [int] -and $Code -ne 0) { " $Code" } else { '' })).Append($rs) }
    }
    [void]$sb.Append("`n").Append((Get-HallowAnsi $(if ($Ok) { $T.Accent } else { '31' }))).Append([char]0x276F).Append($rs).Append(' ')
    $sb.ToString()
}

# ---------------------------------------------------------------- the `hallow` command
# is the app's pipe there? (the list of pipes is read at most once a second; a missing pipe never waits for a timeout)
function global:Test-HallowPipe([string]$App) {
    $T = $global:HallowTerm
    if (-not $T.Pipes -or ((Get-Date) - $T.PipesAt).TotalMilliseconds -gt 1000) {
        $T.PipesAt = Get-Date; $T.Pipes = @{}
        try { foreach ($p in [IO.Directory]::GetFiles('\\.\pipe\')) { $T.Pipes[$p.Substring(9)] = 1 } } catch { }
    }
    $T.Pipes.ContainsKey("$($T.PipePrefix).$App.$([Environment]::UserName)")
}
# one line to a running app's pipe, its one-line reply back ($null when the app isn't running)
function global:Send-HallowPipe([string]$App, [string]$Line, [int]$TimeoutMs = 6000) {
    if (-not (Test-HallowPipe $App)) { return $null }
    $c = New-Object IO.Pipes.NamedPipeClientStream('.', "$($global:HallowTerm.PipePrefix).$App.$([Environment]::UserName)", [IO.Pipes.PipeDirection]::InOut)
    try {
        $c.Connect(1500)
        $b = (New-Object Text.UTF8Encoding($false)).GetBytes("$Line`n"); $c.Write($b, 0, $b.Length); $c.Flush()
        $rd = New-Object IO.StreamReader($c, (New-Object Text.UTF8Encoding($false)))
        $t = $rd.ReadLineAsync()
        if (-not $t.Wait($TimeoutMs)) { return 'error no answer in time' }
        "$($t.Result)"
    } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; "error $($e.Message)" } finally { $c.Dispose() }
}
function global:ConvertFrom-HallowReply([string]$Reply) {
    if ($Reply -and $Reply.StartsWith('ok {')) { try { return ($Reply.Substring(3) | ConvertFrom-Json -ErrorAction Stop) } catch { } }
    $null
}
# fresh status: the pipe's `status` while the app runs, else status.json (last known)
function global:Get-HallowLiveStatus([string]$App) {
    $r = Send-HallowPipe $App 'status'
    $j = ConvertFrom-HallowReply $r
    if ($j) { return @{ Data = $j; Running = $true } }
    @{ Data = (Read-HallowStatus $App); Running = [bool]$r }
}
function global:Resolve-HallowAppName([string]$Name) {
    $n = "$Name".Trim() -replace '^hallow\s*', ''
    foreach ($a in @($global:HallowTerm.Apps) + 'Toolkit') { if ($a -ieq $n) { return $a } }
    $null
}
function global:Get-HallowAppVersion([string]$App, $Status) {
    if ($App -eq 'Toolkit') { try { return ([regex]::Match([IO.File]::ReadAllText((Join-Path $global:HallowTerm.Root 'HallowCore.ps1')), "AppVersion = '([^']+)'")).Groups[1].Value } catch { return '?' } }
    if ($Status -and $Status.version) { return "$($Status.version)" }
    try { $v = [Diagnostics.FileVersionInfo]::GetVersionInfo((Get-HallowExe $App)); if ($v.ProductVersion) { return ($v.ProductVersion -replace '(\.0)+$', '') } } catch { }
    '?'
}
function global:Format-HallowKBps($v) { if ($v -eq $null) { return '' }; $d = [double]$v; if ($d -ge 1024) { '{0:0.0} MB/s' -f ($d / 1024) } else { '{0:0} KB/s' -f $d } }
# one line saying what an app is doing - only counts, names the user typed for devices and states (never secrets)
function global:Get-HallowStateLine([string]$App, $s) {
    if (-not $s) { return '' }
    $t = switch ($App) {
        'VPN' {
            if ($s.connected -eq $true) { "connected to $($s.server)$(if ($s.country) { " ($($s.country))" })$(if ($s.protocol) { ", $($s.protocol)" })" }
            elseif ($s.connecting -eq $true) { 'connecting' } elseif ($s.paused -eq $true) { 'paused for a game' } else { 'off' }
            if ($s.killSwitch -eq $true) { 'kill switch on' }
        }
        'Torrents' {
            "$([int]$s.active) active, $([int]$s.paused) paused, $([int]$s.seeding) seeding"
            if ($s.downKBps -ne $null -and [double]$s.downKBps -gt 0) { "down $(Format-HallowKBps $s.downKBps)" }
            if ($s.held) { "held ($($s.held))" }
        }
        'Gear' { @($s.devices | Select-Object -First 3 | ForEach-Object { "$($_.name) $(if ($_.battery -ne $null) { "$($_.battery)%" } else { $_.state })" }) -join ', ' }
        'Guard' { if ($s.score -ne $null) { "score $($s.score)$(if ($s.scoreLabel) { " - $($s.scoreLabel)" })" }; if ($s.scanning -eq $true) { 'scanning' } }
        'Clips' { if ($s.recording -eq $true) { "recording$(if ($s.game) { " $($s.game)" })" } else { 'not recording' } }
        'Hub' { if ($s.playing) { "playing $(@($s.playing | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) -join ', ')" } }
        'Vault' { "$(@($s.games).Count) games$(if ($s.busy -eq $true) { ', backing up' })" }
        'Overlay' { if ($s.visible -eq $true) { 'panel showing' } else { 'panel hidden' } }
        'Email' { if ($s.unread -ne $null) { "$($s.unread) unread" } }
        'Financials' { if ($s.locked -eq $true) { 'locked' } elseif ($s.vault -eq $true) { 'unlocked' }; if ([int]$s.billsDueSoon -gt 0) { "$($s.billsDueSoon) bills due soon" } }
        'Home' { if ($s.connected -eq $true) { 'connected to Home Assistant' } elseif ($s.configured -eq $false) { 'not set up' } else { 'not connected' }; if ([int]$s.alerts -gt 0) { "$($s.alerts) alerts" } }
        'Tasks' { if ($s.game) { "game: $($s.game)" } elseif ($s.cpu -ne $null) { "CPU $([int]$s.cpu)%" } }
        'Browser' { if ($s.tabs -ne $null) { "$($s.tabs) tabs" } }
        'Assist' { if ($s.session -and $s.session -ne 'none') { "session: $($s.session)" } else { 'no session' } }
        default { '' }
    }
    $t = @($t | Where-Object { $_ }) -join ', '
    if ($s.lastCrash) { try { $lc = [datetime]::Parse("$($s.lastCrash)"); if (((Get-Date) - $lc).TotalDays -le 7) { $t = ($t, "crashed $($lc.ToString('ddd HH:mm'))" | Where-Object { $_ }) -join ', ' } } catch { } }
    $t
}
function global:Write-HallowLine([string]$Text, [string]$Code) { if ($Code) { "$(Get-HallowAnsi $Code)$Text$(Get-HallowAnsi '0')" } else { $Text } }

function global:Invoke-HallowStatus {
    $T = $global:HallowTerm
    $rows = foreach ($a in $T.Apps) {
        if (-not [IO.File]::Exists((Get-HallowExe $a))) { continue }
        $running = $(if ($a -eq 'Setup') { $null } else { Test-HallowPipe $a })   # Setup has no pipe: it only runs while you use it
        $file = Read-HallowStatus $a; $s = $file
        if ($running) { $j = ConvertFrom-HallowReply (Send-HallowPipe $a 'status' 1500); if ($j) { $s = $j } }
        [pscustomobject]@{ App = $a; Running = $running; Version = (Get-HallowAppVersion $a $(if ($s -and $s.version) { $s } else { $file })); State = $(if ($a -eq 'Setup') { 'hallow update uses it' } else { Get-HallowStateLine $a $s }) }
    }
    $rows = @($rows) + [pscustomobject]@{ App = 'Toolkit'; Running = $null; Version = (Get-HallowAppVersion 'Toolkit' $null); State = 'this terminal comes from it' }
    if ($rows.Count -eq 1) { Write-HallowLine 'No Hallow apps are installed yet - Hallow Setup or the Hallow tab in Hallow Toolkit installs them.' '90' }
    foreach ($r in $rows) {
        $u = $global:HallowTerm.Color   # plain ASCII when the output goes to a file or pipe (any code page)
        $dot = if ($r.Running -eq $true) { Write-HallowLine $(if ($u) { [string][char]0x25CF } else { '+' }) '32' } elseif ($r.Running -eq $false) { Write-HallowLine $(if ($u) { [string][char]0x25CB } else { '-' }) '90' } else { ' ' }
        $run = if ($r.Running -eq $true) { 'running    ' } elseif ($r.Running -eq $false) { 'not running' } else { '           ' }
        '{0} {1,-11} {2,-9} {3}  {4}' -f $dot, $r.App, $r.Version, $(if ($r.Running -eq $true) { Write-HallowLine $run '32' } else { Write-HallowLine $run '90' }), $r.State
    }
    0
}
function global:Invoke-HallowVpn([string]$What, [string[]]$More) {
    if (-not [IO.File]::Exists((Get-HallowExe 'VPN'))) { Write-HallowLine "Hallow VPN isn't installed." '33'; return 2 }
    $st = Get-HallowLiveStatus 'VPN'; $s = $st.Data
    if ($What -in '', 'status') {
        if (-not $st.Running) { Write-HallowLine "Hallow VPN isn't running$(if ($s) { ' - last known:' } else { '.' })" '90' }
        if ($s) { "VPN: $(Get-HallowStateLine 'VPN' $s)"; if ($s.connected -eq $true -and $s.since) { try { "Since $([datetime]::Parse("$($s.since)").ToString('ddd HH:mm'))" } catch { } }; if ($s.splitMode) { "Split tunnelling: $($s.splitMode)" } }
        return 0
    }
    if (-not $st.Running) { Write-HallowLine "Hallow VPN isn't running. Start it with: hallow open vpn" '33'; return 2 }
    if ($What -eq 'on') {
        if ($s.connected -eq $true) { "Already connected to $($s.server)."; return 0 }
        if ($s.needsUac -and $s.needsUac.connect -eq $true) { Write-HallowLine "This connect uses $(if ($s.nextProtocol) { $s.nextProtocol } else { 'NordLynx' }), which needs Windows to ask you (UAC) - do it from the VPN window: hallow open vpn" '33'; return 3 }
        $line = 'connect' + $(if ($More) { ' ' + ($More -join ' ') } else { '' })
        $r = Send-HallowPipe 'VPN' $line
    } elseif ($What -eq 'off') {
        if ($s -and $s.connected -ne $true -and $s.connecting -ne $true) { 'The VPN is already off.'; return 0 }
        if ($s.needsUac -and $s.needsUac.disconnect -eq $true) { Write-HallowLine 'Disconnecting NordLynx needs Windows to ask you (UAC) - do it from the VPN window: hallow open vpn' '33'; return 3 }
        $r = Send-HallowPipe 'VPN' 'disconnect'
    } else { Write-HallowLine "Use: hallow vpn on [fastest|gaming|<country>|<server>] | off | status" '33'; return 1 }
    if ($r -like 'ok*') { Write-HallowLine $(if ($What -eq 'on') { 'Connecting... (hallow vpn status shows when it is up)' } else { 'Disconnecting.' }) '32'; return 0 }
    Write-HallowLine "Hallow VPN: $(($r -replace '^error\s*', ''))" '31'; 1
}
function global:Invoke-HallowTorrents([string]$What) {
    if (-not [IO.File]::Exists((Get-HallowExe 'Torrents'))) { Write-HallowLine "Hallow Torrents isn't installed." '33'; return 2 }
    $st = Get-HallowLiveStatus 'Torrents'
    if ($What -in '', 'status') {
        if (-not $st.Running) { Write-HallowLine "Hallow Torrents isn't running$(if ($st.Data) { ' - last known:' } else { '.' })" '90' }
        if ($st.Data) { $s = $st.Data; "Torrents: $(Get-HallowStateLine 'Torrents' $s)"; "Total $([int]$s.total), done $([int]$s.done), queued $([int]$s.queued)$(if ($s.upKBps -ne $null) { ", up $(Format-HallowKBps $s.upKBps)" })"; if ($s.vpnRequired -eq $true) { "Runs only over the VPN$(if ($s.vpnLocked -eq $true) { ' - locked: waiting for the VPN' })" } }
        return 0
    }
    if (-not $st.Running) { Write-HallowLine "Hallow Torrents isn't running. Start it with: hallow open torrents" '33'; return 2 }
    $cmd = @{ pause = 'pause-all'; resume = 'resume-all' }[$What]
    if (-not $cmd) { Write-HallowLine 'Use: hallow torrents pause | resume | status' '33'; return 1 }
    $r = Send-HallowPipe 'Torrents' $cmd
    if ($r -like 'ok*') { Write-HallowLine $(if ($What -eq 'pause') { 'Paused every torrent.' } else { 'Resumed.' }) '32'; return 0 }
    Write-HallowLine "Hallow Torrents: $(($r -replace '^error\s*', ''))" '31'; 1
}
function global:Invoke-HallowGear {
    if (-not [IO.File]::Exists((Get-HallowExe 'Gear'))) { Write-HallowLine "Hallow Gear isn't installed." '33'; return 2 }
    $st = Get-HallowLiveStatus 'Gear'; $s = $st.Data
    if (-not $st.Running) { Write-HallowLine "Hallow Gear isn't running$(if ($s) { ' - last known:' } else { '.' })" '90' }
    if (-not $s -or -not @($s.devices).Count) { 'No devices found yet.'; return 0 }
    $low = if ($s.lowAt) { [int]$s.lowAt } else { 20 }
    foreach ($d in @($s.devices)) {
        $b = if ($d.battery -ne $null) { [int]$d.battery } else { $null }
        $code = if ($b -eq $null) { '90' } elseif ($b -le $low) { '31' } elseif ($b -le 40) { '33' } else { '32' }
        $full = $(if ($global:HallowTerm.Color) { [char]0x25A0 } else { '#' }); $empty = $(if ($global:HallowTerm.Color) { [char]0x00B7 } else { '.' })
        $bar = if ($b -ne $null) { ([string]$full * [math]::Ceiling($b / 20)).PadRight(5, $empty) } else { '     ' }
        '{0,-20} {1} {2,4}  {3}' -f "$($d.name)", (Write-HallowLine $bar $code), $(if ($b -ne $null) { "$b%" } else { '' }), "$($d.state)$(if ($d.paused -eq $true) { ' (not asked during a game)' })"
    }
    0
}
function global:Invoke-HallowOpen([string]$Name) {
    $a = Resolve-HallowAppName $Name
    if (-not $a) { Write-HallowLine "Which app? hallow open <$((@($global:HallowTerm.Apps) + 'Toolkit') -join '|')>" '33'; return 1 }
    if ($a -eq 'Toolkit') {
        $bat = Join-Path $global:HallowTerm.Root 'Hallow Toolkit.bat'
        if (-not [IO.File]::Exists($bat)) { Write-HallowLine "Can't find Hallow Toolkit next to this terminal." '31'; return 1 }
        Start-Process -FilePath $bat -WindowStyle Hidden; 'Opening Hallow Toolkit (Windows asks for admin).'; return 0
    }
    $r = Send-HallowPipe $a 'open'
    if ($r -like 'ok*') { "Hallow $a is in front."; return 0 }
    $exe = Get-HallowExe $a
    if (-not [IO.File]::Exists($exe)) { Write-HallowLine "Hallow $a isn't installed - hallow update shows what is." '33'; return 2 }
    Start-Process -FilePath $exe; "Starting Hallow $a."; 0
}
function global:Invoke-HallowUpdate([string]$Name) {
    $exe = Get-HallowExe 'Setup'
    if (-not [IO.File]::Exists($exe)) { Write-HallowLine "hallow update uses Hallow Setup, which isn't installed (github.com/Dom428/hallow-setup)." '33'; return 2 }
    $v = $null; try { $v = [version]([Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion) } catch { }
    if ($v -and $v -lt [version]'1.18') { Write-HallowLine "hallow update needs Hallow Setup 1.18 or newer (this is $($v.Major).$($v.Minor)) - update Hallow Setup from its window first." '33'; return 2 }
    if ($Name) {
        $a = Resolve-HallowAppName $Name
        if (-not $a -and $Name -ine 'shield') { Write-HallowLine "There's no Hallow app called $Name." '33'; return 1 }
        if (-not $a) { $a = 'Shield' }
        Start-Process -FilePath $exe -ArgumentList '--update', $a
        "Hallow Setup is updating Hallow $a in its window."; return 0
    }
    $out = Join-Path ([IO.Path]::GetTempPath()) "hallow-update-$PID.json"
    Write-HallowLine 'Asking GitHub for the newest versions (Hallow Setup --list --check)...' '90'
    try {
        $p = Start-Process -FilePath $exe -ArgumentList '--list', '--check', '--json', '--out', "`"$out`"" -WindowStyle Hidden -PassThru
        if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch { }; Write-HallowLine 'Hallow Setup took too long - try again later.' '31'; return 1 }
        $raw = [IO.File]::ReadAllText($out) | ConvertFrom-Json; $items = @($raw | ForEach-Object { $_ })
    } catch { Write-HallowLine "Couldn't read Hallow Setup's answer: $($_.Exception.Message)" '31'; return 1 }
    finally { Remove-Item $out -Force -ErrorAction SilentlyContinue }
    $n = 0
    foreach ($i in @($items | Where-Object { $_.installed -eq $true })) {
        if ($i.updateAvailable -eq $true) { $n++; '{0,-12} {1,-8} -> {2}' -f $i.name, $i.version, (Write-HallowLine "$($i.latest) is out" '33') }
        else { '{0,-12} {1,-8} {2}' -f $i.name, $i.version, (Write-HallowLine $(if ($i.latest) { 'up to date' } else { '' }) '32') }
    }
    if (-not @($items | Where-Object { $_.installed -eq $true }).Count) { 'No Hallow apps are installed yet.' }
    if ($n) { ''; "To update one: hallow update <app>  (Hallow Setup does it in its window)" } else { Write-HallowLine 'Everything is up to date.' '32' }
    0
}
function global:Get-HallowHelp {
    @"
$(Write-HallowLine 'hallow' "1;$($global:HallowTerm.Accent)") - the Hallow apps from the terminal

  hallow status                 every Hallow app on this PC: running or not, version, what it's doing
  hallow vpn on [target]        connect Hallow VPN (target: fastest, gaming, a country code or a server)
  hallow vpn off | status       disconnect / show the connection
  hallow torrents pause|resume  pause or resume every torrent (status: counts and speed)
  hallow gear                   batteries of your mouse, headset and other gear (Hallow Gear)
  hallow open <app>             bring an app to the front, or start it (Tab completes the names)
  hallow update [app]           newest versions from GitHub (Hallow Setup); with an app: update it
  hallow help                   this list

Only the apps' status files and their own commands are used - nothing private is shown.
"@
}
function global:hallow {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Command, [Parameter(Position = 1)][string]$Target, [Parameter(Position = 2, ValueFromRemainingArguments = $true)][string[]]$Rest)
    $code = switch ("$Command".ToLower()) {
        { $_ -in '', 'help', '-h', '--help', '/?' } { Get-HallowHelp; 0; break }
        'status' { Invoke-HallowStatus; break }
        'vpn' { Invoke-HallowVpn "$Target".ToLower() $Rest; break }
        'torrents' { Invoke-HallowTorrents "$Target".ToLower(); break }
        'gear' { Invoke-HallowGear; break }
        'open' { Invoke-HallowOpen $Target; break }
        'update' { Invoke-HallowUpdate $Target; break }
        default { Write-HallowLine "Unknown command: $Command" '33'; Get-HallowHelp; 1 }
    }
    # the last number written is the exit code; everything before it is the output
    $all = @($code); $global:LASTEXITCODE = [int]$all[-1]
    if ($all.Count -gt 1) { $all[0..($all.Count - 2)] }
}
Register-ArgumentCompleter -CommandName hallow -ParameterName Command -ScriptBlock {
    param($cmd, $param, $word)
    'status', 'vpn', 'torrents', 'gear', 'open', 'update', 'help' | Where-Object { $_ -like "$word*" } | ForEach-Object { New-Object System.Management.Automation.CompletionResult $_, $_, 'ParameterValue', $_ }
}
Register-ArgumentCompleter -CommandName hallow -ParameterName Target -ScriptBlock {
    param($cmd, $param, $word, $ast, $bound)
    $list = switch ("$($bound['Command'])".ToLower()) {
        'vpn' { 'on', 'off', 'status' }
        'torrents' { 'pause', 'resume', 'status' }
        'open' { @($global:HallowTerm.Apps) + 'Toolkit' | ForEach-Object { $_.ToLower() } }
        'update' { @($global:HallowTerm.Apps | Where-Object { $_ -ne 'Setup' }) + 'Toolkit', 'Shield' | ForEach-Object { $_.ToLower() } }
        default { @() }
    }
    $list | Where-Object { $_ -like "$word*" } | ForEach-Object { New-Object System.Management.Automation.CompletionResult $_, $_, 'ParameterValue', $_ }
}

# ---------------------------------------------------------------- start
if ($Cli) {   # called from Hallow Command Prompt (or a script): run one hallow command and exit with its code
    $a = @($CliArgs)
    hallow @a
    exit $LASTEXITCODE
}

$global:HallowTerm.Git = $(if ($env:HALLOW_PROMPT_GIT) { $env:HALLOW_PROMPT_GIT } elseif ($env:HALLOW_PROMPT_NOGIT) { $null } else { $g = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($g) { $g.Source } })
$null = '{}' | ConvertFrom-Json   # loads the JSON reader now, not in the first prompt
try {   # errors and warnings on the window's own background (not a black band in the light scheme)
    $bgc = $Host.UI.RawUI.BackgroundColor
    foreach ($k in 'ErrorBackgroundColor', 'WarningBackgroundColor', 'DebugBackgroundColor', 'VerboseBackgroundColor', 'ProgressBackgroundColor') { $Host.PrivateData.$k = $bgc }
    $Host.UI.RawUI.WindowTitle = 'Hallow PowerShell'
} catch { }
Update-HallowLook
$null = Get-HallowPromptText $true $null; $global:HallowTerm.LastHistory = -1   # warm up (compiles everything now, not in the first prompt)
function global:prompt {
    $ok = $?; $code = $global:LASTEXITCODE
    try {
        $c = $(if ($code -ne $global:HallowTerm.LastExit) { $code } else { $null }); $global:HallowTerm.LastExit = $code
        Get-HallowPromptText $ok $c
    } catch { "PS $($executionContext.SessionState.Path.CurrentLocation)> " }
}
# when `git status` comes back with something different from what the prompt shows, redraw the prompt (PSReadLine idle event)
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -SupportEvent -Action {
    try {
        $T = $global:HallowTerm
        if (-not $T.GitJob -or -not $T.GitJob.Handle.IsCompleted) { return }
        $key = $T.GitJob.Key
        [void](Receive-HallowGitJob)
        if ($T.Shown.Key -eq $key -and $T.Shown.Dirty -ne $T.GitState[$key].Dirty) { [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
    } catch { }
}
Write-Host "$(Get-HallowAnsi "1;$($global:HallowTerm.Accent)")Hallow PowerShell$(Get-HallowAnsi '0')$(Get-HallowAnsi '90')  $([char]0x00B7)  type hallow help$(Get-HallowAnsi '0')"
