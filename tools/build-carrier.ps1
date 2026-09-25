# Build the NCM Carrier plugin and assemble the hosted package.
#
# Produces THREE things and stops:
#   dist/ncm_carrier/red4ext/plugins/ncm_carrier/ncm_carrier.dll   the tree as it lands in the game
#   dist/ncm-carrier-<version>.zip                                 the blob the launcher downloads
#   a declaration snippet, printed, for tools/staging/declare-carrier.py
#
# It declares nothing and deploys nothing. **Test the DLL by hand before it becomes a join requirement**
# (MASTER_TEST section AT1): copy the tree into the game, launch, and read red4ext/logs/. A plugin that stops
# the game launching must be found by us, once, and not by every player at the same time.
#
#   .\tools\build-carrier.ps1                 build and package
#   .\tools\build-carrier.ps1 -SkipBuild      repackage what is already in build/
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$carrier = Join-Path $root "ncm\carrier"
$dist = Join-Path $root "dist"

if (-not (Test-Path (Join-Path $carrier "third_party\RED4ext.SDK\CMakeLists.txt"))) {
    throw "RED4ext.SDK is not checked out. Run: git submodule update --init --recursive"
}

if (-not $SkipBuild) {
    if (-not $env:VCPKG_ROOT) {
        throw "VCPKG_ROOT is not set. The build needs vcpkg for SDL2 and nlohmann-json."
    }
    Write-Host "== configuring" -ForegroundColor Cyan
    & cmake --preset release -S $carrier
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

    Write-Host "== building" -ForegroundColor Cyan
    & cmake --build (Join-Path $carrier "build") --config $Configuration
    if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
}

$dll = Get-ChildItem -Path (Join-Path $carrier "build") -Filter "ncm_carrier.dll" -Recurse |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $dll) { throw "ncm_carrier.dll was not produced" }

# SDL2 ships beside the plugin. RED4ext loads the DLL from its own directory, and Windows resolves its
# imports from there, so a vendored SDL2 does not collide with anything else the game has loaded.
$sdl = Get-ChildItem -Path (Join-Path $carrier "build") -Filter "SDL2.dll" -Recurse |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1

$version = (Select-String -Path (Join-Path $carrier "CMakeLists.txt") -Pattern 'VERSION (\d+\.\d+\.\d+)').Matches[0].Groups[1].Value

$stage = Join-Path $dist "ncm_carrier"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$pluginDir = Join-Path $stage "red4ext\plugins\ncm_carrier"
New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null

Copy-Item $dll.FullName $pluginDir
if ($sdl) { Copy-Item $sdl.FullName $pluginDir } else { Write-Warning "SDL2.dll not found beside the build -- force feedback will not load" }

# The licences travel with the binary. IDEA-468: no package is declared without its redistribution terms
# recorded, and a player reads NCM's name beside whatever NCM hosts.
$licences = Join-Path $pluginDir "THIRD_PARTY_LICENSES.md"
@"
# NCM Carrier -- third-party components

| Component | Licence | Redistributable |
|---|---|---|
| RED4ext.SDK (WopsS) | MIT | Yes |
| SDL2 | zlib | Yes |
| nlohmann/json | MIT | Yes (header-only, compiled in) |

Full texts: ncm/carrier/third_party/RED4ext.SDK/LICENSE.md and the vcpkg port directories.
"@ | Set-Content -Encoding utf8 $licences

$zip = Join-Path $dist "ncm-carrier-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip

$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
$size = (Get-Item $zip).Length

Write-Host ""
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
Write-Host "  $size bytes"
Write-Host ""
Write-Host "== declaration (for tools/staging/declare-carrier.py)" -ForegroundColor Green
@"
{
  "id": "ncm-carrier",
  "source": "hosted",
  "displayName": "NCM Carrier",
  "version": "$version",
  "sha256": "$hash",
  "sizeBytes": $size,
  "capability": "executable"
}
"@ | Write-Host

Write-Host "NEXT, IN THIS ORDER:" -ForegroundColor Yellow
Write-Host "  1. Copy dist\ncm_carrier\red4ext\ into the game by hand and launch it."
Write-Host "     Read <game>\red4ext\logs\ and red4ext\plugins\ncm_carrier\ncm_carrier.log."
Write-Host "     THE GAME MUST LAUNCH. Do not skip this."
Write-Host "  2. Only then host the blob and declare it on DEVELOPMENT."
Write-Host "  3. Production is a separate decision on a separate day."
