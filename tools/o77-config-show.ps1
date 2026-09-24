<#
.SYNOPSIS
  Print an OPEN//77 server.jsonc (or acl.jsonc) with secret-bearing values masked.
  This is the ONLY way the assistant reads server configuration. Any "key": "value" pair whose key
  contains license, key, secret, token, password, connection, pin or credential (case-insensitive)
  is masked wherever it appears on a line, except path-like keys (signingKeyFile, cacheDirectory).

.USAGE
  .\tools\o77-config-show.ps1 -Path tools\open77\server\server.jsonc
#>
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'
$allow = @('signingKeyFile', 'cacheDirectory', 'signingKeyPath')
$pattern = '"(?<k>[^"]*(?i:license|key|secret|token|password|connection|pin|credential)[^"]*)"\s*:\s*"(?<v>(?:[^"\\]|\\.)*)"'
Get-Content -LiteralPath $Path | ForEach-Object {
    [regex]::Replace($_, $pattern, {
        param($m)
        $k = $m.Groups['k'].Value
        if ($allow -contains $k) { return $m.Value }
        return '"' + $k + '": "<masked ' + $m.Groups['v'].Value.Length + ' chars>"'
    })
}
