using '../main.bicep'

var catalog = loadJsonContent('../catalog.json')

param environmentName = 'development'
param location = 'uksouth'
param namePrefix = 'azsu'
param deploymentNumber = '20'
param virtualMachines = catalog.landscapes.cloudConnector

param image = {
  publisher: 'SUSE'
  offer: 'sles-sap-15-sp6-byos'
  sku: 'gen2'
  version: 'REQUIRED_DEVELOPMENT_PINNED_IMAGE_VERSION'
}
param adminUsername = 'azureuser'
param sshPublicKey = 'REQUIRED_DEVELOPMENT_SSH_PUBLIC_KEY'
param encryptionAtHost = true
param sapSupportReviewReference = 'REQUIRED_SAP_SUPPORT_REVIEW_REFERENCE'

param network = {
  resourceGroupName: 'REQUIRED_DEVELOPMENT_NETWORK_RESOURCE_GROUP'
  virtualNetworkName: 'REQUIRED_DEVELOPMENT_VNET'
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
  serviceTicketRequestId: 'REQUIRED_CHANGE_REQUEST'
  projectName: 'SAP'
  costCodeId: 'REQUIRED_COST_CODE'
}
param bootstrap = {
  mode: 'disabled'
}
