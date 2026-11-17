<#
  Hallow Toolkit - before/after snapshot and security check. No window code. Dot-sourced by HallowCore.ps1.
#>

# ================================================================ BEFORE / AFTER SNAPSHOT
# A snapshot lists what's installed and set to run: apps, startup items, services, scheduled tasks and
# browser extensions. Compare two to see what an installer or update changed.
$SnapshotDir = Join-Path $HallowRoot 'snapshots'
$BrowserProfiles = [ordered]@{ 'Chrome' = "$env:LOCALAPPDATA\Google\Chrome\User Data"; 'Edge' = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; 'Brave' = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" }

# Reads one browser extension's name, version and permissions from its manifest.
function Get-ExtensionInfo([string]$Dir) {
    $ver = Get-ChildItem -LiteralPath $Dir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $ver) { return }
    $mf = Join-Path $ver.FullName 'manifest.json'
    try { $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { return }
    $name = "$($m.name)"
    if ($name -match '^__MSG_(.+)__$') {
        $key = $Matches[1]; $loc = $(if ($m.default_locale) { $m.default_locale } else { 'en' })
        foreach ($l in @('en', 'en_US', $loc)) {
            $msgs = Join-Path $ver.FullName "_locales\$l\messages.json"
            if (Test-Path -LiteralPath $msgs) {
                try {
                    $j = Get-Content -LiteralPath $msgs -Raw -Encoding UTF8 | ConvertFrom-Json
                    $p = $j.PSObject.Properties | Where-Object { $_.Name -ieq $key } | Select-Object -First 1
                    if ($p) { $name = $p.Value.message; break }
                } catch { }
            }
        }
    }
    $perms = @(@($m.permissions) + @($m.host_permissions) + @($m.content_scripts | ForEach-Object { $_.matches }) | Where-Object { $_ -is [string] } | Select-Object -Unique)
    [pscustomobject]@{ Id = (Split-Path $Dir -Leaf); Name = $name; Version = "$($m.version)"; Perms = $perms }
}
function Get-BrowserExtensions {
    foreach ($b in $BrowserProfiles.Keys) {
        $root = $BrowserProfiles[$b]; if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($prof in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) {
            foreach ($e in Get-ChildItem (Join-Path $prof.FullName 'Extensions') -Directory -ErrorAction SilentlyContinue) {
                $i = Get-ExtensionInfo $e.FullName
                if ($i -and $i.Name -and $i.Name -notmatch '^__MSG_') { $i | Add-Member Browser $(if ($prof.Name -eq 'Default') { $b } else { "$b ($($prof.Name))" }); $i }
            }
        }
    }
}
$RunKeys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
function Get-StartupEntries {
    foreach ($k in $RunKeys) {
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue; if (-not $p) { continue }
        foreach ($n in $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) { [pscustomobject]@{ Name = $n.Name; Command = "$($n.Value)"; Where = $(if ($k -like 'HKCU*') { 'you' } else { 'all users' }) } }
    }
    foreach ($d in [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup')) {
        foreach ($f in Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini') { [pscustomobject]@{ Name = $f.BaseName; Command = $f.FullName; Where = 'Startup folder' } }
    }
}
function Get-SystemSnapshot {
    $snap = [ordered]@{ Taken = (Get-Date).ToString('o'); Apps = [ordered]@{}; Startup = [ordered]@{}; Services = [ordered]@{}; Tasks = [ordered]@{}; Extensions = [ordered]@{} }
    $uk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($a in Get-ItemProperty $uk -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent }) { $snap.Apps["$($a.DisplayName)"] = "$($a.DisplayVersion)" }
    foreach ($s in Get-StartupEntries) { $snap.Startup["$($s.Name) ($($s.Where))"] = $s.Command }
    foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) { $snap.Services["$($s.DisplayName) [$($s.Name)]"] = "$($s.StartMode)" }
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) { $snap.Tasks["$($t.TaskPath)$($t.TaskName)"] = "$($t.State)" }
    foreach ($e in Get-BrowserExtensions) { $snap.Extensions["$($e.Name) ($($e.Browser))"] = $e.Version }
    $snap
}
function Save-SystemSnapshot {
    New-Item -ItemType Directory -Force $SnapshotDir | Out-Null
    $snap = Get-SystemSnapshot
    $file = Join-Path $SnapshotDir ("snapshot-{0:yyyy-MM-dd_HHmmss}.json" -f (Get-Date))
    $snap | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
    Log ("Snapshot saved: {0} apps, {1} startup items, {2} services, {3} scheduled tasks, {4} browser extensions." -f $snap.Apps.Count, $snap.Startup.Count, $snap.Services.Count, $snap.Tasks.Count, $snap.Extensions.Count)
    $file
}
function Get-SnapshotFiles { @(Get-ChildItem $SnapshotDir -Filter 'snapshot-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending) }
function ConvertTo-Map($o) {
    if ($o -is [System.Collections.IDictionary]) { return $o }
    $h = @{}; if ($o) { foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = "$($p.Value)" } }; $h
}
# Rows: Kind, Item, Change ('Added' | 'Removed' | 'Changed'), Detail
function Compare-SystemSnapshot($Old, $New) {
    $kinds = [ordered]@{ Apps = 'App'; Startup = 'Startup'; Services = 'Service'; Tasks = 'Scheduled task'; Extensions = 'Browser extension' }
    foreach ($k in $kinds.Keys) {
        $a = ConvertTo-Map $(if ($Old -is [System.Collections.IDictionary]) { $Old[$k] } else { $Old.$k })
        $b = ConvertTo-Map $(if ($New -is [System.Collections.IDictionary]) { $New[$k] } else { $New.$k })
        foreach ($n in @($b.Keys)) {
            if (-not $a.Contains($n)) { [pscustomobject]@{ Kind = $kinds[$k]; Item = $n; Change = 'Added'; Detail = "$($b[$n])" } }
            elseif ("$($a[$n])" -ne "$($b[$n])") { [pscustomobject]@{ Kind = $kinds[$k]; Item = $n; Change = 'Changed'; Detail = "$($a[$n]) -> $($b[$n])" } }
        }
        foreach ($n in @($a.Keys)) { if (-not $b.Contains($n)) { [pscustomobject]@{ Kind = $kinds[$k]; Item = $n; Change = 'Removed'; Detail = "$($a[$n])" } } }
    }
}

# ================================================================ SECURITY CHECK
# Read-only. Rows: Area, Check, State ('OK' | 'Problem' | 'Note'), Detail, Fix (a settings page to open, or 'sigs' / 'scan').
$RiskyExtPerms = 'webRequest', 'webRequestBlocking', 'cookies', 'history', 'nativeMessaging', 'debugger', 'proxy', 'management', 'clipboardRead'
$QuietListeners = 'System', 'svchost', 'lsass', 'wininit', 'services', 'spoolsv', 'Idle'
function New-SecRow($Area, $Check, $State, $Detail, $Fix = '') { [pscustomobject]@{ Area = $Area; Check = $Check; State = $State; Detail = $Detail; Fix = $Fix } }
function Get-SecurityCheck {
    # antivirus
    $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    $other = @($av | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' })
    $mp = $null; try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }
    if ($other) { New-SecRow 'Antivirus' 'Antivirus' 'OK' "$((@($other.displayName) | Select-Object -Unique) -join ', ') is protecting this PC" }
    elseif ($mp) {
        if ($mp.RealTimeProtectionEnabled) { New-SecRow 'Antivirus' 'Defender real-time protection' 'OK' 'On' }
        else { New-SecRow 'Antivirus' 'Defender real-time protection' 'Problem' 'OFF - nothing scans files as they arrive' 'windowsdefender://threat/' }
        $age = $mp.AntivirusSignatureAge
        if ($age -gt 3) { New-SecRow 'Antivirus' 'Virus definitions' 'Problem' "$age days old" 'sigs' }
        else { New-SecRow 'Antivirus' 'Virus definitions' 'OK' $(if ($age -eq 0) { 'Updated today' } else { "$age day(s) old" }) }
        $qs = $mp.QuickScanAge
        if ($qs -ge 4000) { New-SecRow 'Antivirus' 'Last quick scan' 'Note' 'Never' 'scan' }
        elseif ($qs -gt 14) { New-SecRow 'Antivirus' 'Last quick scan' 'Note' "$qs days ago" 'scan' }
        else { New-SecRow 'Antivirus' 'Last quick scan' 'OK' $(if ($qs -eq 0) { 'Today' } else { "$qs day(s) ago" }) }
    } else { New-SecRow 'Antivirus' 'Antivirus' 'Problem' 'No antivirus found running' 'windowsdefender://threat/' }
    # firewall
    foreach ($p in Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        if ($p.Enabled) { New-SecRow 'Firewall' "$($p.Name) network firewall" 'OK' 'On' }
        else { New-SecRow 'Firewall' "$($p.Name) network firewall" 'Problem' 'OFF - anything can connect in' 'windowsdefender://network/' }
    }
    # User Account Control
    $sys = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue
    if ($sys.EnableLUA -eq 0) { New-SecRow 'Windows' 'User Account Control' 'Problem' 'OFF - every program runs with full control' 'UserAccountControlSettings.exe' }
    elseif ($sys.ConsentPromptBehaviorAdmin -eq 0) { New-SecRow 'Windows' 'User Account Control' 'Problem' 'Set to never notify - apps get admin rights without asking' 'UserAccountControlSettings.exe' }
    else { New-SecRow 'Windows' 'User Account Control' 'OK' 'Asks before apps make changes' }
    # SMB1
    $smb1 = $null; try { $smb1 = (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } catch { }
    if ($smb1) { New-SecRow 'Windows' 'SMB1 file sharing' 'Problem' 'On - an old, unsafe sharing protocol. Turn off in Windows Features.' 'optionalfeatures.exe' }
    elseif ($null -ne $smb1) { New-SecRow 'Windows' 'SMB1 file sharing' 'OK' 'Off' }
    # Remote Desktop
    if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0) {
        New-SecRow 'Remote access' 'Remote Desktop' 'Note' 'On - anyone with your password can log in over the network. Turn off if you don''t use it.' 'ms-settings:remotedesktop'
    } else { New-SecRow 'Remote access' 'Remote Desktop' 'OK' 'Off' }
    # startup programs: running from temp folders, or not signed
    foreach ($s in Get-StartupEntries) {
        $exe = $(if ($s.Command -match '^\s*"([^"]+)"') { $Matches[1] } elseif ($s.Command -match '^\s*(\S+\.(exe|bat|cmd|vbs|ps1|lnk))') { $Matches[1] } else { $null })
        if (-not $exe) { continue }
        $exe = [Environment]::ExpandEnvironmentVariables($exe)
        if ($exe -match '\\(Temp|Tmp)\\') { New-SecRow 'Startup' $s.Name 'Problem' "Starts from a temp folder ($exe) - malware often does this" 'startup'; continue }
        if ($exe -notmatch '\.exe$' -or -not (Test-Path -LiteralPath $exe)) { continue }
        $sig = Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -ne 'Valid') { New-SecRow 'Startup' $s.Name 'Note' "Not signed by its maker ($exe) - fine if you know it" 'startup' }
    }
    # programs accepting connections from the network
    foreach ($g in Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -in '0.0.0.0', '::' } | Group-Object OwningProcess) {
        $p = Get-Process -Id ([int]$g.Name) -ErrorAction SilentlyContinue
        if (-not $p -or $QuietListeners -contains $p.ProcessName) { continue }
        New-SecRow 'Network' "$($p.ProcessName) accepts connections" 'Note' ("Port {0} open to your network - normal for servers, Steam and some games" -f ((@($g.Group.LocalPort) | Sort-Object -Unique) -join ', '))
    }
    # browser extensions that can read every site AND hold a sensitive permission
    foreach ($e in Get-BrowserExtensions) {
        $all = @($e.Perms | Where-Object { $_ -match '<all_urls>|^\*://\*/|^https?://\*/' }).Count -gt 0
        $risky = @($e.Perms | Where-Object { $RiskyExtPerms -contains $_ })
        if ($all -and $risky) { New-SecRow 'Browser' "$($e.Name) ($($e.Browser))" 'Note' "Can read and change every website, plus: $($risky -join ', '). Fine for ad blockers and password managers you installed - remove anything you don't recognise." }
    }
}
