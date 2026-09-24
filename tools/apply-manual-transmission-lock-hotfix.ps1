$ErrorActionPreference = 'Stop'
$game = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
$relative = 'bin\x64\plugins\cyber_engine_tweaks\mods\MANUAL TRANSMISSION V10\modules\stateManager.lua'
$source = Join-Path $PSScriptRoot '..\staging\checkpoint-03\extracted\28342\MANUAL TRANSMISSION V10 - IMMERSIVE GEAR SHIFTING(OG Shifting)\bin\x64\plugins\cyber_engine_tweaks\mods\MANUAL TRANSMISSION V10\modules\stateManager.lua'
$target = Join-Path $game $relative
$recordRoot = Join-Path $PSScriptRoot '..\install-records\checkpoint-03\hotfix-block-change-gear'
$backup = Join-Path $recordRoot $relative

if (Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue) { throw 'Cyberpunk 2077 is running.' }
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Patched source missing.' }
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Installed v4.1 stateManager.lua missing.' }

New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
Copy-Item -LiteralPath $target -Destination $backup -Force
$before = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
Copy-Item -LiteralPath $source -Destination $target -Force
$after = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash

[pscustomobject]@{
    applied_at = (Get-Date).ToString('o')
    relative_path = $relative
    original_sha256 = $before
    patched_sha256 = $after
    backup = $backup
    change = 'Clear Vehicle/BlockChangeGear explicitly when vehicle state initializes in automatic mode.'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $recordRoot 'hotfix.json') -Encoding UTF8

[pscustomobject]@{Success=$true;OriginalSHA256=$before;PatchedSHA256=$after;Backup=$backup} | ConvertTo-Json
