<#
  Builds "Hallow Toolkit.zip" in Downloads (what you send to friends and attach to GitHub releases).
    .\Build-Release.ps1              build the zip
    .\Build-Release.ps1 -Deploy      also update your own install in %USERPROFILE%\HallowToolkit
    .\Build-Release.ps1 -Publish     also create GitHub release v<AppVersion> with the zip (needs gh + the repo)
  Bump $AppVersion in HallowCore.ps1 before publishing, or everyone's auto-update won't see it.
#>
param([switch]$Deploy, [switch]$Publish, [string]$Notes = '')
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$version = ([regex]::Match((Get-Content "$src\HallowCore.ps1" -Raw), "AppVersion = '([^']+)'")).Groups[1].Value
$repo = ([regex]::Match((Get-Content "$src\HallowUpdates.ps1" -Raw), "UpdateRepo = '([^']+)'")).Groups[1].Value
$runtime = Get-ChildItem $src -File | Where-Object { ($_.Extension -in '.ps1', '.ico', '.bat') -and $_.Name -ne 'Build-Release.ps1' }

$stage = Join-Path $env:TEMP "hallow-build-$version"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$files = New-Item -ItemType Directory -Force "$stage\Hallow Toolkit\files"
$runtime | Copy-Item -Destination $files
Copy-Item "$src\release\Install.ps1" $files
Copy-Item "$src\release\INSTALL.bat", "$src\release\README.txt" "$stage\Hallow Toolkit"
$zip = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\Hallow Toolkit.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$stage\Hallow Toolkit" -DestinationPath $zip
Remove-Item $stage -Recurse -Force
"Built $zip  (v$version, $([math]::Round((Get-Item $zip).Length / 1KB)) KB)"

if ($Deploy) {
    $dest = Join-Path $env:USERPROFILE 'HallowToolkit'
    if ((Resolve-Path $dest).Path -ne $src) { $runtime | Copy-Item -Destination $dest -Force }
    "Updated your install in $dest"
}
if ($Publish) {
    if (-not $Notes) { $Notes = "Hallow Toolkit v$version" }
    gh release create "v$version" $zip --repo $repo --title "Hallow Toolkit v$version" --notes $Notes
}
