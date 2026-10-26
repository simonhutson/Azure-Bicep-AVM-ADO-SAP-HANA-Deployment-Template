BeforeAll {
    $script:Root = Split-Path $PSScriptRoot
    . (Join-Path $PSScriptRoot 'Fixtures.ps1')
    $script:Validate = Join-Path $Root 'pipelines\scripts\Test-Configuration.ps1'
}

Describe 'Fail-closed environment preflight' {
    BeforeEach {
        $script:Fixture = New-ArtifactFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString()))
        $script:ParametersFile = Join-Path $Fixture 'development.parameters.json'
        $script:Document = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json -AsHashtable
    }
    It 'accepts a fully configured environment with dynamic addresses' {
        $result = & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development
        $result.environmentName | Should -Be 'development'
        $result.virtualMachines.Count | Should -Be 1
        $result.virtualMachines[0].vmSize | Should -Be 'Standard_E4ds_v5'
    }
    It 'rejects the unconfigured example rather than deploying a sample by accident' {
        { & $Validate -ParametersFile (Join-Path $Root '.build\iac\development.parameters.json') -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw '*placeholders*'
    }
    It 'rejects selecting one environment with another parameter file' {
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName production } | Should -Throw '*Selected environment*'
    }
    It 'honors literal defaults from the compiled Bicep template' {
        $Document.parameters.Remove('adminUsername')
        $Document.parameters.Remove('bootstrap')
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        $result = & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development
        $result.adminUsername | Should -Be 'azureuser'
        $result.bootstrap.mode | Should -Be 'disabled'
    }
    It 'rejects duplicate same-category VM names across different roles' {
        $other = ($Document.parameters.virtualMachines.value[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable)
        $other.role = 'app-bw'
        $Document.parameters.virtualMachines.value += $other
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw '*Duplicate VM naming identity*'
    }
    It 'allows different instances of the same role to share an availability set' {
        $other = ($Document.parameters.virtualMachines.value[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable)
        $other.instance = '8'
        $Document.parameters.virtualMachines.value += $other
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        (& $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development).virtualMachines.Count | Should -Be 2
    }
    It 'rejects invalid input: <Label>' -ForEach @(
        @{ Label = 'unpinned image'; Field = 'image'; Value = @{ publisher = 'SUSE'; offer = 'sles-sap-15-sp6-byos'; sku = 'gen2'; version = 'latest' }; ExpectedMessage = '*Pin the marketplace image*' },
        @{ Label = 'old image'; Field = 'image'; Value = @{ publisher = 'SUSE'; offer = 'SLES-SAP-BYOS'; sku = '12-SP2'; version = '1.0.0' }; ExpectedMessage = '*SLES for SAP 15*' },
        @{ Label = 'nonnumeric deployment'; Field = 'deploymentNumber'; Value = 'aa'; ExpectedMessage = '*two digits*' },
        @{ Label = 'private SSH key'; Field = 'sshPublicKey'; Value = '-----BEGIN OPENSSH PRIVATE KEY-----'; ExpectedMessage = '*public key*' },
        @{ Label = 'root login'; Field = 'adminUsername'; Value = 'root'; ExpectedMessage = '*non-root*' },
        @{ Label = 'empty selection'; Field = 'virtualMachines'; Value = @(); ExpectedMessage = '*between 1 and 50*' }
    ) {
        $Document.parameters[$Field].value = $Value
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw $ExpectedMessage
    }
    It 'rejects invalid IPs, too many IPs and duplicate static addresses' -ForEach @(
        @{ IPs = @('999.1.2.3'); ExpectedMessage = '*Invalid IPv4*' },
        @{ IPs = @('::1'); ExpectedMessage = '*Invalid IPv4*' },
        @{ IPs = @('', '', '', '', ''); ExpectedMessage = '*1-4 IPv4*' },
        @{ IPs = @('10.0.0.8', '10.0.0.8'); ExpectedMessage = '*Duplicate static address*' },
        @{ IPs = @(''); ExpectedMessage = ''; Valid = $true }
    ) {
        $Document.parameters.virtualMachines.value[0].nic1IpAddresses = $IPs
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        if ($Valid) {
            { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Not -Throw
        } else {
            { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw $ExpectedMessage
        }
    }
    It 'rejects bootstrap without immutable content verification and identity access' {
        $Document.parameters.bootstrap.value = @{
            mode = 'custom-script'
            scriptUri = 'https://example.blob.core.windows.net/v1/bootstrap.sh?sig=not-allowed'
            sha256 = 'not-a-hash'
            managedIdentityResourceId = ''
        }
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw '*Bootstrap requires*'
    }
    It 'accepts an explicit checksum-pinned identity-based replacement bootstrap' {
        $Document.parameters.bootstrap.value = @{
            mode = 'custom-script'
            scriptUri = 'https://example.blob.core.windows.net/v1/bootstrap.sh'
            sha256 = 'a' * 64
            managedIdentityResourceId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-shared/providers/Microsoft.ManagedIdentity/userAssignedIdentities/bootstrap'
        }
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Not -Throw
    }
    It 'requires host encryption in production' {
        $prod = New-ArtifactFixture (Join-Path $TestDrive 'prod') -EnvironmentName production
        $file = Join-Path $prod 'production.parameters.json'
        $document = Get-Content $file -Raw | ConvertFrom-Json -AsHashtable
        $document.parameters.encryptionAtHost.value = $false
        $document | ConvertTo-Json -Depth 100 | Set-Content $file
        { & $Validate -ParametersFile $file -CatalogFile (Join-Path $prod 'catalog.json') -EnvironmentName production } | Should -Throw '*Production requires encryptionAtHost*'
    }
    It 'resolves production and nonproduction database defaults differently' {
        $test = New-ArtifactFixture (Join-Path $TestDrive 'test-sizes') -EnvironmentName test
        $p = & $Validate -ParametersFile (Join-Path $test 'test.parameters.json') -CatalogFile (Join-Path $test 'catalog.json') -EnvironmentName test
        $p.virtualMachines[1].vmSize | Should -Be 'Standard_E8ds_v5'
        $prod = New-ArtifactFixture (Join-Path $TestDrive 'prod-sizes') -EnvironmentName production
        $p = & $Validate -ParametersFile (Join-Path $prod 'production.parameters.json') -CatalogFile (Join-Path $prod 'catalog.json') -EnvironmentName production
        ($p.virtualMachines | Where-Object role -EQ 'db-nw-gateway').vmSize | Should -Be 'Standard_E20ds_v5'
        ($p.virtualMachines | Where-Object role -EQ 'db-utilities').vmSize | Should -Be 'Standard_E32ds_v5'
        ($p.virtualMachines | Where-Object role -EQ 'db-bw').vmSize | Should -Be 'Standard_M32ls'
    }
    It 'does not allow a smaller production HANA override or an OLTP-only SKU for BW' -ForEach @(
        @{ Role = 'db-nw-gateway'; Size = 'Standard_E8ds_v5' },
        @{ Role = 'db-bw'; Size = 'Standard_E20ds_v5' },
        @{ Role = 'db-bw'; Size = 'Standard_E32ds_v5' },
        @{ Role = 'db-bw'; Size = 'Standard_M16ms' }
    ) {
        $prod = New-ArtifactFixture (Join-Path $TestDrive "prod-$Role-$Size") -EnvironmentName production
        $file = Join-Path $prod 'production.parameters.json'
        $doc = Get-Content $file -Raw | ConvertFrom-Json -AsHashtable
        ($doc.parameters.virtualMachines.value | Where-Object role -EQ $Role).vmSize = $Size
        $doc | ConvertTo-Json -Depth 100 | Set-Content $file
        { & $Validate -ParametersFile $file -CatalogFile (Join-Path $prod 'catalog.json') -EnvironmentName production } | Should -Throw '*single-node certification*'
    }
    It 'allows an explicitly documented production HANA override with the matching workload' {
        $prod = New-ArtifactFixture (Join-Path $TestDrive 'prod-override') -EnvironmentName production
        $file = Join-Path $prod 'production.parameters.json'
        $doc = Get-Content $file -Raw | ConvertFrom-Json -AsHashtable
        ($doc.parameters.virtualMachines.value | Where-Object role -EQ 'db-nw-gateway').vmSize = 'Standard_M32ls'
        $doc | ConvertTo-Json -Depth 100 | Set-Content $file
        (& $Validate -ParametersFile $file -CatalogFile (Join-Path $prod 'catalog.json') -EnvironmentName production).virtualMachines.Count | Should -Be 16
    }
    It 'rejects an arbitrary Standard_ application SKU rather than trusting its family prefix' {
        $Document.parameters.virtualMachines.value[0].vmSize = 'Standard_B4ms'
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw '*application candidate set*'
    }
    It 'rejects an arbitrary nonproduction HANA SKU without Note evidence' {
        $Document.parameters.virtualMachines.value[0].role = 'db-nw-gateway'
        $Document.parameters.virtualMachines.value[0].vmSize = 'Standard_E2ds_v5'
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw '*Nonproduction HANA VM size*'
    }
    It 'requires a recorded operator support review instead of claiming SAP Note access' {
        $Document.parameters.sapSupportReviewReference.value = ''
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw '*SAP Note 1928533*'
    }
    It 'rejects a Gen1 image for the selected HANA-certified baseline' {
        $Document.parameters.image.value.sku = 'gen1'
        $Document | ConvertTo-Json -Depth 100 | Set-Content $ParametersFile
        { & $Validate -ParametersFile $ParametersFile -CatalogFile (Join-Path $Fixture 'catalog.json') -EnvironmentName development } | Should -Throw '*Gen2 marketplace image*'
    }
}
