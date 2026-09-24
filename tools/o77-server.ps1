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
