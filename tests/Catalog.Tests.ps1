BeforeDiscovery {
    $root = Split-Path $PSScriptRoot
    $data = Get-Content -LiteralPath (Join-Path $root 'infra\catalog.json') -Raw | ConvertFrom-Json -AsHashtable
    $roles = @($data.roles.Keys | ForEach-Object { @{ Role = $_ } })
    $landscapes = @(
        @{ Profile = 'netweaverGateway'; ExpectedRoles = @('app-nw-gateway', 'db-nw-gateway'); Instances = @('1', '0'); Nic1Counts = @(4, 2); Nic2Counts = @(3, 2) },
        @{ Profile = 'gatewayFes'; ExpectedRoles = @('app-gateway-fes', 'db-gateway-fes'); Instances = @('2', '2'); Nic1Counts = @(4, 2); Nic2Counts = @(3, 2) },
        @{ Profile = 'sapPo'; ExpectedRoles = @('app-po', 'db-po'); Instances = @('1', '1'); Nic1Counts = @(4, 2); Nic2Counts = @(3, 2) },
        @{ Profile = 'sapBw'; ExpectedRoles = @('app-bw', 'db-bw'); Instances = @('3', '3'); Nic1Counts = @(4, 2); Nic2Counts = @(3, 2) },
        @{ Profile = 'utilities'; ExpectedRoles = @('app-utilities', 'db-utilities'); Instances = @('4', '4'); Nic1Counts = @(4, 2); Nic2Counts = @(3, 2) },
        @{ Profile = 'cloudConnector'; ExpectedRoles = @('app-cloud-connector'); Instances = @('9'); Nic1Counts = @(4); Nic2Counts = @(3) },
        @{ Profile = 'hybrisBilling'; ExpectedRoles = @('app-cc', 'app-ci', 'app-som-abap', 'app-som-java', 'db-hybris'); Instances = @('5', '6', '7', '8', '5'); Nic1Counts = @(3, 3, 3, 3, 4); Nic2Counts = @(3, 3, 3, 3, 4) },
        @{
            Profile = 'full'
            ExpectedRoles = @('app-nw-gateway', 'app-po', 'app-gateway-fes', 'app-bw', 'app-utilities', 'app-cc', 'app-ci', 'app-som-abap', 'app-som-java', 'app-cloud-connector', 'db-nw-gateway', 'db-po', 'db-gateway-fes', 'db-bw', 'db-utilities', 'db-hybris')
            Instances = @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '1', '2', '3', '4', '5')
            Nic1Counts = (@(3) * 16)
            Nic2Counts = (@(3) * 10 + @(4) * 6)
        }
    )
}

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    $catalog = Get-Content -LiteralPath (Join-Path $Root 'infra\catalog.json') -Raw | ConvertFrom-Json -AsHashtable
    $template = Get-Content -LiteralPath (Join-Path $Root '.build\iac\main.json') -Raw | ConvertFrom-Json -AsHashtable
    $databaseDisks = @{
        'db-nw-gateway' = @(32, 32, 64, 128, 64, 32)
        'db-po' = @(32, 32, 64, 128, 64, 31)
        'db-gateway-fes' = @(32, 32, 64, 128, 64, 32)
        'db-bw' = @(32, 32, 128, 512, 128, 64)
        'db-utilities' = @(32, 32, 128, 512, 128, 64)
        'db-hybris' = @(32, 32, 128, 256, 128, 64, 128, 256, 128, 64, 128, 256, 128, 64)
    }
    $imos = "IMOS $([char]0x2013) EUR"
    $serviceNames = @{
        'nw-gateway' = $imos
        'po' = $imos
        'gateway-fes' = 'SAP NETWEAVER GATEWAY - EUR'
        'bw' = 'SAP BUSINESS WAREHOUSE - EUR'
        'utilities' = 'UTILITIES - EUR'
        'cc' = 'SAP HYBRIS BILLING - EUR'
        'ci' = 'SAP HYBRIS BILLING - EUR'
        'som-abap' = 'SAP HYBRIS BILLING - EUR'
        'som-java' = 'SAP HYBRIS BILLING - EUR'
        'cloud-connector' = 'SAP CLOUD CONNECTOR'
        'hybris' = 'SAP HYBRIS BILLING - EUR'
    }
}

Describe 'Bicep role and landscape catalogue' {
    It 'covers every typed Bicep role without aliases or omissions' {
        $roleDefinitions = @($template.definitions.GetEnumerator() | Where-Object Key -Match '(^|\.)roleType$')
        $roleDefinitions.Count | Should -Be 1
        $catalog.roles.Count | Should -Be 16
        @($catalog.roles.Keys | Sort-Object) -join '|' | Should -Be (@($roleDefinitions[0].Value.allowedValues | Sort-Object) -join '|')
    }
    It 'uses the expected ordered disks and service classification for <Role>' -ForEach $roles {
        $profile = $catalog.roles[$Role]
        $expectedCategory = if ($Role.StartsWith('app-')) { 'sap' } else { 'han' }
        $expectedDisks = if ($expectedCategory -eq 'sap') { @(32, 32, 64) } else { $databaseDisks[$Role] }
        $profile.category | Should -Be $expectedCategory
        ($profile.dataDiskSizesGB -join ',') | Should -Be ($expectedDisks -join ',')
        $profile.serviceName | Should -Be $serviceNames[($Role -replace '^(app|db)-', '')]
        @('gateway', 'po', 'bw', 'utilities', 'hybris', 'cloudConnector') | Should -Contain $profile.network
    }
    It 'defines the expected roles, instances and NIC cardinalities for <Profile>' -ForEach $landscapes {
        $new = $catalog.landscapes[$Profile]
        $new.Count | Should -Be $ExpectedRoles.Count
        for ($i = 0; $i -lt $new.Count; $i++) {
            $new[$i].role | Should -Be $ExpectedRoles[$i]
            $new[$i].instance | Should -Be $Instances[$i]
            $new[$i].nic1IpAddresses.Count | Should -Be $Nic1Counts[$i]
            $new[$i].nic2IpAddresses.Count | Should -Be $Nic2Counts[$i]
            @($new[$i].nic1IpAddresses + $new[$i].nic2IpAddresses | Where-Object { $_ -ne '' }).Count | Should -Be 0
        }
    }
    It 'gives every role a distinct availability-set naming identity' {
        @($catalog.roles.Values | ForEach-Object { "$($_.category)/$($_.availabilitySuffix)" } | Sort-Object -Unique).Count | Should -Be 16
    }
    It 'retains FULL as 16 VMs, 32 NICs and 74 data disks without provisioning SAP' {
        $catalog.landscapes.full.Count | Should -Be 16
        ($catalog.landscapes.full.Count * 2) | Should -Be 32
        ($catalog.landscapes.full | ForEach-Object { $catalog.roles[$_.role].dataDiskSizesGB.Count } | Measure-Object -Sum).Sum | Should -Be 74
    }
}

Describe 'Workload-specific SAP VM policy' {
    It 'keeps applications and nonproduction HANA on explicit Edsv5 candidates, not a family-wide certification claim' {
        foreach ($profile in $catalog.roles.Values) {
            if ($profile.category -eq 'sap') {
                $profile.vmSize | Should -Be 'Standard_E4ds_v5'
                $catalog.vmPolicy.applicationCandidates | Should -Contain $profile.vmSize
            } else {
                $catalog.vmPolicy.nonProductionHanaCandidates | Should -Contain $profile.vmSize
            }
        }
        $catalog.vmPolicy.sapNote1928533Access | Should -Match 'not independently verified'
    }
    It 'selects production HANA SKUs with a source for the exact workload' {
        foreach ($profile in @($catalog.roles.Values | Where-Object category -EQ 'han')) {
            $catalog.vmPolicy.hanaCertifications[$profile.productionVmSize].ContainsKey($profile.hanaWorkload) | Should -BeTrue
        }
        $catalog.roles.'db-nw-gateway'.productionVmSize | Should -Be 'Standard_E20ds_v5'
        $catalog.roles.'db-po'.productionVmSize | Should -Be 'Standard_E20ds_v5'
        $catalog.roles.'db-gateway-fes'.productionVmSize | Should -Be 'Standard_E20ds_v5'
        $catalog.roles.'db-utilities'.productionVmSize | Should -Be 'Standard_E32ds_v5'
        $catalog.roles.'db-hybris'.productionVmSize | Should -Be 'Standard_E32ds_v5'
        $catalog.roles.'db-bw'.productionVmSize | Should -Be 'Standard_M32ls'
    }
    It 'does not treat OLTP-only E-series certifications as BW OLAP certification' {
        $catalog.roles.'db-bw'.hanaWorkload | Should -Be 'olap'
        $catalog.vmPolicy.hanaCertifications.Standard_E20ds_v5.ContainsKey('olap') | Should -BeFalse
        $catalog.vmPolicy.hanaCertifications.Standard_E32ds_v5.ContainsKey('olap') | Should -BeFalse
        $catalog.vmPolicy.hanaCertifications.Standard_M32ls.olap | Should -Match 'id=s:2008$'
    }
}

Describe 'Compiled AVM deployment baseline' {
    BeforeAll {
        $script:VmModule = $template.resources.vms
        $script:AsModule = $template.resources.availabilitySets
    }
    It 'uses only resource-sized AVM modules, not property-sized linked deployments' {
        $template.resources.Count | Should -Be 2
        $VmModule.properties.template.metadata._generator.name | Should -Be 'bicep'
        $AsModule.properties.parameters.platformUpdateDomainCount.value | Should -Be 20
        $AsModule.properties.parameters.platformFaultDomainCount.value | Should -Be 2
        ($template | ConvertTo-Json -Depth 100 -Compress) | Should -Not -Match '"templateLink"|"debugSetting"'
    }
    It 'enforces SSH-only access, identity and managed boot diagnostics' {
        $VmModule.properties.parameters.disablePasswordAuthentication.value | Should -BeTrue
        $VmModule.properties.parameters.bootDiagnostics.value | Should -BeTrue
        $VmModule.properties.parameters.managedIdentities.value.systemAssigned | Should -BeTrue
        $template.parameters.ContainsKey('adminPassword') | Should -BeFalse
        $template.parameters.bootstrap.defaultValue.mode | Should -Be 'disabled'
    }
    It 'makes disk retention, premium data storage and checksum-gated bootstrap explicit' {
        $vmCode = Get-Content -LiteralPath (Join-Path $Root 'infra\main.bicep') -Raw
        $vmCode | Should -Match "deleteOption: 'Detach'"
        $vmCode | Should -Match "storageAccountType: 'Premium_LRS'"
        $vmCode | Should -Match 'sha256sum --check --status && /bin/bash'
        $vmCode | Should -Not -Match 'puppetPreshared|scriptStorageAccountKey'
    }
    It 'pins both AVMs to the versions whose contracts were verified' {
        $code = Get-Content -LiteralPath (Join-Path $Root 'infra\main.bicep') -Raw
        $code | Should -Match 'br/public:avm/res/compute/virtual-machine:0\.22\.3'
        $code | Should -Match 'br/public:avm/res/compute/availability-set:0\.2\.4'
    }
    It 'compiles the environment-specific default before applying a caller SKU override' {
        $template.variables.instances | Should -Match 'productionVmSize'
        $template.variables.instances | Should -Match "environmentName"
        $template.parameters.sapSupportReviewReference.minLength | Should -Be 1
    }
    It 'compiles independent environment selections and keeps bootstrap disabled' {
        $expected = @{ development = 1; test = 2; production = 16 }
        foreach ($envName in $expected.Keys) {
            $p = (Get-Content -LiteralPath (Join-Path $Root ".build\iac\$envName.parameters.json") -Raw | ConvertFrom-Json -AsHashtable).parameters
            $p.environmentName.value | Should -Be $envName
            $p.virtualMachines.value.Count | Should -Be $expected[$envName]
            $p.bootstrap.value.mode | Should -Be 'disabled'
            $p.encryptionAtHost.value | Should -BeTrue
            $p.image.value.version | Should -Not -Be 'latest'
        }
    }
}
