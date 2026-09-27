# Twice-applied dry-run for schema 034 (ghost_lap).
#
# **What this proves and why it is worth a harness.** A migration that is not replay-safe does not fail when it
# is written; it fails the second time the server starts, and by then the version row is missing and the runner
# is wedged. Schema 019 records the mechanism: MariaDB commits DDL implicitly, so if a later statement in a
# migration fails, the earlier ones have already landed while the version row has not -- and the next start
# replays the whole list onto a database that already has half of it.
#
# 034 has exactly the shape that breaks: one CREATE TABLE and one multi-column ALTER. `IF NOT EXISTS` on every
# clause is what makes the replay a no-op, and this asserts it rather than trusting it.
#
# Requires `NCM_DB_ROOT` in the environment and a local MariaDB. Both are the operator's to supply; without
# them the dry-run is OWED, not passed.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$database = 'ncm_ghost_034_check'
$client = Get-ChildItem 'C:\Program Files\MariaDB*\bin' -Include mariadb.exe, mysql.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $client) { throw 'MariaDB client not found' }
if (-not $env:NCM_DB_ROOT) { throw 'NCM_DB_ROOT was not injected' }

$env:MYSQL_PWD = $env:NCM_DB_ROOT
function Invoke-Sql([string]$sql, [switch]$NoDatabase) {
    $a = @('-h', '127.0.0.1', '-P', '3306', '-u', 'root', '--protocol=tcp', '--batch', '--skip-column-names')
    if (-not $NoDatabase) { $a += $database }
    $a += @('-e', $sql)
    $out = & $client.FullName @a
    if ($LASTEXITCODE -ne 0) { throw "MariaDB command failed (exit $LASTEXITCODE)" }
    return $out
}

# The statements under test, read from the migration itself rather than copied -- a copy would drift and then
# this harness would be proving something the server does not run.
$migration = Get-Content -Raw 'ncm\online\resources\ncm_league\server\schema\034_ghost_lap.lua'
$statements = [regex]::Matches($migration, '(?s)\[\[(.*?)\]\]') | ForEach-Object { $_.Groups[1].Value }
if ($statements.Count -lt 2) { throw "expected at least 2 statements in 034, found $($statements.Count)" }

$bad = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "  PASS $what" } else { Write-Host "  FAIL $what"; $script:bad++ }
}

try {
    Invoke-Sql "DROP DATABASE IF EXISTS ``$database``; CREATE DATABASE ``$database`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" -NoDatabase | Out-Null

    # `practice_run` as migration 010 left it, so the ALTER is applied to the real prior shape.
    Invoke-Sql @'
CREATE TABLE practice_run (
  id BIGINT NOT NULL AUTO_INCREMENT,
  server_id VARCHAR(96) NOT NULL,
  event_id VARCHAR(160) NOT NULL,
  route_id VARCHAR(160) NOT NULL,
  ncm_driver_id CHAR(36) NOT NULL,
  session_id CHAR(36) NULL,
  run_ms INT NOT NULL,
  incident_ms INT NOT NULL DEFAULT 0,
  incident_count INT NOT NULL DEFAULT 0,
  at BIGINT NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
'@ | Out-Null

    foreach ($pass in 1, 2) {
        Write-Host "=== pass $pass"
        foreach ($s in $statements) { Invoke-Sql $s | Out-Null }
        Check $true "every statement applied on pass $pass"
    }

    # The columns exist exactly once and the table is there.
    $cols = Invoke-Sql "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$database' AND TABLE_NAME='practice_run' AND COLUMN_NAME IN ('run_started_at','run_finished_at','ghost_id') ORDER BY COLUMN_NAME;"
    Check (($cols -join ',') -eq 'ghost_id,run_finished_at,run_started_at') "the three practice_run columns exist once: $($cols -join ',')"

    $ghostCols = (Invoke-Sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$database' AND TABLE_NAME='ghost_lap';") -as [int]
    # 26, counted against the live table after deploy 2026-09-27 rather than by reading the CREATE and hoping.
    Check ($ghostCols -eq 26) "ghost_lap has its 26 columns (found $ghostCols)"

    # The JSON_VALID constraint actually refuses. A CHECK that is declared but not enforced is worse than none,
    # because the column then carries a guarantee nothing is keeping.
    $rejected = $false
    try {
        Invoke-Sql "INSERT INTO ghost_lap (ghost_id,format,server_id,ncm_driver_id,route_id,run_started_at,run_finished_at,elapsed_ms,pose_count,pose_hz,poses_json,at) VALUES ('x',1,'s','d','r',1,2,1000,4,10,'not json',1);" | Out-Null
    } catch { $rejected = $true }
    Check $rejected "poses_json refuses a non-JSON body"

    $accepted = $true
    try {
        Invoke-Sql "INSERT INTO ghost_lap (ghost_id,format,server_id,ncm_driver_id,route_id,run_started_at,run_finished_at,elapsed_ms,pose_count,pose_hz,poses_json,at) VALUES ('y',1,'s','d','r',1,2,1000,4,10,'[[0,1,2,3,4]]',1);" | Out-Null
    } catch { $accepted = $false }
    Check $accepted "and accepts a real pose array"
}
finally {
    try { Invoke-Sql "DROP DATABASE IF EXISTS ``$database``;" -NoDatabase | Out-Null } catch {}
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
}

Write-Host "=== ghost migration dry-run: $bad bad"
exit $bad
