# Fetch the NCM Host plugin's two source dependencies into third_party/ (gitignored; this script reproduces them).
#   Lua 5.4 (lua.org, MIT) -- the SAME language OPEN//77 runs the NCM resources in: integers, coroutines, load with env
#   SQLite amalgamation (sqlite.org, public domain) -- the single-player database (doc 55 §4)
# RED4ext.SDK is shared from ncm/carrier/third_party (header-only submodule).
#   .\ncm\host_native\fetch-deps.ps1
[CmdletBinding()]
param(
    [string]$LuaVersion = "5.4.7",
    [string]$SqliteYear = "2025",
    [string]$SqliteVersion = "3490100",
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$tp = Join-Path $PSScriptRoot "third_party"
New-Item -ItemType Directory -Force -Path $tp | Out-Null

$luaDir = Join-Path $tp "lua"
if ($Force -and (Test-Path $luaDir)) { Remove-Item -Recurse -Force $luaDir }
if (Test-Path (Join-Path $luaDir "src\lua.h")) {
    Write-Host "Lua already present at $luaDir" -ForegroundColor DarkGray
} else {
    $tgz = Join-Path $env:TEMP "lua-$LuaVersion.tar.gz"
    Write-Host "downloading Lua $LuaVersion" -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://www.lua.org/ftp/lua-$LuaVersion.tar.gz" -OutFile $tgz -UseBasicParsing
    $unpack = Join-Path $env:TEMP "lua-unpack-$LuaVersion"
    if (Test-Path $unpack) { Remove-Item -Recurse -Force $unpack }
    New-Item -ItemType Directory -Force $unpack | Out-Null
    tar -xzf $tgz -C $unpack
    if ($LASTEXITCODE -ne 0) { throw "tar failed" }
    Move-Item (Join-Path $unpack "lua-$LuaVersion") $luaDir
}

$sqlDir = Join-Path $tp "sqlite"
if ($Force -and (Test-Path $sqlDir)) { Remove-Item -Recurse -Force $sqlDir }
if (Test-Path (Join-Path $sqlDir "sqlite3.c")) {
    Write-Host "SQLite already present at $sqlDir" -ForegroundColor DarkGray
} else {
    $zip = Join-Path $env:TEMP "sqlite-amalgamation-$SqliteVersion.zip"
    Write-Host "downloading SQLite $SqliteVersion" -ForegroundColor Cyan
    Invoke-WebRequest -Uri "https://www.sqlite.org/$SqliteYear/sqlite-amalgamation-$SqliteVersion.zip" -OutFile $zip -UseBasicParsing
    $unpack = Join-Path $env:TEMP "sqlite-unpack-$SqliteVersion"
    if (Test-Path $unpack) { Remove-Item -Recurse -Force $unpack }
    Expand-Archive -Path $zip -DestinationPath $unpack
    Move-Item (Join-Path $unpack "sqlite-amalgamation-$SqliteVersion") $sqlDir
}
Write-Host "third_party ready: Lua $LuaVersion, SQLite $SqliteVersion" -ForegroundColor Green
