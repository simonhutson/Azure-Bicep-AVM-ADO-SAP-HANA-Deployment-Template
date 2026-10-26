#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ParametersFile,
    [Parameter(Mandatory)] [string] $CatalogFile,
    [Parameter(Mandatory)] [ValidateSet('development', 'test', 'production')] [string] $EnvironmentName
)

$ErrorActionPreference = 'Stop'
$document = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json -AsHashtable
$catalog = Get-Content -LiteralPath $CatalogFile -Raw | ConvertFrom-Json -AsHashtable
$template = Get-Content -LiteralPath (Join-Path (Split-Path $ParametersFile) 'main.json') -Raw | ConvertFrom-Json -AsHashtable
$p = @{}
foreach ($entry in $template.parameters.GetEnumerator()) {
    if ($entry.Value.ContainsKey('defaultValue')) { $p[$entry.Key] = $entry.Value.defaultValue }
}
foreach ($entry in $document.parameters.GetEnumerator()) {
    if (-not $entry.Value.ContainsKey('value')) { throw "Parameter '$($entry.Key)' must have a compiled value; secret references are not supported by this SSH-only baseline." }
    $p[$entry.Key] = $entry.Value.value
}
$errors = [System.Collections.Generic.List[string]]::new()
if (($p | ConvertTo-Json -Depth 100) -match 'REQUIRED_|<your-|CHANGEME') {
    $errors.Add('Replace all REQUIRED_ configuration placeholders before running an authenticated plan or deployment.')
}
if ($p.environmentName -cne $EnvironmentName) { $errors.Add('Selected environment does not match the compiled parameter file.') }
if ($p.namePrefix -cnotmatch '^[a-z][a-z0-9]{1,11}$') { $errors.Add('namePrefix must be 2-12 lowercase alphanumeric characters, beginning with a letter.') }
if ($p.deploymentNumber -notmatch '^\d{2}$') { $errors.Add('deploymentNumber must contain exactly two digits.') }
if ($p.adminUsername -cnotmatch '^[a-z_][a-z0-9_-]{0,31}$' -or $p.adminUsername -eq 'root') {
    $errors.Add('Use a non-root Linux administrator username, not a shell expression.')
}
if ($p.sshPublicKey -notmatch '^(ssh-rsa|ssh-ed25519) ([A-Za-z0-9+/]+={0,2})( [^\r\n]*)?$') {
    $errors.Add('sshPublicKey must be a single OpenSSH RSA or ED25519 public key, never a private key.')
} else {
    try {
        $keyBytes = [Convert]::FromBase64String($Matches[2])
        if ($keyBytes.Length -lt 32) { $errors.Add('SSH public key data is too short.') }
    } catch [FormatException] {
        $errors.Add('SSH public key data is not valid base64.')
    }
}
if ($p.image.publisher -cne 'SUSE' -or $p.image.offer -notmatch '^sles-sap-15-.+-byos$') {
    $errors.Add('Select a SUSE SLES for SAP 15 BYOS marketplace image; legacy SLES 12 is not supported by the new baseline.')
}
if ($p.image.version -notmatch '^\d+\.\d+\.\d+$') { $errors.Add('Pin the marketplace image to an explicit Major.Minor.Build version; latest is not allowed.') }
if ($p.image.sku -cne 'gen2') { $errors.Add('The selected SAP VM policy requires a Gen2 marketplace image (sku=gen2).') }
if ([string]::IsNullOrWhiteSpace($p.sapSupportReviewReference)) {
    $errors.Add('Record sapSupportReviewReference for the SAP Note 1928533 and workload/OS/HANA/storage support review before deployment.')
}
if ($EnvironmentName -eq 'production' -and $p.encryptionAtHost -ne $true) { $errors.Add('Production requires encryptionAtHost=true.') }
if ($p.virtualMachines.Count -lt 1 -or $p.virtualMachines.Count -gt 50) { $errors.Add('Select between 1 and 50 VM instances.') }

$identities = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$addresses = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($vm in $p.virtualMachines) {
    if (-not $catalog.roles.ContainsKey($vm.role)) { $errors.Add("Unknown VM role '$($vm.role)'."); continue }
    $profile = $catalog.roles[$vm.role]
    if ($vm.instance -notmatch '^\d$') { $errors.Add("Role '$($vm.role)' requires a single-digit instance.") }
    if (-not $identities.Add("$($profile.category)$($vm.instance)")) {
        $errors.Add("Duplicate VM naming identity: $($profile.category)$($vm.instance).")
    }
    if ($null -ne $vm.vmSize -and $vm.vmSize -notmatch '^Standard_[A-Za-z0-9_-]+$') {
        $errors.Add("Invalid VM size override for '$($vm.role)'.")
    }
    $defaultSize = if ($EnvironmentName -eq 'production') { $profile.productionVmSize ?? $profile.vmSize } else { $profile.vmSize }
    $vm.vmSize = $vm.vmSize ?? $defaultSize
    if ($profile.category -eq 'sap') {
        if ($vm.vmSize -cnotin $catalog.vmPolicy.applicationCandidates) {
            $errors.Add("VM size '$($vm.vmSize)' for '$($vm.role)' is outside the reviewed application candidate set. Add exact-SKU SAP Note 1928533 evidence through a reviewed policy change.")
        }
    } elseif ($EnvironmentName -eq 'production') {
        $certification = $catalog.vmPolicy.hanaCertifications[$vm.vmSize]
        if ($null -eq $certification -or -not $certification.ContainsKey($profile.hanaWorkload)) {
            $errors.Add("Production HANA role '$($vm.role)' requires an exact SKU with a recorded '$($profile.hanaWorkload)' single-node certification; '$($vm.vmSize)' does not qualify.")
        }
    } elseif ($vm.vmSize -cnotin $catalog.vmPolicy.nonProductionHanaCandidates) {
        $errors.Add("Nonproduction HANA VM size '$($vm.vmSize)' for '$($vm.role)' is outside the reviewed candidate set. Verify the exact SKU in SAP Note 1928533; family membership is insufficient.")
    }
    $sizes = $vm.dataDiskSizesGB ?? $profile.dataDiskSizesGB
    if ($sizes.Count -lt 1 -or $sizes.Count -gt 64 -or @($sizes | Where-Object { $_ -isnot [long] -and $_ -isnot [int] -or $_ -lt 1 -or $_ -gt 32767 }).Count -gt 0) {
        $errors.Add("Invalid data disk capacities/count for '$($vm.role)'.")
    }
    $pair = $p.network.subnetPairs[$profile.network]
    if ($null -eq $pair -or [string]::IsNullOrWhiteSpace($pair.nic1) -or [string]::IsNullOrWhiteSpace($pair.nic2) -or $pair.nic1 -eq $pair.nic2) {
        $errors.Add("Role '$($vm.role)' needs two distinct existing subnets.")
    }
    foreach ($nic in 1, 2) {
        $ips = $vm["nic${nic}IpAddresses"]
        if ($ips.Count -lt 1 -or $ips.Count -gt 4) { $errors.Add("Role '$($vm.role)' NIC $nic needs 1-4 IPv4 address entries.") }
        foreach ($address in $ips) {
            if ($address -isnot [string]) { $errors.Add("NIC $nic address entries must be strings."); continue }
            if ($address -ceq '') { continue }
            $parsed = $null
            if (-not [System.Net.IPAddress]::TryParse($address, [ref] $parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or $parsed.ToString() -cne $address) {
                $errors.Add("Invalid IPv4 address '$address' for '$($vm.role)' NIC $nic.")
            } elseif (-not $addresses.Add("$($pair["nic$nic"]):$address")) {
                $errors.Add("Duplicate static address '$address' in subnet '$($pair["nic$nic"])'.")
            }
        }
    }
}
foreach ($server in $p.network.dnsServers) {
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($server, [ref] $parsed) -or $parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        $errors.Add("Invalid DNS server IPv4 address '$server'.")
    }
}

if ($p.bootstrap.mode -eq 'custom-script') {
    $uri = $null
    if (-not [Uri]::TryCreate($p.bootstrap.scriptUri, [UriKind]::Absolute, [ref] $uri) -or
        $uri.Scheme -ne 'https' -or $uri.Host -notmatch '^[a-z0-9]+\.blob\.core\.windows\.net$' -or
        -not $uri.AbsolutePath.EndsWith('/bootstrap.sh', [StringComparison]::Ordinal) -or
        $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.UserInfo -ne '') {
        $errors.Add('Bootstrap requires an HTTPS Azure Blob /bootstrap.sh URI without credentials, query strings, or fragments.')
    }
    if ($p.bootstrap.sha256 -notmatch '^[a-f0-9]{64}$') { $errors.Add('Bootstrap requires a 64-character hexadecimal SHA-256 checksum.') }
    if ($p.bootstrap.managedIdentityResourceId -notmatch '^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\.ManagedIdentity/userAssignedIdentities/[^/]+$') {
        $errors.Add('Bootstrap requires an existing user-assigned managed identity resource ID.')
    }
} elseif ($p.bootstrap.mode -ne 'disabled') {
    $errors.Add('Bootstrap mode must be disabled or custom-script.')
}

if ($errors.Count -gt 0) { throw ("Configuration preflight failed:`n- " + ($errors -join "`n- ")) }
Write-Host "Configuration preflight passed for $EnvironmentName ($($p.virtualMachines.Count) VM instances)."
return $p
