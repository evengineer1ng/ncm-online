<#
.SYNOPSIS
  NPC economy audit (L297): READ-ONLY queries against the NCM database that answer "when you see SOLD OUT, where did
  they go?" -- who bought every unit, what NPCs bought and why, where their money came from, where the parts are.

  The connection comes from the DPAPI secret `db-connection` (tools\db-setup.ps1). The password travels to the
  client in MYSQL_PWD for this process only and is never printed. The session is READ ONLY: any write would fail.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\npc-economy-audit.ps1 [-People p01290,p00210]
  Output: tools\open77\server\npc-economy-audit-<stamp>.txt
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string[]]$People = @('p01290', 'p00210', 'p01226', 'p01227'),
    [int]$Recent = 15
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$store = Join-Path $env:LOCALAPPDATA 'NCM\secrets'

function Read-Secret([string]$name) {
    $path = Join-Path $store "$name.dpapi"
    if (-not (Test-Path $path)) { throw "secret '$name' not found (run tools\db-setup.ps1)" }
    $secure = (Get-Content -LiteralPath $path -Raw).Trim() | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
function Part([string]$conn, [string]$key) {
    foreach ($kv in $conn -split ';') { $p = $kv -split '=', 2; if ($p.Count -eq 2 -and $p[0].Trim() -ieq $key) { return $p[1].Trim() } }
    return $null
}

$conn = Read-Secret 'db-connection'
$hostName = Part $conn 'Server'; if (-not $hostName) { $hostName = '127.0.0.1' }
$port = Part $conn 'Port'; if (-not $port) { $port = '3306' }
$db = Part $conn 'Database'; $user = Part $conn 'User ID'; if (-not $user) { $user = Part $conn 'Uid' }
$client = Get-ChildItem 'C:\Program Files\MariaDB*\bin' -Include mariadb.exe, mysql.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $client) { throw 'MariaDB client not found' }

foreach ($p in $People) { if ($p -notmatch '^p\d{3,6}$') { throw "bad person id: $p" } }
$peopleList = ($People | ForEach-Object { "'$_'" }) -join ','
$ts = 'FROM_UNIXTIME'

$sql = @"
SET SESSION TRANSACTION READ ONLY;
START TRANSACTION READ ONLY;

SELECT '== B. ENVIRONMENT (KB-281: SQL 1292)' AS section;
SELECT server_id, seed, season_id, FROM_UNIXTIME(created_at) AS created FROM paddock_world;
SELECT VERSION() AS version, @@SESSION.sql_mode AS sql_mode;
SHOW CREATE TABLE vehicle_asset;

SELECT '== A1. VEHICLE LINES: what each shelf holds and where its units went' AS section;
SELECT mi.market_id, a.vehicle_key, SUM(mi.state='available') AS available, SUM(mi.state='sold' AND mi.sold_to_driver_id IS NOT NULL) AS to_players,
  SUM(mi.state='sold' AND mi.sold_to_principal IS NOT NULL) AS to_npcs, SUM(mi.state='withdrawn') AS withdrawn, COUNT(*) AS ever_listed,
  $ts(MAX(mi.listed_at)) AS last_listed, $ts(MAX(mi.sold_at)) AS last_sold
FROM market_inventory mi JOIN vehicle_asset a ON a.asset_id = mi.asset_id
GROUP BY mi.market_id, a.vehicle_key ORDER BY mi.market_id, a.vehicle_key;

SELECT '== A2. EVERY SOLD VEHICLE UNIT: buyer, price, and where the car is now' AS section;
SELECT mi.market_id, a.vehicle_key, a.asset_id, a.model_ordinal, mi.price, $ts(mi.sold_at) AS sold_at,
  COALESCE(mi.sold_to_principal, CONCAT('driver:', LEFT(mi.sold_to_driver_id, 8))) AS bought_by,
  COALESCE(CONCAT(a.owner_principal_kind, ':', a.owner_principal_id), CONCAT('driver:', LEFT(a.ncm_driver_id, 8))) AS owner_now,
  a.odometer_m, a.lifecycle,
  (SELECT COUNT(*) FROM vehicle_asset_transfer t WHERE t.asset_id = a.asset_id) AS transfers
FROM market_inventory mi JOIN vehicle_asset a ON a.asset_id = mi.asset_id
WHERE mi.state = 'sold' ORDER BY mi.sold_at DESC LIMIT 200;

SELECT '== A3. PRODUCTION: when each line last minted' AS section;
SELECT r.market_id, r.vehicle_key, COUNT(*) AS ticks, SUM(r.minted) AS minted_total, SUM(r.sold_in_cycle) AS sold_total,
  $ts(MAX(IF(r.minted > 0, r.tick_at, NULL))) AS last_mint, $ts(MAX(r.tick_at)) AS last_tick,
  SUM(r.minted = 0 AND r.batch > 0 AND r.available_before < r.ceiling) AS ticks_wanting_but_zero
FROM market_production_run r GROUP BY r.market_id, r.vehicle_key ORDER BY last_mint;

SELECT '== A4. VEHICLES IN EXISTENCE by origin and owner kind' AS section;
SELECT a.origin, a.vehicle_key IS NULL AS no_key,
  CASE WHEN a.ncm_driver_id IS NOT NULL THEN 'player' WHEN a.owner_principal_kind IS NOT NULL THEN a.owner_principal_kind ELSE 'shelf/unowned' END AS owner_kind,
  COUNT(*) AS n, $ts(MAX(a.produced_at)) AS newest_produced
FROM vehicle_asset a GROUP BY 1, 2, 3 ORDER BY 1, 3;

SELECT '== C1. THE LAST NPC PART PURCHASES, traced' AS section;
SELECT $ts(t.occurred_at) AS at, t.market_id, t.amount, d.family, d.tier, d.manufacturer_key, LEFT(t.asset_id, 8) AS asset,
  CONCAT(a.owner_principal_kind, ':', a.owner_principal_id) AS owner_now, a.location_kind, a.machine_asset_id,
  (SELECT m.amount FROM npc_money m WHERE m.ref = t.asset_id AND m.kind = 'part_purchase' LIMIT 1) AS money_row,
  COALESCE(pp.cash, po.cash) AS owner_cash_now
FROM component_asset_transfer t JOIN component_asset a ON a.asset_id = t.asset_id JOIN component_design d ON d.design_id = a.design_id
LEFT JOIN paddock_person pp ON a.owner_principal_kind = 'person' AND pp.person_id = a.owner_principal_id
LEFT JOIN paddock_org po ON a.owner_principal_kind = 'org' AND po.org_id = a.owner_principal_id
WHERE t.kind = 'npc_purchase' ORDER BY t.occurred_at DESC LIMIT $Recent;

SELECT '== C2. NPC MONEY by who and why (npc_money ledger)' AS section;
SELECT server_id, principal_kind, kind, COUNT(*) AS n, SUM(amount) AS total, $ts(MIN(created_at)) AS first, $ts(MAX(created_at)) AS last
FROM npc_money GROUP BY server_id, principal_kind, kind ORDER BY server_id, principal_kind, kind;

SELECT '== C3. REPEAT BUYS: one owner holding several parts of the same family and tier' AS section;
SELECT CONCAT(a.owner_principal_kind, ':', a.owner_principal_id) AS owner, d.family, d.tier, COUNT(*) AS n,
  SUM(a.location_kind = 'npc_fitted') AS fitted, SUM(a.location_kind = 'npc_storage') AS stored
FROM component_asset a JOIN component_design d ON d.design_id = a.design_id
WHERE a.owner_principal_kind IS NOT NULL GROUP BY 1, 2, 3 HAVING COUNT(*) > 1 ORDER BY n DESC LIMIT 40;

SELECT '== D1. INDEPENDENT AND TEAM-DRIVER CASH' AS section;
SELECT server_id, IF(org_id IS NULL, 'independent', 'team driver') AS kind, role, state, COUNT(*) AS n, MIN(cash) AS min_cash,
  ROUND(AVG(cash)) AS avg_cash, MAX(cash) AS max_cash, SUM(cash) AS total_cash
FROM paddock_person WHERE role = 'driver' GROUP BY 1, 2, 3, 4;

SELECT '== D2. TEAM CASH by tier and lifecycle' AS section;
SELECT server_id, tier, lifecycle, COUNT(*) AS n, MIN(cash) AS min_cash, ROUND(AVG(cash)) AS avg_cash, MAX(cash) AS max_cash
FROM paddock_org GROUP BY server_id, tier, lifecycle ORDER BY server_id, tier, lifecycle;

SELECT '== D3. PURSES PAID (paddock_result) vs NPC market spend' AS section;
SELECT server_id, IF(org_id IS NULL OR org_id = '', 'independent', 'team') AS to_whom, COUNT(*) AS results, SUM(purse) AS purses
FROM paddock_result GROUP BY 1, 2;

SELECT '== E1. NPC-OWNED PARTS by place' AS section;
SELECT owner_principal_kind, location_kind, machine_asset_id IS NULL AS on_no_machine, COUNT(*) AS n
FROM component_asset WHERE owner_principal_kind IS NOT NULL GROUP BY 1, 2, 3;

SELECT '== E2. EXCHANGE: NPC posts and settlements' AS section;
SELECT principal_kind, state, COUNT(*) AS posts FROM exchange_post GROUP BY 1, 2;
SELECT payer_kind, payee_kind, COUNT(*) AS settlements, SUM(cash) AS cash FROM exchange_settlement GROUP BY 1, 2;

SELECT '== F. NAMED NPCs: their car, cash, team, owned vehicles and parts' AS section;
SELECT server_id, person_id, display, org_id, league_id, role, state, cash, LEFT(car_json, 220) AS car_json, LEFT(evidence_json, 200) AS evidence
FROM paddock_person WHERE person_id IN ($peopleList);
SELECT a.owner_principal_id AS person, a.asset_id, a.vehicle_key, a.odometer_m, a.lifecycle
FROM vehicle_asset a WHERE a.owner_principal_kind = 'person' AND a.owner_principal_id IN ($peopleList);
SELECT a.owner_principal_id AS person, d.family, d.tier, d.manufacturer_key, a.location_kind, a.machine_asset_id, $ts(a.acquired_at) AS acquired
FROM component_asset a JOIN component_design d ON d.design_id = a.design_id
WHERE a.owner_principal_kind = 'person' AND a.owner_principal_id IN ($peopleList) ORDER BY 1, a.acquired_at;
SELECT p.person_id, p.org_id, LEFT(o.car_json, 200) AS team_car, o.cash AS team_cash FROM paddock_person p
JOIN paddock_org o ON o.org_id = p.org_id WHERE p.person_id IN ($peopleList);

ROLLBACK;
"@

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $here "open77\server\npc-economy-audit-$stamp.txt"
$sqlFile = Join-Path $env:TEMP ('ncm-audit-' + [guid]::NewGuid().ToString('N') + '.sql')
Set-Content -LiteralPath $sqlFile -Value $sql -Encoding ascii
try {
    $env:MYSQL_PWD = (Part $conn 'Password'); if (-not $env:MYSQL_PWD) { $env:MYSQL_PWD = Part $conn 'Pwd' }
    & $client.FullName -h $hostName -P $port -u $user --protocol=tcp --table --force $db -e "source $sqlFile" 2>&1 | ForEach-Object { "$_" } | Out-File -LiteralPath $out -Encoding utf8
    $code = $LASTEXITCODE
} finally {
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    Remove-Item -Force -LiteralPath $sqlFile -ErrorAction SilentlyContinue
}
Write-Host "npc-economy-audit: exit $code -> $out"
