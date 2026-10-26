targetScope = 'resourceGroup'

import { marketplacePlanType } from '../types.bicep'

@description('Region of the existing VNet and the development VM.')
param location string = 'uksouth'

@description('2-12 lowercase alphanumeric characters, beginning with a letter.')
@minLength(2)
@maxLength(12)
param namePrefix string = 'azsu'

@description('Development deployment number, rendered as two digits in resource names.')
@minValue(0)
@maxValue(99)
param deploymentNumber int = 20

@description('Non-root Linux administrator username.')
@minLength(1)
@maxLength(32)
param adminUsername string = 'azureuser'

@description('OpenSSH RSA or ED25519 public key. Never supply a private key.')
@minLength(1)
param sshPublicKey string

@description('Major component of an available SUSE SLES for SAP 15 SP6 BYOS Gen2 image version.')
@minValue(0)
param imageMajorVersion int = 15

@description('Minor component of the selected image version.')
@minValue(0)
param imageMinorVersion int = 6

@description('Build component of the exact image version. Select an available version; latest and wildcards are not accepted.')
@minValue(0)
param imageBuildVersion int

@description('Optional name/product/publisher purchase-plan object from the selected image metadata. Accept marketplace terms separately.')
param marketplacePlan marketplacePlanType?

@description('Resource group containing the existing VNet, in the deployment subscription.')
@minLength(1)
param networkResourceGroupName string

@description('Existing VNet in the selected region. This deployment does not create networking.')
@minLength(1)
param virtualNetworkName string

@description('Existing subnet for the Cloud Connector primary NIC.')
@minLength(1)
param nic1SubnetName string

@description('Existing subnet for the Cloud Connector secondary NIC.')
@minLength(1)
param nic2SubnetName string

@description('Service owner recorded in resource tags.')
@minLength(1)
param serviceOwner string

@description('Change request or service ticket recorded in resource tags.')
@minLength(1)
param serviceTicketRequestId string

@description('Project name recorded in resource tags.')
@minLength(1)
param projectName string = 'SAP'

@description('Cost code recorded in resource tags.')
@minLength(1)
param costCodeId string

@description('Non-secret reference to the authorized SAP product, exact SKU, OS and storage support review.')
@minLength(1)
param sapSupportReviewReference string

var catalog = loadJsonContent('../catalog.json')
var subnetPair = {
  nic1: nic1SubnetName
  nic2: nic2SubnetName
}

module infrastructure '../main.bicep' = {
  params: {
    environmentName: 'development'
    location: location
    namePrefix: namePrefix
    deploymentNumber: padLeft(deploymentNumber, 2, '0')
    virtualMachines: catalog.landscapes.cloudConnector
    image: {
      publisher: 'SUSE'
      offer: 'sles-sap-15-sp6-byos'
      sku: 'gen2'
      version: '${imageMajorVersion}.${imageMinorVersion}.${imageBuildVersion}'
    }
    marketplacePlan: marketplacePlan
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    network: {
      resourceGroupName: networkResourceGroupName
      virtualNetworkName: virtualNetworkName
      subnetPairs: {
        gateway: subnetPair
        po: subnetPair
        bw: subnetPair
        utilities: subnetPair
        hybris: subnetPair
        cloudConnector: subnetPair
      }
      dnsServers: []
    }
    ownership: {
      serviceOwner: serviceOwner
      serviceTicketRequestId: serviceTicketRequestId
      projectName: projectName
      costCodeId: costCodeId
    }
    sapSupportReviewReference: sapSupportReviewReference
    deploymentSource: 'Azure portal / Bicep AVM'
    encryptionAtHost: true
    bootstrap: {
      mode: 'disabled'
    }
  }
}

@description('VM identities, managed identities and private NIC configurations, not SAP readiness.')
output virtualMachineResources array = infrastructure.outputs.virtualMachineResources
