[CmdletBinding()]
param([string]$Configuration = "Release", [switch]$SkipScriptCheck, [string]$Pack = "D:\ncm-radio\pack", [switch]$NoPack)

# Builds the NCM Radio required mod (package id `ncm-radio`; doc 59, L348):
#   * ncm_radio.dll   -- plays the `ncm_radio` resource's programme (loopback 127.0.0.1:38680-38683) + four natives
#   * NcmRadio.reds   -- Race Week Live as a row in the vanilla radio popup; default on, never locked in
#   * station.yaml    -- the RadioStation record (TweakXL)
#   * pack/           -- the rendered voice clips (ncm/radio/voice/render.py), beside the DLL
# It shares no code, state, port range or package with the Carrier, the Rig Bridge, Pace or any other NCM plugin.
#
# Before packaging, the scripts are compiled against the game's own vanilla bundle AND every script currently
# installed, in a scratch cache -- the game's r6/cache is never touched. A redscript compile error disables every
# script mod a player has, so it must never reach a zip.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\radio"
$dist = Join-Path $root "dist"
$game = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
$scripts = Join-Path $project "r6\scripts\ncm_radio"

Write-Host "== configuring NCM Radio" -ForegroundColor Cyan
& cmake --preset release -S $project
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "== building NCM Radio" -ForegroundColor Cyan
& cmake --build (Join-Path $project "build") --config $Configuration
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
& (Join-Path $project "build\$Configuration\ncm_radio_timeline_tests.exe")
if ($LASTEXITCODE -ne 0) { throw "timeline tests failed" }

# KB-182: natives must be globals, and every declared native must be one the DLL registers.
Write-Host "== checking native declarations against the DLL's registrations" -ForegroundColor Cyan
$registered = [regex]::Matches((Get-Content -Raw (Join-Path $project "src\natives.cpp")), 'add\("(\w+)"') | ForEach-Object { $_.Groups[1].Value }
foreach ($file in Get-ChildItem (Join-Path $scripts "*.reds")) {
    $text = Get-Content -Raw $file.FullName
    $natives = [regex]::Matches($text, '(?m)^\s*(?:public\s+)?(?:static\s+)?native\s+func\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
    if ($natives -and ($text -match '(?m)^\s*module\s+\w')) {
        throw "$($file.Name) declares natives inside a module ($($natives -join ', ')); RED4ext would refuse to start the game"
    }
    foreach ($n in $natives) {
        if ($registered -notcontains $n) { throw "$($file.Name) declares native $n, which ncm_radio.dll does not register" }
    }
}
Write-Host "  natives: $($registered -join ', ')" -ForegroundColor Green

if (-not $SkipScriptCheck) {
    Write-Host "== compiling redscript against vanilla + installed scripts (scratch cache)" -ForegroundColor Cyan
    $scratch = Join-Path $env:TEMP "ncm-radio-scc"
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
    New-Item -ItemType Directory -Force (Join-Path $scratch "scripts\ncm_radio"), (Join-Path $scratch "cache") | Out-Null
    Get-ChildItem (Join-Path $game "r6\scripts") -Directory |
        Where-Object { $_.Name -ne "ncm_radio" -and $_.Name -ne "ncm_pace_diag" } |
        ForEach-Object { Copy-Item -Recurse $_.FullName (Join-Path $scratch "scripts") }
    Get-ChildItem (Join-Path $game "red4ext\plugins") -Directory | Where-Object { $_.Name -ne "ncm_radio" } | ForEach-Object {
        $ps = Join-Path $_.FullName "Scripts"
        if (Test-Path $ps) { Copy-Item -Recurse $ps (Join-Path $scratch ("scripts\plugin_" + $_.Name)) }
    }
    Copy-Item (Join-Path $scripts "*.reds") (Join-Path $scratch "scripts\ncm_radio")
    Copy-Item (Join-Path $game "r6\cache\final.redscripts") (Join-Path $scratch "cache")
    $out = & (Join-Path $game "engine\tools\scc.exe") -compile (Join-Path $scratch "scripts") -customCacheDir (Join-Path $scratch "cache") 2>&1
    $out | Where-Object { $_ -match 'ERROR|WARN' } | ForEach-Object { Write-Host "  $_" }
    if (-not ($out -match 'Compilation complete')) { throw "redscript did not compile; see the errors above" }
    Write-Host "  redscript compiles" -ForegroundColor Green
}

$dll = Join-Path $project "build\$Configuration\ncm_radio.dll"
if (-not (Test-Path $dll)) { throw "ncm_radio.dll was not produced" }

$version = (Select-String (Join-Path $project "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+)').Matches[0].Groups[1].Value
$stage = Join-Path $dist "ncm_radio"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_radio"
$scriptDir = Join-Path $stage "r6\scripts\ncm_radio"
$tweakDir = Join-Path $stage "r6\tweaks"
New-Item -ItemType Directory -Force $pluginDir, $scriptDir, $tweakDir | Out-Null
Copy-Item $dll $pluginDir
Copy-Item (Join-Path $project "README.md") $pluginDir
Copy-Item (Join-Path $scripts "*.reds") $scriptDir
Copy-Item (Join-Path $project "r6\tweaks\ncm_radio") $tweakDir -Recurse

if (-not $NoPack) {
    # The voice pack: every rendered clip, plus VERSION (the manifest hash the resource checks it airs against).
    $clips = Join-Path $Pack "clips"
    if (-not (Test-Path $clips)) { throw "no rendered pack at $Pack (run ncm/radio/voice/render.py), or pass -NoPack" }
    Write-Host "== copying the voice pack" -ForegroundColor Cyan
    Copy-Item -Recurse $clips (Join-Path $pluginDir "pack\clips")
    $packVersion = (Get-FileHash -Algorithm SHA256 (Join-Path $Pack "manifest.json")).Hash.Substring(0, 12).ToLower()
    # .NET, not Set-Content: Set-Content silently wrote nothing here, and the plugin reported "pack " to the server
    [System.IO.File]::WriteAllText((Join-Path $pluginDir "pack\VERSION"), $packVersion)
    if (-not (Test-Path (Join-Path $pluginDir "pack\VERSION"))) { throw "pack VERSION was not written" }
    $n = (Get-ChildItem -Recurse -File (Join-Path $pluginDir "pack\clips")).Count
    Write-Host "  $n clips, pack version $packVersion"
}

# the whole build; split-radio-pack.py turns it into the published parts (ncm-radio-<v>.zip is part one)
$zip = Join-Path $dist "ncm-radio-$version-full.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel NoCompression
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip  ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
Write-Host "  sha256 $hash"
# OPEN//77 never serves a required-mod archive over 64 MiB (KB-418): split into ncm-radio + ncm-radio-voices-<n>
python (Join-Path $root "tools\split-radio-pack.py") $zip --version $version
if ($LASTEXITCODE -ne 0) { throw "split-radio-pack failed" }
Write-Host "  publish EACH part: python3 publish-carrier.py <server-root> --zip <part>.zip --version $version --id <ncm-radio | ncm-radio-voices-N> --display-name <...> --import-blob --enable; then chown the store to the service user"
Write-Host "  also: deploy the ncm_radio resource (ncm/online/resources/ncm_radio) with the same pack's corpus_data.lua"
