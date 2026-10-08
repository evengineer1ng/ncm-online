<#
.SYNOPSIS
  Pack NIGHT CITY MOTORSPORTS 3.0 (single player): the ncm_host RED4ext plugin (Lua 5.4 + SQLite running the NCM Host
  and the NCM resources unchanged) + the thin CET mod (the Tape Deck, the Race Week line, the game bindings) + the
  redscript natives. (L338, doc 55; KB-385: CET's sandbox cannot run the resources itself.)

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-host-build.ps1          # build + self-test + stage + zip
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-host-build.ps1 -Check   # verify the stage only

  Output: dist/ncm-<version>/ (a game-folder-shaped tree) and dist/ncm-<version>.zip. Not installed by this script.
  -Check exits 1 if a staged resource Lua file differs from ncm/online/resources (the plugin must carry the dev server's
  own code, byte for byte) or a required file is missing.
#>
[CmdletBinding(PositionalBinding = $false)]
param([switch]$Check, [string]$Version = '3.0.0-alpha.7')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stage = Join-Path $repo ("dist\ncm-" + $Version)
$mod = Join-Path $stage 'bin\x64\plugins\cyber_engine_tweaks\mods\NCM'
$plugin = Join-Path $stage 'red4ext\plugins\ncm_host'
$resources = @('ncm_league', 'ncm_world', 'ncm_paddock', 'ncm_speed', 'ncm_broadcast', 'ncm_scanner', 'ncm_observer', 'ncm_aero')

if (-not $Check) {
    & (Join-Path $PSScriptRoot 'build-host-native.ps1')   # builds, stages dist/ncm-host-native, runs the self-test (throws on FAIL)
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    Copy-Item -Recurse (Join-Path $repo 'dist\ncm-host-native') $stage
    # L340: no CET half any more -- the game itself drives NCM (r6/scripts/ncm_host/*.reds). The README rides with the plugin.
    Copy-Item (Join-Path $repo 'ncm\host\package\README.txt') (Join-Path $plugin 'README.txt')
}

# ---------------------------------------------------------------------------------------------------- verify
$bad = 0; $n = 0
foreach ($r in $resources) {
    $src = Join-Path $repo "ncm\online\resources\$r"
    Get-ChildItem -LiteralPath $src -Recurse -File -Filter *.lua | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length).TrimStart('\')
        $dst = Join-Path $plugin "resources\$r\$rel"
        $n++
        if (-not (Test-Path -LiteralPath $dst)) { $bad++; Write-Host "  MISSING $r\$rel"; return }
        if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $dst).Hash) { $bad++; Write-Host "  DIFFERS $r\$rel" }
    }
}
foreach ($f in @('red4ext\plugins\ncm_host\ncm_host.dll', 'red4ext\plugins\ncm_host\host\native.lua', 'red4ext\plugins\ncm_host\host\app.lua',
        'red4ext\plugins\ncm_host\save\.keep', 'r6\scripts\ncm_host\NcmHostNatives.reds',
        'r6\scripts\ncm_host\NcmHostRuntime.reds', 'r6\scripts\ncm_host\NcmHostHud.reds', 'r6\scripts\ncm_host\NcmHostSettings.reds')) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $f))) { $bad++; Write-Host "  MISSING $f" }
}
Write-Host ("ncm-host-build: {0} resource Lua file(s) compared, {1} problem(s)" -f $n, $bad)
if ($bad -ne 0) { exit 1 }

if (-not $Check) {
    $zip = Join-Path $repo ("dist\ncm-" + $Version + ".zip")
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
    Write-Host ("ncm-host-build: {0} ({1} MB). Install: tools/install-ncm3-kimiko.ps1 -UpdateNcm" -f $zip, [math]::Round((Get-Item $zip).Length / 1MB, 2))
}
exit 0
