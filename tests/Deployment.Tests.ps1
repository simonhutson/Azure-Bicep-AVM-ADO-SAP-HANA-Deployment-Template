BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    . (Join-Path $PSScriptRoot 'Fixtures.ps1')
    $script:DeployScript = Join-Path $Root 'pipelines\scripts\Invoke-Deployment.ps1'
    function az { param([Parameter(ValueFromRemainingArguments)] [object[]] $Arguments) throw 'Tests must mock every Azure CLI call.' }
}

Describe 'Plan/apply orchestration without Azure access' {
    BeforeEach {
        $script:Fixture = New-ArtifactFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        $script:Arguments = @{
            EnvironmentName = 'development'
            SubscriptionId = '11111111-1111-1111-1111-111111111111'
            ResourceGroupName = 'rg-sap-dev'
            ArtifactDirectory = $Fixture
            ReportDirectory = Join-Path $Fixture 'plan'
            SourceVersion = (Get-Content (Join-Path $Fixture 'manifest.json') -Raw | ConvertFrom-Json).sourceVersion
            DeploymentName = 'sap-development-123'
        }
        $state = @{
            Calls = [System.Collections.Generic.List[string]]::new()
            AccountId = $Arguments.SubscriptionId
            AzureFailure = $false
            VmProvisioningState = 'Succeeded'
            FeatureState = 'Registered'
            VnetLocation = 'uksouth'
            Subnets = @(@{ name = 'cloudConnector-an' }, @{ name = 'cloudConnector-normal' })
            ImagePlan = $null
            ImageHyperVGeneration = 'V2'
            VmSize = 'Standard_E4ds_v5'
            Skus = @(@{
                name = 'Standard_E4ds_v5'
                restrictions = @()
                capabilities = @(
                    @{ name = 'CpuArchitectureType'; value = 'x64' }
                    @{ name = 'HyperVGenerations'; value = 'V1,V2' }
                    @{ name = 'MaxNetworkInterfaces'; value = '2' }
                    @{ name = 'MaxDataDiskCount'; value = '64' }
                    @{ name = 'PremiumIO'; value = 'True' }
                    @{ name = 'EncryptionAtHostSupported'; value = 'True' }
                    @{ name = 'AcceleratedNetworkingEnabled'; value = 'True' }
                )
            })
            CliVersion = '2.80.0'
            WhatIfResult = @{
                status = 'Succeeded'
                changes = @(@{ resourceId = '/subscriptions/example/resourceGroups/rg-sap-dev/providers/Microsoft.Compute/virtualMachines/azsu-d-sap209'; changeType = 'Create'; after = @{ name = 'azsu-d-sap209'; properties = @{ size = 'Standard_E4ds_v5' } } })
            }
        }
        Mock az ({
            param([object[]] $Arguments)
            $command = ($Arguments | Select-Object -First 3) -join ' '
            $state.Calls.Add($command)
            $global:LASTEXITCODE = 0
            if ($state.AzureFailure) { $global:LASTEXITCODE = 1; return '' }
            $result = switch -Wildcard ($command) {
                'account show*' { @{ id = $state.AccountId }; break }
                'group show*' { @{ name = 'rg-sap-dev' }; break }
                'version*' { @{ 'azure-cli' = $state.CliVersion }; break }
                'vm image show' { @{ name = '15.6.2026010101'; plan = $state.ImagePlan; hyperVGeneration = $state.ImageHyperVGeneration }; break }
                'vm list-skus*' { return (ConvertTo-Json -InputObject @($state.Skus) -Depth 100 -Compress) }
                'feature show*' { @{ properties = @{ state = $state.FeatureState } }; break }
                'network vnet show' { @{ location = $state.VnetLocation; subnets = $state.Subnets }; break }
                'deployment group validate' { @{ properties = @{ provisioningState = 'Succeeded' } }; break }
                'deployment group what-if' { $state.WhatIfResult; break }
                'deployment group create' {
                    @{ id = '/deployments/example'; properties = @{ provisioningState = 'Succeeded'; outputs = @{ virtualMachineResources = @{ value = @(@{ role = 'app-cloud-connector'; name = 'azsu-d-sap209'; resourceId = '/vms/example' }) } } } }
                    break
                }
                'vm show*' {
                    @{
                        name = 'azsu-d-sap209'
                        provisioningState = $state.VmProvisioningState
                        hardwareProfile = @{ vmSize = $state.VmSize }
                        networkProfile = @{ networkInterfaces = @(@{}, @{}) }
                        osProfile = @{ linuxConfiguration = @{ disablePasswordAuthentication = $true } }
                        storageProfile = @{ dataDisks = @(@{ lun = 0; diskSizeGb = 32 }, @{ lun = 1; diskSizeGb = 32 }, @{ lun = 2; diskSizeGb = 64 }) }
                    }
                    break
                }
                default { throw "Unmocked Azure operation: $command" }
            }
            return ($result | ConvertTo-Json -Depth 100 -Compress)
        }.GetNewClosure())
    }
    It 'validates and plans without a create operation' {
        & $DeployScript -Operation Plan @Arguments
        Test-Path (Join-Path $Arguments.ReportDirectory 'what-if.json') | Should -BeTrue
        Test-Path (Join-Path $Arguments.ReportDirectory 'plan.json') | Should -BeTrue
        $state.Calls | Should -Contain 'deployment group validate'
        $state.Calls | Should -Contain 'deployment group what-if'
        $state.Calls | Should -Not -Contain 'deployment group create'
        $plan = Get-Content (Join-Path $Arguments.ReportDirectory 'plan.json') -Raw | ConvertFrom-Json
        $plan.vmSelections[0].vmSize | Should -Be 'Standard_E4ds_v5'
        $plan.sapSupportReviewReference | Should -Be 'configured'
    }
    It 'applies only the matching plan after a fresh what-if and verifies the VMs' {
        & $DeployScript -Operation Plan @Arguments
        $planDirectory = $Arguments.ReportDirectory
        $Arguments.ReportDirectory = Join-Path $Fixture 'deployed'
        & $DeployScript -Operation Deploy -PlanDirectory $planDirectory @Arguments
        $state.Calls | Should -Contain 'deployment group create'
        @($state.Calls | Where-Object { $_ -eq 'deployment group what-if' }).Count | Should -Be 2
        $result = Get-Content (Join-Path $Arguments.ReportDirectory 'deployment.json') -Raw | ConvertFrom-Json
        $result.sapReadinessVerified | Should -BeFalse
        $result.provisioningState | Should -Be 'Succeeded'
    }
    It 'fails before Azure access when an artifact is changed' {
        Add-Content -LiteralPath (Join-Path $Fixture 'main.json') -Value ' '
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*checksum mismatch*'
        $state.Calls.Count | Should -Be 0
    }
    It 'fails before Azure access when the commit binding is wrong' {
        $Arguments.SourceVersion = 'f' * 40
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*Artifact commit*'
        $state.Calls.Count | Should -Be 0
    }
    It 'does not switch subscriptions or deploy with the wrong service connection' {
        $state.AccountId = '22222222-2222-2222-2222-222222222222'
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*wrong subscription*'
        @($state.Calls | Where-Object { $_ -match 'deployment group|account set' }).Count | Should -Be 0
    }
    It 'surfaces CLI errors rather than manufacturing a successful plan' {
        $state.AzureFailure = $true
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*Azure CLI operation failed*'
        Test-Path (Join-Path $Arguments.ReportDirectory 'plan.json') | Should -BeFalse
    }
    It 'blocks incomplete or destructive what-if result <ChangeType>' -ForEach @(
        @{ ChangeType = 'Delete' }, @{ ChangeType = 'Unsupported' }, @{ ChangeType = 'Ignore' }, @{ ChangeType = 'Unexpected' }
    ) {
        $state.WhatIfResult.changes[0].changeType = $ChangeType
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*What-if*'
        $state.Calls | Should -Not -Contain 'deployment group create'
    }
    It 'does not apply a changed plan after approval' {
        & $DeployScript -Operation Plan @Arguments
        $state.WhatIfResult.changes[0].after.properties.size = 'Standard_E8ds_v5'
        { & $DeployScript -Operation Deploy -PlanDirectory $Arguments.ReportDirectory @Arguments } | Should -Throw '*changeDigest*'
        $state.Calls | Should -Not -Contain 'deployment group create'
    }
    It 'handles a successful no-change plan and repeat apply' {
        $state.WhatIfResult.changes = @()
        & $DeployScript -Operation Plan @Arguments
        { & $DeployScript -Operation Deploy -PlanDirectory $Arguments.ReportDirectory @Arguments } | Should -Not -Throw
    }
    It 'requires a published plan for apply' {
        { & $DeployScript -Operation Deploy @Arguments } | Should -Throw '*previously published plan*'
        $state.Calls | Should -Not -Contain 'deployment group create'
    }
    It 'does not apply a plan for another resource group' {
        & $DeployScript -Operation Plan @Arguments
        $Arguments.ResourceGroupName = 'rg-other'
        { & $DeployScript -Operation Deploy -PlanDirectory $Arguments.ReportDirectory @Arguments } | Should -Throw '*resourceGroupName*'
        $state.Calls | Should -Not -Contain 'deployment group create'
    }
    It 'rejects an unregistered host-encryption feature before validation' {
        $state.FeatureState = 'NotRegistered'
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*EncryptionAtHost*'
        $state.Calls | Should -Not -Contain 'deployment group validate'
    }
    It 'rejects an image that requires an unconfigured marketplace plan' {
        $state.ImagePlan = @{ name = 'gen2'; publisher = 'SUSE'; product = 'sles-sap-15-sp6-byos' }
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*marketplacePlan*'
        $state.Calls | Should -Not -Contain 'deployment group validate'
    }
    It 'rejects a VNet in a different region' {
        $state.VnetLocation = 'ukwest'
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*regions must match*'
    }
    It 'rejects a missing subnet without creating networking' {
        $state.Subnets = @()
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*does not exist*'
        $state.Calls | Should -Not -Contain 'deployment group create'
    }
    It 'requires an Azure CLI version with provider-level validation support' {
        $state.CliVersion = '2.75.0'
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*2.76.0 or newer*'
    }
    It 'rejects a regional image whose metadata is Gen1' {
        $state.ImageHyperVGeneration = 'V1'
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*marketplace image is not Gen2*'
    }
    It 'rejects a policy-approved SKU unavailable to the selected subscription/region' {
        $state.Skus = @()
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*not uniquely available*'
        $state.Calls | Should -Not -Contain 'deployment group validate'
    }
    It 'rejects subscription-restricted SKU capacity before ARM validation' {
        $state.Skus[0].restrictions = @(@{ type = 'Location'; values = @('uksouth'); reasonCode = 'NotAvailableForSubscription' })
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*subscription/location restriction*'
    }
    It 'does not reject irrelevant zone-only restrictions for availability-set deployment' {
        $state.Skus[0].restrictions = @(@{ type = 'Zone'; values = @('uksouth'); restrictionInfo = @{ locations = @('uksouth'); zones = @('3') } })
        { & $DeployScript -Operation Plan @Arguments } | Should -Not -Throw
    }
    It 'checks actual platform capabilities for <Capability>' -ForEach @(
        @{ Capability = 'CpuArchitectureType'; Value = 'Arm64'; ExpectedMessage = '*x64 Gen2*' },
        @{ Capability = 'HyperVGenerations'; Value = 'V1'; ExpectedMessage = '*x64 Gen2*' },
        @{ Capability = 'MaxNetworkInterfaces'; Value = '1'; ExpectedMessage = '*two NICs*' },
        @{ Capability = 'MaxDataDiskCount'; Value = '2'; ExpectedMessage = '*cannot attach*' },
        @{ Capability = 'PremiumIO'; Value = 'False'; ExpectedMessage = '*Premium storage*' },
        @{ Capability = 'EncryptionAtHostSupported'; Value = 'False'; ExpectedMessage = '*encryption-at-host*' }
    ) {
        ($state.Skus[0].capabilities | Where-Object name -EQ $Capability).value = $Value
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw $ExpectedMessage
        $state.Calls | Should -Not -Contain 'deployment group create'
    }
    It 'checks accelerated networking when the selected role is HANA' {
        $file = Join-Path $Fixture 'development.parameters.json'
        $doc = Get-Content $file -Raw | ConvertFrom-Json -AsHashtable
        $doc.parameters.virtualMachines.value[0].role = 'db-nw-gateway'
        $doc | ConvertTo-Json -Depth 100 | Set-Content $file
        Update-ArtifactFixture $Fixture
        $state.Subnets = @(@{ name = 'gateway-an' }, @{ name = 'gateway-normal' })
        $state.Skus[0].name = 'Standard_E8ds_v5'
        ($state.Skus[0].capabilities | Where-Object name -EQ 'AcceleratedNetworkingEnabled').value = 'False'
        { & $DeployScript -Operation Plan @Arguments } | Should -Throw '*accelerated networking*'
    }
    It 'normalizes JSON property order before checking an unchanged approved plan' {
        & $DeployScript -Operation Plan @Arguments
        $state.WhatIfResult.changes = @(@{ after = @{ properties = @{ size = 'Standard_E4ds_v5' }; name = 'azsu-d-sap209' }; changeType = 'Create'; resourceId = '/subscriptions/example/resourceGroups/rg-sap-dev/providers/Microsoft.Compute/virtualMachines/azsu-d-sap209' })
        { & $DeployScript -Operation Deploy -PlanDirectory $Arguments.ReportDirectory @Arguments } | Should -Not -Throw
    }
    It 'does not claim verification success when a VM failed' {
        & $DeployScript -Operation Plan @Arguments
        $state.VmProvisioningState = 'Failed'
        { & $DeployScript -Operation Deploy -PlanDirectory $Arguments.ReportDirectory @Arguments } | Should -Throw '*post-deployment verification failed*'
        Test-Path (Join-Path $Arguments.ReportDirectory 'deployment.json') | Should -BeFalse
    }
    It 'verifies that the VM actually uses the planned size' {
        & $DeployScript -Operation Plan @Arguments
        $state.VmSize = 'Standard_E8ds_v5'
        { & $DeployScript -Operation Deploy -PlanDirectory $Arguments.ReportDirectory @Arguments } | Should -Throw '*post-deployment verification failed*'
    }
}
