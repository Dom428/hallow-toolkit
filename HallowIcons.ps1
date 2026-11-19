<#
  Hallow Toolkit - Font Awesome icons (Font Awesome Free 6, solid; font under SIL OFL 1.1, icons under CC BY 4.0 -
  see FontAwesome-LICENSE.txt). Icons are drawn from the font into small bitmaps for buttons, menus and headers.
  If the font file is missing the toolkit still works and shows its old text symbols.
  Dot-sourced by HallowCore.ps1.
#>
Add-Type -AssemblyName System.Drawing

$IconFontFile = Join-Path $HallowRoot 'fa-solid-900.ttf'
$IconFontSha  = 'AF19D135D3A935B3EBFBD80320716FFE1202052C5F68DC2C5F1ABC57005AC605'
$IconFontUrl  = "https://raw.githubusercontent.com/$UpdateRepo/main/fa-solid-900.ttf"

$Fa = @{
    'wand-magic-sparkles' = 0xf72b; 'gauge-high' = 0xf625; 'heart-pulse' = 0xf21e; 'rocket' = 0xf135; 'gamepad' = 0xf11b
    'wifi' = 0xf1eb; 'hard-drive' = 0xf0a0; 'trash-can' = 0xf2ed; 'screwdriver-wrench' = 0xf7d9; 'microchip' = 0xf2db
    'sliders' = 0xf1de; 'code' = 0xf121; 'server' = 0xf233; 'broom' = 0xf51a; 'arrows-rotate' = 0xf021; 'wrench' = 0xf0ad
    'bug' = 0xf188; 'memory' = 0xf538; 'temperature-half' = 0xf2c9; 'globe' = 0xf0ac; 'bolt' = 0xf0e7; 'cubes' = 0xf1b3
    'floppy-disk' = 0xf0c7; 'share-nodes' = 0xf1e0; 'file-import' = 0xf56f; 'folder-open' = 0xf07c; 'power-off' = 0xf011
    'clock-rotate-left' = 0xf1da; 'volume-high' = 0xf028; 'tower-broadcast' = 0xf519; 'magnifying-glass' = 0xf002
    'store' = 0xf54e; 'image' = 0xf03e; 'clock' = 0xf017; 'user-shield' = 0xf505; 'eye-slash' = 0xf070
    'clipboard-check' = 0xf46c; 'copy' = 0xf0c5; 'list-check' = 0xf0ae; 'book' = 0xf02d; 'gears' = 0xf085
    'circle-chevron-right' = 0xf138; 'computer-mouse' = 0xf8cc; 'display' = 0xf390; 'play' = 0xf04b; 'stop' = 0xf04d
    'circle-xmark' = 0xf057; 'download' = 0xf019; 'gear' = 0xf013; 'plug' = 0xf1e6; 'code-branch' = 0xf126
    'file-lines' = 0xf15c; 'arrow-up-right-from-square' = 0xf08e; 'stopwatch' = 0xf2f2; 'caret-right' = 0xf0da
    'shield-halved' = 0xf3ed; 'film' = 0xf008; 'chart-line' = 0xf201; 'circle-check' = 0xf058
    'triangle-exclamation' = 0xf071; 'skull' = 0xf54c; 'network-wired' = 0xf6ff; 'plus' = 0x2b; 'pen' = 0xf304
    'rotate' = 0xf2f1; 'database' = 0xf1c0; 'eraser' = 0xf12d; 'keyboard' = 0xf11c; 'fire' = 0xf06d; 'star' = 0xf005
    'house' = 0xf015; 'circle-info' = 0xf05a; 'box-archive' = 0xf187; 'list' = 0xf03a; 'terminal' = 0xf120
    'lock' = 0xf023; 'location-dot' = 0xf3c5; 'microphone' = 0xf130; 'camera' = 0xf030; 'clipboard' = 0xf328
    'comments' = 0xf086; 'link' = 0xf0c1; 'link-slash' = 0xf127; 'mobile-screen' = 0xf3cf
    'headphones' = 0xf025; 'truck-moving' = 0xf4df; 'wave-square' = 0xf83e
    'layer-group' = 0xf5fd; 'circle-question' = 0xf059; 'cloud' = 0xf0c2; 'moon' = 0xf186; 'window-maximize' = 0xf2d0; 'hourglass-half' = 0xf252
}

# Button title -> icon. First match wins, so specific words come before general ones.
$ToolIconRules = @(
    ,@('^(un)?tick', 'list-check')
    ,@('uninstall|leftover|remove|delete|trash|recycle', 'trash-can')
    ,@('crash|reliability', 'bug')
    ,@('sleep|wake', 'moon')
    ,@('boot|after boot|delay', 'stopwatch')
    ,@('memory|\bram\b', 'memory')
    ,@('driver', 'microchip')
    ,@('bios|pbo|curve', 'microchip')
    ,@('ssd|drive health|disk map|huge files|duplicate', 'hard-drive')
    ,@('backup|back up|backed up|\bsaves?\b', 'floppy-disk')
    ,@('download', 'download')
    ,@('\bimport\b', 'file-import')
    ,@('export|share', 'share-nodes')
    ,@('\bcopy\b', 'copy')
    ,@('clean|junk|tidy|clear', 'broom')
    ,@('privacy|camera|who used', 'user-shield')
    ,@('shader', 'cubes')
    ,@('temp|heat|\bhot\b', 'temperature-half')
    ,@('ping|speed|latency|benchmark', 'gauge-high')
    ,@('\bdns\b', 'globe')
    ,@('network|wi-?fi|apps using internet|adapter', 'wifi')
    ,@('\bports?\b', 'plug')
    ,@('\bgit\b|repo|projects?\b', 'code-branch')
    ,@('vs code', 'code')
    ,@('terminal', 'terminal')
    ,@('audio|sound', 'volume-high')
    ,@('bluetooth', 'tower-broadcast')
    ,@('report', 'clipboard-check')
    ,@('support|help', 'circle-question')
    ,@('restore|undo|history', 'clock-rotate-left')
    ,@('\bstore\b', 'store')
    ,@('icon|thumbnail', 'image')
    ,@('clock', 'clock')
    ,@('chart', 'chart-line')
    ,@('update|upgrade', 'arrows-rotate')
    ,@('search|find|scan|check|test|who is', 'magnifying-glass')
    ,@('^refresh|reload', 'arrows-rotate')
    ,@('repair|fix|reset', 'wrench')
    ,@('session|boost', 'rocket')
    ,@('\bplay\b', 'play')
    ,@('game|steam', 'gamepad')
    ,@('power', 'bolt')
    ,@('restart|reboot', 'power-off')
    ,@('mouse', 'computer-mouse')
    ,@('display|monitor|screen', 'display')
    ,@('folder|biggest|largest|\bopen\b', 'folder-open')
    ,@('server|radarr|gloam|jellyfin', 'server')
    ,@('task manager|services|resource', 'list-check')
    ,@('event|\blogs?\b', 'file-lines')
    ,@('device', 'microchip')
    ,@('set to|disable|apply|tweak|\bpin\b', 'sliders')
    ,@('settings|tray|startup|auto ', 'gear')
    ,@('\b(close|kill|end|stop)\b', 'circle-xmark')
    ,@('install|\bget\b', 'download')
    ,@('start|run|launch', 'play')
    ,@('hidden|show', 'list')
)
function Get-ToolIconName([string]$Title) {
    foreach ($r in $ToolIconRules) { if ($Title -match $r[0]) { return $r[1] } }
    'circle-chevron-right'
}

$script:IconFonts = $null
$script:IconCache = @{}
function Get-IconFamily {
    if ($null -eq $script:IconFonts) {
        $script:IconFonts = $false
        if (Test-Path $IconFontFile) {
            try {
                # Load a private copy: GDI+ keeps the font file locked while the app runs, which would block updates
                # from replacing the toolkit's own copy.
                $len = (Get-Item $IconFontFile).Length
                $copy = Join-Path $env:TEMP "hallow-fa-solid-$len.ttf"
                if (-not (Test-Path $copy) -or (Get-Item $copy).Length -ne $len) { Copy-Item $IconFontFile $copy -Force -ErrorAction Stop }
                $pfc = New-Object System.Drawing.Text.PrivateFontCollection
                $pfc.AddFontFile($copy)
                if ($pfc.Families.Count) { $script:IconFonts = $pfc }
            } catch { }
        }
    }
    if ($script:IconFonts) { $script:IconFonts.Families[0] } else { $null }
}
function Test-IconFont { [bool](Get-IconFamily) }

# Returns a square bitmap of the icon in the given colour, or $null when the font is missing.
function Get-Icon([string]$Name, [System.Drawing.Color]$Color, [int]$Size = 16, [int]$PadRight = 0) {
    if (-not $Fa.ContainsKey($Name)) { return $null }
    $fam = Get-IconFamily
    if (-not $fam) { return $null }
    $key = "$Name|$($Color.ToArgb())|$Size|$PadRight"
    if ($script:IconCache.ContainsKey($key)) { return $script:IconCache[$key] }
    $bmp = New-Object System.Drawing.Bitmap(($Size + $PadRight), $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $font = New-Object System.Drawing.Font($fam, [float]($Size * 0.8), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat ([System.Drawing.StringFormat]::GenericTypographic)
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $brush = New-Object System.Drawing.SolidBrush $Color
    $g.DrawString([char]::ConvertFromUtf32($Fa[$Name]), $font, $brush, (New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)), $sf)
    $brush.Dispose(); $font.Dispose(); $sf.Dispose(); $g.Dispose()
    $script:IconCache[$key] = $bmp
    $bmp
}

# Older installs updated from v3.5 or earlier did not copy the font. Fetch it from this toolkit's own GitHub repo
# (checked against a pinned SHA256), so icons appear on the next start.
$IconFontFetchWork = {
    param($Url, $Dest, $Sha)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = "$Dest.download"
        $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'HallowToolkit'; $wc.DownloadFile($Url, $tmp); $wc.Dispose()
        if ((Get-FileHash $tmp -Algorithm SHA256).Hash -ne $Sha) { Remove-Item $tmp -Force; return 'Icon font download did not match its checksum - skipped.' }
        Move-Item $tmp $Dest -Force
        'Downloaded the icon font - icons show next time the toolkit opens.'
    } catch { "Could not download the icon font ($($_.Exception.Message))." }
}
