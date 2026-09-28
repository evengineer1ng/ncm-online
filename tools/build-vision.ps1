[CmdletBinding()]
param([string]$Version = "0.1.0", [switch]$SkipScriptCheck)

# Builds the NCM Vision required mod (IDEA-679): the vanilla scanner's green render on Tab / Caps Lock, with
# no scan HUD, no movement restriction and no time dilation. Redscript only -- no DLL, no socket, nothing
# shared with the Carrier or the Rig Bridge.
#
# Before packaging, the script is compiled against the game's own vanilla bundle AND every script currently
# installed (OPEN//77, the rig bridge, the radial) in a scratch cache -- the game's r6/cache is never
# touched. A redscript compile error disables every script mod a player has, so it must never reach a zip.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "ncm\vision"
$dist = Join-Path $root "dist"
$game = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077"
$reds = Join-Path $project "r6\scripts\ncm_vision\NcmVision.reds"

if (-not $SkipScriptCheck) {
    Write-Host "== compiling redscript against vanilla + installed scripts (scratch cache)" -ForegroundColor Cyan
    $scratch = Join-Path $env:TEMP "ncm-vision-scc"
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
    New-Item -ItemType Directory -Force (Join-Path $scratch "scripts\ncm_vision"), (Join-Path $scratch "cache") | Out-Null
    Get-ChildItem (Join-Path $game "r6\scripts") -Directory |
        Where-Object { $_.Name -ne "ncm_vision" } |
        ForEach-Object { Copy-Item -Recurse $_.FullName (Join-Path $scratch "scripts") }
    Copy-Item $reds (Join-Path $scratch "scripts\ncm_vision")
    Copy-Item (Join-Path $game "r6\cache\final.redscripts") (Join-Path $scratch "cache")
    $out = & (Join-Path $game "engine\tools\scc.exe") -compile (Join-Path $scratch "scripts") -customCacheDir (Join-Path $scratch "cache") 2>&1
    $out | Where-Object { $_ -match 'ERROR|WARN' } | ForEach-Object { Write-Host "  $_" }
    if (-not ($out -match 'Compilation complete')) { throw "redscript did not compile; see the errors above" }
    Write-Host "  redscript compiles" -ForegroundColor Green
}

$stage = Join-Path $dist "ncm_vision"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$scriptDir = Join-Path $stage "r6\scripts\ncm_vision"
New-Item -ItemType Directory -Force $scriptDir | Out-Null
Copy-Item $reds $scriptDir
Copy-Item (Join-Path $project "README.md") $scriptDir

$zip = Join-Path $dist "ncm-vision-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
Write-Host "  publish (dev):  python tools\staging\publish-carrier.py tools\open77\server --zip `"$zip`" --version $Version --id ncm-vision --display-name `"NCM Vision`" --import-blob --enable"
Write-Host "  live QA remains required: MASTER_TEST section for IDEA-679 (green on foot + driving, time scale 1.0, free movement, release, detach)"
