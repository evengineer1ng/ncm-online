# Build the NCM Carrier plugin and assemble the hosted package.
#
# Builds, packages and -- with -PublishDev -- hosts it on the local Development server and restarts it.
# Then you launch the game and join. There is no manual copy step: the launcher installs the package, which
# is the path that actually ships, and it is the path worth testing.
#
# RECOVERY IF THE GAME WILL NOT LAUNCH. One command, server-side, nothing to hunt for on disk:
#
#   python tools/staging/publish-carrier.py tools/open77/server --remove
#   .\tools\build-carrier.ps1 -RestartDevOnly
#
# The launcher then removes what it projected on the next join. That is why hosting beats copying by hand:
# the uninstall is somebody else's job and it is already written.
#
#   .\tools\build-carrier.ps1                     build and package only
#   .\tools\build-carrier.ps1 -PublishDev         build, package, host on Development, restart it
#   .\tools\build-carrier.ps1 -SkipBuild -PublishDev   repackage and host what is already built
#   .\tools\build-carrier.ps1 -RestartDevOnly     just bounce the Development server
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$PublishDev,
    [switch]$RestartDevOnly,
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$carrier = Join-Path $root "ncm\carrier"
$dist = Join-Path $root "dist"

$devRoot = Join-Path $root "tools\open77\server"

function Restart-DevServer {
    # Stop whatever is serving, then start it detached the way o77-server.ps1 does, so the licence key
    # still comes from the DPAPI secret store and never from a file or an argument.
    $running = Get-Process -Name "Open77.Server" -ErrorAction SilentlyContinue
    foreach ($proc in $running) {
        Write-Host "stopping Open77.Server (pid $($proc.Id))" -ForegroundColor DarkGray
        try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
    }
    if ($running) { Start-Sleep -Seconds 2 }

    $script = Join-Path $root "tools\o77-server.ps1"
    Start-Process -FilePath "powershell" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script) `
        -WorkingDirectory $root -WindowStyle Minimized | Out-Null
    Write-Host "Development server starting..." -ForegroundColor Cyan

    # Wait for the manifest rather than for a fixed sleep: the digest is the thing we actually care about.
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        try {
            $manifest = Invoke-RestMethod -Uri "http://127.0.0.1:11779/mods/v1/manifest" -TimeoutSec 3
            return $manifest
        } catch { }
    }
    Write-Warning "server did not answer /mods/v1/manifest within 60s -- check its console window"
    return $null
}

if ($RestartDevOnly) {
    $m = Restart-DevServer
    if ($m) {
        Write-Host "manifest digest: $($m.digest)" -ForegroundColor Green
        Write-Host "enabled: $($m.enabled)  packages: $($m.mods.Count)"
    }
    return
}

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
if (-not $PublishDev) {
    Write-Host "Not published. Run again with -PublishDev to host it on Development." -ForegroundColor Yellow
    return
}

Write-Host "== publishing to Development" -ForegroundColor Cyan
# RB15 and its liveries are still declared on Development, parked. Enabling requiredMods would make them
# required to join again, and `L142` ceased their redistribution -- so they go as the carrier arrives.
& python (Join-Path $root "tools\staging\publish-carrier.py") $devRoot `
    --zip $zip --version $version --enable `
    --drop "rb15-f1-inert-v10" --drop "ncm-rb15-liveries"
if ($LASTEXITCODE -ne 0) { throw "publish failed -- server.jsonc was not changed" }

$manifest = Restart-DevServer
if ($manifest) {
    Write-Host ""
    Write-Host "== Development is serving" -ForegroundColor Green
    Write-Host "  digest   $($manifest.digest)"
    Write-Host "  enabled  $($manifest.enabled)"
    foreach ($mod in $manifest.mods) { Write-Host "  package  $($mod.id) $($mod.version)" }
    if ($manifest.digest -notmatch $hash.Substring(0, 8) -and $manifest.mods.Count -eq 0) {
        Write-Warning "no packages in the manifest -- requiredMods may still be parked"
    }
}

Write-Host ""
Write-Host "NEXT: launch the game and join Development." -ForegroundColor Yellow
Write-Host "  The launcher will name NCM Carrier as executable content and ask you to accept it."
Write-Host "  Then MASTER_TEST section AT: AT1 the game launches, AT2 the bridge connects, AT4 weather"
Write-Host "  reaches a freshly spawned car, AT6 one drive closes KB-106."
Write-Host ""
Write-Host "IF THE GAME WILL NOT LAUNCH:" -ForegroundColor Yellow
Write-Host "  python tools/staging/publish-carrier.py tools/open77/server --remove"
Write-Host "  .\tools\build-carrier.ps1 -RestartDevOnly"
Write-Host "  Rejoin; the launcher removes what it projected. Read ncm_carrier.log for why."
