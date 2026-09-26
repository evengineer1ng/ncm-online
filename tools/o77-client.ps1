<#
.SYNOPSIS
  Start an additional OPEN//77 game client on this PC under its OWN identity profile, joining the same
  world the launcher last joined.

.DESCRIPTION
  **This script used to pass `OP77_WORLD_SERVER=-` and `OP77_WORLD_MODS_DIGEST=-`.** It was written on
  2026-09-19 by reading one line out of `launcher.log`, and those two placeholders were guesses that were
  never revisited. The launcher passes real values for both, every time:

      OP77_CONNECT=52.60.225.137:11778  OP77_CONNECT_MASTER=alpha
      OP77_WORLD_SERVER=6b154fdc-d515-4903-97dd-df37cb966151
      OP77_WORLD_MODS_DIGEST=82ede6a3a860...

  `OP77_WORLD_SERVER` is the world id the launcher keys its **mod profile** on
  (`launcher-settings.json` -> `activeProfile: "world:<id>"`), and `OP77_WORLD_MODS_DIGEST` is the server's
  required-mods digest, which the client uses to decide whether its mod stack matches the world it is
  joining. A client told `-` for both is telling the plugin it is joining no known world with no known mod
  stack. `KB-4` -- "a second instance creates every WebUI surface but none is ever imported" -- was
  recorded against a client launched exactly that way and has never been retested with correct values.

  The digest is resolved live from the server's public manifest because it **changes on every carrier
  publish** (twice on 2026-09-26 alone), so hard-coding it guarantees a stale value within a day.

  **This script cannot apply a mod stack.** The launcher owns that: it downloads required mods, swaps mod
  profiles and quarantines the Solo profile's files (E0 note 6, 223 files). So client 1 must have been
  launched through the launcher into this world at least once, and must not be mid-update. This script
  starts a second process against the mod stack already on disk.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-client.ps1 -Profile ncm-tester2 -Name ncmtester2

  Defaults follow the launcher's own last successful launch. Override any of:
    -Server 127.0.0.1:11778   -Master alpha   -WorldId <guid>   -ModsDigest <sha256>
    -SkipDigest               join with no digest (the OLD behaviour; for A/B only)
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [string]$Name,
    [string]$Server,
    [string]$Master,
    [string]$WorldId,
    [string]$ModsDigest,
    [string]$ManifestUrl = 'https://52-60-225-137.sslip.io:11779/mods/v1/manifest',
    [switch]$SkipDigest,
    [string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
)
$ErrorActionPreference = 'Stop'
if ($Profile -notmatch '^[a-z0-9][a-z0-9\-_]{1,31}$') { throw 'Profile: lowercase letters, digits, - or _' }
$exe = Join-Path $GameDir 'bin\x64\Cyberpunk2077.exe'
if (-not (Test-Path $exe)) { throw "Game not found: $exe" }

# ---------------------------------------------------------------------------------------------------
# Defaults are read from the launcher's own state, not hard-coded. "What the launcher last did" is the
# only definition of correct here, and it is the definition this script claimed to follow but did not.
# ---------------------------------------------------------------------------------------------------
$settingsPath = Join-Path $env:LOCALAPPDATA 'Open77\launcher-settings.json'
$logPath = Join-Path $env:LOCALAPPDATA 'Open77\launcher.log'

if (-not $WorldId -or -not $Master) {
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if (-not $Master -and $settings.master) { $Master = $settings.master }
        if (-not $WorldId -and $settings.activeProfile -and $settings.activeProfile -match '^world:(.+)$') {
            $WorldId = $Matches[1]
            $worldName = $null
            if ($settings.worlds -and $settings.worlds.$WorldId) { $worldName = $settings.worlds.$WorldId.name }
            Write-Host ("world from launcher settings: {0}{1}" -f $WorldId,
                $(if ($worldName) { " ($worldName)" } else { '' }))
        }
    }
}
if (-not $Master) { $Master = 'alpha' }

# The launcher log records the endpoint it last launched into. Preferring it over a hard-coded localhost
# default is what stops this script quietly sending a second client to the dev server while client 1 is on
# Production -- two clients in different worlds look exactly like a broken client.
if (-not $Server -and (Test-Path $logPath)) {
    $line = Select-String -Path $logPath -Pattern 'launched pid .*OP77_CONNECT=(\S+)' |
        Select-Object -Last 1
    if ($line -and $line.Matches[0].Groups[1].Value) {
        $Server = $line.Matches[0].Groups[1].Value
        Write-Host ("server from the launcher's last launch: {0}" -f $Server)
    }
}
if (-not $Server) { $Server = '127.0.0.1:11778' }

# ---------------------------------------------------------------------------------------------------
# The digest. Live, because it changes whenever the carrier is republished.
# ---------------------------------------------------------------------------------------------------
if (-not $SkipDigest -and -not $ModsDigest) {
    try {
        $manifest = Invoke-RestMethod -Uri $ManifestUrl -TimeoutSec 20
        if ($manifest.digest) {
            $ModsDigest = $manifest.digest
            Write-Host ("mods digest from {0}: {1}" -f $ManifestUrl, $ModsDigest)
            if ($manifest.note) { Write-Host ("  declared: {0}" -f $manifest.note) }
        }
    } catch {
        Write-Host ("WARNING: could not read the mods manifest ({0})." -f $_.Exception.Message)
    }
}

# Refuse rather than repeat the old placeholder. A client that silently joins with no world and no digest
# is the configuration KB-4 was measured against, and passing `-` here is how that went unnoticed for a
# week. `-SkipDigest` still allows it, deliberately and loudly, because A/B-ing the two is the experiment.
if (-not $SkipDigest) {
    if (-not $WorldId) {
        throw "No world id. Launch client 1 through the launcher into the target world first, or pass -WorldId."
    }
    if (-not $ModsDigest) {
        throw "No mods digest. Pass -ModsDigest <sha256>, or -SkipDigest to reproduce the old (KB-4) launch."
    }
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.WorkingDirectory = Split-Path -Parent $exe
$psi.UseShellExecute = $false
$psi.Environment['OP77_CONNECT'] = $Server
$psi.Environment['OP77_CONNECT_MASTER'] = $Master
$psi.Environment['OP77_WORLD_SERVER'] = $(if ($WorldId) { $WorldId } else { '-' })
$psi.Environment['OP77_WORLD_MODS_DIGEST'] = $(if ($ModsDigest) { $ModsDigest } else { '-' })
# Steam: without these the exe hands off to Steam and is relaunched WITHOUT our environment
# (observed 2026-09-19: client booted to the vanilla menu with no connect target).
$psi.Environment['SteamAppId'] = '1091500'
$psi.Environment['SteamGameId'] = '1091500'
$psi.Environment['OP77_IDENTITY_PROFILE'] = $Profile
if ($Name) { $psi.Environment['OP77_PLAYER_NAME'] = $Name }

Write-Host ''
Write-Host ("Launching client: profile={0} name={1}" -f $Profile, ($(if ($Name) { $Name } else { '<profile default>' })))
Write-Host ("  OP77_CONNECT            = {0}" -f $psi.Environment['OP77_CONNECT'])
Write-Host ("  OP77_CONNECT_MASTER     = {0}" -f $psi.Environment['OP77_CONNECT_MASTER'])
Write-Host ("  OP77_WORLD_SERVER       = {0}" -f $psi.Environment['OP77_WORLD_SERVER'])
Write-Host ("  OP77_WORLD_MODS_DIGEST  = {0}" -f $psi.Environment['OP77_WORLD_MODS_DIGEST'])
Write-Host ''
Write-Host 'Expect 60-150 s before the window appears. Cross the "press any key to continue" screen yourself.'

$before = (Get-ChildItem (Join-Path $GameDir 'red4ext\logs') -Filter 'open77-*.log' -ErrorAction SilentlyContinue).Name
$p = [System.Diagnostics.Process]::Start($psi)
Write-Host ("pid {0}" -f $p.Id)
Start-Sleep -Seconds 25
if ($p.HasExited) {
    Write-Host ("WARNING: pid {0} exited after 25s (Steam relaunch?). Cyberpunk processes now:" -f $p.Id)
} else {
    Write-Host ("pid {0} still running after 25s (good: no Steam relaunch)." -f $p.Id)
}
Get-CimInstance Win32_Process -Filter "Name='Cyberpunk2077.exe'" | Select-Object ProcessId, ParentProcessId, CreationDate | Format-Table -AutoSize

# ---------------------------------------------------------------------------------------------------
# The KB-4 measurement, taken automatically instead of being assumed.
# ---------------------------------------------------------------------------------------------------
# KB-4's evidence was a count: client 1 logged 18 `WebUI surface ... imported`, client 2 logged 0. That is
# a good measurement and it should not have to be repeated by hand. This prints the same number for the
# instance just launched, so the question "does a correctly-launched second client render UI" is answered
# by running the script rather than by argument.
Write-Host ''
Write-Host 'Waiting 90 s for this instance to write its client log, then counting imported WebUI surfaces...'
Start-Sleep -Seconds 90
$after = Get-ChildItem (Join-Path $GameDir 'red4ext\logs') -Filter 'open77-*.log' -ErrorAction SilentlyContinue |
    Where-Object { $before -notcontains $_.Name } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $after) {
    Write-Host 'No new client log appeared. The instance may still be loading -- count manually:'
    Write-Host '  Select-String -Path "<gamedir>\red4ext\logs\open77-*.log" -Pattern "WebUI surface" | Measure-Object'
} else {
    $imported = (Select-String -Path $after.FullName -Pattern 'imported' -CaseSensitive:$false |
        Where-Object { $_.Line -match 'WebUI surface' } | Measure-Object).Count
    $created = (Select-String -Path $after.FullName -Pattern 'WebUI surface' | Measure-Object).Count
    Write-Host ("  log: {0}" -f $after.Name)
    Write-Host ("  WebUI surface lines: {0}; imported: {1}" -f $created, $imported)
    if ($imported -gt 0) {
        Write-Host '  -> This second client IS importing WebUI surfaces. KB-4 does not reproduce; update it.'
    } else {
        Write-Host '  -> 0 imported, as KB-4 recorded. The env fix alone is not the cause; keep the log and say so.'
    }
}
