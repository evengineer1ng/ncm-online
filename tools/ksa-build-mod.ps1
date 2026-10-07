<#
.SYNOPSIS
  Build NCM's Kitten Space Agency adapter (ncm/ksa/NcmKsa, a StarMap code mod) and install it for the local KSA (L335).

.DESCRIPTION
  Uses the private .NET 10 SDK under %LOCALAPPDATA%\NCM\dotnet (installed with Microsoft's dotnet-install script, no
  admin) against the INSTALLED game and loader: KSA.dll etc. from C:\Program Files\Kitten Space Agency and StarMap.API
  from %LOCALAPPDATA%\NCM\StarMap. Nothing of KSA or StarMap is copied into the repository.

  Installs to Documents\My Games\Kitten Space Agency\mods\NcmKsa and makes sure KSA's mod manifest enables it.
  KSA must not be running (the DLL is locked while it is).

  Afterwards: GET http://127.0.0.1:47710/ksa/status and POST /ksa/selftest on the host bridge prove it end to end.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dotnetDir = Join-Path $env:LOCALAPPDATA 'NCM\dotnet'
$out = Join-Path $env:LOCALAPPDATA 'NCM\build\NcmKsa'
$docs = Join-Path ([Environment]::GetFolderPath('Personal')) 'My Games\Kitten Space Agency'
$modDir = Join-Path $docs 'mods\NcmKsa'

if (Get-Process StarMap, KSA -ErrorAction SilentlyContinue) { throw 'KSA is running: close it first (its mod DLL is locked).' }
if (-not (Test-Path (Join-Path $dotnetDir 'dotnet.exe'))) { throw "No .NET 10 SDK at $dotnetDir (install: dotnet-install.ps1 -Channel 10.0 -InstallDir $dotnetDir -NoPath)" }

$env:DOTNET_ROOT = $dotnetDir
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
& (Join-Path $dotnetDir 'dotnet.exe') build (Join-Path $repo 'ncm\ksa\NcmKsa\NcmKsa.csproj') -c Release -o $out
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

New-Item -ItemType Directory -Force $modDir | Out-Null
Copy-Item (Join-Path $out 'NcmKsa.dll'), (Join-Path $out 'NcmKsa.pdb'), (Join-Path $out 'mod.toml') $modDir -Force
# L336: the Machine's craft -- NCM's XML (content/, vehicles/) from the repo; its body from the player's own game files
$src = Join-Path $repo 'ncm\ksa\NcmKsa'
foreach ($d in 'content', 'vehicles') {
  Copy-Item (Join-Path $src $d) $modDir -Recurse -Force
}
if (-not (Test-Path (Join-Path $modDir 'Meshes\NcmHella_MeshAtlas.glb'))) {
  Write-Host 'Making the Hella''s KSA body from your game files (tools/ksa-hella-body.py) ...'
  & python (Join-Path $repo 'tools\ksa-hella-body.py')
  if ($LASTEXITCODE -ne 0) { throw "ksa-hella-body.py failed ($LASTEXITCODE)" }
}

$manifest = Join-Path $docs 'manifest.toml'
$text = if (Test-Path $manifest) { Get-Content $manifest -Raw } else { "[[mods]]`nid = `"Core`"`nenabled = true`n" }
if ($text -notmatch 'id = "NcmKsa"') {
  $text = $text.TrimEnd() + "`n`n[[mods]]`nid = `"NcmKsa`"`nenabled = true`n"
  [IO.File]::WriteAllText($manifest, $text, (New-Object Text.UTF8Encoding($false)))
}
Write-Host "NcmKsa installed to $modDir"
