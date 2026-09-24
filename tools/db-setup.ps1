<#
.SYNOPSIS
  Install MariaDB locally and create the NCM database/user for the OPEN//77 server.
  Passwords are generated here, stored DPAPI-encrypted through tools\ncm-secret.ps1 and never printed:
    db-root        MariaDB root password
    db-connection  MySqlConnector connection string for the server (OP77_DATABASE_CONNECTION)

  Note: the root password is passed to the MSI on its command line during install (visible to local
  processes for a few seconds). Everything after that goes through environment variables only.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\db-setup.ps1 [-SkipInstall]
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SkipInstall,
    [string]$DbName = 'ncm',
    [string]$DbUser = 'ncm',
    [int]$Port = 3306
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$secretTool = Join-Path $here 'ncm-secret.ps1'
$store = Join-Path $env:LOCALAPPDATA 'NCM\secrets'
New-Item -ItemType Directory -Force -Path $store | Out-Null

function New-Password([int]$len = 28) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'
    $bytes = New-Object byte[] $len
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}
function Save-Secret([string]$name, [string]$value) {
    $secure = ConvertTo-SecureString $value -AsPlainText -Force
    $path = Join-Path $store "$name.dpapi"
    $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $path -Encoding ascii
    icacls $path /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
}
function Read-Secret([string]$name) {
    $path = Join-Path $store "$name.dpapi"
    $secure = (Get-Content -LiteralPath $path -Raw).Trim() | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# 1. Passwords (reuse existing root secret if present so a re-run does not desync from the installed server).
if (Test-Path (Join-Path $store 'db-root.dpapi')) {
    $rootPw = Read-Secret 'db-root'; Write-Host 'db-root: reusing stored secret'
} else {
    $rootPw = New-Password; Save-Secret 'db-root' $rootPw; Write-Host 'db-root: generated and stored'
}
$ncmPw = New-Password
$conn = "Server=127.0.0.1;Port=$Port;Database=$DbName;User ID=$DbUser;Password=$ncmPw;"
Save-Secret 'db-connection' $conn
Write-Host "db-connection: stored ($($conn.Length) chars)"

# 2. Install.
if (-not $SkipInstall) {
    $svc = Get-Service | Where-Object { $_.Name -match '^MariaDB' } | Select-Object -First 1
    if ($svc) {
        Write-Host "MariaDB service already present: $($svc.Name) ($($svc.Status)); skipping install"
    } else {
        Write-Host 'Installing MariaDB.Server via winget (UAC prompt expected)...'
        $override = "/qn PASSWORD=$rootPw SERVICENAME=MariaDB PORT=$Port UTF8=1"
        winget install --id MariaDB.Server --exact --accept-source-agreements --accept-package-agreements --override $override
        if ($LASTEXITCODE -ne 0) { throw "winget install failed with exit code $LASTEXITCODE" }
    }
}

# 3. Wait for the service and find the client.
$deadline = (Get-Date).AddMinutes(3)
do {
    $svc = Get-Service | Where-Object { $_.Name -match '^MariaDB' } | Select-Object -First 1
    if ($svc -and $svc.Status -ne 'Running') { try { Start-Service $svc.Name } catch {} }
    Start-Sleep -Seconds 2
} while ((-not $svc -or $svc.Status -ne 'Running') -and (Get-Date) -lt $deadline)
if (-not $svc -or $svc.Status -ne 'Running') { throw 'MariaDB service not running' }
Write-Host "Service $($svc.Name) is running"

$client = Get-ChildItem 'C:\Program Files\MariaDB*\bin' -Include mariadb.exe, mysql.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $client) { throw 'MariaDB client (mariadb.exe/mysql.exe) not found under C:\Program Files\MariaDB*' }
Write-Host "Client: $($client.FullName)"

# 4. Create database and user (idempotent). Root password travels via MYSQL_PWD only.
$sql = @"
CREATE DATABASE IF NOT EXISTS ``$DbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DbUser'@'127.0.0.1' IDENTIFIED BY '$ncmPw';
ALTER USER '$DbUser'@'127.0.0.1' IDENTIFIED BY '$ncmPw';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP, REFERENCES ON ``$DbName``.* TO '$DbUser'@'127.0.0.1';
FLUSH PRIVILEGES;
SELECT 'ncm database and user ready' AS status;
"@
$sqlFile = Join-Path $env:TEMP ('ncm-db-setup-' + [guid]::NewGuid().ToString('N') + '.sql')
Set-Content -LiteralPath $sqlFile -Value $sql -Encoding ascii
icacls $sqlFile /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
try {
    $env:MYSQL_PWD = $rootPw
    & $client.FullName -h 127.0.0.1 -P $Port -u root --protocol=tcp -e "source $sqlFile"
    $code = $LASTEXITCODE
} finally {
    Remove-Item -Force $env:TEMP\ncm-db-setup-*.sql -ErrorAction SilentlyContinue
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
}
if ($code -ne 0) { throw "database setup SQL failed (exit $code)" }

# 5. Verify with the NCM user via a throwaway env (no secrets printed).
$env:MYSQL_PWD = $ncmPw
try { & $client.FullName -h 127.0.0.1 -P $Port -u $DbUser --protocol=tcp -e "SELECT DATABASE() AS db, CURRENT_USER() AS user, VERSION() AS version" $DbName }
finally { Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue }
Write-Host 'db-setup complete'
