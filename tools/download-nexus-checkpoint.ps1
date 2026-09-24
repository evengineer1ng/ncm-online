param(
    [int[]]$ModIds = @(107, 2380, 1511, 7780, 4198, 4197, 3518, 4885, 4575, 3819),
    [string]$Stage = (Join-Path $PSScriptRoot '..\staging\checkpoint-02'),
    [hashtable]$FileOverrides = @{}
)

$ErrorActionPreference = 'Stop'
$Stage = [IO.Path]::GetFullPath($Stage)
New-Item -ItemType Directory -Path $Stage -Force | Out-Null

$secretPath = Join-Path $env:TEMP 'codex-cp2077-nexus-key.dpapi'
$cipher = (Get-Content -Raw -LiteralPath $secretPath).Trim()
$secure = ConvertTo-SecureString -String $cipher
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

try {
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    $headers = @{
        apikey = $apiKey
        accept = 'application/json'
        'application-version' = '1.0.0'
        'application-name' = 'codex-cp2077-installer'
    }

    $manifest = foreach ($modId in $ModIds) {
        $filesUri = "https://api.nexusmods.com/v1/games/cyberpunk2077/mods/$modId/files.json"
        $files = (Invoke-RestMethod -Uri $filesUri -Headers $headers).files
        $file = $null
        if ($FileOverrides.ContainsKey($modId)) {
            $wantedFileId = [int]$FileOverrides[$modId]
            $file = $files | Where-Object { $_.file_id -eq $wantedFileId } | Select-Object -First 1
            if ($null -eq $file) { throw "Override file $wantedFileId not found for Nexus mod $modId" }
        }
        if ($null -eq $file) {
            $file = $files |
                Where-Object { $_.is_primary -eq $true -and $_.category_name -eq 'MAIN' } |
                Sort-Object uploaded_timestamp -Descending |
                Select-Object -First 1
        }
        if ($null -eq $file) {
            $file = $files |
                Where-Object { $_.category_name -eq 'MAIN' } |
                Sort-Object uploaded_timestamp -Descending |
                Select-Object -First 1
        }
        if ($null -eq $file) { throw "No primary MAIN file found for Nexus mod $modId" }

        $linksUri = "https://api.nexusmods.com/v1/games/cyberpunk2077/mods/$modId/files/$($file.file_id)/download_link.json"
        $links = Invoke-RestMethod -Uri $linksUri -Headers $headers
        $link = $links | Select-Object -First 1
        if ($null -eq $link.URI) { throw "No Premium download link returned for Nexus mod $modId" }

        $safeName = ($file.file_name -replace '[^A-Za-z0-9._-]', '_')
        if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "mod-$modId-file-$($file.file_id).7z" }
        $destination = Join-Path $Stage $safeName
        if (-not (Test-Path -LiteralPath $destination) -or (Get-Item -LiteralPath $destination).Length -ne ($file.size_kb * 1024)) {
            Invoke-WebRequest -Uri $link.URI -OutFile $destination -UseBasicParsing
        }
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash

        [pscustomobject]@{
            mod_id = $modId
            file_id = $file.file_id
            name = $file.name
            version = $file.version
            archive = [IO.Path]::GetFileName($destination)
            bytes = (Get-Item -LiteralPath $destination).Length
            sha256 = $hash
            uploaded = $file.uploaded_time
        }
    }

    $manifestPath = Join-Path $Stage 'manifest.json'
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifest | Select-Object mod_id, file_id, name, version, archive, bytes | Format-Table -AutoSize
}
finally {
    if ($pointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    $apiKey = $null
}
