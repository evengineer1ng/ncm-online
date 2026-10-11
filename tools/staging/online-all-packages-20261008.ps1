<#
  One-shot (2026-10-08): bring NCM Online to dev's full client stack and manual gearboxes.
    1. back up /opt/ncm/server/server.jsonc
    2. declare Carrier 0.1.38, Gearbox 0.3.2, Snowglobe 0.0.5, Thrust 0.0.2 (publish-carrier.py, --id per package)
    3. deploy-staging.ps1 -ThawOnline: the resources (gearbox.lua: manuals are manuals on online) and the restart
  Run only on the owner's go, with nobody on Online.
#>
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$key = Join-Path $env:USERPROFILE '.ssh\lightsail-ncm.pem'
$h = 'ubuntu@52.60.225.137'
$note = 'NCM Carrier 0.1.38 (handling, weather, parts), NCM Gearbox 0.3.2 (manual and stacked gearboxes), NCM Snowglobe 0.0.5 (altitude doorway), NCM Thrust 0.0.2 (flight thrust), NCM Rig Bridge 0.1.7 (wheel, pedals, force feedback), NCM Scanner 0.4.0 (scanner, quickhacks, pad LB hold), NCM Pace 0.9.2 (NPC racers), NCM Broadcast 0.1.0 (timing tower, nameplates), NCM Clock 0.1.0, ArchiveXL 1.27.1 and TweakXL 1.11.4'
$pkgs = @(
    @{ id = 'ncm-carrier';   name = 'NCM Carrier';   zip = 'ncm-carrier-0.1.38.zip';  ver = '0.1.38' },
    @{ id = 'ncm-gearbox';   name = 'NCM Gearbox';   zip = 'ncm-gearbox-0.3.2.zip';   ver = '0.3.2' },
    @{ id = 'ncm-snowglobe'; name = 'NCM Snowglobe'; zip = 'ncm-snowglobe-0.0.5.zip'; ver = '0.0.5' },
    @{ id = 'ncm-thrust';    name = 'NCM Thrust';    zip = 'ncm-thrust-0.0.2.zip';    ver = '0.0.2' }
)

$who = & ssh -i $key -o BatchMode=yes $h "grep -E 'connected: player=' /opt/ncm/logs/server.log | tail -4"
Write-Host "Last joins/leaves on Online:`n$($who -join "`n")"

$files = @($pkgs | ForEach-Object { Join-Path $repo "dist\$($_.zip)" }) + (Join-Path $repo 'tools\staging\publish-carrier.py')
& scp -i $key -o BatchMode=yes @files "${h}:/tmp/"
if ($LASTEXITCODE) { throw 'scp failed' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$remote = @("set -e -o pipefail", "cp /opt/ncm/server/server.jsonc /opt/ncm/server/server.jsonc.bak-$stamp")
foreach ($p in $pkgs) {
    $remote += "cp /tmp/$($p.zip) /opt/ncm/mods/"
    $remote += "python3 /tmp/publish-carrier.py /opt/ncm/server --id $($p.id) --display-name '$($p.name)' --zip /opt/ncm/mods/$($p.zip) --version $($p.ver) --import-blob --enable --note '$note' | tail -2"
}
$remote += "grep -E 'version' /opt/ncm/server/server.jsonc"
& ssh -i $key -o BatchMode=yes $h ($remote -join ' && ')
if ($LASTEXITCODE) { throw 'declaring the packages failed; server.jsonc backup: server.jsonc.bak-' + $stamp }

# resources + restart
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\deploy-staging.ps1') -Target online -ThawOnline
