<#
.SYNOPSIS
  Build the NCM Host plugin (ncm/host_native: Lua 5.4 + SQLite in a RED4ext DLL), stage it with the NCM host Lua and
  the NCM resources (unchanged), and run the native self-test against the staged folder (L338, KB-385).

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-host-native.ps1
  Output: dist/ncm-host-native/  (red4ext/plugins/ncm_host/... + r6/scripts/ncm_host/NcmHostNatives.reds)
  The self-test must pass or the script fails. Nothing is installed by this script.
#>
[CmdletBinding(PositionalBinding = $false)]
param([string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src = Join-Path $repo 'ncm\host_native'
if (-not (Test-Path (Join-Path $src 'third_party\lua\src\lua.h'))) { & (Join-Path $src 'fetch-deps.ps1') }

& cmake --preset release -S $src | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }
& cmake --build (Join-Path $src 'build') --config $Configuration | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'cmake build failed' }

$stage = Join-Path $repo 'dist\ncm-host-native'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$plugin = Join-Path $stage 'red4ext\plugins\ncm_host'
New-Item -ItemType Directory -Force $plugin, (Join-Path $plugin 'save'), (Join-Path $stage 'r6\scripts\ncm_host') | Out-Null
Copy-Item (Join-Path $src "build\$Configuration\ncm_host.dll") $plugin
# L340: the natives + the runtime, HUD line and menu front door (no CET)
Copy-Item (Join-Path $src 'r6\scripts\ncm_host\*.reds') (Join-Path $stage 'r6\scripts\ncm_host\')
Set-Content (Join-Path $plugin 'save\.keep') '' -Encoding ascii

# the host Lua the plugin runs (the CET-only files -- init.lua, ui/, game/, driver_cet, driver_ffi, isolate -- are not needed)
$hostSrc = Join-Path $repo 'ncm\host'
foreach ($f in @('native.lua', 'app.lua', 'runtime.lua', 'clock.lua', 'tapes.lua', 'api\headless.lua', 'webui\init.lua', 'sql\translate.lua',
        'sql\schema.lua', 'sql\mysql.lua', 'sql\driver_native.lua')) {
    $dst = Join-Path $plugin "host\$f"
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    Copy-Item (Join-Path $hostSrc $f) $dst
}
# the NCM resources, as the dev server runs them: ONE list, ncm/host/app.lua App.RESOURCES (read here, never copied);
# no CEF pages: web/ stays behind (L370: every screen is ink)
$appLua = Get-Content -Raw (Join-Path $repo 'ncm\host\app.lua')
if ($appLua -notmatch 'App\.RESOURCES\s*=\s*\{([^}]*)\}') { throw 'App.RESOURCES not found in ncm/host/app.lua' }
$resources = @([regex]::Matches($Matches[1], '"([a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value })
if ($resources.Count -lt 1) { throw 'App.RESOURCES is empty' }
foreach ($r in $resources) {
    $from = Join-Path $repo "ncm\online\resources\$r"
    Get-ChildItem -LiteralPath $from -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($from.Length).TrimStart('\')
        if ($rel -like 'web\*') { return }
        $dst = Join-Path $plugin "resources\$r\$rel"
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $dst
    }
}

Write-Host 'self-test (the plugin VM, the staged host and resources, no game):'
$log = Join-Path $src 'build\selftest.log'
$exe = Join-Path $src "build\$Configuration\ncm_host_selftest.exe"
$p = Start-Process -FilePath $exe -ArgumentList ('"' + ($plugin -replace '\\', '/') + '"') -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError (Join-Path $src 'build\selftest.stderr.log')
$code = $p.ExitCode
Get-Content $log | Where-Object { $_ -match 'PASS|FAIL|selftest:' } | ForEach-Object { Write-Host ('  ' + $_.Substring(0, [Math]::Min(160, $_.Length))) }
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $plugin 'save\ncm_tapes.selftest.json'), (Join-Path $plugin 'save\ncm_tapes.selftest.json.bak')
if ($code -ne 0) { throw "ncm_host self-test FAILED ($code)" }
$n = (Get-ChildItem $stage -Recurse -File).Count
Write-Host ("build-host-native: staged {0} file(s) at {1}; self-test PASS" -f $n, $stage)
