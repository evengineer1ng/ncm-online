<#
.SYNOPSIS
  Store and use secrets (OPEN//77 license key, DB connection string) without exposing them.

  Secrets are encrypted with Windows DPAPI in CurrentUser scope and kept OUTSIDE the
  workspace at %LOCALAPPDATA%\NCM\secrets\<name>.dpapi. Only this Windows account on this
  machine can decrypt them. Nothing here ever prints a secret value.

.USAGE
  # Store (interactive, masked input; run this yourself in a terminal):
  .\tools\ncm-secret.ps1 -Set open77-license
  .\tools\ncm-secret.ps1 -Set db-connection

  # List stored names (never values):
  .\tools\ncm-secret.ps1 -List

  # Run a command with secrets injected as environment variables of the CHILD process only:
  .\tools\ncm-secret.ps1 -Run -Env @{ 'OP77_DATABASE_CONNECTION' = 'db-connection' } -- <exe> [args...]

  # Remove:
  .\tools\ncm-secret.ps1 -Remove open77-license
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Set,
    [switch]$List,
    [string]$Remove,
    [switch]$Run,
    [hashtable]$Env,
    [switch]$Test,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Argv
)

$ErrorActionPreference = 'Stop'
$store = Join-Path $env:LOCALAPPDATA 'NCM\secrets'
if (-not (Test-Path $store)) { New-Item -ItemType Directory -Force -Path $store | Out-Null }

function Get-SecretPath([string]$name) {
    if ($name -notmatch '^[a-z0-9][a-z0-9\-]{0,63}$') { throw "Secret name must be lowercase letters, digits, dashes: '$name'" }
    return Join-Path $store "$name.dpapi"
}

function Read-SecretPlain([string]$name) {
    $path = Get-SecretPath $name
    if (-not (Test-Path $path)) { throw "No secret named '$name'. Store it with: .\tools\ncm-secret.ps1 -Set $name" }
    $secure = (Get-Content -LiteralPath $path -Raw).Trim() | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if ($Set) {
    $path = Get-SecretPath $Set
    $secure = Read-Host -Prompt "Enter value for '$Set' (input is hidden)" -AsSecureString
    if ($secure.Length -eq 0) { throw 'Empty value; nothing stored.' }
    $confirm = Read-Host -Prompt "Re-enter to confirm" -AsSecureString
    $a = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirm)
    try {
        $same = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($a) -ceq [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($a); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
    }
    if (-not $same) { throw 'Values did not match; nothing stored.' }
    $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $path -Encoding ascii
    # Restrict the file to this user (belt and braces on top of DPAPI).
    icacls $path /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
    Write-Host "Stored '$Set' -> $path (DPAPI, CurrentUser; $($secure.Length) chars)."
    return
}

if ($List) {
    Get-ChildItem -LiteralPath $store -Filter '*.dpapi' | ForEach-Object {
        [pscustomobject]@{ Name = $_.BaseName; Stored = $_.LastWriteTime }
    } | Format-Table -AutoSize
    return
}

if ($Remove) {
    $path = Get-SecretPath $Remove
    if (Test-Path $path) { Remove-Item -LiteralPath $path -Force; Write-Host "Removed '$Remove'." } else { Write-Host "No secret named '$Remove'." }
    return
}

if ($Test) {
    # Proves a secret decrypts, without revealing it: prints only its length and a SHA-256 prefix.
    foreach ($f in Get-ChildItem -LiteralPath $store -Filter '*.dpapi') {
        $plain = Read-SecretPlain $f.BaseName
        $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($plain))).Replace('-','').Substring(0,12)
        Write-Host ("{0}: decrypts OK, {1} chars, sha256[0:12]={2}" -f $f.BaseName, $plain.Length, $sha)
        $plain = $null
    }
    return
}

if ($Run) {
    if (-not $Env -or $Env.Count -eq 0) { throw 'Provide -Env @{ ENVVAR = secret-name; ... }' }
    if (-not $Argv -or $Argv.Count -eq 0) { throw 'Provide the command after --' }
    if ($Argv[0] -eq '--') { $Argv = $Argv[1..($Argv.Count - 1)] }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Argv[0]
    $psi.Arguments = ($Argv | Select-Object -Skip 1 | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = (Get-Location).Path
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = (Read-SecretPlain $Env[$k]) }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    exit $p.ExitCode
}

Get-Help $MyInvocation.MyCommand.Path -Detailed
