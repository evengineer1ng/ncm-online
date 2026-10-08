<#
.SYNOPSIS
  Compile NCM 3.0's redscript (ncm/host_native/r6/scripts/ncm_host) against the installed game's scripts in a scratch
  cache (L340 phase 2). Nothing in the game folder is touched.

  The scratch set is what the game compiles at launch: every r6/scripts folder, plus the .reds that RED4ext plugins
  ship in their own folders (Codeware, Mod Settings, ...). NCM 2.0's MT_Ecosystem is left out: NCM 3.0 disables it.
  KB-182: a `native func` must never sit inside a `module` -- refused here before the game would refuse to start.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-host-redscript.ps1
#>
[CmdletBinding(PositionalBinding = $false)]
param([string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mine = Join-Path $repo 'ncm\host_native\r6\scripts\ncm_host'
$scc = Join-Path $Game 'engine\tools\scc.exe'
if (-not (Test-Path $scc)) { throw "no redscript compiler at $scc" }

foreach ($f in Get-ChildItem $mine -Filter *.reds) {
    $t = Get-Content -Raw $f.FullName
    if ($t -match '(?m)^\s*module\s' -and $t -match 'native\s+func') { throw "$($f.Name): natives inside a module (KB-182)" }
}

$scratch = Join-Path $env:TEMP 'ncm-host-scc'
if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch }
$scripts = Join-Path $scratch 'scripts'
New-Item -ItemType Directory -Force $scripts, (Join-Path $scratch 'cache') | Out-Null
Get-ChildItem (Join-Path $Game 'r6\scripts') -Directory | Where-Object { $_.Name -notin @('ncm_host', 'MT_Ecosystem') } |
    ForEach-Object { Copy-Item -Recurse $_.FullName $scripts }
Get-ChildItem (Join-Path $Game 'r6\scripts') -File -Filter *.reds | ForEach-Object { Copy-Item $_.FullName $scripts }
$n = 0
Get-ChildItem (Join-Path $Game 'red4ext\plugins') -Directory | ForEach-Object {
    $plugin = $_
    Get-ChildItem $plugin.FullName -Recurse -File -Filter *.reds -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\cache\\' } | ForEach-Object {
        $dst = Join-Path $scripts ("_plugin_" + $plugin.Name + "\" + $_.FullName.Substring($plugin.FullName.Length + 1))
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item $_.FullName $dst
        $n++
    }
}
New-Item -ItemType Directory -Force (Join-Path $scripts 'ncm_host') | Out-Null
Copy-Item (Join-Path $mine '*.reds') (Join-Path $scripts 'ncm_host')
Copy-Item (Join-Path $Game 'r6\cache\final.redscripts') (Join-Path $scratch 'cache')
Write-Host ("compiling ncm_host redscript with the game's scripts and {0} plugin script file(s) ..." -f $n)
$out = & $scc -compile $scripts -customCacheDir (Join-Path $scratch 'cache') 2>&1
$out | Where-Object { "$_" -match 'ERROR|WARN' } | ForEach-Object { Write-Host "  $_" }
if (-not ($out -match 'Compilation complete')) { throw 'redscript did not compile; see the errors above' }
Write-Host 'ncm_host redscript compiles' -ForegroundColor Green
