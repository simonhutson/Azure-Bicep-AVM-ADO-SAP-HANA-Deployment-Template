function New-ConfiguredParameters {
    param([string] $EnvironmentName = 'development')
    $document = Get-Content -LiteralPath (Join-Path $script:Root ".build\iac\$EnvironmentName.parameters.json") -Raw | ConvertFrom-Json -AsHashtable
    $document = (($document | ConvertTo-Json -Depth 100) -replace 'REQUIRED_[A-Z0-9_]+', 'configured') | ConvertFrom-Json -AsHashtable
    $p = $document.parameters
    $p.image.value.version = '15.6.2026010101'
    $keyBytes = [byte[]](@(0, 0, 0, 11) + [Text.Encoding]::ASCII.GetBytes('ssh-ed25519') + @(0, 0, 0, 32) + @(1..32))
    $p.sshPublicKey.value = 'ssh-ed25519 ' + [Convert]::ToBase64String($keyBytes) + ' fixture-only'
    foreach ($family in @($p.network.value.subnetPairs.Keys)) {
        $p.network.value.subnetPairs[$family] = @{ nic1 = "$family-an"; nic2 = "$family-normal" }
    }
    return $document
}

function New-ArtifactFixture {
    param([Parameter(Mandatory)] [string] $Directory, [string] $EnvironmentName = 'development')
    $null = New-Item -ItemType Directory -Path $Directory -Force
    Copy-Item -Path (Join-Path $script:Root '.build\iac\*.json') -Destination $Directory
    New-ConfiguredParameters $EnvironmentName | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $Directory "$EnvironmentName.parameters.json")
    Update-ArtifactFixture $Directory
    return $Directory
}

function Update-ArtifactFixture {
    param([Parameter(Mandatory)] [string] $Directory)
    $path = Join-Path $Directory 'manifest.json'
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    foreach ($file in @($manifest.files.Keys)) {
        $manifest.files[$file] = (Get-FileHash -LiteralPath (Join-Path $Directory $file) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
}
