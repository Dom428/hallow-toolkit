<#
  Hallow Toolkit - motherboard driver & BIOS updates, Windows Update drivers, and toolkit self-update.
  Dot-sourced by HallowCore.ps1. The *Work scriptblocks run in background runspaces, so they are self-contained.
#>

# GitHub repo that hosts toolkit releases (each release has the share zip attached).
$UpdateRepo = 'Dom428/hallow-toolkit'
$DriverDownloadRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\Hallow Drivers'

# ================================================================ MOTHERBOARD

function Get-BoardInfo {
    $b = Get-CimInstance Win32_BaseBoard; $bi = Get-CimInstance Win32_BIOS
    $mf = "$($b.Manufacturer)".Trim(); $model = "$($b.Product)".Trim()
    $vendor = switch -Regex ($mf) {
        'ASUS' { 'ASUS'; break } 'Micro-Star|^MSI' { 'MSI'; break } 'Gigabyte' { 'Gigabyte'; break }
        'ASRock' { 'ASRock'; break } 'Dell' { 'Dell'; break } 'HP|Hewlett' { 'HP'; break } 'Lenovo' { 'Lenovo'; break }
        default { $mf }
    }
    [pscustomobject]@{ Vendor = $vendor; Maker = $mf; Model = $model; Bios = "$($bi.SMBIOSBIOSVersion)".Trim(); BiosDate = $bi.ReleaseDate }
}

function Get-BoardSupportUrl($Board) {
    $q = [uri]::EscapeDataString($Board.Model)
    switch ($Board.Vendor) {
        'ASUS'     { "https://www.asus.com/support/search-result/?searchType=support&searchKey=$q" }
        'MSI'      { "https://www.msi.com/search/$q" }
        'Gigabyte' { "https://www.gigabyte.com/Search?kw=$q" }
        'ASRock'   { "https://www.asrock.com/search/index.asp?Keyword=$q" }
        'Dell'     { 'https://www.dell.com/support/home/' }
        'HP'       { 'https://support.hp.com/drivers' }
        'Lenovo'   { 'https://pcsupport.lenovo.com/' }
        default    { "https://www.bing.com/search?q=$q+motherboard+drivers+support" }
    }
}

# Finds the newest drivers + BIOS for the board (ASUS has a public API) and compares them with what is installed.
$BoardScanWork = {
    param($Vendor, $Model, $CurrentBios)
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($Vendor -ne 'ASUS') { return [pscustomobject]@{ Error = 'NOAPI' } }
    $slug = ($Model -replace '[^A-Za-z0-9]+', '-').Trim('-')
    $hdr = @{ 'User-Agent' = 'Mozilla/5.0 (HallowToolkit)' }
    function Query([string]$Endpoint, [string]$Extra) {
        foreach ($sys in 'rog', 'asus') {
            $u = "https://rog.asus.com/support/webapi/product/${Endpoint}?website=us&model=$slug&cpu=&pdid=0&LevelTagId=0&systemCode=$sys$Extra"
            try { $r = Invoke-RestMethod $u -Headers $hdr -TimeoutSec 30; if ($r.Status -eq 'SUCCESS' -and $r.Result.Obj) { return $r.Result.Obj } } catch { }
        }
        $null
    }
    function Ver([string]$s) { $m = [regex]::Match("$s", '\d+(\.\d+){1,3}'); if ($m.Success) { try { [version]$m.Value } catch { $null } } else { $null } }
    function Brand([string]$s) {
        switch -Regex ($s) {
            'MTK|MediaTek' { 'mediatek'; break } 'QCA|Qualcomm|Killer' { 'qualcomm'; break } 'Intel' { 'intel'; break }
            'Realtek|RTK' { 'realtek'; break } 'Marvell|Aquantia' { 'marvell'; break } 'AMD' { 'amd'; break }
            'ITE' { 'ite'; break } default { 'other' }
        }
    }

    $installed = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceClass -in 'NET', 'MEDIA', 'BLUETOOTH' -and $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' -and
            $_.DeviceName -notmatch 'Virtual|Tailscale|Nord|WAN Miniport|TAP|OpenVPN|WireGuard|NVIDIA|Hyper-V' })
    $match = @{
        'LAN'       = { param($d) $d.DeviceClass -eq 'NET' -and $d.DeviceName -match 'Ethernet|LAN|GbE|2\.5G|5G|10G|Controller' -and $d.DeviceName -notmatch 'Wi-?Fi|Wireless|WLAN|802\.11' }
        'Wireless'  = { param($d) $d.DeviceClass -eq 'NET' -and $d.DeviceName -match 'Wi-?Fi|Wireless|WLAN|802\.11' }
        'Bluetooth' = { param($d) $d.DeviceClass -eq 'BLUETOOTH' }
        'Audio'     = { param($d) $d.DeviceClass -eq 'MEDIA' -and $d.DeviceName -match 'Realtek|Audio' -and $d.DeviceName -notmatch 'NVIDIA|AMD High Definition' }
    }
    $chipsetVer = $null
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        $c = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^AMD Chipset Software|Intel.*Chipset Device Software' } | Select-Object -First 1
        if ($c) { $chipsetVer = $c.DisplayVersion; break }
    }
    $hasIgpu = [bool](Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'AMD Radeon\(TM\) Graphics|Intel.*(UHD|Iris|Arc).*Graphics' -and $_.Status -eq 'OK' })

    $out = New-Object System.Collections.ArrayList
    $bios = Query 'GetPDBIOS' ''
    if ($bios) {
        $f = @($bios[0].Files | Where-Object { "$($_.IsRelease)" -eq '1' -and $_.Title -notmatch 'Firmware|Tool' -and "$($_.DownloadUrl.Global)" -match '\.zip' })[0]
        if ($f) {
            $cur = 0; [void][int]::TryParse(($CurrentBios -replace '\D', ''), [ref]$cur)
            $new = 0; [void][int]::TryParse(("$($f.Version)" -replace '\D', ''), [ref]$new)
            $status = if ($new -gt $cur) { "Newer (you have $CurrentBios)" } else { 'Up to date' }
            [void]$out.Add([pscustomobject]@{ Kind = 'BIOS'; Category = 'BIOS'; Title = "BIOS $($f.Version)"; Version = "$($f.Version)"; Date = "$($f.ReleaseDate)"
                Size = "$($f.FileSize)"; Status = $status; Url = "$($f.DownloadUrl.Global)"; Sha256 = "$($f.sha256)"; Notes = ("$($f.Description)" -replace '<br\s*/?>', ' ' -replace '"', '' -replace '\s*Before running the USB BIOS Flashback.*$', '' -replace '\s+', ' ').Trim() })
        }
    }
    $drv = Query 'GetPDDrivers' '&osid=52'
    if (-not $drv -and -not $bios) { return [pscustomobject]@{ Error = "ASUS has no download list for '$Model' (or the site did not answer)." } }
    foreach ($cat in @($drv)) {
        $name = "$($cat.Name)"
        $files = @($cat.Files | Where-Object { "$($_.IsRelease)" -ne '0' -and "$($_.DownloadUrl.Global)" })
        if (-not $files) { continue }
        $groups = $files | Group-Object { if ($name -like 'Utilities*') { ("$($_.Title)" -replace '\s+[vV]?\d[\d\.]*.*$', '').Trim() } else { Brand $_.Title } }
        $devs = if ($match.ContainsKey($name)) { @($installed | Where-Object { & $match[$name] $_ }) } else { @() }
        foreach ($g in $groups) {
            $f = $g.Group | Sort-Object { [datetime]::ParseExact("$($_.ReleaseDate)", 'yyyy/MM/dd', $null) } -Descending | Select-Object -First 1
            $brand = Brand $f.Title
            $kind = 'Driver'; $status = 'Optional'; $have = ''
            if ($match.ContainsKey($name)) {
                $dev = @($devs | Where-Object { (Brand "$($_.DriverProviderName) $($_.DeviceName) $($_.Manufacturer)") -eq $brand }) | Select-Object -First 1
                if (-not $dev) { continue }     # you don't have this chip - skip it
                $have = "$($dev.DriverVersion)"
                $nv = Ver $f.Version; $iv = Ver $have
                $fileDate = [datetime]::ParseExact("$($f.ReleaseDate)", 'yyyy/MM/dd', $null)
                if ($nv -and $iv -and $nv.Major -eq $iv.Major) { $status = if ($nv -gt $iv) { "Newer (you have $have)" } else { 'Up to date' } }
                elseif ($dev.DriverDate -and $fileDate -gt $dev.DriverDate.AddDays(30)) { $status = "Newer (yours is from {0:yyyy-MM-dd})" -f $dev.DriverDate }
                else { $status = 'Up to date' }
            } elseif ($name -eq 'Chipset') {
                $nv = Ver $f.Version; $iv = Ver $chipsetVer
                $status = if (-not $iv) { 'Recommended (not found)' } elseif ($nv -and $nv -gt $iv) { "Newer (you have $chipsetVer)" } else { 'Up to date' }
            } elseif ($name -eq 'VGA') { $status = if ($hasIgpu) { 'Only if you use CPU graphics' } else { continue } }
            elseif ($name -eq 'SATA') { $status = 'Only for RAID setups' }
            elseif ($name -like 'Utilities*') { $kind = 'App'; $status = 'Optional app' }
            [void]$out.Add([pscustomobject]@{ Kind = $kind; Category = $name; Title = ("$($f.Title)" -replace '\s+', ' ' -replace '\s*for\s+(for\s+)?Windows.*$|\s*\(WHQL\)|\.$', '').Trim(); Version = "$($f.Version)"; Date = "$($f.ReleaseDate)"
                Size = "$($f.FileSize)"; Status = $status; Url = "$($f.DownloadUrl.Global)"; Sha256 = "$($f.sha256)"; Notes = '' })
        }
    }
    $order = @{ 'BIOS' = 0; 'Chipset' = 1; 'LAN' = 2; 'Wireless' = 3; 'Bluetooth' = 4; 'Audio' = 5; 'USB' = 6; 'SATA' = 7; 'VGA' = 8 }
    $out | Sort-Object @{ e = { if ($order.ContainsKey($_.Category)) { $order[$_.Category] } else { 50 } } }, Title
}

# Downloads each picked item, checks its SHA-256 against the maker's, unpacks it and runs the signed installer.
$DriverInstallWork = {
    param($Items, $Root)
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force $Root | Out-Null
    foreach ($it in $Items) {
        $url = ($it.Url -split '\?')[0]
        $file = [IO.Path]::GetFileName($url)
        $safe = ($it.Category -replace '[^\w\- ]', '').Trim()
        $dir = Join-Path $Root "$safe - $([IO.Path]::GetFileNameWithoutExtension($file))"
        $zip = Join-Path $Root $file
        "== $($it.Title)"
        try {
            if (-not (Test-Path $zip)) {
                "   downloading $($it.Size) from ASUS..."
                $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'Mozilla/5.0 (HallowToolkit)'
                $wc.DownloadFile($it.Url, $zip); $wc.Dispose()
            }
            $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
            if ($it.Sha256) {
                if ($hash -ne $it.Sha256.ToUpper()) { Remove-Item $zip -Force; "   STOPPED: checksum does not match the maker's - file deleted, nothing installed."; continue }
                '   checksum matches the maker''s - file is genuine'
            } else { '   (the maker lists no checksum for this file)' }
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            Expand-Archive $zip $dir -Force
            if ($it.Kind -eq 'BIOS') {
                $cap = Get-ChildItem $dir -Recurse -Include *.CAP, *.ROM, *.BIN | Select-Object -First 1
                "   BIOS file ready: $($cap.FullName)"
                '   Flash it from the BIOS: restart, press Del, F7 (Advanced), Tool > EZ Flash 3 > pick this file (or "via Internet").'
                '   Do not turn the PC off while it flashes. Afterwards re-enable EXPO/XMP for your RAM.'
                continue
            }
            $exe = $null
            foreach ($n in 'AsusSetup.exe', 'Setup.exe', 'Install.exe', 'Installer.exe') {
                $exe = Get-ChildItem $dir -Recurse -Filter $n -File | Sort-Object { $_.FullName.Length } | Select-Object -First 1
                if ($exe) { break }
            }
            if (-not $exe) { $exe = Get-ChildItem $dir -Recurse -Filter *.exe -File | Sort-Object { $_.FullName.Split('\').Count }, Length -Descending | Select-Object -First 1 }
            if ($exe) {
                $sig = Get-AuthenticodeSignature $exe.FullName
                if ($sig.Status -ne 'Valid') { "   STOPPED: $($exe.Name) is not properly signed ($($sig.Status)). Files left in $dir"; continue }
                "   running $($exe.Name) (signed by $(($sig.SignerCertificate.Subject -split ',')[0] -replace 'CN=', '')) - follow its window..."
                $p = Start-Process $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru -Wait
                "   installer finished (exit code $($p.ExitCode))"
            } elseif (Get-ChildItem $dir -Recurse -Filter *.inf -File | Select-Object -First 1) {
                '   no installer - adding the driver files with pnputil...'
                pnputil.exe /add-driver "$dir\*.inf" /subdirs /install | Where-Object { $_ -match 'Added|Failed|install|Total' } | ForEach-Object { "   $_" }
            } else { "   no installer found - open $dir" }
        } catch { "   FAILED: $($_.Exception.Message)" }
    }
    "Done. Downloads are kept in $Root - a restart finishes most driver installs."
}

# ================================================================ WINDOWS UPDATE DRIVERS (any brand)

$WuDriverScanWork = {
    $s = New-Object -ComObject Microsoft.Update.Session
    $se = $s.CreateUpdateSearcher()
    $r = $se.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    foreach ($u in $r.Updates) {
        [pscustomobject]@{ Id = $u.Identity.UpdateID; Title = $u.Title; Class = "$($u.DriverClass)"; Date = $u.DriverVerDate; MB = [math]::Round($u.MaxDownloadSize / 1MB, 1) }
    }
}

$WuDriverInstallWork = {
    param([string[]]$Ids)
    $s = New-Object -ComObject Microsoft.Update.Session
    $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $r.Updates) { if ($Ids -contains $u.Identity.UpdateID) { if (-not $u.EulaAccepted) { $u.AcceptEula() }; [void]$coll.Add($u) } }
    if ($coll.Count -eq 0) { 'Nothing to install (already installed?)'; return }
    "Downloading $($coll.Count) driver(s) from Windows Update..."
    $d = $s.CreateUpdateDownloader(); $d.Updates = $coll; [void]$d.Download()
    "Installing..."
    $i = $s.CreateUpdateInstaller(); $i.Updates = $coll; $res = $i.Install()
    for ($n = 0; $n -lt $coll.Count; $n++) {
        $code = $res.GetUpdateResult($n).ResultCode
        $txt = @{ 2 = 'installed'; 3 = 'installed with errors'; 4 = 'FAILED'; 5 = 'cancelled' }[[int]$code]
        "  $($coll.Item($n).Title) - $txt"
    }
    if ($res.RebootRequired) { 'Restart the PC to finish.' }
}

# ================================================================ TOOLKIT SELF-UPDATE

$SelfUpdateCheckWork = {
    param($Repo)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $r = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'HallowToolkit'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 20
    } catch {
        $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        return [pscustomobject]@{ Error = $(if ($code -eq 404) { 'No releases published yet.' } else { "Could not reach GitHub: $($_.Exception.Message)" }) }
    }
    $asset = @($r.assets | Where-Object { $_.name -like '*.zip' })[0]
    [pscustomobject]@{
        Error = $null; Version = ($r.tag_name -replace '^[vV]', ''); Notes = "$($r.body)"; Page = $r.html_url
        Url = $asset.browser_download_url; Sha256 = ("$($asset.digest)" -replace '^sha256:', '')
    }
}

$SelfUpdateDownloadWork = {
    param($Url, $Sha)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP ("hallow-update-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'update.zip'
    $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = 'HallowToolkit'; $wc.DownloadFile($Url, $zip); $wc.Dispose()
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($Sha -and $hash -ne $Sha.ToUpper()) { return [pscustomobject]@{ Error = 'Checksum mismatch - update not installed.' } }
    Expand-Archive $zip (Join-Path $tmp 'x') -Force
    $main = Get-ChildItem (Join-Path $tmp 'x') -Recurse -Filter 'HallowToolkit.ps1' | Select-Object -First 1
    if (-not $main) { return [pscustomobject]@{ Error = 'The update zip does not contain the toolkit.' } }
    [pscustomobject]@{ Error = $null; Folder = $main.DirectoryName; Temp = $tmp; Verified = [bool]$Sha }
}

function Test-NewerVersion([string]$Latest, [string]$Current) {
    try { return ([version]($Latest + '.0' * (3 - ($Latest -split '\.').Count))) -gt ([version]($Current + '.0' * (3 - ($Current -split '\.').Count))) } catch { $false }
}

# Copies the new files over this install (settings, logs, backups stay) - call from the window thread.
function Install-SelfUpdateFiles([string]$Folder, [string]$Temp) {
    $n = 0
    Get-ChildItem $Folder -File | Where-Object { $_.Extension -in '.ps1', '.ico', '.bat', '.txt' -and $_.Name -ne 'Install.ps1' } | ForEach-Object {
        Copy-Item $_.FullName $HallowRoot -Force; Unblock-File (Join-Path $HallowRoot $_.Name) -ErrorAction SilentlyContinue; $n++
    }
    if ($Temp -like "$env:TEMP*hallow-update-*") { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
    $n
}
