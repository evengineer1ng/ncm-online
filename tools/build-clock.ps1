[CmdletBinding()]
param([double]$Scale = 0.125, [string]$Version = "0.1.0")

# Builds NCM Clock (package id `ncm-clock`; KB-217, IDEA-729): Night City's day runs at real time, natively.
#
# The engine advances game time at a base 8x, multiplied by one curve, `time_of_the_day_to_timescale`, in
# base\gameplay\game_time.curveset (CDPR shapes it to stretch dawn and dusk; "Custom Timescale" and "Game Time Tweaks"
# on Nexus rewrite the same curve). A flat 0.125 makes it exactly 8 x 0.125 = 1x at every hour. With every client at
# 1x, the server can run the OPEN//77 clock at rate 1.0 on US Eastern time and the projection never has to correct it,
# so there are no world time-jumps (OPEN//77's weather guide: any rate but the engine's own means one every ~15 s).
#
# Nothing of CDPR's is committed: this regenerates the resource from the local game every build (the IDEA-704 / POI
# pattern), extracting one named file only. Output: dist/ncm-clock-<version>.zip with archive/pc/mod/ncm_clock.archive.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $root "tools\WolvenKit.Console-8.20.0\WolvenKit.CLI.exe"
$engine = "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077\archive\pc\content\basegame_1_engine.archive"
$work = Join-Path $env:TEMP "ncm-clock-build"
$dist = Join-Path $root "dist"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force $work | Out-Null

Write-Host "== extracting base\gameplay\game_time.curveset (one named file)" -ForegroundColor Cyan
& $cli extract $engine --outpath (Join-Path $work "vanilla") --regex "base.gameplay.game_time\.curveset$" | Out-Null
$vanilla = Join-Path $work "vanilla\base\gameplay\game_time.curveset"
if (-not (Test-Path $vanilla)) { throw "game_time.curveset was not extracted" }
& $cli convert serialize $vanilla | Out-Null
$json = "$vanilla.json"
if (-not (Test-Path $json)) { throw "serialize failed" }

Write-Host "== flattening time_of_the_day_to_timescale to $Scale (base 8x -> $([math]::Round(8 * $Scale, 3))x)" -ForegroundColor Cyan
$doc = Get-Content -Raw $json | ConvertFrom-Json
$curves = @($doc.Data.RootChunk.curves)
if ($curves.Count -ne 1 -or $curves[0].name.'$value' -ne "time_of_the_day_to_timescale") { throw "unexpected curveset shape; CDPR changed the resource -- re-read it before building" }
foreach ($e in $curves[0].curve.Elements) { $e.Value = $Scale }
$stage = Join-Path $work "ncm_clock\base\gameplay"
New-Item -ItemType Directory -Force $stage | Out-Null
$outJson = Join-Path $stage "game_time.curveset.json"
$doc | ConvertTo-Json -Depth 32 | Set-Content -Encoding utf8 $outJson
& $cli convert deserialize $outJson | Out-Null
$built = Join-Path $stage "game_time.curveset"
if (-not (Test-Path $built)) { throw "deserialize failed" }
Remove-Item $outJson

Write-Host "== verifying the built resource reads back flat" -ForegroundColor Cyan
$check = Join-Path $work "check"
New-Item -ItemType Directory -Force $check | Out-Null
Copy-Item $built $check
& $cli convert serialize (Join-Path $check "game_time.curveset") | Out-Null
$back = Get-Content -Raw (Join-Path $check "game_time.curveset.json") | ConvertFrom-Json
$values = @($back.Data.RootChunk.curves[0].curve.Elements | ForEach-Object { [double]$_.Value } | Sort-Object -Unique)
if ($values.Count -ne 1 -or [math]::Abs($values[0] - $Scale) -gt 1e-6) { throw "built curve is not flat at $Scale ($($values -join ','))" }
Write-Host "  flat at $Scale across $(@($back.Data.RootChunk.curves[0].curve.Elements).Count) points" -ForegroundColor Green

Write-Host "== packing" -ForegroundColor Cyan
& $cli pack (Join-Path $work "ncm_clock") --outpath $work | Out-Null
$archive = Join-Path $work "ncm_clock.archive"
if (-not (Test-Path $archive)) { throw "pack failed" }

$pkg = Join-Path $work "pkg"
New-Item -ItemType Directory -Force (Join-Path $pkg "archive\pc\mod") | Out-Null
Copy-Item $archive (Join-Path $pkg "archive\pc\mod\ncm_clock.archive")
@"
NCM Clock $Version -- Night City's day at real time (x$([math]::Round(8 * $Scale, 3))), for NCM Online servers that run
the OPEN//77 clock at rate $([math]::Round(8 * $Scale, 3)) on US Eastern time. Replaces base\gameplay\game_time.curveset
(time_of_the_day_to_timescale, flat $Scale). Conflicts with any other mod that replaces the same curve
(Custom Timescale, Game Time Tweaks): only one can win.
"@ | Set-Content -Encoding utf8 (Join-Path $pkg "archive\pc\mod\ncm_clock.txt")
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "ncm-clock-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $pkg "*") -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
Write-Host "== package" -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  sha256 $hash"
Write-Host "  publish (dev):  python tools\staging\publish-carrier.py tools\open77\server --zip `"$zip`" --version $Version --id ncm-clock --display-name `"NCM Clock`" --import-blob --enable"
Write-Host "  dev joins by address never receive required mods (KB-126): also  python tools\dev-hand-install-mods.py --only ncm-clock"
