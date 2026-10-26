#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '..\..\.build\iac'),
    [string] $SourceVersion = $env:BUILD_SOURCEVERSION,
    [switch] $UpdatePortalTemplate
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
$files = @('main.json', 'development.portal.json', 'catalog.json', 'development.parameters.json', 'test.parameters.json', 'production.parameters.json')
$unexpected = @(Get-ChildItem -LiteralPath $OutputDirectory -Force | Where-Object Name -NotIn ($files + 'manifest.json'))
if ($unexpected.Count -gt 0) { throw 'Output directory contains unrelated files. Select a dedicated build directory.' }

& az bicep build --file (Join-Path $root 'infra\main.bicep') --outfile (Join-Path $OutputDirectory 'main.json') --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Bicep build/lint failed.' }
& az bicep build --file (Join-Path $root 'infra\portal\development.bicep') --outfile (Join-Path $OutputDirectory 'development.portal.json') --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Development portal build/lint failed.' }
foreach ($environment in 'development', 'test', 'production') {
    & az bicep build-params --file (Join-Path $root "infra\environments\$environment.bicepparam") --outfile (Join-Path $OutputDirectory "$environment.parameters.json") --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Bicep parameter build failed for $environment." }
}
Copy-Item -LiteralPath (Join-Path $root 'infra\catalog.json') -Destination (Join-Path $OutputDirectory 'catalog.json')
if ($UpdatePortalTemplate) {
    $profiles = [ordered]@{
        single = 'single.json'
        full = 'full.json'
        netweaverGateway = 'netweaver-gateway.json'
        gatewayFes = 'gateway-fes.json'
        sapPo = 'sap-po.json'
        sapBw = 'sap-bw.json'
        utilities = 's4hana-utilities.json'
        cloudConnector = 'development.json'
        hybrisBilling = 's4hana-hybris-billing.json'
    }
    $portal = Get-Content -LiteralPath (Join-Path $OutputDirectory 'development.portal.json') -Raw | ConvertFrom-Json
    if (@(Compare-Object @($profiles.Keys | Sort-Object) @($portal.parameters.landscape.allowedValues | Sort-Object)).Count -gt 0) {
        throw 'Published portal profiles must match the profiles allowed by the Bicep entry point.'
    }
    # Profile defaults change after compilation, so the compiler hash must not describe the modified template.
    $portal.metadata._generator.PSObject.Properties.Remove('templateHash')
    foreach ($profile in $profiles.GetEnumerator()) {
        $portal.parameters.landscape.defaultValue = $profile.Key
        $portal.parameters.landscape.allowedValues = @($profile.Key)
        $portal.metadata | Add-Member -NotePropertyName portalProfile -NotePropertyValue $profile.Key -Force
        $portal | ConvertTo-Json -Depth 100 |
            Set-Content -LiteralPath (Join-Path $root "infra\portal\$($profile.Value)") -Encoding utf8
    }
    Write-Host "Refreshed $($profiles.Count) published development portal templates."
}

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
