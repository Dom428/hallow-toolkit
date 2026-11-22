<#
  Hallow Toolkit 5.18 - the "Hallow Terminal" section on the Hallow page: Install / Update / Open / Remove the Hallow look
  for Windows Terminal (HallowTerminal.ps1 does the work). Dot-sourced by HallowToolkit.ps1 after the pages exist.
  Everything is written when YOU click (the toolkit runs as you, so it lands in your own %LOCALAPPDATA% and toolkit folder).
#>
. (Join-Path $PSScriptRoot 'HallowTerminal.ps1')

$f = $script:PageFlows['Hallow']
$termFirst = $f.Controls.Count
Add-Section $f 'Hallow Terminal - PowerShell and Command Prompt in the Hallow look' 'terminal'
$script:TermNote = Add-Note $f ''
$script:TermNote.Height = 56
$script:TermInstall = Add-Tool $f 'Install' 'Add the Hallow look to Windows Terminal' { Invoke-TerminalInstall } -Primary -Width 205 -Icon 'download'
$script:TermUpdate = Add-Tool $f 'Update' 'Your accent, light / dark, newest prompt' { Invoke-TerminalInstall -Update } -Width 205 -Icon 'arrows-rotate'
$script:TermOpen = Add-Tool $f 'Open' 'Hallow PowerShell in a new Terminal window' { Open-HallowTerminal } -Width 205 -Icon 'terminal'
$script:TermRemove = Add-Tool $f 'Remove' 'Only the Hallow Terminal files' { Invoke-TerminalRemove } -Width 205 -Icon 'trash-can'
$f.SetFlowBreak($f.Controls[$f.Controls.Count - 1], $true)
$termHelp = Add-Note $f ("Make it the default: in Windows Terminal open Settings (Ctrl+,) > Startup > Default profile > Hallow PowerShell (a fragment can add profiles but not change your default). " +
    "In it, type hallow status, hallow vpn on, hallow torrents pause, hallow gear, hallow open <app>, hallow update or hallow help (Tab completes app names). Your own PowerShell profile and Terminal settings are never changed.")
$termHelp.Height = 56
# show it right after the accent and light / dark pickers, above the (long) link check results
$linksAt = -1
for ($i = 0; $i -lt $termFirst; $i++) { if ("$($f.Controls[$i].Text)" -eq 'LINKS BETWEEN THE APPS') { $linksAt = $i; break } }
if ($linksAt -gt 0) {
    if ($f.Controls[$linksAt - 1] -is [System.Windows.Forms.PictureBox]) { $linksAt-- }   # the section's icon comes first
    $mine = @(for ($i = $termFirst; $i -lt $f.Controls.Count; $i++) { $f.Controls[$i] })
    $at = $linksAt; foreach ($ctl in $mine) { $f.Controls.SetChildIndex($ctl, $at); $at++ }   # ($c would be the palette)
}$tips.SetToolTip($script:TermRemove, 'Deletes the Hallow fragment (hallow.json, hallow.ico) and the toolkit''s terminal folder - nothing else')

# primary (accent) button follows the state: Install until it's set up, then Update while something changed
function Set-TerminalPrimary($B, [bool]$On) {
    if ($script:PrimaryButtons.Contains($B) -eq $On) { return }
    if ($On) { [void]$script:PrimaryButtons.Add($B) } else { [void]$script:PrimaryButtons.Remove($B) }
    $icon = @{ $script:TermInstall = 'download'; $script:TermUpdate = 'arrows-rotate' }[$B]
    if ($icon -and (Test-IconFont)) { $B.Image = Get-Icon $icon $(if ($On) { $C.AccentText } else { $C.Accent }) 20 }
    $B.Font = New-Font 9.5 $(if ($On) { 'Bold' } else { 'Regular' }); $B.Invalidate()
}
function Update-TerminalSection([switch]$AutoRefresh) {
    $st = Get-HallowTerminalState
    # set up already, only the accent / light-dark / prompt changed: rewrite our own files quietly (they're ours)
    if ($AutoRefresh -and $st.Installed -and -not $st.Current -and -not $env:HALLOW_SNAP) {
        try { [void](Install-HallowTerminal -FontFace $(if ($st.Info -and @($st.Info.PSObject.Properties.Name) -contains 'font') { "$($st.Info.font)" } else { '?' })); Log "Hallow Terminal updated ($($st.Why -join ', ')) - open a new Terminal window to see it."; $st = Get-HallowTerminalState } catch { Log "Hallow Terminal: could not update - $($_.Exception.Message)" }
    }
    $wt = $(if ($st.Terminal) { '' } else { ' Windows Terminal isn''t installed yet - get it from the Microsoft Store (or winget install Microsoft.WindowsTerminal); the look is ready for it.' })
    $script:TermNote.Text = $(if (-not $st.Installed) {
            "Your own PowerShell and Command Prompt: Hallow Dark / Hallow Light colour schemes with your accent, the Hallow icon, and a prompt that shows the folder, git branch, Hallow VPN, the game you're playing, slow commands and errors - plus a hallow command for the apps.$wt"
        } elseif ($st.Current) {
            "Set up: Hallow PowerShell and Hallow Command Prompt are in Windows Terminal's profile list ($(@{ dark = 'dark'; light = 'light'; system = 'light / dark like Windows' }["$($st.Info.mode)"]), accent $($st.Info.accent)).$wt"
        } else { "Set up, but $($st.Why -join ', ') - click Update.$wt" })
    $script:TermNote.ForeColor = $(if ($st.Installed -and -not $st.Current) { $C.Warn } else { $C.Muted })
    Set-TerminalPrimary $script:TermInstall (-not $st.Installed)
    Set-TerminalPrimary $script:TermUpdate ($st.Installed -and -not $st.Current)
    $script:TermInstall.Text = "$(if ($st.Installed) { 'Reinstall' } else { 'Install' })`n$(if ($st.Installed) { 'Write every file again' } else { 'Add the Hallow look to Windows Terminal' })"
}
function Invoke-TerminalInstall([switch]$Update) {
    $st = Get-HallowTerminalState
    if ($Update -and -not $st.Installed) { Log 'Hallow Terminal isn''t set up yet - click Install.'; return }
    try { foreach ($l in (Install-HallowTerminal)) { Log $l } } catch { Log "Hallow Terminal: could not write the files - $($_.Exception.Message)"; return }
    if (-not $st.Terminal) { Log 'Windows Terminal isn''t installed yet: get it from the Microsoft Store or with winget install Microsoft.WindowsTerminal - it picks the Hallow look up by itself.' }
    Update-TerminalSection
}
function Open-HallowTerminal {
    $st = Get-HallowTerminalState
    if (-not $st.Installed) { Log 'Click Install first - then Hallow PowerShell opens here.'; return }
    if (-not $st.Terminal) { Log 'Windows Terminal isn''t installed (Microsoft Store or winget install Microsoft.WindowsTerminal).'; return }
    $lnk = Join-Path $st.Files 'Hallow PowerShell.lnk'
    if (-not (Test-Path $lnk)) { [void](Install-HallowTerminal) }
    Start-Process explorer.exe "`"$lnk`""   # Explorer starts it as you, not as admin
    Log 'Opening Hallow PowerShell in Windows Terminal.'
}
function Invoke-TerminalRemove {
    $st = Get-HallowTerminalState
    if (-not $st.Installed) { Log 'Hallow Terminal isn''t set up - nothing to remove.'; return }
    if (-not (Confirm-Action "Remove Hallow Terminal?`n`nDeletes only the Hallow fragment (hallow.json and hallow.ico in Windows Terminal's Fragments\Hallow folder) and the toolkit's terminal folder. Your Terminal settings and PowerShell profile stay as they are.")) { return }
    $gone = @(Remove-HallowTerminal)
    Log "Hallow Terminal removed - deleted $($gone.Count) items:"
    foreach ($g in $gone) { Log "  $g" }
    Log 'Nothing else was changed. If Hallow PowerShell was your default profile, pick another one in Terminal > Settings > Startup.'
    Update-TerminalSection
}
# the accent or light / dark changed on this page: keep the terminal look in step (called from HallowFamilyPage.ps1)
function Update-HallowTerminalAfterLook { try { if ((Get-HallowTerminalState).Installed) { Update-TerminalSection -AutoRefresh } } catch { } }

Update-TerminalSection
$script:TerminalPrevHook = $script:PageShowHooks['Hallow']
$script:PageShowHooks['Hallow'] = { if ($script:TerminalPrevHook) { & $script:TerminalPrevHook }; Update-TerminalSection -AutoRefresh }
