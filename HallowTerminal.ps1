<#
  Hallow Toolkit 5.18 - Hallow Terminal: a Hallow look for Windows Terminal, set up from the Hallow tab.
  - A Windows Terminal JSON fragment (Microsoft's supported way to add colour schemes and profiles without touching your
    settings.json): %LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\Hallow\hallow.json + hallow.ico next to it.
    Schemes "Hallow Dark" / "Hallow Light" (the family palette + your Hallow accent), profiles "Hallow PowerShell" and
    "Hallow Command Prompt" (scheme from theme.json's mode: dark, light, or both for "Same as Windows").
  - <toolkit>\terminal\: hallow-prompt.ps1 (the prompt + the `hallow` command, from HallowTerminalShell.ps1), hallow-cmd.cmd
    (Command Prompt's PROMPT and `hallow`), installed.json, and a "Hallow PowerShell" shortcut.
  Never touches Terminal's settings.json or your $PROFILE. Remove deletes only those files and folders.
  No window code here (HallowTerminalPage.ps1 has the section); tests dot-source this file on its own.
  Tests only: HALLOW_TERMINAL_LOCALAPPDATA = a stand-in for %LOCALAPPDATA%.
#>

$HallowTerminalVersion = '1.0'
$TerminalFragmentApp = 'Hallow'
$TerminalNamespace = [guid]'f65ddb7e-706b-4499-8a50-40313caf510a'   # Windows Terminal's namespace for fragment profiles
$TerminalShellSource = Join-Path $PSScriptRoot 'HallowTerminalShell.ps1'

function Get-TerminalLocalAppData { if ($env:HALLOW_TERMINAL_LOCALAPPDATA) { $env:HALLOW_TERMINAL_LOCALAPPDATA } else { $env:LOCALAPPDATA } }
function Get-TerminalFragmentDir([string]$LocalAppData = (Get-TerminalLocalAppData)) { Join-Path $LocalAppData "Microsoft\Windows Terminal\Fragments\$TerminalFragmentApp" }
function Get-TerminalFilesDir([string]$Root) { Join-Path $Root 'terminal' }
# Windows Terminal itself: the per-user wt.exe alias (Store / winget installs and Windows 11's built-in copy all add it)
function Test-WindowsTerminal([string]$LocalAppData = (Get-TerminalLocalAppData)) {
    (Test-Path (Join-Path $LocalAppData 'Microsoft\WindowsApps\wt.exe')) -or (Test-Path (Join-Path $LocalAppData 'Microsoft\WindowsApps\Microsoft.WindowsTerminal_8wekyb3d8bbwe\wt.exe'))
}

# ---------------------------------------------------------------- GUIDs (RFC 4122 version 5, as Microsoft's docs describe)
# name bytes are UTF-16LE; the app's namespace = v5(Terminal's namespace, "Hallow"), a profile = v5(app namespace, its name)
function ConvertTo-TerminalRfcBytes([byte[]]$B) { $c = [byte[]]$B.Clone(); [Array]::Reverse($c, 0, 4); [Array]::Reverse($c, 4, 2); [Array]::Reverse($c, 6, 2); , $c }
function New-TerminalGuidV5([guid]$Namespace, [string]$Name) {
    $ns = ConvertTo-TerminalRfcBytes $Namespace.ToByteArray()
    $nb = [Text.Encoding]::Unicode.GetBytes($Name)
    $sha = [Security.Cryptography.SHA1]::Create(); $h = $sha.ComputeHash([byte[]]($ns + $nb)); $sha.Dispose()
    $g = [byte[]]$h[0..15]
    $g[6] = ($g[6] -band 0x0F) -bor 0x50; $g[8] = ($g[8] -band 0x3F) -bor 0x80
    [guid]::new([byte[]](ConvertTo-TerminalRfcBytes $g))
}
function Get-TerminalProfileGuid([string]$ProfileName, [string]$App = $TerminalFragmentApp) {
    '{' + (New-TerminalGuidV5 (New-TerminalGuidV5 $TerminalNamespace $App) $ProfileName).ToString() + '}'
}

# ---------------------------------------------------------------- colours
function ConvertFrom-TerminalHex([string]$Hex) { @([Convert]::ToInt32($Hex.Substring(1, 2), 16), [Convert]::ToInt32($Hex.Substring(3, 2), 16), [Convert]::ToInt32($Hex.Substring(5, 2), 16)) }
function ConvertTo-TerminalHex([int[]]$Rgb) { '#{0:X2}{1:X2}{2:X2}' -f $Rgb[0], $Rgb[1], $Rgb[2] }
function Get-TerminalLuminance([string]$Hex) {
    $f = { param($v) $v = $v / 255.0; if ($v -le 0.03928) { $v / 12.92 } else { [math]::Pow(($v + 0.055) / 1.055, 2.4) } }
    $c = ConvertFrom-TerminalHex $Hex
    0.2126 * (& $f $c[0]) + 0.7152 * (& $f $c[1]) + 0.0722 * (& $f $c[2])
}
function Get-TerminalContrast([string]$A, [string]$B) {
    $la = Get-TerminalLuminance $A; $lb = Get-TerminalLuminance $B
    ([math]::Max($la, $lb) + 0.05) / ([math]::Min($la, $lb) + 0.05)
}
# the accent moved toward white (dark background) or black (light background) until it reaches $Min against $Bg
function Get-TerminalReadableAccent([string]$Accent, [string]$Bg, [double]$Min = 4.5) {
    $c = ConvertFrom-TerminalHex $Accent; $to = $(if ((Get-TerminalLuminance $Bg) -gt 0.4) { 0 } else { 255 })
    for ($i = 0; $i -lt 60 -and (Get-TerminalContrast (ConvertTo-TerminalHex $c) $Bg) -lt $Min; $i++) { $c = @($c | ForEach-Object { [int][math]::Round($_ + ($to - $_) * 0.06) }) }
    ConvertTo-TerminalHex $c
}
function Get-TerminalAccentHex {
    $h = $null
    try { if (Get-Command Get-HallowAccentHex -ErrorAction SilentlyContinue) { $h = Get-HallowAccentHex } } catch { }
    if ($h -match '^#[0-9A-Fa-f]{6}$') { $h.ToUpper() } else { '#F07820' }   # the family's default orange
}
function Get-TerminalMode {
    $m = 'dark'
    try { if (Get-Command Get-HallowMode -ErrorAction SilentlyContinue) { $m = Get-HallowMode } } catch { }
    if ($m -in 'dark', 'light', 'system') { $m } else { 'dark' }
}
# The two schemes. Dark = the family's dark palette, Light = THEME-MODE-SPEC's light palette. Every ANSI colour reads on its
# background (4.5:1; on the dark one "black" is a background colour and is left out). In the light scheme "white" and
# "bright white" are dark greys on purpose, so text that programs print in white stays readable.
function Get-HallowTerminalSchemes([string]$Accent = '#F07820') {
    $dark = [ordered]@{
        name = 'Hallow Dark'; background = '#121018'; foreground = '#ECE8F4'
        cursorColor = (Get-TerminalReadableAccent $Accent '#121018' 3.0); selectionBackground = '#463A5C'
        black = '#2A2433'; red = '#F05A5A'; green = '#6ED28C'; yellow = '#F0BE5A'; blue = '#6CA8FF'; purple = '#B08CFF'; cyan = '#5AC8C8'; white = '#CFC8DC'
        brightBlack = '#8A8299'; brightRed = '#FF8A8A'; brightGreen = '#95E6AE'; brightYellow = '#FFD98F'; brightBlue = '#9BC4FF'; brightPurple = '#CDB6FF'; brightCyan = '#8CE3E3'; brightWhite = '#FFFFFF'
    }
    $light = [ordered]@{
        name = 'Hallow Light'; background = '#F6F4FA'; foreground = '#1E1A26'
        cursorColor = (Get-TerminalReadableAccent $Accent '#F6F4FA' 3.0); selectionBackground = '#DAD3E6'
        black = '#1E1A26'; red = '#C2333F'; green = '#1B7A44'; yellow = '#8F5B00'; blue = '#1F5FC4'; purple = '#7A5CC0'; cyan = '#0B7380'; white = '#5E5770'
        brightBlack = '#6B6478'; brightRed = '#A3222E'; brightGreen = '#13633A'; brightYellow = '#704700'; brightBlue = '#1A4C9E'; brightPurple = '#5E3FA6'; brightCyan = '#085A64'; brightWhite = '#3B3448'
    }
    , @($dark, $light)
}
$TerminalAnsiNames = 'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white', 'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'
# every pair a scheme has to keep readable: name, ratio, minimum
function Get-TerminalContrastPairs($Scheme) {
    $bg = $Scheme.background; $isDark = (Get-TerminalLuminance $bg) -lt 0.4
    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add([pscustomobject]@{ Pair = 'foreground'; Ratio = (Get-TerminalContrast $Scheme.foreground $bg); Min = 7.0 })
    foreach ($n in $TerminalAnsiNames) {
        if ($isDark -and $n -eq 'black') { continue }
        $rows.Add([pscustomobject]@{ Pair = $n; Ratio = (Get-TerminalContrast $Scheme[$n] $bg); Min = 4.5 })
    }
    $rows.Add([pscustomobject]@{ Pair = 'cursorColor'; Ratio = (Get-TerminalContrast $Scheme.cursorColor $bg); Min = 3.0 })
    $rows.Add([pscustomobject]@{ Pair = 'foreground on selection'; Ratio = (Get-TerminalContrast $Scheme.foreground $Scheme.selectionBackground); Min = 4.5 })
    $rows.ToArray()
}

# ---------------------------------------------------------------- the fragment
# Cascadia Mono when Windows or Windows Terminal has it (Terminal 1.x ships it), else Terminal's own default
function Find-TerminalFont {
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts') {
        try { $p = Get-ItemProperty $k -ErrorAction Stop; foreach ($n in 'Cascadia Mono', 'Cascadia Code') { if (@($p.PSObject.Properties.Name | Where-Object { $_ -like "$n*" }).Count) { return $n } } } catch { }
    }
    # WindowsApps can't be listed, but the package knows where it is
    try { foreach ($p in @(Get-AppxPackage -Name 'Microsoft.WindowsTerminal*' -ErrorAction Stop)) { if ($p.InstallLocation -and [IO.File]::Exists((Join-Path $p.InstallLocation 'CascadiaMono.ttf'))) { return 'Cascadia Mono' } } } catch { }
    $null
}
function Get-TerminalPowerShellCommand([string]$Root) {
    "`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File `"$(Join-Path (Get-TerminalFilesDir $Root) 'hallow-prompt.ps1')`""
}
function New-HallowTerminalFragment([string]$Root, [string]$Accent = '#F07820', [string]$Mode = 'dark', [string]$FontFace = $null) {
    $schemes = Get-HallowTerminalSchemes $Accent
    $scheme = switch ($Mode) { 'light' { 'Hallow Light' } 'system' { [ordered]@{ light = 'Hallow Light'; dark = 'Hallow Dark' } } default { 'Hallow Dark' } }
    $profiles = foreach ($p in @(
            @{ Name = 'Hallow PowerShell'; Cmd = (Get-TerminalPowerShellCommand $Root) },
            @{ Name = 'Hallow Command Prompt'; Cmd = "`"%SystemRoot%\System32\cmd.exe`" /k `"$(Join-Path (Get-TerminalFilesDir $Root) 'hallow-cmd.cmd')`"" })) {
        $o = [ordered]@{ guid = (Get-TerminalProfileGuid $p.Name); name = $p.Name; commandline = $p.Cmd; startingDirectory = '%USERPROFILE%'
            icon = 'hallow.ico'; colorScheme = $scheme; cursorShape = 'bar'; padding = '12, 10'; hidden = $false }
        $o['font'] = [ordered]@{ size = 11 }; if ($FontFace) { $o['font'] = [ordered]@{ face = $FontFace; size = 11 } }
        # a slight acrylic only in the dark look (95 % opaque keeps every colour above its contrast minimum); light stays solid
        if ($Mode -eq 'dark') { $o['opacity'] = 95; $o['useAcrylic'] = $true } else { $o['opacity'] = 100; $o['useAcrylic'] = $false }
        $o
    }
    [ordered]@{ profiles = @($profiles); schemes = @($schemes) }
}
function ConvertTo-TerminalJson($Fragment) { $Fragment | ConvertTo-Json -Depth 8 }

# Command Prompt: PROMPT with cmd's codes ($E = escape, $P = path, $_ = new line, $G = >), the same two-line look, and
# `hallow` through doskey (calls hallow-prompt.ps1 -Cli). "Same as Windows" uses ANSI lilac, which both schemes define.
function Get-HallowCmdScript([string]$Root, [string]$Accent = '#F07820', [string]$Mode = 'dark') {
    $e = [char]27
    if ($Mode -eq 'system') { $col = '35' } else {
        $a = ConvertFrom-TerminalHex (Get-TerminalReadableAccent $Accent $(if ($Mode -eq 'light') { '#F6F4FA' } else { '#121018' }))
        $col = "38;2;$($a[0]);$($a[1]);$($a[2])"
    }
    $ps = Join-Path (Get-TerminalFilesDir $Root) 'hallow-prompt.ps1'
    @(
        '@echo off'
        'rem Hallow Command Prompt (Hallow Toolkit 5.18) - written by the toolkit, Remove on its Hallow tab deletes it'
        'title Hallow Command Prompt'
        "doskey hallow=`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ps`" -Cli `$*"
        "prompt `$E[1;$($col)m`$P`$E[0m`$_`$E[$($col)m`$G`$E[0m`$S"
        "echo $e[1;$($col)mHallow Command Prompt$e[0m$e[90m  -  type hallow help$e[0m"
    ) -join "`r`n"
}

# ---------------------------------------------------------------- install / update / state / remove
function Write-TerminalFile([string]$Path, [string]$Text, $Encoding) {
    $tmp = "$Path.tmp"; [IO.File]::WriteAllText($tmp, $Text, $Encoding)
    if (Test-Path $Path) { Remove-Item $Path -Force }
    Move-Item $tmp $Path -Force
}
function Get-TerminalFileHash([string]$Path) { try { (Get-FileHash $Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { '' } }
# writes (or rewrites) everything; returns the lines to show
function Install-HallowTerminal([string]$Root = $HallowRoot, [string]$LocalAppData = (Get-TerminalLocalAppData), [string]$Accent = (Get-TerminalAccentHex), [string]$Mode = (Get-TerminalMode), [string]$FontFace = '?') {
    if ($FontFace -eq '?') { $FontFace = Find-TerminalFont }
    $frag = Get-TerminalFragmentDir $LocalAppData; $files = Get-TerminalFilesDir $Root
    New-Item -ItemType Directory -Force $frag, $files | Out-Null
    $utf8 = New-Object Text.UTF8Encoding($false)
    # the prompt (UTF-8 with BOM so Windows PowerShell 5.1 reads it right), the Command Prompt script (OEM code page, like cmd)
    Write-TerminalFile (Join-Path $files 'hallow-prompt.ps1') ([IO.File]::ReadAllText($TerminalShellSource)) (New-Object Text.UTF8Encoding($true))
    Write-TerminalFile (Join-Path $files 'hallow-cmd.cmd') (Get-HallowCmdScript $Root $Accent $Mode) ([Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage))
    $ico = Join-Path $Root 'hallow.ico'; if (Test-Path $ico) { Copy-Item $ico (Join-Path $frag 'hallow.ico') -Force }
    Write-TerminalFile (Join-Path $frag 'hallow.json') (ConvertTo-TerminalJson (New-HallowTerminalFragment $Root $Accent $Mode $FontFace)) $utf8
    # "Hallow PowerShell" shortcut: Explorer opens it as you (not as admin, which the toolkit is)
    $lnk = Join-Path $files 'Hallow PowerShell.lnk'
    try {
        $ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $LocalAppData 'Microsoft\WindowsApps\wt.exe'; $s.Arguments = '-p "Hallow PowerShell"'
        if (Test-Path $ico) { $s.IconLocation = $ico }; $s.Save()
    } catch { }
    $state = [ordered]@{ version = $HallowTerminalVersion; toolkit = "$AppVersion"; accent = $Accent; mode = $Mode; font = $FontFace; prompt = (Get-TerminalFileHash $TerminalShellSource); installed = (Get-Date).ToString('s') }
    Write-TerminalFile (Join-Path $files 'installed.json') ([pscustomobject]$state | ConvertTo-Json) $utf8
    @(
        "Hallow Terminal is set up: colour schemes Hallow Dark and Hallow Light, profiles Hallow PowerShell and Hallow Command Prompt ($(@{ dark = 'dark'; light = 'light'; system = 'light / dark like Windows' }[$Mode]), accent $Accent$(if ($FontFace) { ", $FontFace" }))."
        "Added: $frag\hallow.json (a Windows Terminal fragment - your Terminal settings.json is not changed) and $files."
        'Open a new Windows Terminal window to see them. To start in it every time: Terminal > Settings (Ctrl+,) > Startup > Default profile > Hallow PowerShell.'
    )
}
# what's there now: Installed, Current (accent / mode / prompt match), and why not
function Get-HallowTerminalState([string]$Root = $HallowRoot, [string]$LocalAppData = (Get-TerminalLocalAppData), [string]$Accent = (Get-TerminalAccentHex), [string]$Mode = (Get-TerminalMode)) {
    $frag = Join-Path (Get-TerminalFragmentDir $LocalAppData) 'hallow.json'
    $files = Get-TerminalFilesDir $Root
    $inst = $null; try { $inst = Get-Content (Join-Path $files 'installed.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { }
    $installed = (Test-Path $frag) -or (Test-Path (Join-Path $files 'hallow-prompt.ps1'))
    $why = @()
    if ($installed) {
        if (-not (Test-Path $frag)) { $why += 'the Terminal fragment is missing' }
        if (-not (Test-Path (Join-Path $files 'hallow-prompt.ps1'))) { $why += 'the prompt file is missing' }
        if (-not $inst) { $why += 'set up by hand' } else {
            if ("$($inst.accent)" -ne $Accent) { $why += "the Hallow accent changed to $Accent" }
            if ("$($inst.mode)" -ne $Mode) { $why += "light / dark changed to $Mode" }
            if ("$($inst.prompt)" -ne (Get-TerminalFileHash $TerminalShellSource) -or "$($inst.version)" -ne $HallowTerminalVersion) { $why += 'this toolkit has a newer prompt' }
        }
    }
    [pscustomobject]@{ Installed = $installed; Current = ($installed -and -not $why); Why = $why; Terminal = (Test-WindowsTerminal $LocalAppData); Fragment = $frag; Files = $files; Info = $inst }
}
# deletes only what Install wrote: the fragment folder's hallow.json + hallow.ico (and the folder when that leaves it empty)
# and <toolkit>\terminal's files (and the folder when empty). Returns what it removed.
$TerminalOwnFiles = 'hallow-prompt.ps1', 'hallow-cmd.cmd', 'installed.json', 'Hallow PowerShell.lnk', 'hallow-prompt.ps1.tmp', 'hallow-cmd.cmd.tmp', 'installed.json.tmp'
function Remove-HallowTerminal([string]$Root = $HallowRoot, [string]$LocalAppData = (Get-TerminalLocalAppData)) {
    $gone = New-Object System.Collections.Generic.List[string]
    $frag = Get-TerminalFragmentDir $LocalAppData
    foreach ($n in 'hallow.json', 'hallow.ico', 'hallow.json.tmp') { $p = Join-Path $frag $n; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $gone.Add($p) } }
    if ((Test-Path $frag) -and -not @(Get-ChildItem -LiteralPath $frag -Force).Count) { Remove-Item -LiteralPath $frag -Force; $gone.Add("$frag\") }
    $files = Get-TerminalFilesDir $Root
    foreach ($n in $TerminalOwnFiles) { $p = Join-Path $files $n; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $gone.Add($p) } }
    if ((Test-Path $files) -and -not @(Get-ChildItem -LiteralPath $files -Force).Count) { Remove-Item -LiteralPath $files -Force; $gone.Add("$files\") }
    $gone.ToArray()
}
