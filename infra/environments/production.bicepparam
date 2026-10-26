using '../main.bicep'

var catalog = loadJsonContent('../catalog.json')

param environmentName = 'production'
param location = 'uksouth'
param namePrefix = 'azsu'
param deploymentNumber = '30'
// Catalogue production defaults use workload-specific certified HANA SKUs; application support and full-system sizing still require review.
param virtualMachines = catalog.landscapes.full

param image = {
  publisher: 'SUSE'
  offer: 'sles-sap-15-sp6-byos'
  sku: 'gen2'
  version: 'REQUIRED_PRODUCTION_PINNED_IMAGE_VERSION'
}
param adminUsername = 'azureuser'
param sshPublicKey = 'REQUIRED_PRODUCTION_SSH_PUBLIC_KEY'
param encryptionAtHost = true
param sapSupportReviewReference = 'REQUIRED_SAP_SUPPORT_REVIEW_REFERENCE'

param network = {
  resourceGroupName: 'REQUIRED_PRODUCTION_NETWORK_RESOURCE_GROUP'
  virtualNetworkName: 'REQUIRED_PRODUCTION_VNET'
  subnetPairs: {
    gateway: { nic1: 'REQUIRED_GATEWAY_NIC1_SUBNET', nic2: 'REQUIRED_GATEWAY_NIC2_SUBNET' }
    po: { nic1: 'REQUIRED_PO_NIC1_SUBNET', nic2: 'REQUIRED_PO_NIC2_SUBNET' }
    bw: { nic1: 'REQUIRED_BW_NIC1_SUBNET', nic2: 'REQUIRED_BW_NIC2_SUBNET' }
    utilities: { nic1: 'REQUIRED_UTILITIES_NIC1_SUBNET', nic2: 'REQUIRED_UTILITIES_NIC2_SUBNET' }
    hybris: { nic1: 'REQUIRED_HYBRIS_NIC1_SUBNET', nic2: 'REQUIRED_HYBRIS_NIC2_SUBNET' }
    cloudConnector: { nic1: 'REQUIRED_CLOUD_NIC1_SUBNET', nic2: 'REQUIRED_CLOUD_NIC2_SUBNET' }
  }
  dnsServers: []
}

param ownership = {
  serviceOwner: 'REQUIRED_SERVICE_OWNER'
  serviceTicketRequestId: 'REQUIRED_PRODUCTION_CHANGE_REQUEST'
  projectName: 'SAP'
  costCodeId: 'REQUIRED_COST_CODE'
}
param bootstrap = {
  mode: 'disabled'
}
