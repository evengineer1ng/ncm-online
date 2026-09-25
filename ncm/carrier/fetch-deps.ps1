# Fetch the carrier's two binary dependencies into third_party/.
#
# **No vcpkg.** SDL2 ships an official prebuilt VC package with headers, import library and DLL, and
# nlohmann/json is a single header. Between them that is the whole dependency list, so asking a solo
# developer to install and bootstrap a package manager to build two files was overhead with no payoff.
#
# Run once. The downloads are gitignored; this script is what reproduces them.
#
#   .\ncm\carrier\fetch-deps.ps1
[CmdletBinding()]
param(
    [string]$SdlVersion = "2.32.10",
    [string]$JsonVersion = "3.11.3",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$here = $PSScriptRoot
$thirdParty = Join-Path $here "third_party"
New-Item -ItemType Directory -Force -Path $thirdParty | Out-Null

# ----------------------------------------------------------------------------------------------- SDL2
$sdlDir = Join-Path $thirdParty "SDL2"
if ($Force -and (Test-Path $sdlDir)) { Remove-Item -Recurse -Force $sdlDir }

if (Test-Path (Join-Path $sdlDir "include\SDL.h")) {
    Write-Host "SDL2 already present at $sdlDir" -ForegroundColor DarkGray
} else {
    $url = "https://github.com/libsdl-org/SDL/releases/download/release-$SdlVersion/SDL2-devel-$SdlVersion-VC.zip"
    $zip = Join-Path $env:TEMP "SDL2-devel-$SdlVersion-VC.zip"
    Write-Host "downloading SDL2 $SdlVersion" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

    $unpack = Join-Path $env:TEMP "sdl2-unpack-$SdlVersion"
    if (Test-Path $unpack) { Remove-Item -Recurse -Force $unpack }
    Expand-Archive -Path $zip -DestinationPath $unpack

    # The archive contains one top-level SDL2-<version> directory; flatten it so the CMake paths are stable
    # across upgrades.
    $inner = Get-ChildItem -Path $unpack -Directory | Select-Object -First 1
    Move-Item $inner.FullName $sdlDir
    Remove-Item -Recurse -Force $unpack
    Remove-Item -Force $zip
    Write-Host "SDL2 -> $sdlDir" -ForegroundColor Green
}

# ------------------------------------------------------------------------------------------- nlohmann
$jsonDir = Join-Path $thirdParty "json\nlohmann"
$jsonHeader = Join-Path $jsonDir "json.hpp"
if ((Test-Path $jsonHeader) -and -not $Force) {
    Write-Host "nlohmann/json already present" -ForegroundColor DarkGray
} else {
    New-Item -ItemType Directory -Force -Path $jsonDir | Out-Null
    $url = "https://github.com/nlohmann/json/releases/download/v$JsonVersion/json.hpp"
    Write-Host "downloading nlohmann/json $JsonVersion" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $jsonHeader -UseBasicParsing
    Write-Host "json.hpp -> $jsonHeader" -ForegroundColor Green
}

Write-Host ""
Write-Host "Dependencies ready. Next: .\tools\build-carrier.ps1 -PublishDev" -ForegroundColor Yellow
