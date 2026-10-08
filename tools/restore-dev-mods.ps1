<#
.SYNOPSIS
  Put the hand-installed NCM dev-server mods back into the game (KB-391): the OPEN//77 launcher quarantines every mod it
  did not project ("player choice") whenever it switches mode (solo <-> world), and on 2026-10-07 20:04 it took the
  redscript halves and archives of the NCM plugins while their DLLs stayed -- half-installed plugins. The single-player
  install (solo-adjust) had also switched ncm_thrust / ncm_snowglobe off.

  Sources, nothing guessed:
    * dist/<plugin>/  -- the build scripts' staged, game-shaped copies you hand-install from (Broadcast, Pace, Rig Bridge,
                         Vision, Snowglobe): files missing in the game are copied; differing non-config files replaced
    * the launcher's own quarantine (modstore blobs, by sha256) -- for what has no staged copy (gearbox scripts + tweaks,
                         NCM Clock, IWN braking, Pace diag)
    * install-records/ncm3-kimiko/solo-adjust-backup -- the original ncm_thrust / ncm_snowglobe configs (enabled)
  Never touched: NCM 3.0 (ncm_host), ncm_radial (parked, KB-182), existing plugin configs other than those two, and the
  third-party mods the launcher keeps out of world sessions. Everything replaced is backed up; the record lists it all.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\restore-dev-mods.ps1        (game closed)
#>
[CmdletBinding(PositionalBinding = $false)]
param([string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue) { throw 'Cyberpunk 2077 is running: close it first.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rec = Join-Path $repo "install-records\dev-restore-$stamp"
$backup = Join-Path $rec 'backup'
New-Item -ItemType Directory -Force $backup | Out-Null
$log = [System.Collections.ArrayList]@()

function Put([string]$src, [string]$rel, [string]$why) {
    $dst = Join-Path $Game $rel
    if (Test-Path -LiteralPath $dst) {
        if ((Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $dst).Hash) { return }
        $b = Join-Path $backup $rel
        New-Item -ItemType Directory -Force (Split-Path $b) | Out-Null
        Copy-Item -LiteralPath $dst -Destination $b -Force
        $action = 'replaced'
    } else { $action = 'added' }
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    [void]$log.Add([pscustomobject]@{ path = $rel; action = $action; source = $why; sha256 = (Get-FileHash -LiteralPath $dst).Hash })
    Write-Host ("  {0,-8} {1}  ({2})" -f $action, $rel, $why)
}

# 1. the staged builds
foreach ($p in @('ncm_broadcast', 'ncm_pace', 'ncm_rig_bridge', 'ncm_vision', 'ncm_snowglobe')) {
    $root = Join-Path $repo "dist\$p"
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\')
        if ($rel -match '\.md$|\.txt$') { return }
        $isConfig = $rel -match '\\red4ext\\plugins\\[^\\]+\\[^\\]+\.json$' -or $rel -match '^red4ext\\plugins\\[^\\]+\\[^\\]+\.json$'
        if ($isConfig -and (Test-Path -LiteralPath (Join-Path $Game $rel))) { return }   # a player's config is theirs
        Put $_.FullName $rel "dist\$p"
    }
}

# 2. the launcher's quarantine, for what has no staged copy
$store = Join-Path $env:LOCALAPPDATA 'Open77\modstore'
$q = Get-Content -Raw (Join-Path $store 'state\quarantine.json') | ConvertFrom-Json
foreach ($m in $q.mods) {
    if ($m.key -notmatch 'ncm_gearbox|ncm_clock|ncm_iwn_braking|ncm_pace_diag') { continue }
    foreach ($f in $m.files) {
        $blob = Join-Path $store ("blobs\" + $f.sha256.Substring(0, 2) + "\" + $f.sha256)
        if (-not (Test-Path -LiteralPath $blob)) { Write-Host "  MISSING blob for $($f.path)"; continue }
        $rel = $f.path -replace '/', '\'
        if (Test-Path -LiteralPath (Join-Path $Game $rel)) { continue }
        Put $blob $rel 'launcher quarantine'
    }
}

# 3. the dev-only configs the single-player install switched off
$sa = Join-Path $repo 'install-records\ncm3-kimiko\solo-adjust-backup'
Put (Join-Path $sa 'ncm_thrust_config.json') 'red4ext\plugins\ncm_thrust\ncm_thrust_config.json' 'solo-adjust-backup (enabled)'
Put (Join-Path $sa 'ncm_snowglobe_config.json') 'red4ext\plugins\ncm_snowglobe\ncm_snowglobe_config.json' 'solo-adjust-backup (enabled)'

[pscustomobject]@{ at = (Get-Date -Format s); game = $Game; reason = 'KB-391: launcher quarantine + solo-adjust took the hand-installed NCM dev mods'; files = $log } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $rec 'restore.json') -Encoding utf8
Write-Host ("restore-dev-mods: {0} file(s) put back; record {1}" -f $log.Count, $rec)
