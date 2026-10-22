<#
.SYNOPSIS
  Install (or remove) the first NCM 3.0 Collection test on this PC (L338): the RB15 F1 (Nexus 31543 v10, the owner's own
  download in staging/checkpoint-04), NCM's ten RB15 liveries (Kimiko Racing / Orbital Air among them), and NCM 3.0 itself.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-ncm3-kimiko.ps1              # install (game closed)
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-ncm3-kimiko.ps1 -Uninstall   # remove exactly what it added
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install-ncm3-kimiko.ps1 -UpdateNcm   # re-copy NCM 3.0 after a rebuild

  Every file it writes is recorded (sha256) in install-records/ncm3-kimiko/deployment.json; a file it overwrites is backed
  up first and restored by -Uninstall. NCM's data (mods/NCM/db.sqlite3, mods/NCM/save/) is never overwritten or removed.
  Play WITHOUT the OPEN//77 launcher (start Cyberpunk from Steam): the launcher manages its own per-world mod set.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077',
    [switch]$Uninstall,
    [switch]$UpdateNcm,
    [string]$NcmVersion = '3.0.0-alpha.8'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$records = Join-Path $repo 'install-records\ncm3-kimiko'
$recordFile = Join-Path $records 'deployment.json'
$backupRoot = Join-Path $records 'backup'
if (-not (Test-Path -LiteralPath (Join-Path $Game 'bin\x64\Cyberpunk2077.exe'))) { throw "Not a Cyberpunk 2077 folder: $Game" }
if (Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue) { throw 'Cyberpunk 2077 is running: close it first.' }

if ($Uninstall) {
    if (-not (Test-Path $recordFile)) { throw 'Nothing recorded to uninstall.' }
    $rec = Get-Content -Raw $recordFile | ConvertFrom-Json
    $removed = 0; $restored = 0
    if ($rec.PSObject.Properties.Name -contains 'parked') {
        foreach ($p in @($rec.parked)) {
            $src = Join-Path $Game $p.to; $back = Join-Path $Game $p.from
            if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $back)) { Move-Item -LiteralPath $src -Destination $back; $restored++ }
        }
    }
    foreach ($f in $rec.files) {
        $dst = Join-Path $Game $f.relative_path
        if ($f.backup) { Copy-Item -LiteralPath (Join-Path $backupRoot $f.relative_path) -Destination $dst -Force; $restored++ }
        elseif (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force; $removed++ }
    }
    Write-Host ("ncm3-kimiko uninstall: {0} file(s) removed, {1} restored. NCM data in mods/NCM (db.sqlite3, save/) left in place." -f $removed, $restored)
    Rename-Item -LiteralPath $recordFile -NewName ("deployment.uninstalled-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    exit 0
}

if ($UpdateNcm) {
    # Re-copy NCM 3.0's own files from dist/ (after tools/ncm-host-build.ps1); the RB15 and liveries are left alone.
    if (-not (Test-Path $recordFile)) { throw 'Not installed yet: run without -UpdateNcm first.' }
    $rec = Get-Content -Raw $recordFile | ConvertFrom-Json
    $root = Join-Path $repo ('dist\ncm-' + $NcmVersion)
    if (-not (Test-Path $root)) { throw "Missing $root (run tools/ncm-host-build.ps1)" }
    # prune: NCM files an earlier build installed that this build no longer ships (alpha.1 ran inside CET: host/,
    # resources/, compiled/ under mods/NCM). NCM's data is never pruned (save/, *.sqlite3).
    $ship = @{}
    Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $ship[$_.FullName.Substring($root.Length).TrimStart('\').ToLower()] = $true }
    $keep = [System.Collections.ArrayList]@()
    $pruned = 0
    foreach ($f in $rec.files) {
        $isNcm = $f.source -like 'NCM 3.0*'
        $isData = ($f.relative_path -match '\\save\\') -or ($f.relative_path -match '\.sqlite3$')
        if ($isNcm -and -not $isData -and -not $ship.ContainsKey($f.relative_path.ToLower())) {
            $old = Join-Path $Game $f.relative_path
            if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
            $pruned++
        } else { [void]$keep.Add($f) }
    }
    # folders the prune emptied, only inside NCM's own CET folder
    $ncmCet = Join-Path $Game 'bin\x64\plugins\cyber_engine_tweaks\mods\NCM'
    foreach ($sub in @('host', 'resources', 'compiled')) {
        $dir = Join-Path $ncmCet $sub
        if ((Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Recurse -File)) { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    $rec.files = $keep
    $known = @{}; foreach ($f in $rec.files) { $known[$f.relative_path.ToLower()] = $f }
    $files = [System.Collections.ArrayList]@($rec.files)
    $changed = 0; $added = 0
    Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\')
        $dst = Join-Path $Game $rel
        $hash = (Get-FileHash -LiteralPath $_.FullName).Hash
        if ((Test-Path -LiteralPath $dst) -and (Get-FileHash -LiteralPath $dst).Hash -eq $hash) { return }
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
        $k = $known[$rel.ToLower()]
        if ($k) { $k.sha256 = $hash; $changed++ }
        else { [void]$files.Add([pscustomobject]@{ source = 'NCM 3.0 alpha'; relative_path = $rel; sha256 = $hash; backup = $false }); $added++ }
    }
    $rec.files = $files
    # L340: NCM 2.0's redscript (r6/scripts/MT_Ecosystem) wraps every map-pin controller and the HUD on every update,
    # whatever is running; its CET half was parked already (solo-adjust). Park the redscript too: MOVED out of the
    # scripts folder, never deleted; -Uninstall moves it back.
    $parked = @()
    if ($rec.PSObject.Properties.Name -contains 'parked') { $parked = @($rec.parked) }
    $mte = Join-Path $Game 'r6\scripts\MT_Ecosystem'
    if (Test-Path -LiteralPath $mte) {
        $dest = Join-Path $Game 'r6\ncm3-parked\MT_Ecosystem'
        if (Test-Path -LiteralPath $dest) { $dest = $dest + '-' + (Get-Date -Format 'yyyyMMddHHmmss') }
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Move-Item -LiteralPath $mte -Destination $dest
        $parked += [pscustomobject]@{ from = 'r6\scripts\MT_Ecosystem'; to = $dest.Substring($Game.Length).TrimStart('\') }
        Write-Host "  parked NCM 2.0 redscript: r6\scripts\MT_Ecosystem -> $($dest.Substring($Game.Length).TrimStart('\'))"
    }
    $rec | Add-Member -NotePropertyName parked -NotePropertyValue $parked -Force
    $rec | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $recordFile -Encoding utf8
    Write-Host ("ncm3-kimiko -UpdateNcm ({2}): {0} file(s) updated, {1} added, {3} pruned (NCM data untouched)." -f $changed, $added, $NcmVersion, $pruned)
    exit 0
}

if (Test-Path $recordFile) { throw "Already installed (record $recordFile). Run -Uninstall first to reinstall, or -UpdateNcm." }
$sources = @(
    @{ Name = 'RB15 F1 Car Mod Demo (Nexus 31543 v10)'; Root = Join-Path $repo 'staging\checkpoint-04\extracted\31543\RB'; Exclude = '^(meta\.ini|[^\\]+\.txt)$' },
    @{ Name = 'NCM RB15 liveries (10)'; Root = Join-Path $repo 'wolvenkit-projects\ncm_rb15_liveries\out\payload'; Exclude = '^$' },
    @{ Name = 'NCM 3.0 alpha'; Root = Join-Path $repo ('dist\ncm-' + $NcmVersion); Exclude = '^$' }
)
foreach ($s in $sources) { if (-not (Test-Path $s.Root)) { throw ("Missing {0} at {1} (build it first: liveries -> build_liveries.py, NCM -> tools/ncm-host-build.ps1)" -f $s.Name, $s.Root) } }

New-Item -ItemType Directory -Force $records, $backupRoot | Out-Null
$files = @()
foreach ($s in $sources) {
    $n = 0
    Get-ChildItem -LiteralPath $s.Root -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($s.Root.Length).TrimStart('\')
        if ($rel -match $s.Exclude) { return }
        $dst = Join-Path $Game $rel
        $backup = $false
        if (Test-Path -LiteralPath $dst) {
            if ((Get-FileHash -LiteralPath $dst).Hash -ne (Get-FileHash -LiteralPath $_.FullName).Hash) {
                $b = Join-Path $backupRoot $rel
                New-Item -ItemType Directory -Force (Split-Path $b) | Out-Null
                Copy-Item -LiteralPath $dst -Destination $b -Force
                $backup = $true
            }
        }
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
        $files += [pscustomobject]@{ source = $s.Name; relative_path = $rel; sha256 = (Get-FileHash -LiteralPath $dst).Hash; backup = $backup }
        $n++
    }
    Write-Host ("  {0}: {1} file(s)" -f $s.Name, $n)
}
[pscustomobject]@{ installed_at = (Get-Date).ToString('s'); game = $Game; files = $files } | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $recordFile -Encoding utf8
Write-Host ("ncm3-kimiko: installed {0} file(s); {1} backed up. Record: {2}" -f $files.Count, ($files | Where-Object backup).Count, $recordFile)
Write-Host "Next: start Cyberpunk from Steam (not the OPEN//77 launcher), load a save, enter a tape, Tape Deck hotkey -> GARAGE -> Claim Kimiko Racing."
