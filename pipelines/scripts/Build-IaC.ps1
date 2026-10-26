#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\.build\iac'),
    [string] $SourceVersion = $env:BUILD_SOURCEVERSION
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tools = Import-PowerShellDataFile (Join-Path $root 'pipelines\tools.psd1')

$versionText = (& az bicep version --only-show-errors) -join "`n"
if ($LASTEXITCODE -ne 0 -or $versionText -notmatch "Bicep CLI version $([regex]::Escape($tools.BicepVersion))\b") {
    throw "Install the pinned Bicep compiler: az bicep install --version v$($tools.BicepVersion)"
}

if ([string]::IsNullOrWhiteSpace($SourceVersion)) {
    $SourceVersion = (& git -C $root rev-parse --verify HEAD) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the source commit for the artifact.' }
}
if ($SourceVersion -notmatch '^[0-9a-f]{40}$') { throw 'A full source commit SHA is required.' }

$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$files = @('main.json', 'catalog.json', 'development.parameters.json', 'test.parameters.json', 'production.parameters.json')
$unexpected = @(Get-ChildItem -LiteralPath $OutputDirectory -Force | Where-Object Name -NotIn ($files + 'manifest.json'))
if ($unexpected.Count -gt 0) { throw 'Output directory contains unrelated files. Select a dedicated build directory.' }

& az bicep build --file (Join-Path $root 'infra\main.bicep') --outfile (Join-Path $OutputDirectory 'main.json') --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Bicep build/lint failed.' }
foreach ($environment in 'development', 'test', 'production') {
    & az bicep build-params --file (Join-Path $root "infra\environments\$environment.bicepparam") --outfile (Join-Path $OutputDirectory "$environment.parameters.json") --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Bicep parameter build failed for $environment." }
}
Copy-Item -LiteralPath (Join-Path $root 'infra\catalog.json') -Destination (Join-Path $OutputDirectory 'catalog.json')

$hashes = [ordered]@{}
foreach ($file in $files) {
    $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $file) -Algorithm SHA256).Hash.ToLowerInvariant()
}
[ordered]@{
    sourceVersion = $SourceVersion
    bicepVersion = $tools.BicepVersion
    files = $hashes
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Encoding utf8

Write-Host "Compiled all environments with Bicep $($tools.BicepVersion). Artifact: $OutputDirectory"
