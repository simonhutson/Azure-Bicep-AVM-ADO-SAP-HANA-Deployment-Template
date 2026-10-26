BeforeDiscovery {
    $profiles = @(
        @{ Profile = 'single'; File = 'single.json'; Apps = 1; Databases = 0; Label = 'Deploy a SINGLE development VM (one selected application or database role)' },
        @{ Profile = 'full'; File = 'full.json'; Apps = 10; Databases = 6; Label = 'Deploy the FULL development landscape (10xApp, 6xDB; 16 VMs)' },
        @{ Profile = 'netweaverGateway'; File = 'netweaver-gateway.json'; Apps = 1; Databases = 1; Label = 'Deploy a NetWeaver Gateway Environment (1xApp, 1xDB)' },
        @{ Profile = 'gatewayFes'; File = 'gateway-fes.json'; Apps = 1; Databases = 1; Label = 'Deploy a Gateway FES Environment (1xApp, 1xDB)' },
        @{ Profile = 'sapPo'; File = 'sap-po.json'; Apps = 1; Databases = 1; Label = 'Deploy a SAP PO Environment (1xApp, 1xDB)' },
        @{ Profile = 'sapBw'; File = 'sap-bw.json'; Apps = 1; Databases = 1; Label = 'Deploy a SAP BW Environment (1xApp, 1xDB)' },
        @{ Profile = 'utilities'; File = 's4hana-utilities.json'; Apps = 1; Databases = 1; Label = 'Deploy a S/4HANA Utilities Environment (1xApp, 1xDB)' },
        @{ Profile = 'cloudConnector'; File = 'development.json'; Apps = 1; Databases = 0; Label = 'Deploy a Cloud Connector Environment (1xApp)' },
        @{ Profile = 'hybrisBilling'; File = 's4hana-hybris-billing.json'; Apps = 4; Databases = 1; Label = 'Deploy a S/4HANA Hybris Billing Environment (4xApp, 1xDB)' }
    )
}

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    $portalPath = Join-Path $Root '.build\iac\development.portal.json'
    $portalText = Get-Content -LiteralPath $portalPath -Raw
    $portal = $portalText | ConvertFrom-Json -AsHashtable
    $main = Get-Content -LiteralPath (Join-Path $Root '.build\iac\main.json') -Raw | ConvertFrom-Json -AsHashtable
    $development = (Get-Content -LiteralPath (Join-Path $Root '.build\iac\development.parameters.json') -Raw | ConvertFrom-Json -AsHashtable).parameters
    $module = if ($portal.resources -is [System.Collections.IDictionary]) { $portal.resources.infrastructure } else { $portal.resources[0] }
    $bindings = $module.properties.parameters
    $catalogReference = [regex]::Match($portal.variables.catalog, "^\[variables\('([^']+)'\)\]$")
    $compiledCatalog = $portal.variables[$catalogReference.Groups[1].Value]
    $readme = Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw
    [xml]$html = '<root>' + $readme.Replace('<br>', '<br />') + '</root>'
    $portalPrefix = 'https://portal.azure.com/#create/Microsoft.Template/uri/'
    $rawPrefix = 'https://raw.githubusercontent.com/simonhutson/Azure-Bicep-AVM-ADO-SAP-HANA-Deployment-Template/main/infra/portal/'
    $buttons = @($html.SelectNodes('//a[starts-with(@href, "https://portal.azure.com/#create/Microsoft.Template/uri/")]'))
}

Describe 'Modern development portal deployment' {
    It 'inlines the shared implementation without remote template dependencies' {
        $portal.resources.Count | Should -Be 1
        ($module.properties.template | ConvertTo-Json -Depth 100 -Compress) |
            Should -BeExactly ($main | ConvertTo-Json -Depth 100 -Compress)
        $module.properties.expressionEvaluationOptions.scope | Should -Be 'inner'
        $portalText | Should -Not -Match '"templateLink"|REQUIRED_'
    }

    It 'fixes the development environment, host encryption and disabled bootstrap' {
        $bindings.environmentName.value | Should -Be 'development'
        $bindings.encryptionAtHost.value | Should -BeTrue
        $bindings.bootstrap.value.mode | Should -Be 'disabled'
        foreach ($name in 'environmentName', 'virtualMachines', 'vmSize', 'dataDiskSizesGB', 'bootstrap', 'encryptionAtHost') {
            $portal.parameters.ContainsKey($name) | Should -BeFalse
        }
    }

    It 'matches the current development defaults and selects the requested catalogue profile' {
        $catalogReference.Success | Should -BeTrue
        $preset = $compiledCatalog.landscapes[$portal.parameters.landscape.defaultValue]
        $preset.Count | Should -Be 1
        (ConvertTo-Json -InputObject $preset -Depth 10 -Compress) |
            Should -BeExactly (ConvertTo-Json -InputObject $development.virtualMachines.value -Depth 10 -Compress)
        $bindings.virtualMachines.value | Should -Be "[variables('virtualMachines')]"
        $portal.variables.virtualMachines |
            Should -Be "[if(equals(parameters('landscape'), 'single'), variables('singleVirtualMachines'), variables('catalog').landscapes[parameters('landscape')])]"
        @($portal.parameters.landscape.allowedValues | Sort-Object) -join ',' |
            Should -Be (@(@('single') + $compiledCatalog.landscapes.Keys | Sort-Object) -join ',')
        foreach ($name in 'location', 'namePrefix', 'adminUsername') {
            $portal.parameters[$name].defaultValue | Should -Be $development[$name].value
        }
        $portal.parameters.projectName.defaultValue | Should -Be $development.ownership.value.projectName
        $portal.parameters.deploymentNumber.defaultValue | Should -Be ([int]$development.deploymentNumber.value)
    }

    It 'allows any typed application or database role for exactly one SINGLE VM' {
        $roleDefinitionName = ($portal.parameters.singleRole.'$ref' -split '/')[-1]
        @($portal.definitions[$roleDefinitionName].allowedValues | Sort-Object) -join ',' |
            Should -Be (@($compiledCatalog.roles.Keys | Sort-Object) -join ',')
        $portal.parameters.singleInstanceNumber.type | Should -Be 'int'
        $portal.parameters.singleInstanceNumber.minValue | Should -Be 0
        $portal.parameters.singleInstanceNumber.maxValue | Should -Be 9
        $portal.variables.singleVirtualMachines.Count | Should -Be 1
        $single = $portal.variables.singleVirtualMachines[0]
        $single.role | Should -Be "[parameters('singleRole')]"
        $single.instance | Should -Be "[string(parameters('singleInstanceNumber'))]"
        $single.nic1IpAddresses.Count | Should -Be 4
        $single.nic2IpAddresses.Count | Should -Be 4
        @($single.nic1IpAddresses + $single.nic2IpAddresses | Where-Object { $_ -ne '' }).Count | Should -Be 0
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
        foreach ($pair in $bindings.network.value.subnetPairs.Values) {
            $pair | Should -Be "[variables('subnetPair')]"
        }
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

    It 'offers exactly nine distinct portal options and valid local documentation links' {
        $buttons.Count | Should -Be 9
        @($buttons.href | Sort-Object -Unique).Count | Should -Be 9
        foreach ($anchor in $html.SelectNodes('//a[not(starts-with(@href, "https://"))]')) {
            $relative = $anchor.href.Split('#')[0].Replace('/', '\')
            Test-Path -LiteralPath (Join-Path $Root $relative) | Should -BeTrue
        }
    }

    It 'publishes the exact <Profile> topology and matching README option' -ForEach $profiles {
        $publishedPath = Join-Path $Root "infra\portal\$File"
        $publishedText = Get-Content -LiteralPath $publishedPath -Raw
        $published = $publishedText | ConvertFrom-Json
        $expected = $portalText | ConvertFrom-Json
        $expected.parameters.landscape.defaultValue = $Profile
        $expected.parameters.landscape.allowedValues = @($Profile)
        $expected.metadata._generator.PSObject.Properties.Remove('templateHash')
        $expected.metadata | Add-Member -NotePropertyName portalProfile -NotePropertyValue $Profile
        ($published | ConvertTo-Json -Depth 100 -Compress) |
            Should -BeExactly ($expected | ConvertTo-Json -Depth 100 -Compress)
        $published.parameters.landscape.defaultValue | Should -Be $Profile
        $published.parameters.landscape.allowedValues.Count | Should -Be 1
        $published.parameters.landscape.allowedValues[0] | Should -Be $Profile
        $published.metadata.portalProfile | Should -Be $Profile
        (Get-Item -LiteralPath $publishedPath).Length | Should -BeLessThan (4 * 1024 * 1024)
        $selectedRoles = if ($Profile -eq 'single') {
            @($portal.parameters.singleRole.defaultValue)
        } else {
            @($compiledCatalog.landscapes[$Profile].role)
        }
        $selectedRoles.Count | Should -Be ($Apps + $Databases)
        @($selectedRoles | Where-Object { $compiledCatalog.roles[$_].category -eq 'sap' }).Count | Should -Be $Apps
        @($selectedRoles | Where-Object { $compiledCatalog.roles[$_].category -eq 'han' }).Count | Should -Be $Databases
        $button = @($buttons | Where-Object { [Uri]::UnescapeDataString($_.href) -eq "$portalPrefix$rawPrefix$File" })
        $button.Count | Should -Be 1
        ($button[0].ParentNode.InnerText -replace '\s+', ' ').Trim() | Should -Be $Label
    }
}
