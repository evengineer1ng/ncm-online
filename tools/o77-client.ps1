<#
.SYNOPSIS
  Start an additional OPEN//77 game client on this PC under its OWN identity profile, connecting
  straight to the local NCM server. Mirrors what the launcher does (observed in launcher.log on
  2026-09-19) plus the identity-profile variables the client plugin honours.

  VRAM: ~4.2 GiB per in-world client. Two in-world clients is the practical ceiling on this PC.
  All instances share the save folder: run tools\o77-backup-saves.ps1 first.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-client.ps1 -Profile ncm-tester2 -Name ncmtester2
  Optional: -Server 127.0.0.1:11778  -Master alpha  -GameDir "<path to Cyberpunk 2077>"
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [string]$Name,
    [string]$Server = '127.0.0.1:11778',
    [string]$Master = 'alpha',
    [string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
)
$ErrorActionPreference = 'Stop'
if ($Profile -notmatch '^[a-z0-9][a-z0-9\-_]{1,31}$') { throw 'Profile: lowercase letters, digits, - or _' }
$exe = Join-Path $GameDir 'bin\x64\Cyberpunk2077.exe'
if (-not (Test-Path $exe)) { throw "Game not found: $exe" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.WorkingDirectory = Split-Path -Parent $exe
$psi.UseShellExecute = $false
$psi.Environment['OP77_CONNECT'] = $Server
$psi.Environment['OP77_CONNECT_MASTER'] = $Master
$psi.Environment['OP77_WORLD_SERVER'] = '-'
$psi.Environment['OP77_WORLD_MODS_DIGEST'] = '-'
# Steam: without these the exe hands off to Steam and is relaunched WITHOUT our environment
# (observed 2026-09-19: client booted to the vanilla menu with no connect target).
$psi.Environment['SteamAppId'] = '1091500'
$psi.Environment['SteamGameId'] = '1091500'
$psi.Environment['OP77_IDENTITY_PROFILE'] = $Profile
if ($Name) { $psi.Environment['OP77_PLAYER_NAME'] = $Name }

Write-Host ("Launching client: profile={0} name={1} -> {2} (master {3})" -f $Profile, ($(if ($Name) { $Name } else { '<profile default>' })), $Server, $Master)
Write-Host 'Expect 60-150 s before the window appears. Cross the "press any key to continue" screen yourself.'
$p = [System.Diagnostics.Process]::Start($psi)
Write-Host ("pid {0}" -f $p.Id)
Start-Sleep -Seconds 25
if ($p.HasExited) {
    Write-Host ("WARNING: pid {0} exited after {1}s (Steam relaunch?). Cyberpunk processes now:" -f $p.Id, 25)
} else {
    Write-Host ("pid {0} still running after 25s (good: no Steam relaunch)." -f $p.Id)
}
Get-CimInstance Win32_Process -Filter "Name='Cyberpunk2077.exe'" | Select-Object ProcessId, ParentProcessId, CreationDate | Format-Table -AutoSize
