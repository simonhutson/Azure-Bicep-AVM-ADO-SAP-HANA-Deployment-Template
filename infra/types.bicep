@export()
type environmentType = 'development' | 'test' | 'production'

@export()
type roleType =
  | 'app-nw-gateway'
  | 'app-po'
  | 'app-gateway-fes'
  | 'app-bw'
  | 'app-utilities'
  | 'app-cc'
  | 'app-ci'
  | 'app-som-abap'
  | 'app-som-java'
  | 'app-cloud-connector'
  | 'db-nw-gateway'
  | 'db-po'
  | 'db-gateway-fes'
  | 'db-bw'
  | 'db-utilities'
  | 'db-hybris'

@export()
@sealed()
type virtualMachineType = {
  role: roleType
  @minLength(1)
  @maxLength(1)
  instance: string
  @minLength(1)
  @maxLength(4)
  nic1IpAddresses: string[]
  @minLength(1)
  @maxLength(4)
  nic2IpAddresses: string[]
  @description('Exact SKU override. Pipeline preflight enforces the role/environment VM policy, including OLTP versus OLAP production HANA certification.')
  @minLength(1)
  vmSize: string?
  @minLength(1)
  @maxLength(64)
  dataDiskSizesGB: int[]?
}

@export()
@sealed()
type imageType = {
  @minLength(1)
  publisher: string
  @minLength(1)
  offer: string
  @minLength(1)
  sku: string
  @minLength(1)
  version: string
}

@export()
@sealed()
type marketplacePlanType = {
  name: string
  product: string
  publisher: string
}

@sealed()
type subnetPairType = {
  @minLength(1)
  nic1: string
  @minLength(1)
  nic2: string
}

@export()
@sealed()
type networkType = {
  @minLength(1)
  resourceGroupName: string
  @minLength(1)
  virtualNetworkName: string
  subnetPairs: {
    gateway: subnetPairType
    po: subnetPairType
    bw: subnetPairType
    utilities: subnetPairType
    hybris: subnetPairType
    cloudConnector: subnetPairType
  }
  @maxLength(4)
  dnsServers: string[]?
}

@export()
@sealed()
type ownershipType = {
  @minLength(1)
  serviceOwner: string
  @minLength(1)
  serviceTicketRequestId: string
  @minLength(1)
  projectName: string
  @minLength(1)
  costCodeId: string
}

@sealed()
type disabledBootstrapType = {
  mode: 'disabled'
}

@sealed()
type customScriptBootstrapType = {
  mode: 'custom-script'
  @description('HTTPS Azure Blob URI ending in /bootstrap.sh, without a SAS token. Use an immutable artifact path.')
  scriptUri: string
  @minLength(64)
  @maxLength(64)
  sha256: string
  @description('Existing user-assigned identity with Blob Data Reader access. No keys or secret values belong in this configuration.')
  managedIdentityResourceId: string
}

@export()
@discriminator('mode')
type bootstrapType = disabledBootstrapType | customScriptBootstrapType
