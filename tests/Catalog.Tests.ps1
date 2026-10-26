BeforeDiscovery {
    $root = Split-Path $PSScriptRoot
    $data = Get-Content -LiteralPath (Join-Path $root 'infra\catalog.json') -Raw | ConvertFrom-Json -AsHashtable
    $roles = @($data.roles.Keys | ForEach-Object { @{ Role = $_ } })
    $landscapes = @(
        @{ Profile = 'netweaverGateway'; File = 'azuredeploy.netweavergateway.json' },
        @{ Profile = 'gatewayFes'; File = 'azuredeploy.gatewayfes.json' },
        @{ Profile = 'sapPo'; File = 'azuredeploy.sappo.json' },
        @{ Profile = 'sapBw'; File = 'azuredeploy.sapbw.json' },
        @{ Profile = 'utilities'; File = 'azuredeploy.s4hanautilities.json' },
        @{ Profile = 'cloudConnector'; File = 'azuredeploy.cloudconnector.json' },
        @{ Profile = 'hybrisBilling'; File = 'azuredeploy.s4hanahybrisbilling.json' },
        @{ Profile = 'full'; File = 'azuredeploy.full.json' }
    )
}

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    $script:Archive = Join-Path $Root 'archive'
    $catalog = Get-Content -LiteralPath (Join-Path $Root 'infra\catalog.json') -Raw | ConvertFrom-Json -AsHashtable
    $legacySizes = Get-Content -LiteralPath (Join-Path $Archive 'settings.vm.hardwareprofile.json') -Raw | ConvertFrom-Json -AsHashtable
    $legacyDisks = Get-Content -LiteralPath (Join-Path $Archive 'settings.vm.storageprofile.datadisks.json') -Raw | ConvertFrom-Json -AsHashtable
    $legacyTags = Get-Content -LiteralPath (Join-Path $Archive 'tags.json') -Raw | ConvertFrom-Json -AsHashtable
    $core = Get-Content -LiteralPath (Join-Path $Archive 'azuredeploy.json') -Raw | ConvertFrom-Json -AsHashtable
    $template = Get-Content -LiteralPath (Join-Path $Root '.build\iac\main.json') -Raw | ConvertFrom-Json -AsHashtable
}

Describe 'Source-grounded role catalogue' {
    It 'keeps the complete original deployment bundle in archive rather than the repository root' {
        @(Get-ChildItem -LiteralPath $Archive -File -Filter '*.json').Count | Should -Be 47
        @(Get-ChildItem -LiteralPath (Join-Path $Archive 'scripts') -File -Filter '*.sh').Count | Should -Be 6
        Test-Path -LiteralPath (Join-Path $Archive 'SAP HANA Dev Test.png') | Should -BeTrue
        foreach ($file in Get-ChildItem -LiteralPath $Archive -File -Filter '*.json') {
            Test-Path -LiteralPath (Join-Path $Root $file.Name) | Should -BeFalse
        }
        Test-Path -LiteralPath (Join-Path $Root 'scripts') | Should -BeFalse
    }
    It 'covers all sixteen original roles without aliases or omissions' {
        $catalog.roles.Count | Should -Be 16
        @($catalog.roles.Values.legacyRole | Sort-Object) -join '|' | Should -Be (@($core.parameters.vmRole.allowedValues | Sort-Object) -join '|')
    }
    It 'preserves historical compute evidence, ordered disks and service tags for <Role>' -ForEach $roles {
        $profile = $catalog.roles[$Role]
        $profile.legacyVmSize | Should -Be $legacySizes.variables.vmSize.'SAP Dev Test'[$profile.legacyRole]
        ($profile.dataDiskSizesGB -join ',') | Should -Be ($legacyDisks.variables.diskSizes.'SAP Dev Test'[$profile.legacyRole].disks.diskSizeGB -join ',')
        $profile.serviceName | Should -Be $legacyTags.variables.tagServiceNames[$profile.legacyRole].tagServiceName
    }
    It 'preserves topology, instance numbers and NIC cardinalities for <Profile>' -ForEach $landscapes {
        $old = Get-Content -LiteralPath (Join-Path $Archive $File) -Raw | ConvertFrom-Json -AsHashtable
        $new = $catalog.landscapes[$Profile]
        $new.Count | Should -Be $old.resources.Count
        for ($i = 0; $i -lt $new.Count; $i++) {
            $p = $old.resources[$i].properties.parameters
            $role = $p.vmRole.value
            if ($role -in 'App - NetWeaver Gateway', 'DB - NetWeaver Gateway') { $role += ' (IMOS)' }
            $catalog.roles[$new[$i].role].legacyRole | Should -Be $role
            $new[$i].instance | Should -Be $p.vmInstanceNumber.value
            foreach ($nic in 1, 2) {
                $p["nic${nic}IpAddresses"].value | Should -Match "parameters\('([^']+)'\)"
                $parameterName = [regex]::Match($p["nic${nic}IpAddresses"].value, "parameters\('([^']+)'\)").Groups[1].Value
                $new[$i]["nic${nic}IpAddresses"].Count | Should -Be $old.parameters[$parameterName].defaultValue.Count
            }
        }
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
        $vmCode | Should -Not -Match 'sles-bootstrap-|puppetPreshared|scriptStorageAccountKey'
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
