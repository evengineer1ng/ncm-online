<#
.SYNOPSIS
  Pin the local development database to MariaDB 10.11.14 -- the exact version NCM Online runs
  on Lightsail (10.11.14-MariaDB-0ubuntu0.24.04.1, verified over SSH 2026-09-23).

.WHY THIS EXISTS
  The Windows box became the place where changes are instrumented BEFORE they reach the live
  world. That only works if the two sides behave the same. The box had MariaDB 13.0 (from
  winget, which has no 10.11 build) -- three major versions ahead of production.

  The danger is directional. A newer engine ACCEPTS syntax an older one rejects, so the dev
  box would go green and production would still break. False greens flow downhill into the
  canonical world; false reds do not. That asymmetry is the whole argument for pinning.

.WHAT IT DOES
  1. Refuses to start without a verified dump of the current dev database.
  2. Uninstalls MariaDB 13.0, KEEPING its data directory as a second safety net.
  3. Installs the checksum-verified MariaDB 10.11.14 MSI.
  4. Restores the dump.
  5. Calls db-setup.ps1 -SkipInstall to recreate the ncm user/grants and re-store the
     connection string in DPAPI. No password is ever printed or written to disk.

  Production data is NEVER touched. This script only ever talks to 127.0.0.1.

.REQUIREMENTS
  Elevation (MSI install/uninstall). Run from an admin PowerShell, or let the caller launch
  it with -Verb RunAs.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\db-pin-1011.ps1 -MsiPath <path-to-verified-msi>
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\db-pin-1011.ps1 -MsiPath <...> -DumpPath <...>

.ROLLBACK
  The dump and the old MariaDB 13.0 data directory both survive. To go back:
  reinstall MariaDB 13.0 (winget install MariaDB.Server) and restore the dump.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$MsiPath,
    [string]$DumpPath,
    [string]$ExpectedSha256 = 'd56947403e28f1543ffdf41ddeda70e559a34e8f3f915093ad3e3b6cd8a54380',
    [string]$OldProductCode = '{240168B2-20AC-4648-98DB-A3D529878694}',
    [int]$Port = 3306,
    [string]$DbName = 'ncm'
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = { param($m) Write-Host ("[db-pin] " + $m) }

# --- 0. Preconditions -------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Not elevated. MSI install/uninstall needs administrator rights."
}

if (-not (Test-Path $MsiPath)) { throw "MSI not found: $MsiPath" }
$actual = (Get-FileHash $MsiPath -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $ExpectedSha256.ToLower()) {
    throw "MSI checksum mismatch.`n  expected $ExpectedSha256`n  actual   $actual`nRefusing to install."
}
& $log "MSI checksum verified (10.11.14)"

# A dump is not optional. Uninstalling the engine without one is how dev data dies quietly.
if (-not $DumpPath) {
    $bk = Join-Path $env:LOCALAPPDATA 'NCM\backups'
    $DumpPath = (Get-ChildItem $bk -Filter 'ncm-devdb-*.sql' -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $DumpPath -or -not (Test-Path $DumpPath)) {
    throw "No dump found. Take one first (mysqldump --databases $DbName) -- this script will not uninstall the engine without a restore path."
}
$dumpTables = (Select-String -Path $DumpPath -Pattern '^CREATE TABLE' -AllMatches).Count
if ($dumpTables -lt 1) { throw "Dump at $DumpPath contains no CREATE TABLE statements; refusing to proceed." }
& $log ("dump: {0} ({1} tables, {2:N0} bytes)" -f $DumpPath, $dumpTables, (Get-Item $DumpPath).Length)

# --- 1. Remove MariaDB 13.0, keeping its data directory ---------------------------------
$svc = Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') { & $log "stopping MariaDB service"; Stop-Service MariaDB -Force; Start-Sleep 3 }

$old = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
       Where-Object { $_.DisplayName -like 'MariaDB*' -and $_.DisplayVersion -like '13.*' } | Select-Object -First 1
if ($old) {
    & $log ("uninstalling {0} {1} (data directory kept)" -f $old.DisplayName, $old.DisplayVersion)
    # CLEANUPDATA=0 is the point: the old data dir stays as a second safety net beside the dump.
    $p = Start-Process msiexec.exe -ArgumentList @('/x', $OldProductCode, '/qn', '/norestart', 'CLEANUPDATA=0') -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Uninstall failed with exit code $($p.ExitCode)" }
    & $log "uninstall complete"
} else {
    & $log "no MariaDB 13.x found; skipping uninstall"
}

# --- 2. Install 10.11.14 -----------------------------------------------------------------
# The root password is read from DPAPI and handed to the MSI the same way db-setup.ps1 did
# originally (briefly visible to local processes; everything after this is env-var only).
$store = Join-Path $env:LOCALAPPDATA 'NCM\secrets'
$secure = (Get-Content -LiteralPath (Join-Path $store 'db-root.dpapi') -Raw).Trim() | ConvertTo-SecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $rootPw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

& $log "installing MariaDB 10.11.14"
$args = @('/i', "`"$MsiPath`"", '/qn', '/norestart', "PASSWORD=$rootPw", 'SERVICENAME=MariaDB', "PORT=$Port", 'UTF8=1')
$p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Install failed with exit code $($p.ExitCode)" }

$deadline = (Get-Date).AddMinutes(3)
do {
    Start-Sleep 2
    $svc = Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') { try { Start-Service MariaDB } catch {} }
} while ((-not $svc -or $svc.Status -ne 'Running') -and (Get-Date) -lt $deadline)
if (-not $svc -or $svc.Status -ne 'Running') { throw 'MariaDB service did not start' }

$client = Get-ChildItem 'C:\Program Files\MariaDB 10.11\bin' -Include mariadb.exe, mysql.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $client) { throw 'MariaDB 10.11 client not found' }
& $log ("client: " + $client.FullName)

# --- 3. Restore the dump -----------------------------------------------------------------
& $log "restoring dump"
try {
    $env:MYSQL_PWD = $rootPw
    & $client.FullName -h 127.0.0.1 -P $Port -u root --protocol=tcp -e "source $DumpPath"
    if ($LASTEXITCODE -ne 0) { throw "restore failed (exit $LASTEXITCODE)" }
    & $log "restore complete"
    & $client.FullName -h 127.0.0.1 -P $Port -u root --protocol=tcp -e "SELECT VERSION() AS version; SELECT COUNT(*) AS tables_restored FROM information_schema.tables WHERE table_schema='$DbName'; SELECT version, name FROM $DbName.schema_migrations ORDER BY version;"
} finally {
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
}

# --- 4. Recreate the ncm user and re-store the connection string -------------------------
& $log "recreating ncm user/grants via db-setup.ps1 -SkipInstall"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'db-setup.ps1') -SkipInstall -DbName $DbName -Port $Port
if ($LASTEXITCODE -ne 0) { throw "db-setup.ps1 failed (exit $LASTEXITCODE)" }

& $log "DONE -- local development database is pinned to the production engine version."
& $log "Dump kept at: $DumpPath"
& $log "Old MariaDB 13.0 data directory kept at: C:\Program Files\MariaDB 13.0\data"
