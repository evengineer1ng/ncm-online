<#
.SYNOPSIS
  Upgrade the LOCAL Windows OPEN//77 server (tools\open77\server) to a new package, preserving
  operator-owned state, with a verified package and an automatic rollback.

.WHY THIS EXISTS
  This is the Windows counterpart of tools/staging/upgrade-open77.sh. It deliberately follows the
  same shape -- verify, preserve, swap, guard, roll back -- because the development box only has
  value if the procedure exercised there is the procedure production will get.

  It also front-loads the failure that cost an hour of downtime on Lightsail (KB-51): an upgrade
  can add a resource and make an already-loaded one depend on it. `resources.load` is an explicit
  allow-list, not a directory scan, so the new resource is never loaded, the server ABORTS ITS
  ENTIRE automatic start set, and still listens and registers with the master -- looking healthy
  while NCM is absent. The load-list guard runs here BEFORE the server is ever started.

.WHAT IS PRESERVED
  server.jsonc, acl.jsonc, tunables.json, .open77\ (identities, warden, signing key), and the
  server icon/banner. Everything else comes from the package. The resources\ncm junction is
  recreated so local edits stay live with no copy step.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-upgrade.ps1 `
      -Package .\open77-server-2.31.13+op77.87-win-x64.zip -ExpectedVersion 2.31.13+op77.87

  Add -MirrorLoadList to rewrite resources.load from a name list (use it to match production).
  Add -WhatIf to verify the package and report what would change without touching anything.

.ROLLBACK
  The previous tree is moved to tools\open77\backups\server-<UTC>, not deleted. If the new server
  fails to start, restore by swapping that directory back into place.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$Package,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [string[]]$MirrorLoadList,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$root   = Resolve-Path (Join-Path $here '..')
$o77    = Join-Path $root 'tools\open77'
$active = Join-Path $o77  'server'
$stamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$cand   = Join-Path $o77  "server.$ExpectedVersion.new"
$backup = Join-Path $o77  "backups\server-$stamp"
$log    = { param($m) Write-Host ("[o77-upgrade] " + $m) }

# Removing a tree that contains a directory junction is dangerous: Remove-Item -Recurse can follow
# the link and delete the TARGET. Here the target is ncm\online\resources -- the entire NCM source.
# So: unlink any junction without recursion before deleting anything.
function Remove-TreeSafely([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $full = [System.IO.Path]::GetFullPath($path)
    $safeRoot = [System.IO.Path]::GetFullPath($o77).TrimEnd('\') + '\'
    if (-not $full.StartsWith($safeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing to remove path outside tools/open77: $full"
    }
    Get-ChildItem -LiteralPath $path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType -in @('Junction', 'SymbolicLink') } |
        ForEach-Object { [System.IO.Directory]::Delete($_.FullName, $false) }
    $self = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($self -and $self.LinkType -in @('Junction', 'SymbolicLink')) { [System.IO.Directory]::Delete($full, $false); return }
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $Package)) { throw "Package not found: $Package" }
if (-not (Test-Path $active))  { throw "No active server at $active" }
Remove-TreeSafely $cand

# --- 1. Extract and verify against the package's own manifest ---------------------------
& $log "extracting package"
New-Item -ItemType Directory -Force -Path $cand | Out-Null
Expand-Archive -LiteralPath $Package -DestinationPath $cand -Force

$manifestPath = Join-Path $cand 'package-manifest.json'
if (-not (Test-Path $manifestPath)) { throw "package-manifest.json missing from package" }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($manifest.version -ne $ExpectedVersion) { throw "manifest version '$($manifest.version)' != '$ExpectedVersion'" }
if ($manifest.runtime -ne 'win-x64')        { throw "wrong runtime: '$($manifest.runtime)' (expected win-x64)" }

& $log ("verifying {0} files against the package manifest" -f $manifest.files.Count)
$bad = 0
foreach ($entry in $manifest.files) {
    $p = Join-Path $cand ($entry.path -replace '/', '\')
    if (-not (Test-Path $p)) { Write-Host "  MISSING $($entry.path)"; $bad++; continue }
    $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $entry.sha256.ToLower()) { Write-Host "  HASH MISMATCH $($entry.path)"; $bad++ }
}
if ($bad -gt 0) { throw "$bad package file(s) failed verification; refusing to upgrade" }
& $log ("package verified: {0} {1} (commit {2})" -f $manifest.version, $manifest.runtime, $manifest.baseCommit)

# --- 2. Carry operator-owned state forward ----------------------------------------------
# These belong to this machine, not to the package. server.jsonc in particular holds the licence
# key and is never read or printed here -- only copied.
$preserve = @('server.jsonc', 'acl.jsonc', 'tunables.json', '.open77', 'server-icon.png', 'server-banner.png')
foreach ($item in $preserve) {
    $src = Join-Path $active $item
    if (Test-Path $src) {
        $dst = Join-Path $cand $item
        Remove-TreeSafely $dst
        Copy-Item -Recurse -Force $src $dst
        & $log "preserved $item"
    }
}

# --- 3. Optionally mirror a known-good load list ----------------------------------------
# Used to make the development box match production exactly. Rewrites only the names inside
# resources.load; every other byte of server.jsonc (including the licence) is left alone.
if ($MirrorLoadList) {
    $conf = Join-Path $cand 'server.jsonc'
    $text = Get-Content $conf -Raw
    $m = [regex]::Match($text, '("load"\s*:\s*\[)(.*?)(\])', 'Singleline')
    if (-not $m.Success) { throw "could not locate resources.load in server.jsonc" }
    $body = "`n" + (($MirrorLoadList | ForEach-Object { '      "' + $_ + '"' }) -join ",`n") + "`n    "
    $text = $text.Remove($m.Groups[2].Index, $m.Groups[2].Length).Insert($m.Groups[2].Index, $body)
    # Written even under -WhatIf: this edits the CANDIDATE tree, which is disposable and is exactly
    # what the guard below must inspect. -WhatIf withholds the swap, not the preparation -- a dry run
    # that skipped this would guard the old config against the new resources and fail for the wrong reason.
    Set-Content -LiteralPath $conf -Value $text -Encoding UTF8
    & $log ("resources.load mirrored: {0} entries" -f $MirrorLoadList.Count)
}

# --- 4. NCM resources junction ------------------------------------------------------------
$junction = Join-Path $cand 'resources\ncm'
$target   = Join-Path $root 'ncm\online\resources'
Remove-TreeSafely $junction
# Created even under -WhatIf: the candidate must be a complete, inspectable tree.
cmd /c mklink /J "$junction" "$target" | Out-Null
& $log "junction resources\ncm -> ncm\online\resources"

# --- 5. Load-list guard, BEFORE the swap and before any start ----------------------------
$guard = Join-Path $root 'tools\staging\check-load-list.py'
& $log "running load-list guard (KB-51)"
& python $guard $cand
if ($LASTEXITCODE -ne 0) {
    throw "Load-list guard FAILED. Not swapping. Fix resources.load, then re-run. Candidate left at: $cand"
}

if ($WhatIf) {
    & $log "-WhatIf: verification and guard passed. Nothing swapped. Candidate at: $cand"
    return
}

# --- 6. Swap, keeping the old tree ---------------------------------------------------------
# Both trees carry the resources\ncm junction, and Move-Item must never see it: when PowerShell 5.1
# cannot rename a directory (a scanner or indexer holding a freshly extracted file), it falls back to
# copy-then-delete, which FOLLOWS the junction -- it copied the whole NCM source into the new tree as
# real files and deleted the originals (2026-09-30, L239). So: unlink both junctions first, swap with
# Directory.Move (a plain rename that throws instead of falling back), then recreate the junction.
foreach ($tree in @($active, $cand)) {
    $link = Join-Path $tree 'resources\ncm'
    $li = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if ($li -and $li.LinkType -in @('Junction', 'SymbolicLink')) { [System.IO.Directory]::Delete($li.FullName, $false) }
    if (Test-Path -LiteralPath $link) { throw "resources\ncm in $tree is not a junction; refusing to swap (inspect it by hand)" }
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
& $log "swapping (previous tree -> $backup)"
[System.IO.Directory]::Move($active, $backup)
try {
    [System.IO.Directory]::Move($cand, $active)
} catch {
    [System.IO.Directory]::Move($backup, $active)
    cmd /c mklink /J "$(Join-Path $active 'resources\ncm')" "$target" | Out-Null
    throw "swap failed ($($_.Exception.Message)); previous tree restored. Close whatever holds $cand and re-run."
}
$junction = Join-Path $active 'resources\ncm'
cmd /c mklink /J "$junction" "$target" | Out-Null
& $log "junction resources\ncm -> ncm\online\resources recreated; the backup carries none"

& $log "DONE. Active version: $ExpectedVersion"
& $log "Previous tree kept at: $backup"
& $log "Start with: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-server.ps1"
