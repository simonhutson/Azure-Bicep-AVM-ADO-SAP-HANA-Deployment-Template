#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('Plan', 'Deploy')] [string] $Operation,
    [Parameter(Mandatory)] [ValidateSet('development', 'test', 'production')] [string] $EnvironmentName,
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroupName,
    [Parameter(Mandatory)] [string] $ArtifactDirectory,
    [Parameter(Mandatory)] [string] $ReportDirectory,
    [Parameter(Mandatory)] [string] $SourceVersion,
    [Parameter(Mandatory)] [string] $DeploymentName,
    [string] $PlanDirectory
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-AzureJson {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $text = (& az @Arguments --only-show-errors --output json) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI operation failed: $($Arguments[0..([Math]::Min(2, $Arguments.Length - 1))] -join ' ')" }
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Azure CLI returned an empty response where JSON was required.' }
    return ($text | ConvertFrom-Json -AsHashtable)
}

function ConvertTo-OrderedValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object -CaseSensitive)) { $ordered[$key] = ConvertTo-OrderedValue $Value[$key] }
        return $ordered
    }
    if ($Value -is [array]) { return ,@($Value | ForEach-Object { ConvertTo-OrderedValue $_ }) }
    return $Value
}

function Get-WhatIfDigest {
    param([System.Collections.IDictionary] $Result)
    if ($Result.status -ne 'Succeeded' -or -not $Result.Contains('changes')) { throw 'What-if did not produce a successful, inspectable change set.' }
    $blocked = @($Result.changes | Where-Object changeType -In @('Delete', 'Unsupported'))
    if ($blocked.Count -gt 0) { throw 'What-if includes a deletion or unsupported change. Resolve it before deployment; this pipeline never bypasses this guard.' }
    if (@($Result.changes | Where-Object { $_.changeType -notin @('Create', 'Modify', 'NoChange', 'Ignore') }).Count -gt 0) {
        throw 'What-if returned an unrecognized change type.'
    }
    if (@($Result.changes | Where-Object changeType -EQ 'Ignore').Count -gt 0) {
        throw 'What-if could not inspect every change (Ignore result). Resolve incomplete evaluation before approval.'
    }
    $changes = @($Result.changes | Where-Object changeType -NE 'NoChange' | Sort-Object resourceId)
    $canonical = ConvertTo-OrderedValue $changes | ConvertTo-Json -Depth 100 -Compress
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant()
}

$manifestPath = Join-Path $ArtifactDirectory 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
if ($manifest.sourceVersion -cne $SourceVersion) { throw 'Artifact commit does not match this pipeline run.' }
$expectedFiles = @('catalog.json', 'main.json', 'development.portal.json', 'development.parameters.json', 'test.parameters.json', 'production.parameters.json')
if (@(Compare-Object ($expectedFiles | Sort-Object) @($manifest.files.Keys | Sort-Object)).Count -gt 0) { throw 'Artifact manifest has an unexpected file set.' }
foreach ($file in $expectedFiles) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $ArtifactDirectory $file) -Algorithm SHA256).Hash
    if ($hash -ine $manifest.files[$file]) { throw "Artifact checksum mismatch: $file" }
}
$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
if ($SubscriptionId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
    [string]::IsNullOrWhiteSpace($ResourceGroupName) -or $ResourceGroupName -match 'REQUIRED_') {
    throw 'Configure a real target subscription ID and existing resource group in the environment pipeline variables.'
}
if ($DeploymentName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$') { throw 'Invalid ARM deployment name.' }

$parametersPath = Join-Path $ArtifactDirectory "$EnvironmentName.parameters.json"
$templatePath = Join-Path $ArtifactDirectory 'main.json'
$configuration = & (Join-Path $PSScriptRoot 'Test-Configuration.ps1') -ParametersFile $parametersPath -CatalogFile (Join-Path $ArtifactDirectory 'catalog.json') -EnvironmentName $EnvironmentName
$account = Invoke-AzureJson @('account', 'show')
if ($account.id -ine $SubscriptionId) { throw 'Service connection is authenticated to the wrong subscription. No subscription switch or deployment was attempted.' }
$null = Invoke-AzureJson @('group', 'show', '--name', $ResourceGroupName)
$tools = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\tools.psd1')
$cli = Invoke-AzureJson @('version')
if ([version]$cli.'azure-cli' -lt [version]$tools.MinimumAzureCliVersion) { throw "Azure CLI $($tools.MinimumAzureCliVersion) or newer is required." }

if ($Operation -eq 'Plan') {
    $image = $configuration.image
    $urn = "$($image.publisher):$($image.offer):$($image.sku):$($image.version)"
    $imageMetadata = Invoke-AzureJson @('vm', 'image', 'show', '--location', $configuration.location, '--urn', $urn)
    if ($imageMetadata.hyperVGeneration -cne 'V2') { throw 'The marketplace image is not Gen2, as required by this SAP VM policy.' }
    if ($null -ne $imageMetadata.plan) {
        if ($null -eq $configuration.marketplacePlan) { throw 'Configure marketplacePlan to match the selected image and accept its terms before deployment.' }
        foreach ($key in 'name', 'publisher', 'product') {
            if ($configuration.marketplacePlan[$key] -cne $imageMetadata.plan[$key]) { throw 'Configure marketplacePlan to match the selected image and accept its terms before deployment.' }
        }
    }
    if ($configuration.encryptionAtHost) {
        $feature = Invoke-AzureJson @('feature', 'show', '--namespace', 'Microsoft.Compute', '--name', 'EncryptionAtHost')
        if ($feature.properties.state -ne 'Registered') { throw 'Register Microsoft.Compute/EncryptionAtHost through your platform administration process before deployment.' }
    }
    $vnet = Invoke-AzureJson @('network', 'vnet', 'show', '--resource-group', $configuration.network.resourceGroupName, '--name', $configuration.network.virtualNetworkName)
    if ($vnet.location -ine $configuration.location) { throw 'VM and existing VNet regions must match.' }
    $catalog = Get-Content -LiteralPath (Join-Path $ArtifactDirectory 'catalog.json') -Raw | ConvertFrom-Json -AsHashtable
    foreach ($family in @($configuration.virtualMachines | ForEach-Object { $catalog.roles[$_.role].network } | Sort-Object -Unique)) {
        foreach ($nic in 'nic1', 'nic2') {
            $subnetName = $configuration.network.subnetPairs[$family][$nic]
            if (@($vnet.subnets | Where-Object name -EQ $subnetName).Count -ne 1) { throw "Required subnet '$subnetName' does not exist in the configured VNet." }
        }
    }
    $requiredSizes = @($configuration.virtualMachines.vmSize | Sort-Object -Unique)
    $skuFilter = '[?' + (($requiredSizes | ForEach-Object { "name=='$_'" }) -join ' || ') + ']'
    $availableSkus = @(Invoke-AzureJson @('vm', 'list-skus', '--location', $configuration.location, '--resource-type', 'virtualMachines', '--all', '--query', $skuFilter))
    foreach ($size in $requiredSizes) {
        $matches = @($availableSkus | Where-Object name -CEQ $size)
        if ($matches.Count -ne 1) { throw "VM SKU '$size' is not uniquely available in '$($configuration.location)' for this subscription." }
        $sku = $matches[0]
        $locationRestrictions = @($sku.restrictions | Where-Object {
            $_.type -eq 'Location' -and (
                $_.values -contains $configuration.location -or
                $_.restrictionInfo.locations -contains $configuration.location -or
                ($null -eq $_.values -and $null -eq $_.restrictionInfo.locations)
            )
        })
        if ($locationRestrictions.Count -gt 0) { throw "VM SKU '$size' has a subscription/location restriction. Request availability or select another policy-approved SKU." }
        $capabilities = @{}
        foreach ($capability in $sku.capabilities) { $capabilities[$capability.name] = $capability.value }
        if ($capabilities.CpuArchitectureType -ine 'x64' -or ($capabilities.HyperVGenerations -split ',') -notcontains 'V2') {
            throw "VM SKU '$size' must support x64 Gen2 guests."
        }
        if ([int]$capabilities.MaxNetworkInterfaces -lt 2 -or $capabilities.PremiumIO -ine 'True') {
            throw "VM SKU '$size' must support two NICs and Premium storage."
        }
        if ($configuration.encryptionAtHost -and $capabilities.EncryptionAtHostSupported -ine 'True') {
            throw "VM SKU '$size' does not advertise encryption-at-host support."
        }
        foreach ($requested in @($configuration.virtualMachines | Where-Object vmSize -CEQ $size)) {
            $profile = $catalog.roles[$requested.role]
            $diskSizes = $requested.dataDiskSizesGB ?? $profile.dataDiskSizesGB
            if ([int]$capabilities.MaxDataDiskCount -lt $diskSizes.Count) { throw "VM SKU '$size' cannot attach the requested $($diskSizes.Count) data disks for '$($requested.role)'." }
            if ($profile.category -eq 'han' -and $capabilities.AcceleratedNetworkingEnabled -ine 'True') {
                throw "VM SKU '$size' must support accelerated networking for HANA roles."
            }
        }
    }
}

$deploymentArgs = @('--resource-group', $ResourceGroupName, '--name', $DeploymentName, '--template-file', $templatePath, '--parameters', "@$parametersPath")
$validationLevel = if ($Operation -eq 'Plan') { 'ProviderNoRbac' } else { 'Provider' }
$null = Invoke-AzureJson (@('deployment', 'group', 'validate') + $deploymentArgs + @('--validation-level', $validationLevel))
$whatIf = Invoke-AzureJson (@('deployment', 'group', 'what-if') + $deploymentArgs + @('--validation-level', $validationLevel, '--result-format', 'FullResourcePayloads', '--no-pretty-print'))
$changeDigest = Get-WhatIfDigest $whatIf
$null = New-Item -ItemType Directory -Path $ReportDirectory -Force
$whatIf | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $ReportDirectory 'what-if.json') -Encoding utf8

if ($Operation -eq 'Plan') {
    [ordered]@{
        sourceVersion = $SourceVersion
        environmentName = $EnvironmentName
        subscriptionId = $SubscriptionId
        resourceGroupName = $ResourceGroupName
        deploymentName = $DeploymentName
        manifestHash = $manifestHash
        changeDigest = $changeDigest
        vmCount = $configuration.virtualMachines.Count
        sapSupportReviewReference = $configuration.sapSupportReviewReference
        vmSelections = @($configuration.virtualMachines | ForEach-Object { @{ role = $_.role; instance = $_.instance; vmSize = $_.vmSize } })
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ReportDirectory 'plan.json') -Encoding utf8
    Write-Host "Plan validated. Review what-if.json before approving $EnvironmentName deployment."
    return
}

if ([string]::IsNullOrWhiteSpace($PlanDirectory)) { throw 'Deploy requires the previously published plan artifact.' }
$plan = Get-Content -LiteralPath (Join-Path $PlanDirectory 'plan.json') -Raw | ConvertFrom-Json -AsHashtable
foreach ($check in @{
    sourceVersion = $SourceVersion
    environmentName = $EnvironmentName
    subscriptionId = $SubscriptionId
    resourceGroupName = $ResourceGroupName
    deploymentName = $DeploymentName
    manifestHash = $manifestHash
    changeDigest = $changeDigest
}.GetEnumerator()) {
    if ($plan[$check.Key] -ine $check.Value) { throw "Approved plan no longer matches '$($check.Key)'. Rerun planning and approval; no deployment was attempted." }
}

$deployment = Invoke-AzureJson (@('deployment', 'group', 'create') + $deploymentArgs + @('--mode', 'Incremental'))
if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'ARM deployment did not reach Succeeded.' }
$outputs = @($deployment.properties.outputs.virtualMachineResources.value)
if ($outputs.Count -ne $configuration.virtualMachines.Count) { throw 'Deployment VM output count does not match the request.' }
$catalog = Get-Content -LiteralPath (Join-Path $ArtifactDirectory 'catalog.json') -Raw | ConvertFrom-Json -AsHashtable
for ($index = 0; $index -lt $outputs.Count; $index++) {
    $vm = Invoke-AzureJson @('vm', 'show', '--ids', $outputs[$index].resourceId)
    $requested = $configuration.virtualMachines[$index]
    $diskSizes = $requested.dataDiskSizesGB ?? $catalog.roles[$requested.role].dataDiskSizesGB
    if ($vm.provisioningState -ne 'Succeeded' -or $vm.hardwareProfile.vmSize -cne $requested.vmSize -or $vm.networkProfile.networkInterfaces.Count -ne 2 -or
        $vm.storageProfile.dataDisks.Count -ne $diskSizes.Count -or $vm.osProfile.linuxConfiguration.disablePasswordAuthentication -ne $true) {
        throw "Infrastructure post-deployment verification failed for '$($vm.name)'."
    }
    $actualSizes = @($vm.storageProfile.dataDisks | Sort-Object lun | ForEach-Object diskSizeGb)
    if (($actualSizes -join ',') -cne ($diskSizes -join ',')) { throw "Data disk capacities/order differ for '$($vm.name)'." }
}
[ordered]@{
    deploymentId = $deployment.id
    provisioningState = $deployment.properties.provisioningState
    virtualMachines = $outputs
    sapReadinessVerified = $false
} | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $ReportDirectory 'deployment.json') -Encoding utf8
Write-Host 'Infrastructure verified. Guest onboarding, filesystem readiness and SAP/HANA readiness require separate checks.'
