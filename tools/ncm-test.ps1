<#
.SYNOPSIS
  Run the ncm-core test suite under BOTH Lua 5.4 and LuaJIT (the CET/OPEN//77 intersection gate).
  Exits non-zero if either interpreter fails or is missing (unless -AllowMissing).

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-test.ps1 [-Filter ids] [-AllowMissing]
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Filter,
    [switch]$AllowMissing,
    [string]$CoreRoot
)
$ErrorActionPreference = 'Continue'
if (-not $CoreRoot) {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $CoreRoot = Join-Path $here '..\ncm\core'
}
$CoreRoot = (Resolve-Path $CoreRoot).Path

function Find-Exe([string[]]$names, [string[]]$hints) {
    foreach ($n in $names) { $c = Get-Command $n -ErrorAction SilentlyContinue; if ($c) { return $c.Source } }
    foreach ($h in $hints) { if (Test-Path $h) { return (Resolve-Path $h).Path } }
    return $null
}

$interpreters = @(
    @{ Name = 'Lua 5.4'; Exe = Find-Exe @('lua54', 'lua5.4', 'lua') @("$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe") },
    @{ Name = 'LuaJIT';  Exe = Find-Exe @('luajit') @("$env:LOCALAPPDATA\Programs\LuaJIT\bin\luajit.exe") }
)

$overall = 0
foreach ($i in $interpreters) {
    Write-Host ("=== {0}: {1}" -f $i.Name, ($(if ($i.Exe) { $i.Exe } else { 'NOT FOUND' })))
    if (-not $i.Exe) {
        if (-not $AllowMissing) { $overall = 1 }
        continue
    }
    $args = @((Join-Path $CoreRoot 'tests\run.lua'), $CoreRoot)
    if ($Filter) { $args += $Filter }
    & $i.Exe @args
    $code = $LASTEXITCODE
    Write-Host ("=== {0} exit code {1}" -f $i.Name, $code)
    if ($code -ne 0) { $overall = 1 }
    # Host-level harnesses: real adapters against deterministic doubles. Discovered rather than hardcoded, so
    # a new tools/test-*.lua joins the gate by existing.
    if (-not $Filter -and (Test-Path (Join-Path (Split-Path $CoreRoot -Parent) 'online/resources'))) {
        foreach ($h in Get-ChildItem $here -Filter 'test-*.lua' | Sort-Object Name) {
            & $i.Exe $h.FullName (Split-Path $here -Parent)
            if ($LASTEXITCODE -ne 0) { $overall = 1; Write-Host ("  HARNESS FAILED: {0}" -f $h.Name) }
        }
    }
}
# Syntax gate over every resource file, client Lua included: the stub never executes client code, and an unfinished
# string in client/race.lua reached staging on 2026-09-21 (resource activation failed, every join dropped).
$luac = Find-Exe @('luac54', 'luac5.4', 'luac') @("$env:LOCALAPPDATA\Programs\Lua\bin\luac.exe")
$resRoot = Join-Path (Split-Path $CoreRoot -Parent) 'online\resources'
if ($luac -and (Test-Path $resRoot)) {
    $bad = 0; $n = 0
    foreach ($f in Get-ChildItem $resRoot -Recurse -Filter *.lua) {
        if ($f.Name -eq 'open77.lua') { continue }   # resource manifests are a declaration DSL, not Lua
        $n++
        & $luac -p $f.FullName 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $bad++; Write-Host ("  SYNTAX {0}" -f $f.FullName); & $luac -p $f.FullName }
    }
    Write-Host ("=== luac -p over {0} resource file(s): {1} bad" -f $n, $bad)
    if ($bad -ne 0) { $overall = 1 }
} else {
    Write-Host '=== luac not found: resource syntax gate skipped'
    if (-not $AllowMissing) { $overall = 1 }
}
# Inline WebUI JavaScript. `panel.html` carries ~21 KB of it and NOTHING checked it until 2026-09-22: a render
# fault there is invisible to luac, shows up as a blank panel, and (before KB-61) could soft-lock the player out
# of their own game. A syntax gate is not a render test, but it is the cheap half and it was simply missing.
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node -and (Test-Path $resRoot)) {
    $jsBad = 0; $jsN = 0
    foreach ($f in Get-ChildItem $resRoot -Recurse -Filter *.js) {
        $jsN++
        $out = & node --check $f.FullName 2>&1
        if ($LASTEXITCODE -ne 0) { $jsBad++; Write-Host ("  JS SYNTAX {0}" -f $f.FullName); $out | Select-Object -First 5 }
    }
    foreach ($f in Get-ChildItem $resRoot -Recurse -Include *.html) {
        $html = Get-Content $f.FullName -Raw
        $blocks = [regex]::Matches($html, '(?s)<script>(.*?)</script>')
        foreach ($b in $blocks) {
            $jsN++
            $tmp = Join-Path $env:TEMP ("ncm-js-check-{0}.js" -f [guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($tmp, $b.Groups[1].Value)
            $out = & node --check $tmp 2>&1
            if ($LASTEXITCODE -ne 0) { $jsBad++; Write-Host ("  JS SYNTAX {0}" -f $f.FullName); $out | Select-Object -First 5 }
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }
    Write-Host ("=== node --check over {0} inline script block(s): {1} bad" -f $jsN, $jsBad)
    if ($jsBad -ne 0) { $overall = 1 }

    # Syntax is not the risk. `guard()` in panel.html emits `panel:drawn` only if the render does NOT throw,
    # and a missing `panel:drawn` is the KB-61 close -- a panel that never draws, on a live server, with no
    # error anywhere. This runs the real render against the payload shapes guide.lua can actually send
    # (car/regs/weather present, absent, null, empty-table-as-[]), and asserts on content as well as survival.
    $renderCheck = Join-Path $here 'panel-render-check.js'
    $webRoot = Join-Path $here (Join-Path '..' 'ncm/online/resources/ncm_world/web')
    if ((Test-Path $renderCheck) -and (Test-Path $webRoot)) {
        $rc = & node $renderCheck $webRoot 2>&1
        $summary = $rc | Select-String -Pattern 'panel render:' | Select-Object -Last 1
        if ($LASTEXITCODE -ne 0) {
            $overall = 1
            Write-Host '=== panel render check FAILED'
            $rc | Select-String -Pattern 'FAIL' | Select-Object -First 12 | ForEach-Object { Write-Host ("  {0}" -f $_) }
        } else {
            $passes = ($rc | Select-String -Pattern '  PASS ').Count
            Write-Host ("=== panel render check: {0} assertion(s), 0 bad" -f $passes)
        }
    }
    $nameplateCheck = Join-Path $here 'nameplate-render-check.js'
    if ((Test-Path $nameplateCheck) -and (Test-Path $webRoot)) {
        $nc = & node $nameplateCheck $webRoot 2>&1
        $summary = $nc | Select-String -Pattern 'nameplate render:' | Select-Object -Last 1
        if ($LASTEXITCODE -ne 0) {
            $overall = 1
            Write-Host '=== nameplate render check FAILED'
            $nc | Select-String -Pattern 'FAIL' | Select-Object -First 12 | ForEach-Object { Write-Host ("  {0}" -f $_) }
        } else {
            $passes = ($nc | Select-String -Pattern '  PASS ').Count
            Write-Host ("=== nameplate render check: {0} assertion(s), 0 bad" -f $passes)
        }
    }

    # The RACE HUD. Added 2026-09-26 with `L159`: this page had no guard and no harness at all, and it
    # carries the lights, strip, board, graph, odometer, driver inputs and the tyre gauge. A throw inside
    # its render took every one of them, silently -- no log line, no error event, and no soft-lock to make
    # it obvious, because the race HUD never takes focus.
    $raceCheck = Join-Path $here 'race-render-check.js'
    if ((Test-Path $raceCheck) -and (Test-Path $webRoot)) {
        $rc = & node $raceCheck $webRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            $overall = 1
            Write-Host '=== race render check FAILED'
            $rc | Select-String -Pattern 'FAIL' | Select-Object -First 12 | ForEach-Object { Write-Host ("  {0}" -f $_) }
        } else {
            $rc | Select-String -Pattern '=== race render check:' | Select-Object -Last 1 | ForEach-Object { Write-Host ("{0}" -f $_) }
        }
    }

    # The SHARED NAVIGATION LAYER (web/ncm-nav.js). This is the file that decides whether a player holding a
    # controller can use NCM at all, and nearly all of it is rectangle geometry and focus state -- wrong in
    # ways `node --check` cannot see. The harness stubs real getBoundingClientRect values and drives the
    # layer the way Lua and the keyboard do. It caught one genuine bug on its first run: a bare half-plane
    # test treated a control 700 px BELOW as "to the right", which is how a player loses their place.
    $navCheck = Join-Path $here 'nav-render-check.js'
    if ((Test-Path $navCheck) -and (Test-Path $webRoot)) {
        $vc = & node $navCheck $webRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            $overall = 1
            Write-Host '=== nav render check FAILED'
            $vc | Select-String -Pattern 'FAIL' | Select-Object -First 12 | ForEach-Object { Write-Host ("  {0}" -f $_) }
        } else {
            $passes = ($vc | Select-String -Pattern '  PASS ').Count
            Write-Host ("=== nav render check: {0} assertion(s), 0 bad" -f $passes)
        }
    }
} else {
    Write-Host '=== node not found: inline JavaScript gate skipped'
}
# Documentation authority (L125). Not a style check: it asserts that a reader can always tell WHICH
# documents claim to be current, and that navigation to them works. Without this the scheme decays in a
# few sessions -- which is exactly how superseded TW2 material came to sit beside current architecture.
$docsCheck = Join-Path $here 'check-docs-authority.py'
$docsRoot = Join-Path $here (Join-Path '..' 'docs/ncm-online')
if ((Test-Path $docsCheck) -and (Test-Path $docsRoot)) {
    $py = Find-Exe @('python', 'python3') @()
    if ($py) {
        $dc = & $py $docsCheck $docsRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            $overall = 1
            Write-Host '=== docs authority FAILED'
            $dc | Select-Object -First 15 | ForEach-Object { Write-Host ("  {0}" -f $_) }
        } else {
            Write-Host ("=== {0}" -f ($dc | Select-Object -Last 1))
        }
    } else {
        Write-Host '=== python not found: docs authority gate skipped'
    }
}

if ($overall -eq 0) { Write-Host 'ncm-test: ALL GREEN under every interpreter' } else { Write-Host 'ncm-test: FAILED' }
exit $overall
