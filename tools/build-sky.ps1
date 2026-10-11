[CmdletBinding()]
param([string]$Configuration = "Release", [switch]$SkipScriptCheck)

# Builds NCM Sky (package id `ncm-sky`; KB-430): the universe drawn in REDengine with FULL orientation.
#   * ncm_sky.dll        -- loopback transport to the `ncm_sky` resource (127.0.0.1:38760-38763) + three natives
#   * NcmSky.reds        -- spawns, turns and removes the bodies the scene names (vanilla spawner + teleport)
#   * ncm_sky.archive    -- the body templates, authored from the game's own q201 Earth (ncm/sky/tools/author_templates.py)
# It shares no code, state, port range or package with the Carrier, the Rig Bridge, the Radial or the Scanner.
#
# Before packaging, the scripts are compiled against the game's own vanilla bundle AND every script currently
# installed in a scratch cache -- the game's r6/cache is never touched. A redscript compile error disables every
# script mod a player has, so it must never reach a zip.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\sky"
$dist = Join-Path $root "dist"
$game = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
$scripts = Join-Path $project "r6\scripts\ncm_sky"
$wk = Join-Path $root "tools\WolvenKit.Console-8.20.0\WolvenKit.CLI.exe"

Write-Host "== configuring NCM Sky" -ForegroundColor Cyan
& cmake --preset release -S $project
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "== building NCM Sky" -ForegroundColor Cyan
& cmake --build (Join-Path $project "build") --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

& (Join-Path $project "build\$Configuration\ncm_sky_state_tests.exe")
if ($LASTEXITCODE -ne 0) { throw "state tests failed" }

# KB-182: refuse natives inside a module, and any declared native the DLL does not register.
Write-Host "== checking native declarations against the DLL's registrations" -ForegroundColor Cyan
$registered = [regex]::Matches((Get-Content -Raw (Join-Path $project "src\rtti.cpp")), 'add\("(\w+)"') | ForEach-Object { $_.Groups[1].Value }
foreach ($file in Get-ChildItem (Join-Path $scripts "*.reds")) {
    $text = Get-Content -Raw $file.FullName
    $natives = [regex]::Matches($text, '(?m)^\s*(?:public\s+)?(?:static\s+)?native\s+func\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
    if ($natives -and ($text -match '(?m)^\s*module\s+\w')) {
        throw "$($file.Name) declares natives inside a module ($($natives -join ', ')); RED4ext would refuse to start the game"
    }
    foreach ($n in $natives) {
        if ($registered -notcontains $n) { throw "$($file.Name) declares native $n, which ncm_sky.dll does not register" }
    }
}
Write-Host "  natives: $($registered -join ', ')" -ForegroundColor Green

if (-not $SkipScriptCheck) {
    Write-Host "== compiling redscript against vanilla + installed scripts (scratch cache)" -ForegroundColor Cyan
    $scratch = Join-Path $env:TEMP "ncm-sky-scc"
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
    New-Item -ItemType Directory -Force (Join-Path $scratch "scripts\ncm_sky"), (Join-Path $scratch "cache") | Out-Null
    Get-ChildItem (Join-Path $game "r6\scripts") -Directory |
        Where-Object { $_.Name -ne "ncm_sky" -and $_.Name -ne "ncm_pace_diag" } |
        ForEach-Object { Copy-Item -Recurse $_.FullName (Join-Path $scratch "scripts") }
    Get-ChildItem (Join-Path $game "red4ext\plugins") -Directory | Where-Object { $_.Name -ne "ncm_sky" } | ForEach-Object {
        $ps = Join-Path $_.FullName "Scripts"
        if (Test-Path $ps) { Copy-Item -Recurse $ps (Join-Path $scratch ("scripts\plugin_" + $_.Name)) }
    }
    Copy-Item (Join-Path $scripts "*.reds") (Join-Path $scratch "scripts\ncm_sky")
    Copy-Item (Join-Path $game "r6\cache\final.redscripts") (Join-Path $scratch "cache")
    $out = & (Join-Path $game "engine\tools\scc.exe") -compile (Join-Path $scratch "scripts") -customCacheDir (Join-Path $scratch "cache") 2>&1
    $out | Where-Object { $_ -match 'ERROR|WARN' } | ForEach-Object { Write-Host "  $_" }
    if (-not ($out -match 'Compilation complete')) { throw "redscript did not compile; see the errors above" }
    Write-Host "  redscript compiles" -ForegroundColor Green
}

# ---- the body templates: authored from the player's own game files, never redistributed as extracted game JSON
Write-Host "== authoring body templates" -ForegroundColor Cyan
$work = Join-Path $env:TEMP "ncm-sky-assets"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
$extract = Join-Path $work "extract"; $json = Join-Path $work "json"; $raw = Join-Path $work "raw"; $packed = Join-Path $work "packed"
New-Item -ItemType Directory -Force $extract, $json, $raw, $packed | Out-Null
& $wk unbundle (Join-Path $game "archive\pc\content") -o $extract -w "base\environment\decoration\unique\quest\q201_q203\q201_q203_earth_globe.ent" | Out-Null
$srcEnt = Join-Path $extract "base\environment\decoration\unique\quest\q201_q203\q201_q203_earth_globe.ent"
if (-not (Test-Path $srcEnt)) { throw "could not extract the q201 Earth template from the game" }
& $wk convert serialize $srcEnt -o $json | Out-Null
$srcJson = Get-ChildItem $json -Filter "*.json" | Select-Object -First 1
$bodies = Join-Path $raw "ncm\sky\bodies"
New-Item -ItemType Directory -Force $bodies | Out-Null
& python (Join-Path $project "tools\author_templates.py") $srcJson.FullName $bodies
if ($LASTEXITCODE -ne 0) { throw "template authoring failed" }
foreach ($j in Get-ChildItem $bodies -Filter "*.ent.json") {
    & $wk convert deserialize $j.FullName -o $bodies | Out-Null
    Remove-Item $j.FullName
}
& $wk pack $raw -o $packed | Out-Null
$archive = Get-ChildItem $packed -Filter "*.archive" | Select-Object -First 1
if (-not $archive) { throw "WolvenKit produced no archive" }

$dll = Join-Path $project "build\$Configuration\ncm_sky.dll"
if (-not (Test-Path $dll)) { throw "ncm_sky.dll was not produced" }

$version = (Select-String (Join-Path $project "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+)').Matches[0].Groups[1].Value
$stage = Join-Path $dist "ncm_sky"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_sky"
$scriptDir = Join-Path $stage "r6\scripts\ncm_sky"
$archiveDir = Join-Path $stage "archive\pc\mod"
New-Item -ItemType Directory -Force $pluginDir, $scriptDir, $archiveDir | Out-Null
Copy-Item $dll $pluginDir
Copy-Item (Join-Path $project "README.md") $pluginDir
Copy-Item (Join-Path $scripts "*.reds") $scriptDir
Copy-Item $archive.FullName (Join-Path $archiveDir "ncm_sky.archive")

$zip = Join-Path $dist "ncm-sky-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
Write-Host "  publish (dev):  python tools\staging\publish-carrier.py tools\open77\server --zip `"$zip`" --version $version --id ncm-sky --display-name `"NCM Sky`" --import-blob --enable"
