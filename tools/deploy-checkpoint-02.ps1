param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077',
    [string]$Stage = (Join-Path $PSScriptRoot '..\staging\checkpoint-02'),
    [string]$Records = (Join-Path $PSScriptRoot '..\install-records\checkpoint-02')
)

$ErrorActionPreference = 'Stop'
$Game = [IO.Path]::GetFullPath($Game)
$Stage = [IO.Path]::GetFullPath($Stage)
$Records = [IO.Path]::GetFullPath($Records)
if (-not (Test-Path -LiteralPath (Join-Path $Game 'bin\x64\Cyberpunk2077.exe'))) {
    throw "Cyberpunk executable not found under $Game"
}
if (Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue) {
    throw 'Cyberpunk 2077 is running. Close it before deployment.'
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $Stage 'manifest.json') | ConvertFrom-Json
$order = @(107, 2380, 1511, 7780, 4198, 4197, 3518, 4885, 4575, 3819)
$extractRoot = Join-Path $Stage 'extracted'
$backupRoot = Join-Path $Records 'backup'
New-Item -ItemType Directory -Path $extractRoot, $backupRoot -Force | Out-Null

$deployed = New-Object System.Collections.Generic.List[object]
foreach ($modId in $order) {
    $item = $manifest | Where-Object { $_.mod_id -eq $modId } | Select-Object -First 1
    if ($null -eq $item) { throw "Missing staged manifest entry for mod $modId" }
    $archive = Join-Path $Stage $item.archive
    $extract = Join-Path $extractRoot ([string]$modId)
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    New-Item -ItemType Directory -Path $extract | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force

    foreach ($source in Get-ChildItem -LiteralPath $extract -File -Recurse) {
        $extractPrefix = $extract.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $source.FullName.StartsWith($extractPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Source escapes extraction directory: $($source.FullName)"
        }
        $relative = $source.FullName.Substring($extractPrefix.Length)
        if ($relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative)) {
            throw "Unsafe archive path: $relative"
        }
        $target = Join-Path $Game $relative
        $targetFull = [IO.Path]::GetFullPath($target)
        if (-not $targetFull.StartsWith($Game + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Target escapes game directory: $targetFull"
        }

        $beforeHash = $null
        $backedUp = $false
        if (Test-Path -LiteralPath $targetFull -PathType Leaf) {
            $beforeHash = (Get-FileHash -LiteralPath $targetFull -Algorithm SHA256).Hash
            $alreadyOwned = $deployed | Where-Object { $_.relative_path -eq $relative } | Select-Object -First 1
            if ($null -eq $alreadyOwned) {
                $backup = Join-Path $backupRoot $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                Copy-Item -LiteralPath $targetFull -Destination $backup -Force
                $backedUp = $true
            }
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $targetFull) -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $targetFull -Force
        $deployed.Add([pscustomobject]@{
            mod_id = $modId
            version = $item.version
            relative_path = $relative
            sha256 = (Get-FileHash -LiteralPath $targetFull -Algorithm SHA256).Hash
            preexisting_sha256 = $beforeHash
            backup_created = $backedUp
        })
    }
}

$deployed | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Records 'deployed-files.json') -Encoding UTF8
[pscustomobject]@{
    deployed_at = (Get-Date).ToString('o')
    game = $Game
    game_version = (Get-Item -LiteralPath (Join-Path $Game 'bin\x64\Cyberpunk2077.exe')).VersionInfo.ProductVersion
    mods = $manifest
    file_events = $deployed.Count
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Records 'deployment.json') -Encoding UTF8

[pscustomobject]@{
    Success = $true
    Mods = $manifest.Count
    FileEvents = $deployed.Count
    Backups = ($deployed | Where-Object backup_created).Count
    Record = (Join-Path $Records 'deployment.json')
} | ConvertTo-Json
