# Hallow Toolkit installer: copies the toolkit to your user folder and adds Desktop + Start Menu shortcuts.
$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$dest = Join-Path $env:USERPROFILE 'HallowToolkit'
New-Item -ItemType Directory -Force $dest | Out-Null
Get-ChildItem $src -File | Where-Object { $_.Name -ne 'Install.ps1' } | ForEach-Object {
    Copy-Item $_.FullName $dest -Force
    Unblock-File (Join-Path $dest $_.Name) -ErrorAction SilentlyContinue
}
$ws = New-Object -ComObject WScript.Shell
$targets = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Hallow Toolkit.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Hallow Toolkit.lnk')
)
foreach ($lnk in $targets) {
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dest\HallowToolkit.ps1`""
    $s.IconLocation = "$dest\hallow.ico"
    $s.WorkingDirectory = $dest
    $s.Save()
    $b = [IO.File]::ReadAllBytes($lnk); $b[0x15] = $b[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnk, $b)   # Run as administrator
}
Write-Host ""
Write-Host "Hallow Toolkit installed to $dest" -ForegroundColor Green
Write-Host "Open it from the 'Hallow Toolkit' icon on your Desktop or in the Start menu."
