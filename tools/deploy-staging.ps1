<#
.SYNOPSIS
  Deploy NCM Online resources to the staging server (AWS Lightsail, Ubuntu) and restart it.

.DESCRIPTION
  Syncs ncm/online/resources/** to /opt/ncm/resources/ncm (linked into the server's resource tree),
  applies the staging config touches (database bridge on, "ncm/*" in resources.load), optionally
  uploads required-mod packages, restarts the systemd unit and prints the startup lines that matter.
  Deploy between sessions: a resource restart can kick connected clients (KNOWN_BUGS KB-5).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1 -Mods
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-staging.ps1 -NoRestart
#>
[CmdletBinding()]
param(
    [string]$HostName = '52.60.225.137',
    [string]$User = 'ubuntu',
    [string]$Key = (Join-Path $env:USERPROFILE '.ssh\lightsail-ncm.pem'),
    [switch]$Mods,          # also upload %LOCALAPPDATA%\NCM\mods\*.zip to /opt/ncm/mods (import them in Warden)
    [switch]$NoRestart,
    [switch]$Logs,          # only tail the remote log
    # Which world this command is aimed at. TODAY there is only one, so 'online' remains the default and
    # nothing about the current workflow changes. Once the Windows development server is running, the default
    # flips to 'dev' and reaching the official world becomes a deliberate act -- see
    # docs/ncm-online/16_ENVIRONMENTS.md. Named now so the habit and the banner exist before the split.
    [ValidateSet('online','dev')][string]$Target = 'online'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# Say out loud which world is about to change. The failure this guards against is not a wrong command; it is
# the right command typed in the wrong terminal.
if ($Target -eq 'dev') {
    Write-Host '  == TARGET: NCM DEVELOPMENT (local Windows server) ==' -ForegroundColor Cyan
    Write-Host '  Use tools\o77-server.ps1. The resources junction means local edits are already live,'
    Write-Host '  so there is nothing to upload. Stopping here: this path can never reach the official world.'
    exit 0
}
Write-Host ''
Write-Host '  ############################################################' -ForegroundColor Yellow
Write-Host ('  #  TARGET: NCM ONLINE  ({0})' -f $HostName)                  -ForegroundColor Yellow
Write-Host '  #  The persistent world players inhabit.'                     -ForegroundColor Yellow
Write-Host '  #  Its database is canonical: deployment never overwrites'    -ForegroundColor Yellow
Write-Host '  #  it, only forward migrations touch it.'                     -ForegroundColor Yellow
Write-Host '  ############################################################' -ForegroundColor Yellow
Write-Host ''

# The remote command travels base64-encoded in argv, so quotes, pipes and encodings survive PowerShell 5.1 + ssh.exe.
function Remote([string]$cmd) { $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd)); & ssh -i $Key -o StrictHostKeyChecking=accept-new "$User@$HostName" "echo $b64 | base64 -d | bash" }
$tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'   # bsdtar: understands Windows drive letters

if ($Logs) { Remote 'tail -n 60 /opt/ncm/logs/server.log'; exit 0 }

Write-Host "== ncm-build (vendor core into resources)"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\ncm-build.ps1') | Select-Object -Last 1

Write-Host "== sync resources -> /opt/ncm/resources/ncm"
$src = Join-Path $repo 'ncm\online\resources'
$tar = Join-Path $env:TEMP 'ncm-resources.tar.gz'
if (Test-Path $tar) { Remove-Item $tar -Force }
& $tarExe -czf $tar -C $src .
& scp -q -i $Key $tar "$User@${HostName}:/tmp/ncm-resources.tar.gz"
Remote 'rm -rf /opt/ncm/resources/ncm.new && mkdir -p /opt/ncm/resources/ncm.new && tar -xzf /tmp/ncm-resources.tar.gz -C /opt/ncm/resources/ncm.new && rm -rf /opt/ncm/resources/ncm && mv /opt/ncm/resources/ncm.new /opt/ncm/resources/ncm && ln -sfn /opt/ncm/resources/ncm /opt/ncm/server/resources/ncm && ls /opt/ncm/resources/ncm'

Write-Host "== config touches (database on, ncm/* loaded)"
$py = @'
import re, json
p = "/opt/ncm/server/server.jsonc"; s = open(p).read(); orig = s
s = re.sub(r'("database"\s*:\s*\{\s*"enabled"\s*:\s*)false', r'\1true', s, count=1)
if '"ncm/*"' not in s:
    s = re.sub(r'("load"\s*:\s*\[)', r'\1\n      "ncm/*",', s, count=1)
if s != orig:
    open(p, "w").write(s); print("server.jsonc updated")
else:
    print("server.jsonc unchanged")
'@
$pyPath = Join-Path $env:TEMP 'ncm-staging-config.py'
Set-Content -Path $pyPath -Value $py -Encoding ASCII
& scp -q -i $Key $pyPath "$User@${HostName}:/tmp/ncm-staging-config.py"
Remote 'python3 /tmp/ncm-staging-config.py'

if ($Mods) {
    Write-Host "== upload mod packages -> /opt/ncm/mods (import them in Warden -> Required mods)"
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'NCM\mods\*.zip') | ForEach-Object {
        & scp -q -i $Key $_.FullName "$User@${HostName}:/opt/ncm/mods/"
        Write-Host "  uploaded $($_.Name)"
    }
}

if (-not $NoRestart) {
    Write-Host "== restart"
    Remote 'sudo systemctl restart ncm-server; sleep 12; systemctl is-active ncm-server; grep -n -i "Required mods\|Registered server\|migration\|scheduler started\|race control\|ERR\|script error\|resource start failed" /opt/ncm/logs/server.log | tail -12 | cut -c1-180'
}
