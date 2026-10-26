BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    $portalPath = Join-Path $Root '.build\iac\development.portal.json'
    $publishedPath = Join-Path $Root 'infra\portal\development.json'
    $portalText = Get-Content -LiteralPath $portalPath -Raw
    $publishedText = Get-Content -LiteralPath $publishedPath -Raw
    $portal = $portalText | ConvertFrom-Json -AsHashtable
    $main = Get-Content -LiteralPath (Join-Path $Root '.build\iac\main.json') -Raw | ConvertFrom-Json -AsHashtable
    $development = (Get-Content -LiteralPath (Join-Path $Root '.build\iac\development.parameters.json') -Raw | ConvertFrom-Json -AsHashtable).parameters
    $module = if ($portal.resources -is [System.Collections.IDictionary]) { $portal.resources.infrastructure } else { $portal.resources[0] }
    $bindings = $module.properties.parameters
}

Describe 'Modern development portal deployment' {
    It 'publishes the current compiler output within the ARM template size limit' {
        ($publishedText | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress) |
            Should -BeExactly ($portalText | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress)
        (Get-Item -LiteralPath $publishedPath).Length | Should -BeLessThan (4 * 1024 * 1024)
        $portal.metadata._generator.name | Should -Be 'bicep'
    }

    It 'inlines the shared implementation without archive or remote template dependencies' {
        $portal.resources.Count | Should -Be 1
        ($module.properties.template | ConvertTo-Json -Depth 100 -Compress) |
            Should -BeExactly ($main | ConvertTo-Json -Depth 100 -Compress)
        $module.properties.expressionEvaluationOptions.scope | Should -Be 'inner'
        $portalText | Should -Not -Match '"templateLink"|archive/|sles-bootstrap-|REQUIRED_'
    }

    It 'fixes the development environment, host encryption and disabled bootstrap' {
        $bindings.environmentName.value | Should -Be 'development'
        $bindings.encryptionAtHost.value | Should -BeTrue
        $bindings.bootstrap.value.mode | Should -Be 'disabled'
        foreach ($name in 'environmentName', 'virtualMachines', 'vmSize', 'dataDiskSizesGB', 'bootstrap', 'encryptionAtHost') {
            $portal.parameters.ContainsKey($name) | Should -BeFalse
        }
    }

    It 'matches the current development preset and ordinary defaults' {
        $catalogReference = [regex]::Match($portal.variables.catalog, "^\[variables\('([^']+)'\)\]$")
        $catalogReference.Success | Should -BeTrue
        $preset = $portal.variables[$catalogReference.Groups[1].Value].landscapes.cloudConnector
        $preset.Count | Should -Be 1
        (ConvertTo-Json -InputObject $preset -Depth 10 -Compress) |
            Should -BeExactly (ConvertTo-Json -InputObject $development.virtualMachines.value -Depth 10 -Compress)
        $bindings.virtualMachines.value | Should -Be "[variables('catalog').landscapes.cloudConnector]"
        foreach ($name in 'location', 'namePrefix', 'adminUsername') {
            $portal.parameters[$name].defaultValue | Should -Be $development[$name].value
        }
        $portal.parameters.projectName.defaultValue | Should -Be $development.ownership.value.projectName
        $portal.parameters.deploymentNumber.defaultValue | Should -Be ([int]$development.deploymentNumber.value)
    }

    It 'requires site-specific inputs rather than publishing configuration placeholders' {
        foreach ($name in 'sshPublicKey', 'imageBuildVersion', 'networkResourceGroupName', 'virtualNetworkName',
            'nic1SubnetName', 'nic2SubnetName', 'serviceOwner', 'serviceTicketRequestId', 'costCodeId', 'sapSupportReviewReference') {
            $portal.parameters.ContainsKey($name) | Should -BeTrue
            $portal.parameters[$name].ContainsKey('defaultValue') | Should -BeFalse
        }
        $portal.parameters.ContainsKey('adminPassword') | Should -BeFalse
        $portal.variables.subnetPair.nic1 | Should -Be "[parameters('nic1SubnetName')]"
        $portal.variables.subnetPair.nic2 | Should -Be "[parameters('nic2SubnetName')]"
        $bindings.network.value.subnetPairs.cloudConnector | Should -Be "[variables('subnetPair')]"
    }

    It 'constructs an exact SLES for SAP image version from numeric components' {
        foreach ($name in 'publisher', 'offer', 'sku') {
            $bindings.image.value[$name] | Should -Be $development.image.value[$name]
        }
        foreach ($name in 'imageMajorVersion', 'imageMinorVersion', 'imageBuildVersion') {
            $portal.parameters[$name].type | Should -Be 'int'
            $portal.parameters[$name].minValue | Should -Be 0
        }
        $bindings.image.value.version |
            Should -Be "[format('{0}.{1}.{2}', parameters('imageMajorVersion'), parameters('imageMinorVersion'), parameters('imageBuildVersion'))]"
    }

    It 'limits deployment numbers to two numeric digits' {
        $portal.parameters.deploymentNumber.type | Should -Be 'int'
        $portal.parameters.deploymentNumber.minValue | Should -Be 0
        $portal.parameters.deploymentNumber.maxValue | Should -Be 99
        $bindings.deploymentNumber.value | Should -Be "[padLeft(parameters('deploymentNumber'), 2, '0')]"
    }

    It 'forwards a marketplace purchase plan only when the selected image requires one' {
        $portal.parameters.ContainsKey('marketplacePlan') | Should -BeTrue
        $portal.parameters.marketplacePlan.defaultValue | Should -BeNullOrEmpty
        $bindings.marketplacePlan.value | Should -Be "[parameters('marketplacePlan')]"
    }

    It 'identifies portal deployments without changing the existing pipeline Source default' {
        $bindings.deploymentSource.value | Should -Be 'Azure portal / Bicep AVM'
        $main.parameters.deploymentSource.defaultValue | Should -Be 'Azure DevOps / Bicep AVM'
        $main.variables.commonTags | Should -Match "'Source', parameters\('deploymentSource'\)"
    }

    It 'includes the portal build in the checksummed artifact' {
        $manifest = Get-Content -LiteralPath (Join-Path $Root '.build\iac\manifest.json') -Raw | ConvertFrom-Json -AsHashtable
        $manifest.files.ContainsKey('development.portal.json') | Should -BeTrue
        $manifest.files['development.portal.json'] | Should -Be (Get-FileHash -LiteralPath $portalPath -Algorithm SHA256).Hash
    }

    It 'links the modern README button to the published template rather than the archive' {
        $readme = Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw
        [xml]$html = '<root>' + $readme.Replace('<br>', '<br />') + '</root>'
        $buttons = @($html.SelectNodes('//a[starts-with(@href, "https://portal.azure.com/#create/Microsoft.Template/uri/")]'))
        $buttons.Count | Should -Be 10
        $modern = @($buttons | Where-Object href -Match '%2Finfra%2Fportal%2Fdevelopment\.json$')
        $modern.Count | Should -Be 1
        [Uri]::UnescapeDataString($modern[0].href) |
            Should -Be 'https://portal.azure.com/#create/Microsoft.Template/uri/https://raw.githubusercontent.com/simonhutson/Azure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template/main/infra/portal/development.json'
        $readme | Should -Not -Match 'SAP HANA Dev Test\.png'
    }
}
