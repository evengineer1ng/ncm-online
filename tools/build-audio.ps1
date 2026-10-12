[CmdletBinding()]
param([string]$Configuration = "Release")

# Builds NCM Audio (package id `ncm-audio`; NCM FX): ncm_audio.dll (loopback transport + miniaudio mixer), its math
# tests, the synthesised voice pack, and dist/ncm-audio-<version>.zip. No scripts, no archive: nothing to compile
# against the game.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\audio"
$dist = Join-Path $root "dist"
if (Test-Path "C:\Program Files\CMake\bin") { $env:Path = "C:\Program Files\CMake\bin;" + $env:Path }

Write-Host "== configuring NCM Audio" -ForegroundColor Cyan
& cmake --preset release -S $project
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
Write-Host "== building NCM Audio" -ForegroundColor Cyan
& cmake --build (Join-Path $project "build") --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
& (Join-Path $project "build\$Configuration\ncm_audio_math_tests.exe")
if ($LASTEXITCODE -ne 0) { throw "math tests failed" }
& (Join-Path $project "build\$Configuration\ncm_audio_smoke.exe") $project
if ($LASTEXITCODE -ne 0) { throw "mixer smoke test failed" }

Write-Host "== rendering the pack" -ForegroundColor Cyan
& python -I (Join-Path $project "tools\render_pack.py") (Join-Path $project "pack")
if ($LASTEXITCODE -ne 0) { throw "pack render failed" }

$version = (Select-String (Join-Path $project "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+) LANGUAGES').Matches[0].Groups[1].Value
$stage = Join-Path $dist "ncm_audio"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_audio"
New-Item -ItemType Directory -Force (Join-Path $pluginDir "pack") | Out-Null
Copy-Item (Join-Path $project "build\$Configuration\ncm_audio.dll") $pluginDir
Copy-Item (Join-Path $project "README.md") $pluginDir
Copy-Item (Join-Path $project "pack\*.wav") (Join-Path $pluginDir "pack")
$zip = Join-Path $dist "ncm-audio-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
