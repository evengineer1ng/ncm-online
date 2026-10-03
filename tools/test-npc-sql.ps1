[CmdletBinding()]
param()
# Runs tools/npc-sql-gen.lua's script against the dev MariaDB inside START TRANSACTION ... ROLLBACK and asserts
# what the NPC market purchase and the posted-Exchange settlement did (L249 steps 4-5). Nothing persists: every
# fixture lives under server id `ncm-test-npc` and the whole script is rolled back (the last check proves it).
# Needs the dev DB secret (`ncm-secret.ps1`, the same store o77-server.ps1 uses) and schema 056.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ncm-npc-sql-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$runner = Join-Path $tmp "run.ps1"
@'
param([string]$SqlFile, [string]$Sql, [string]$Out)
$cs = $env:OP77_DATABASE_CONNECTION
$h = @{}
foreach ($kv in $cs.Split(';')) { $p = $kv.Split('=', 2); if ($p.Count -eq 2) { $h[$p[0].Trim().ToLower()] = $p[1] } }
function pick([string[]]$keys) { foreach ($k in $keys) { if ($h[$k]) { return $h[$k] } } return $null }
$db = pick @('database', 'initial catalog'); $u = pick @('user id', 'uid', 'user', 'username')
$hostName = pick @('server', 'host', 'data source'); if (-not $hostName) { $hostName = '127.0.0.1' }
$port = pick @('port'); if (-not $port) { $port = '3306' }
$env:MYSQL_PWD = pick @('password', 'pwd')
$mysql = "C:\Program Files\MariaDB 10.11\bin\mysql.exe"
if ($SqlFile) { $r = Get-Content -Raw $SqlFile | & $mysql -u $u -h $hostName -P $port -N -B $db 2>&1 }
else { $r = & $mysql -u $u -h $hostName -P $port -N -B $db -e $Sql 2>&1 }
$r | ForEach-Object { "$_" } | Set-Content -Path $Out -Encoding utf8
'@ | Set-Content -Path $runner -Encoding utf8
function Invoke-Db([string]$Sql, [string]$SqlFile) {
    $out = Join-Path $tmp ("out-" + [Guid]::NewGuid().ToString("N") + ".txt")
    $a = if ($SqlFile) { @("-SqlFile", $SqlFile) } else { @("-Sql", $Sql) }
    & (Join-Path $root "tools\ncm-secret.ps1") -Run -Env @{ 'OP77_DATABASE_CONNECTION' = 'db-connection' } -- powershell -NoProfile -ExecutionPolicy Bypass -File $runner @a -Out $out | Out-Null
    if (Test-Path $out) { return Get-Content $out }
    return @()
}
try {
    $fix = Invoke-Db "SELECT d.design_id, d.manufacturer_key, (SELECT market_id FROM market ORDER BY market_id LIMIT 1), (SELECT ncm_driver_id FROM ncm_driver ORDER BY ncm_driver_id LIMIT 1) FROM component_design d ORDER BY d.design_id LIMIT 1;"
    $f = ("$fix").Trim().Split("`t")
    if ($f.Count -lt 4) { throw "could not read fixtures (design, maker, market, driver): '$fix'" }
    $sql = Join-Path $tmp "npc.sql"
    $lua = "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe"
    & $lua (Join-Path $root "tools\npc-sql-gen.lua") $f[0] $f[1] $f[2] $f[3] $sql | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "generator failed" }
    $rows = Invoke-Db $null $sql
    $got = @{}
    foreach ($line in $rows) { $p = "$line".Split("`t"); if ($p.Count -ge 2) { $got[$p[0]] = $p[1] } }
    $driver = $f[3]
    $expect = [ordered]@{
        "A.sold_to" = "org:o_t"; "A.owner" = "org:o_t:npc_storage"; "A.cash_t" = "49000"; "A.cash_u" = "50000"; "A.money_rows" = "1"
        "B.owner" = "${driver}:-:storage"; "B.ledger" = "3800"; "B.cash_t" = "50200"; "B.post" = "filled"; "B.bid" = "accepted"
        "B.reservations" = "0"; "B.settled" = "1"
        "C.owner" = "-:o_u:npc_storage"; "C.ledger" = "3800"; "C.cash_u" = "50000"; "C.post" = "open"; "C.settled" = "0"
        "D.factory_parts" = "11"; "D.installed" = "1"; "D.old_stored" = "npc_storage"; "D.service" = "org:o_t:350"
        "after.rollback" = "0"
    }
    $bad = 0
    foreach ($k in $expect.Keys) {
        if ($got[$k] -eq $expect[$k]) { Write-Host "  PASS $k = $($got[$k])" }
        else { Write-Host "  FAIL $k = '$($got[$k])' (expected '$($expect[$k])')"; $bad++ }
    }
    Write-Host ("npc sql: {0} passed, {1} failed" -f ($expect.Count - $bad), $bad)
    if ($bad -gt 0) { exit 1 }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
