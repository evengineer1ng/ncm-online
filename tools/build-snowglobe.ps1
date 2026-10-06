[CmdletBinding()]
param([string]$Configuration = "Release", [switch]$SkipScriptCheck)

# Builds NCM Snowglobe (package id `ncm-snowglobe`; L317, doc 51 §6). 0.0.1 is SEAM-1 only:
#   * ncm_snowglobe.dll   -- the seam key and its live config, five natives
#   * NcmSnowglobe.reds   -- moves the occupied car with the game's TeleportationFacility and measures the result
# It shares no code, state or package with the Carrier, the Thrust or the Gearbox (feedback: new features, new mods).
#
# Before packaging, the scripts are compiled against the game's own vanilla bundle AND every script currently installed
# in a scratch cache -- the game's r6/cache is never touched. A redscript compile error disables every script mod a
# player has, so it must never reach a zip. Dev only: hand-install with tools/dev-hand-install-mods.py --extra-zip.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\snowglobe"
$dist = Join-Path $root "dist"
$game = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
$scripts = Join-Path $project "r6\scripts\ncm_snowglobe"

Write-Host "== configuring NCM Snowglobe" -ForegroundColor Cyan
& cmake --preset release -S $project | Out-Null
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
Write-Host "== building NCM Snowglobe" -ForegroundColor Cyan
& cmake --build (Join-Path $project "build") --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

# KB-182: natives inside a module compile but close the game at start; every declared native must be registered.
Write-Host "== checking native declarations against the DLL's registrations" -ForegroundColor Cyan
$registered = [regex]::Matches((Get-Content -Raw (Join-Path $project "src\natives.cpp")), 'add\("(\w+)"') | ForEach-Object { $_.Groups[1].Value }
foreach ($file in Get-ChildItem (Join-Path $scripts "*.reds")) {
    $text = Get-Content -Raw $file.FullName
    $natives = [regex]::Matches($text, '(?m)^\s*(?:public\s+)?(?:static\s+)?native\s+func\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
    if ($natives -and ($text -match '(?m)^\s*module\s+\w')) {
        throw "$($file.Name) declares natives inside a module ($($natives -join ', ')); RED4ext would refuse to start the game"
    }
    foreach ($n in $natives) {
        if ($registered -notcontains $n) { throw "$($file.Name) declares native $n, which ncm_snowglobe.dll does not register" }
    }
}
Write-Host "  natives: $($registered -join ', ')" -ForegroundColor Green

if (-not $SkipScriptCheck) {
    Write-Host "== compiling redscript against vanilla + installed scripts (scratch cache)" -ForegroundColor Cyan
    $scratch = Join-Path $env:TEMP "ncm-snowglobe-scc"
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
    New-Item -ItemType Directory -Force (Join-Path $scratch "scripts\ncm_snowglobe"), (Join-Path $scratch "cache") | Out-Null
    Get-ChildItem (Join-Path $game "r6\scripts") -Directory | Where-Object { $_.Name -ne "ncm_snowglobe" } |
        ForEach-Object { Copy-Item -Recurse $_.FullName (Join-Path $scratch "scripts") }
    Get-ChildItem (Join-Path $game "red4ext\plugins") -Directory | Where-Object { $_.Name -ne "ncm_snowglobe" } | ForEach-Object {
        $ps = Join-Path $_.FullName "Scripts"
        if (Test-Path $ps) { Copy-Item -Recurse $ps (Join-Path $scratch ("scripts\plugin_" + $_.Name)) }
    }
    Copy-Item (Join-Path $scripts "*.reds") (Join-Path $scratch "scripts\ncm_snowglobe")
    Copy-Item (Join-Path $game "r6\cache\final.redscripts") (Join-Path $scratch "cache")
    $out = & (Join-Path $game "engine\tools\scc.exe") -compile (Join-Path $scratch "scripts") -customCacheDir (Join-Path $scratch "cache") 2>&1
    $out | Where-Object { $_ -match 'ERROR|WARN' } | ForEach-Object { Write-Host "  $_" }
    if (-not ($out -match 'Compilation complete')) { throw "redscript did not compile; see the errors above" }
    Write-Host "  redscript compiles" -ForegroundColor Green
}

$dll = Join-Path $project "build\$Configuration\ncm_snowglobe.dll"
if (-not (Test-Path $dll)) { throw "ncm_snowglobe.dll was not produced" }
$version = (Select-String (Join-Path $project "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+)').Matches[0].Groups[1].Value
$stage = Join-Path $dist "ncm_snowglobe"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_snowglobe"
$scriptDir = Join-Path $stage "r6\scripts\ncm_snowglobe"
New-Item -ItemType Directory -Force $pluginDir, $scriptDir | Out-Null
Copy-Item $dll $pluginDir
Copy-Item (Join-Path $project "data\ncm_snowglobe_config.json") $pluginDir
Copy-Item (Join-Path $scripts "*.reds") $scriptDir
$zip = Join-Path $dist "ncm-snowglobe-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  install (dev, game closed): python tools\dev-hand-install-mods.py --only none --extra-zip `"$zip`""
