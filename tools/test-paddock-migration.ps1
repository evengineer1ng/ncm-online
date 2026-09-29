# Twice-applied dry-run for schemas 043-051 (the Paddock, doc 44 Â§14.1), plus the constraints that carry rules.
#
# Replay safety: MariaDB commits DDL implicitly, so a migration that is not idempotent wedges the runner the second
# time the server starts (see schema 019). Every statement here runs twice.
#
# Rules as constraints, asserted rather than trusted:
#   * the One-Team Rule: a second ACTIVE affiliation for one driver is refused by `ux_one_team` (doc 14 Â§3)
#   * the NPC circuit admits only the Manager role, and each circuit needs its own org (the CHECK)
#   * one active Paddock contract per person (`ux_paddock_contract_active`)
#
# Requires `NCM_DB_ROOT` and a local MariaDB 10.11. Without them the dry-run is OWED, not passed.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$database = 'ncm_paddock_043_050_check'
$client = Get-ChildItem 'C:\Program Files\MariaDB*\bin' -Include mariadb.exe, mysql.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $client) { throw 'MariaDB client not found' }
if (-not $env:NCM_DB_ROOT) { throw 'NCM_DB_ROOT was not injected' }

$env:MYSQL_PWD = $env:NCM_DB_ROOT
function Invoke-Sql([string]$sql, [switch]$NoDatabase) {
    # PowerShell 5.1 turns a native command's stderr into an ErrorRecord; under 'Stop' that throws before the
    # exit code (and MariaDB's own message) can be read. Judge by $LASTEXITCODE instead.
    $ErrorActionPreference = 'Continue'
    $a = @('-h', '127.0.0.1', '-P', '3306', '-u', 'root', '--protocol=tcp', '--batch', '--skip-column-names')
    if (-not $NoDatabase) { $a += $database }
    $a += @('-e', $sql)
    $out = & $client.FullName @a 2>&1
    if ($LASTEXITCODE -ne 0) { throw "MariaDB command failed (exit $LASTEXITCODE): $out" }
    return $out
}

$statements = @()
foreach ($n in '043_result_conditions', '044_organizations', '045_paddock_world', '046_team_affiliation',
        '047_paddock_racing', '048_paddock_story', '049_billie', '050_paddock_economy', '051_paddock_live') {
    $text = Get-Content -Raw "ncm\online\resources\ncm_league\server\schema\$n.lua"
    $found = [regex]::Matches($text, '(?s)\[\[(.*?)\]\]') | ForEach-Object { $_.Groups[1].Value }
    if ($found.Count -lt 1) { throw "no statements in $n" }
    $statements += $found
}

$bad = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "  PASS $what" } else { Write-Host "  FAIL $what"; $script:bad++ }
}
function Refused([string]$sql) {
    try { Invoke-Sql $sql | Out-Null; return $false } catch { return $true }
}

try {
    Invoke-Sql "DROP DATABASE IF EXISTS ``$database``; CREATE DATABASE ``$database`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" -NoDatabase | Out-Null

    # The prior shapes the ALTERs and foreign keys touch (001, 003, 004, 010, 034), reduced to what matters.
    Invoke-Sql @'
CREATE TABLE ncm_driver (ncm_driver_id CHAR(36) NOT NULL, origin ENUM('sp','online') NOT NULL, PRIMARY KEY (ncm_driver_id)) ENGINE=InnoDB;
CREATE TABLE entry (entry_id CHAR(36) NOT NULL, event_id VARCHAR(160) NOT NULL, ncm_driver_id CHAR(36) NOT NULL, PRIMARY KEY (entry_id)) ENGINE=InnoDB;
CREATE TABLE session_result (session_id CHAR(36) NOT NULL, ncm_driver_id CHAR(36) NOT NULL, position INT NOT NULL, PRIMARY KEY (session_id, ncm_driver_id)) ENGINE=InnoDB;
CREATE TABLE practice_run (id BIGINT NOT NULL AUTO_INCREMENT, server_id VARCHAR(96) NOT NULL, route_id VARCHAR(160) NOT NULL, run_ms INT NOT NULL, PRIMARY KEY (id)) ENGINE=InnoDB;
CREATE TABLE ghost_lap (ghost_id CHAR(36) NOT NULL, class_id VARCHAR(96) NULL, PRIMARY KEY (ghost_id)) ENGINE=InnoDB;
INSERT INTO ncm_driver VALUES ('d-1','online'), ('d-2','online');
'@ | Out-Null

    foreach ($pass in 1, 2) {
        Write-Host "=== pass $pass"
        foreach ($s in $statements) { Invoke-Sql $s | Out-Null }
        Check $true "all $($statements.Count) statements applied on pass $pass"
    }

    $cols = Invoke-Sql "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$database' AND TABLE_NAME='session_result' AND COLUMN_NAME IN ('weather','road_wetness','seconds_of_day','light','series_id','class_id','vehicle_class','conditions_source');"
    Check (([int]$cols) -eq 8) "043 adds eight condition columns to session_result once (found $cols)"

    Invoke-Sql "INSERT INTO team_affiliation (affiliation_id,server_id,ncm_driver_id,circuit,paddock_org_id,role,effective_from) VALUES ('a1','s','d-1','npc','o001','manager',1);" | Out-Null
    Check (Refused "INSERT INTO team_affiliation (affiliation_id,server_id,ncm_driver_id,circuit,organization_id,role,effective_from) VALUES ('a2','s','d-1','sanctioned','g1','driver',2);") "a second active affiliation is refused (One-Team Rule)"
    Invoke-Sql "UPDATE team_affiliation SET effective_to=5, end_reason='resigned' WHERE affiliation_id='a1';" | Out-Null
    Check (-not (Refused "INSERT INTO team_affiliation (affiliation_id,server_id,ncm_driver_id,circuit,organization_id,role,effective_from) VALUES ('a3','s','d-1','sanctioned','g1','driver',6);")) "after it ends, a new affiliation is allowed"
    Check (Refused "INSERT INTO team_affiliation (affiliation_id,server_id,ncm_driver_id,circuit,paddock_org_id,role,effective_from) VALUES ('a4','s','d-2','npc','o002','owner',1);") "the NPC circuit refuses any role but manager"
    Check (Refused "INSERT INTO team_affiliation (affiliation_id,server_id,ncm_driver_id,circuit,role,effective_from) VALUES ('a5','s','d-2','sanctioned','driver',1);") "a sanctioned affiliation needs an organization"

    Invoke-Sql "INSERT INTO paddock_contract (contract_id,server_id,person_id,org_id,wage,starts_season,ends_season,signed_at) VALUES ('c1','s','p00001','o001',100,0,1,1);" | Out-Null
    Check (Refused "INSERT INTO paddock_contract (contract_id,server_id,person_id,org_id,wage,starts_season,ends_season,signed_at) VALUES ('c2','s','p00001','o002',100,0,1,2);") "one active contract per person"
    Check (Refused "INSERT INTO paddock_slip (slip_id,idem_key,server_id,ncm_driver_id,race_id,line_id,market,subject_a,line_version,stake,price,potential,placed_at) VALUES ('x','k','s','nobody','r','l','win','p1',1,10,2.0,20,1);") "a slip needs a real driver"
}
finally {
    try { Invoke-Sql "DROP DATABASE IF EXISTS ``$database``;" -NoDatabase | Out-Null } catch {}
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
}

Write-Host "=== paddock migration dry-run: $bad bad"
exit $bad
