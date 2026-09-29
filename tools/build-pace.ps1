[CmdletBinding()]
param([string]$Configuration = "Release", [switch]$SkipScriptCheck)

# Builds the NCM Pace required mod (package id `ncm-pace`; Paddock phase 5, doc 44 §15, IDEA-744):
#   * ncm_pace.dll  -- loopback transport to the `ncm_paddock` resource (127.0.0.1:38640-38643) + five natives
#   * NcmPace.reds  -- drives a declared live race's cars with the engine's own drive-to-point command
# It shares no code, state, port range or package with the Carrier, the Rig Bridge, the Radial or the Scanner.
#
# Before packaging, the scripts are compiled against the game's own vanilla bundle AND every script currently
# installed (OPEN//77, the rig bridge, the radial, the scanner) in a scratch cache -- the game's r6/cache is never
# touched. A redscript compile error disables every script mod a player has, so it must never reach a zip.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\pace"
$dist = Join-Path $root "dist"
$game = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
$scripts = Join-Path $project "r6\scripts\ncm_pace"

Write-Host "== configuring NCM Pace" -ForegroundColor Cyan
& cmake --preset release -S $project
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "== building NCM Pace" -ForegroundColor Cyan
& cmake --build (Join-Path $project "build") --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

& (Join-Path $project "build\$Configuration\ncm_pace_state_tests.exe")
if ($LASTEXITCODE -ne 0) { throw "state tests failed" }

# KB-182: `scc` compiles a `native func` inside a `module` without complaint, but RED4ext validates natives by
# FULLY QUALIFIED name at game start and closes the game when `Module.Name` is not registered. Refuse that shape,
# and refuse any declared native the DLL does not register.
Write-Host "== checking native declarations against the DLL's registrations" -ForegroundColor Cyan
$registered = [regex]::Matches((Get-Content -Raw (Join-Path $project "src\rtti.cpp")), 'add\("(\w+)"') | ForEach-Object { $_.Groups[1].Value }
foreach ($file in Get-ChildItem (Join-Path $scripts "*.reds")) {
    $text = Get-Content -Raw $file.FullName
    $natives = [regex]::Matches($text, '(?m)^\s*(?:public\s+)?(?:static\s+)?native\s+func\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
    if ($natives -and ($text -match '(?m)^\s*module\s+\w')) {
        throw "$($file.Name) declares natives inside a module ($($natives -join ', ')); RED4ext would refuse to start the game"
    }
    foreach ($n in $natives) {
        if ($registered -notcontains $n) { throw "$($file.Name) declares native $n, which ncm_pace.dll does not register" }
    }
}
Write-Host "  natives: $($registered -join ', ')" -ForegroundColor Green

if (-not $SkipScriptCheck) {
    Write-Host "== compiling redscript against vanilla + installed scripts (scratch cache)" -ForegroundColor Cyan
    $scratch = Join-Path $env:TEMP "ncm-pace-scc"
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
    New-Item -ItemType Directory -Force (Join-Path $scratch "scripts\ncm_pace"), (Join-Path $scratch "cache") | Out-Null
    Get-ChildItem (Join-Path $game "r6\scripts") -Directory |
        Where-Object { $_.Name -ne "ncm_pace" } |
        ForEach-Object { Copy-Item -Recurse $_.FullName (Join-Path $scratch "scripts") }
    Copy-Item (Join-Path $scripts "*.reds") (Join-Path $scratch "scripts\ncm_pace")
    Copy-Item (Join-Path $game "r6\cache\final.redscripts") (Join-Path $scratch "cache")
    $out = & (Join-Path $game "engine\tools\scc.exe") -compile (Join-Path $scratch "scripts") -customCacheDir (Join-Path $scratch "cache") 2>&1
    $out | Where-Object { $_ -match 'ERROR|WARN' } | ForEach-Object { Write-Host "  $_" }
    if (-not ($out -match 'Compilation complete')) { throw "redscript did not compile; see the errors above" }
    Write-Host "  redscript compiles" -ForegroundColor Green
}

$dll = Join-Path $project "build\$Configuration\ncm_pace.dll"
if (-not (Test-Path $dll)) { throw "ncm_pace.dll was not produced" }

$version = (Select-String (Join-Path $project "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+)').Matches[0].Groups[1].Value
$stage = Join-Path $dist "ncm_pace"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_pace"
$scriptDir = Join-Path $stage "r6\scripts\ncm_pace"
New-Item -ItemType Directory -Force $pluginDir, $scriptDir | Out-Null
Copy-Item $dll $pluginDir
Copy-Item (Join-Path $project "README.md") $pluginDir
Copy-Item (Join-Path $scripts "*.reds") $scriptDir

$zip = Join-Path $dist "ncm-pace-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
Write-Host "  publish (dev):  python tools\staging\publish-carrier.py tools\open77\server --zip `"$zip`" --version $version --id ncm-pace --display-name `"NCM Pace`" --import-blob --enable"
Write-Host "  also: deploy ncm_league (schema 051) and ncm_paddock; the resource finds the plugin on loopback by itself"
Write-Host "  live probes: P-PACE-1 (entity mapping) and P-PACE-2 (does the platform leave a native command alone)"
