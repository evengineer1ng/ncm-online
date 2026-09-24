param([Parameter(Mandatory=$true)][string]$Tool, [string]$ArgumentsJson='{}', [string]$OutputPath)
$body = @{jsonrpc='2.0'; id=1; method='tools/call'; params=@{name=$Tool; arguments=($ArgumentsJson | ConvertFrom-Json)}} | ConvertTo-Json -Depth 20
$response = Invoke-WebRequest -UseBasicParsing -Uri 'https://mcp.open2077.net/mcp?build=2.31.13%2Bop77.84' -Method Post -ContentType 'application/json' -Headers @{Accept='application/json, text/event-stream'} -Body $body
$payload = (($response.Content -split "`n" | Where-Object { $_.StartsWith('data: ') }) -replace '^data: ', '') | ConvertFrom-Json
$text = ($payload.result.content | Where-Object type -eq 'text' | ForEach-Object text) -join "`n"
if ($OutputPath) { $text | Set-Content -LiteralPath $OutputPath -Encoding utf8 }
$text

