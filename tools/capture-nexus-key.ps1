$ErrorActionPreference = 'Stop'

$secret = Read-Host 'Paste your Nexus Personal API Key, then press Enter' -AsSecureString
if ($null -eq $secret) {
    throw 'No key was entered.'
}

$encrypted = ConvertFrom-SecureString -SecureString $secret
$destination = Join-Path $env:TEMP 'codex-cp2077-nexus-key.dpapi'
Set-Content -LiteralPath $destination -Value $encrypted -Encoding ASCII

Write-Host ''
Write-Host 'Key stored securely for this Windows account. You may close this window.' -ForegroundColor Green
Start-Sleep -Seconds 3
