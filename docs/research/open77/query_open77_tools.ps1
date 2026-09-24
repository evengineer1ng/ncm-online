# Lists the tools the hosted OPEN//77 devkit MCP actually exposes, with their input schemas.
# The evidence README warns: recheck tools/list rather than assuming a tool's name or arguments.
# Usage:  .\docs\research\open77\query_open77_tools.ps1 [-Build '2.31.13+op77.84'] [-OutputPath <file>]
param([string]$Build = '2.31.13+op77.84', [string]$OutputPath)
$uri = 'https://mcp.open2077.net/mcp?build=' + [uri]::EscapeDataString($Build)
$body = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list' } | ConvertTo-Json -Depth 5
$response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method Post -ContentType 'application/json' `
    -Headers @{ Accept = 'application/json, text/event-stream' } -Body $body
$payload = (($response.Content -split "`n" | Where-Object { $_.StartsWith('data: ') }) -replace '^data: ', '') | ConvertFrom-Json
$lines = foreach ($t in $payload.result.tools) {
    "== $($t.name)"
    "   $($t.description)"
    "   args: " + (($t.inputSchema.properties.PSObject.Properties | ForEach-Object { $_.Name }) -join ', ')
    "   required: " + ($t.inputSchema.required -join ', ')
    ""
}
$text = $lines -join "`n"
if ($OutputPath) { $text | Set-Content -LiteralPath $OutputPath -Encoding utf8 }
$text
