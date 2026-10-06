<#
.SYNOPSIS
  Start the local OPEN//77 dedicated server (tools\open77\server) with the license key injected
  from the DPAPI secret store as OP77_LICENSE_KEY (and the MariaDB connection string as
  OP77_DATABASE_CONNECTION when stored), so server.jsonc never has to contain credentials.

  First run (no server.jsonc yet): Warden onboarding starts on http://127.0.0.1:11780 (local only, via OP77_WARDEN_SETUP_LISTEN).
  Open it in a browser, enter the one-time PIN printed in the console, choose the Freeroam template,
  set the server name/ports, create the Warden admin. Leave the license-key field empty if the
  form allows it (the environment variable is consulted when the file has none); otherwise enter it
  there too and we will remove it from the file afterwards.

  Also ensures the NCM resources are reachable by the server through a directory junction
  resources\ncm -> ncm\online\resources (no copying, no admin rights).

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-server.ps1            # start
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-server.ps1 -SetupOnly # onboarding, then exit
  Extra arguments after -- are passed to Open77.Server.exe.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SetupOnly,
    [string]$SecretName = 'open77-license',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Argv
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-Path (Join-Path $here '..')
$serverDir = Join-Path $root 'tools\open77\server'
$exe = Join-Path $serverDir 'Open77.Server.exe'
if (-not (Test-Path $exe)) { throw "Server not found at $exe (unpack the server package first)" }

# NCM resources junction.
$junction = Join-Path $serverDir 'resources\ncm'
$target = Join-Path $root 'ncm\online\resources'
if (-not (Test-Path $junction)) {
    cmd /c mklink /J "$junction" "$target" | Out-Null
    Write-Host "Created junction resources\ncm -> ncm\online\resources"
}
# Dev-only experiment probe (L301): OUTSIDE the ncm/* load glob so it can never reach Online; started only by its
# own explicit entry in this server's server.jsonc.
$probeJunction = Join-Path $serverDir 'resources\ncm_dev_probe'
$probeTarget = Join-Path $root 'prototypes\ncm_dev_probe'
if ((Test-Path $probeTarget) -and -not (Test-Path $probeJunction)) {
    cmd /c mklink /J "$probeJunction" "$probeTarget" | Out-Null
    Write-Host "Created junction resources\ncm_dev_probe -> prototypes\ncm_dev_probe"
}

$serverArgs = @()
if ($Argv) { $serverArgs = $Argv | Where-Object { $_ -ne '--' } }
$firstRun = -not (Test-Path (Join-Path $serverDir 'server.jsonc'))
if ($firstRun) {
    # Environment form of --setup-listen: the CLI flag was re-parsed as one token when the server
    # relaunched itself after setup (2026-09-19). The child inherits this variable.
    $env:OP77_WARDEN_SETUP_LISTEN = 'http://127.0.0.1:11780'
    Write-Host 'No server.jsonc yet: Warden onboarding will listen on http://127.0.0.1:11780 (local only).'
}

Write-Host ("Starting {0} {1}" -f $exe, ($serverArgs -join ' '))
Write-Host 'The server console is interactive (setup PIN, commands). Keep this window open; Ctrl+C stops it.'

# L327: the NCM host bridge (Assetto Corsa embodiment) runs beside the DEVELOPMENT server, loopback only. Started once;
# a second server start finds it already listening on 47710.
$bridge = Join-Path $here 'ncm-host-bridge.py'
if ((Test-Path $bridge) -and -not (Test-NetConnection -ComputerName 127.0.0.1 -Port 47710 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    Start-Process python -ArgumentList '-I', "`"$bridge`"" -WindowStyle Hidden
    Write-Host 'Started the NCM host bridge on 127.0.0.1:47710'
}

Push-Location $serverDir
try {
    $secretTool = Join-Path $here 'ncm-secret.ps1'
    $envMap = @{ 'OP77_LICENSE_KEY' = $SecretName }
    if (Test-Path (Join-Path $env:LOCALAPPDATA 'NCM\secrets\db-connection.dpapi')) {
        $envMap['OP77_DATABASE_CONNECTION'] = 'db-connection'   # MariaDB (M0.2); server.jsonc database.enabled decides use
    }
    & $secretTool -Run -Env $envMap -- $exe @serverArgs
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $code
