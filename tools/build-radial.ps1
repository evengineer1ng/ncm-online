[CmdletBinding()]
param([string]$Configuration = "Release", [switch]$SkipScriptCheck)

# Builds the NCM Radial required mod: the native plugin (transport + natives) and the redscript that draws the
# wheel. Before packaging, the script is compiled against the game's own vanilla bundle AND the installed
# OPEN//77 scripts in a scratch cache -- the game's r6/cache is never touched -- so a script that would break
# every player's script compile cannot reach a zip.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\radial"
$dist = Join-Path $root "dist"
$game = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"

Write-Host "== configuring NCM Radial" -ForegroundColor Cyan
& cmake --preset release -S $project
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "== building NCM Radial" -ForegroundColor Cyan
& cmake --build (Join-Path $project "build") --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

$tests = Join-Path $project "build\$Configuration\ncm_radial_state_tests.exe"
& $tests
if ($LASTEXITCODE -ne 0) { throw "state tests failed" }

$reds = Join-Path $project "redscript\ncm_radial.reds"
if (-not $SkipScriptCheck) {
    Write-Host "== compiling redscript against vanilla + OPEN//77 (scratch cache)" -ForegroundColor Cyan
    $scratch = Join-Path $env:TEMP "ncm-radial-scc"
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
    New-Item -ItemType Directory -Force (Join-Path $scratch "scripts\ncm_radial"), (Join-Path $scratch "cache") | Out-Null
    Copy-Item $reds (Join-Path $scratch "scripts\ncm_radial")
    $open77 = Join-Path $game "r6\scripts\Open77"
    if (Test-Path $open77) { Copy-Item -Recurse $open77 (Join-Path $scratch "scripts") }
    Copy-Item (Join-Path $game "r6\cache\final.redscripts") (Join-Path $scratch "cache")
    $out = & (Join-Path $game "engine\tools\scc.exe") -compile (Join-Path $scratch "scripts") -customCacheDir (Join-Path $scratch "cache") 2>&1
    $out | Where-Object { $_ -match 'ERROR|WARN' } | ForEach-Object { Write-Host "  $_" }
    if (-not ($out -match 'Compilation complete')) { throw "redscript did not compile; see the errors above" }
    Write-Host "  redscript compiles" -ForegroundColor Green
}

$dll = Join-Path $project "build\$Configuration\ncm_radial.dll"
if (-not (Test-Path $dll)) { throw "ncm_radial.dll was not produced" }

$version = (Select-String (Join-Path $project "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+)').Matches[0].Groups[1].Value
$stage = Join-Path $dist "ncm_radial"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_radial"
$scriptDir = Join-Path $stage "r6\scripts\ncm_radial"
New-Item -ItemType Directory -Force $pluginDir, $scriptDir | Out-Null
Copy-Item $dll $pluginDir
Copy-Item (Join-Path $project "README.md") $pluginDir
Copy-Item $reds $scriptDir

$zip = Join-Path $dist "ncm-radial-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
Write-Host "  publish (dev):  python tools\staging\publish-carrier.py tools\open77\server --zip `"$zip`" --version $version --id ncm-radial --display-name `"NCM Radial`" --import-blob --enable"
Write-Host "  live QA remains required: host found, open/aim/release on pad + keyboard + mouse, actions, close on drop"
