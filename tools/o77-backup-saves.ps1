<#
.SYNOPSIS
  Back up the Cyberpunk 2077 save folder before a multi-client OPEN//77 session
  (all game instances on one machine share it; autosave starts on world entry).

  Writes a dated zip to tools\open77\save-backups\ (outside the game folder; ~300 MB per backup)
  and prunes to the newest -Keep backups.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\o77-backup-saves.ps1 [-Keep 5]
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [int]$Keep = 5,
    [string]$SaveDir = (Join-Path $env:USERPROFILE 'Saved Games\CD Projekt Red\Cyberpunk 2077')
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $here 'open77\save-backups'
New-Item -ItemType Directory -Force -Path $out | Out-Null
if (-not (Test-Path $SaveDir)) { throw "Save folder not found: $SaveDir" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$zip = Join-Path $out "saves-$stamp.zip"
$size = (Get-ChildItem -LiteralPath $SaveDir -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("Backing up {0} ({1:N0} MB) -> {2}" -f $SaveDir, ($size / 1MB), $zip)
Compress-Archive -Path (Join-Path $SaveDir '*') -DestinationPath $zip -CompressionLevel Fastest
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
"{0}  saves-{1}.zip  source={2}" -f $hash, $stamp, $SaveDir | Add-Content -LiteralPath (Join-Path $out 'backups.sha256')
Write-Host "Done. sha256=$hash"

Get-ChildItem -LiteralPath $out -Filter 'saves-*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | ForEach-Object {
    Write-Host "Pruning old backup $($_.Name)"; Remove-Item -LiteralPath $_.FullName -Force
}
