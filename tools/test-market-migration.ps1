[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$database = 'ncm_market_017_check'
$client = Get-ChildItem 'C:\Program Files\MariaDB*\bin' -Include mariadb.exe, mysql.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $client) { throw 'MariaDB client not found' }
if (-not $env:NCM_DB_ROOT) { throw 'NCM_DB_ROOT was not injected' }

$env:MYSQL_PWD = $env:NCM_DB_ROOT
function Invoke-Sql([string]$sql, [switch]$NoDatabase) {
    $args = @('-h', '127.0.0.1', '-P', '3306', '-u', 'root', '--protocol=tcp', '--batch', '--skip-column-names')
    if (-not $NoDatabase) { $args += $database }
    $args += @('-e', $sql)
    $output = & $client.FullName @args
    if ($LASTEXITCODE -ne 0) { throw "MariaDB command failed (exit $LASTEXITCODE)" }
    return $output
}

try {
    Invoke-Sql "DROP DATABASE IF EXISTS ``$database``; CREATE DATABASE ``$database`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" -NoDatabase | Out-Null
    Invoke-Sql @'
CREATE TABLE ncm_driver (
  ncm_driver_id CHAR(36) NOT NULL PRIMARY KEY,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  origin ENUM('sp','online') NOT NULL
) ENGINE=InnoDB;
CREATE TABLE ledger (
  ledger_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  ncm_driver_id CHAR(36) NOT NULL,
  server_id VARCHAR(96) NOT NULL,
  kind VARCHAR(48) NOT NULL,
  amount INT NOT NULL DEFAULT 0,
  currency VARCHAR(16) NOT NULL DEFAULT 'eddies',
  ref VARCHAR(160) NULL,
  note VARCHAR(160) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY ix_ledger_driver (ncm_driver_id, created_at),
  CONSTRAINT fk_ledger_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver(ncm_driver_id)
) ENGINE=InnoDB;
CREATE TABLE vehicle_asset (
  asset_id CHAR(36) NOT NULL PRIMARY KEY,
  server_id VARCHAR(96) NOT NULL,
  ncm_driver_id CHAR(36) NOT NULL,
  vehicle_key VARCHAR(96) NULL,
  record VARCHAR(256) NOT NULL,
  class VARCHAR(32) NULL,
  acquired_via ENUM('grant','progression','prize','purchase','seed') NOT NULL DEFAULT 'grant',
  granted_by VARCHAR(96) NULL,
  acquired_at BIGINT NOT NULL,
  KEY ix_vehicle_asset_owner (ncm_driver_id, server_id),
  KEY ix_vehicle_asset_key (server_id, vehicle_key),
  KEY ix_vehicle_asset_record (server_id, record),
  CONSTRAINT fk_vehicle_asset_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver(ncm_driver_id)
) ENGINE=InnoDB;
'@ | Out-Null

    $migrationPath = Join-Path $PSScriptRoot '..\ncm\online\resources\ncm_league\server\schema\017_market_foundation.lua'
    $migration = Get-Content -LiteralPath $migrationPath -Raw
    $statements = [regex]::Matches($migration, '(?s)\[\[(.*?)\]\]')
    if ($statements.Count -ne 7) { throw "Expected 7 migration statements, found $($statements.Count)" }
    foreach ($match in $statements) { Invoke-Sql $match.Groups[1].Value | Out-Null }

    $driverA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    $driverB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    $asset = '10000000-0000-4000-8000-000000000001'
    Invoke-Sql @"
INSERT INTO ncm_driver (ncm_driver_id, origin) VALUES ('$driverA','online'),('$driverB','online');
INSERT INTO market (market_id, display_name, kind, universally_known) VALUES ('base_market','Base Market','primary',1);
INSERT INTO vehicle_asset (asset_id,server_id,ncm_driver_id,vehicle_key,record,class,acquired_via,acquired_at,allocation_id,allocation_slot)
VALUES ('$asset','test',NULL,'makigai_maimai','Vehicle.v_standard2_makigai_maimai','Compact',NULL,1,'alpha_launch',1);
INSERT INTO market_inventory (market_id,asset_id,price,state,listed_at) VALUES ('base_market','$asset',2500,'available',1);
INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,idem_key) VALUES ('$driverA','test','starter_grant',10000,'starter:test:$driverA');
INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,idem_key) VALUES ('$driverA','test','starter_grant',10000,'starter:test:$driverA');
START TRANSACTION;
UPDATE market_inventory mi SET mi.state='sold',mi.sold_at=2,mi.sold_to_driver_id='$driverA'
 WHERE mi.market_id='base_market' AND mi.asset_id='$asset' AND mi.state='available'
 AND (SELECT COALESCE(SUM(l.amount),0) FROM ledger l WHERE l.ncm_driver_id='$driverA' AND l.server_id='test') >= mi.price;
INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,idem_key,market_id,asset_id)
 SELECT '$driverA','test','vehicle_purchase',-mi.price,'purchase:test:$asset',mi.market_id,mi.asset_id
 FROM market_inventory mi WHERE mi.market_id='base_market' AND mi.asset_id='$asset' AND mi.state='sold' AND mi.sold_to_driver_id='$driverA';
UPDATE vehicle_asset a JOIN market_inventory mi ON mi.asset_id=a.asset_id
 SET a.ncm_driver_id='$driverA',a.acquired_via='purchase',a.granted_by='base_market',a.acquired_at=2
 WHERE a.asset_id='$asset' AND mi.market_id='base_market' AND mi.state='sold' AND mi.sold_to_driver_id='$driverA' AND a.ncm_driver_id IS NULL;
INSERT IGNORE INTO vehicle_asset_transfer (transfer_id,idem_key,server_id,asset_id,from_driver_id,to_driver_id,kind,market_id,amount,occurred_at)
 SELECT 'cccccccc-cccc-4ccc-8ccc-cccccccccccc','purchase:test:$asset','test',mi.asset_id,NULL,'$driverA','primary_purchase',mi.market_id,mi.price,2
 FROM market_inventory mi WHERE mi.market_id='base_market' AND mi.asset_id='$asset' AND mi.state='sold' AND mi.sold_to_driver_id='$driverA';
COMMIT;
"@ | Out-Null

    # Exact retry must be harmless; a competing buyer must receive neither title nor debit.
    Invoke-Sql @"
INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,idem_key,market_id,asset_id)
 SELECT '$driverA','test','vehicle_purchase',-mi.price,'purchase:test:$asset',mi.market_id,mi.asset_id
 FROM market_inventory mi WHERE mi.market_id='base_market' AND mi.asset_id='$asset' AND mi.state='sold' AND mi.sold_to_driver_id='$driverA';
INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,idem_key,market_id,asset_id)
 SELECT '$driverB','test','vehicle_purchase',-mi.price,'purchase:test:$asset',mi.market_id,mi.asset_id
 FROM market_inventory mi WHERE mi.market_id='base_market' AND mi.asset_id='$asset' AND mi.state='sold' AND mi.sold_to_driver_id='$driverB';
"@ | Out-Null

    $result = Invoke-Sql @"
SELECT CONCAT(
 (SELECT COUNT(*) FROM ledger WHERE idem_key='starter:test:$driverA'), '|',
 (SELECT COUNT(*) FROM ledger WHERE idem_key='purchase:test:$asset'), '|',
 (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id='$driverA' AND server_id='test'), '|',
 (SELECT ncm_driver_id FROM vehicle_asset WHERE asset_id='$asset'), '|',
 (SELECT COUNT(*) FROM vehicle_asset_transfer WHERE idem_key='purchase:test:$asset'), '|',
 (SELECT COUNT(*) FROM ledger WHERE ncm_driver_id='$driverB')
);
"@
    $expected = "1|1|7500|$driverA|1|0"
    if (($result | Select-Object -Last 1).Trim() -ne $expected) {
        throw "Market migration/idempotency assertion failed: $result"
    }
    Write-Host 'PASS migration 017 + starter grant + purchase retry + competing buyer conservation'
} finally {
    try { Invoke-Sql "DROP DATABASE IF EXISTS ``$database``;" -NoDatabase | Out-Null } catch {}
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    Remove-Item Env:\NCM_DB_ROOT -ErrorAction SilentlyContinue
}
