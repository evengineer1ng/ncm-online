param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077',
    [string]$Stage = (Join-Path $PSScriptRoot '..\staging\checkpoint-07'),
    [string]$Records = (Join-Path $PSScriptRoot '..\install-records\checkpoint-07')
)

$ErrorActionPreference = 'Stop'
$Game = [IO.Path]::GetFullPath($Game)
$Stage = [IO.Path]::GetFullPath($Stage)
$Records = [IO.Path]::GetFullPath($Records)
if (-not (Test-Path -LiteralPath (Join-Path $Game 'bin\x64\Cyberpunk2077.exe'))) { throw 'Invalid game folder.' }
if (Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue) { throw 'Cyberpunk 2077 is running.' }

$manifest = Get-Content -Raw -LiteralPath (Join-Path $Stage 'manifest.json') | ConvertFrom-Json
$packages = @(
    # In-World Navigation 0.1.20 (Nexus 4583, jackhumbert, MIT). Zip has no wrapper folder: files start at red4ext\...
    [pscustomobject]@{ ModId = 4583; Prefix = ''; Exclude = '^$' }
)
$extractRoot = Join-Path $Stage 'extracted'
$backupRoot = Join-Path $Records 'backup'
New-Item -ItemType Directory -Path $extractRoot, $backupRoot -Force | Out-Null
$deployed = New-Object System.Collections.Generic.List[object]

foreach ($package in $packages) {
    $item = $manifest | Where-Object { $_.mod_id -eq $package.ModId } | Select-Object -First 1
    if ($null -eq $item) { throw "Missing manifest entry for mod $($package.ModId)" }
    $archive = Join-Path $Stage $item.archive
    $extract = Join-Path $extractRoot ([string]$package.ModId)
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    New-Item -ItemType Directory -Path $extract | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
    $contentRoot = if ([string]::IsNullOrEmpty($package.Prefix)) { $extract } else { Join-Path $extract $package.Prefix }
    if (-not (Test-Path -LiteralPath $contentRoot -PathType Container)) { throw "Expected package root missing: $contentRoot" }
    $prefix = $contentRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

    foreach ($source in Get-ChildItem -LiteralPath $contentRoot -File -Recurse) {
        if (-not $source.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe source path.' }
        $relative = $source.FullName.Substring($prefix.Length)
        if ($relative -match $package.Exclude) { continue }
        if ($relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative)) { throw "Unsafe path: $relative" }
        $target = [IO.Path]::GetFullPath((Join-Path $Game $relative))
        if (-not $target.StartsWith($Game + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Target escape: $target" }

        $beforeHash = $null
        $backedUp = $false
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $beforeHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            $prior = $deployed | Where-Object { $_.relative_path -eq $relative } | Select-Object -First 1
            if ($null -eq $prior) {
                $backup = Join-Path $backupRoot $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                Copy-Item -LiteralPath $target -Destination $backup -Force
                $backedUp = $true
            }
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $target -Force
        $deployed.Add([pscustomobject]@{
            mod_id = $package.ModId; version = $item.version; relative_path = $relative
            sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            preexisting_sha256 = $beforeHash; backup_created = $backedUp
        })
    }
}

$deployed | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Records 'deployed-files.json') -Encoding UTF8
[pscustomobject]@{
    deployed_at = (Get-Date).ToString('o'); game = $Game
    game_version = (Get-Item -LiteralPath (Join-Path $Game 'bin\x64\Cyberpunk2077.exe')).VersionInfo.ProductVersion
    mods = $manifest; file_events = $deployed.Count
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Records 'deployment.json') -Encoding UTF8
[pscustomobject]@{Success=$true;Mods=$manifest.Count;FileEvents=$deployed.Count;Backups=($deployed|Where-Object backup_created).Count;Record=(Join-Path $Records 'deployment.json')} | ConvertTo-Json
