[CmdletBinding()]
param([string]$Configuration = "Release")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\rig_bridge"
$dist = Join-Path $root "dist"

Write-Host "== configuring NCM Rig Bridge" -ForegroundColor Cyan
& cmake --preset release -S $project
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "== building NCM Rig Bridge" -ForegroundColor Cyan
& cmake --build (Join-Path $project "build") --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

$dll = Get-ChildItem (Join-Path $project "build") -Filter "ncm_rig_bridge.dll" -Recurse |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $dll) { throw "ncm_rig_bridge.dll was not produced" }

$version = (Select-String (Join-Path $project "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+)').Matches[0].Groups[1].Value
$stage = Join-Path $dist "ncm_rig_bridge"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_rig_bridge"
$scriptDir = Join-Path $stage "r6\scripts\ncm_rig_bridge"
New-Item -ItemType Directory -Force $pluginDir, $scriptDir | Out-Null
Copy-Item $dll.FullName $pluginDir
Copy-Item (Join-Path $project "ncm_rig_bridge.json") $pluginDir
Copy-Item (Join-Path $project "README.md") $pluginDir
Copy-Item (Join-Path $project "THIRD_PARTY_NOTICES.md") $pluginDir
Copy-Item (Join-Path $project "redscript\ncm_rig_bridge.reds") $scriptDir

$zip = Join-Path $dist "ncm-rig-bridge-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
Write-Host "  live QA remains required: device bind, mount scoping, controls, reconnect, FFB arm/watchdog"
