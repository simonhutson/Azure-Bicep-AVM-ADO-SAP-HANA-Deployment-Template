targetScope = 'resourceGroup'

import {
  environmentType
  virtualMachineType
  imageType
  marketplacePlanType
  networkType
  ownershipType
  bootstrapType
} from './types.bicep'

@description('Deployment environment. Names and ownership tags are isolated by environment.')
param environmentName environmentType

@description('Azure region for the VMs and NICs. The referenced VNet must be in this region.')
param location string = resourceGroup().location

@description('Short, lowercase location or organization prefix, for example azsu.')
@minLength(2)
@maxLength(12)
param namePrefix string

@description('Two-digit landscape identifier used in resource names.')
@minLength(2)
@maxLength(2)
param deploymentNumber string

@description('Explicit role/instance selection. Use a catalogue landscape or supply a single/custom VM list.')
@minLength(1)
@maxLength(50)
param virtualMachines virtualMachineType[]

@description('Pinned SLES for SAP 15 marketplace image. latest is rejected by pipeline preflight.')
param image imageType

@description('Purchase plan only when required by the selected marketplace image. Terms must already be accepted.')
param marketplacePlan marketplacePlanType?

@description('Administrator account. Password authentication is always disabled.')
@minLength(1)
@maxLength(32)
param adminUsername string = 'azureuser'

@description('SSH public key only. Never supply or store the private key in this repository or deployment.')
@minLength(1)
param sshPublicKey string

@description('Existing, same-subscription VNet and role-specific subnet pairs. No shared networking is created.')
param network networkType

@description('Required ownership and change-request metadata.')
param ownership ownershipType

@description('Non-secret change/evidence reference for the operator review of SAP Note 1928533, workload/OS/HANA support and storage requirements. This is not automated certification.')
@minLength(1)
param sapSupportReviewReference string

@description('Additional resource tags. Required ownership/management tags cannot be overridden.')
param additionalTags object = {}

@description('Deployment entry point recorded in the Source tag.')
param deploymentSource 'Azure DevOps / Bicep AVM' | 'Azure portal / Bicep AVM' = 'Azure DevOps / Bicep AVM'

@description('Enable host encryption. Confirm regional/SKU support and the subscription EncryptionAtHost feature.')
param encryptionAtHost bool = true

@description('Reviewed custom-script bootstrap only. Disabled by default.')
param bootstrap bootstrapType = {
  mode: 'disabled'
}

var catalog = loadJsonContent('./catalog.json')
var environmentCodes = {
  development: 'd'
  test: 't'
  production: 'p'
}
var environmentCode = environmentCodes[environmentName]
var roleIds = union(map(virtualMachines, vm => vm.role), [])
var commonTags = union(additionalTags, {
  Environment: environmentName
  'Service Owner': ownership.serviceOwner
  'Service Ticket Request ID': ownership.serviceTicketRequestId
  Source: deploymentSource
  'Project Name': ownership.projectName
  'Cost Code ID': ownership.costCodeId
  ManagedBy: 'Bicep-AVM'
  'SAP Support Review': sapSupportReviewReference
})
var instances = map(virtualMachines, vm => {
  role: vm.role
  name: '${namePrefix}-${environmentCode}-${catalog.roles[vm.role].category}${deploymentNumber}${vm.instance}'
  vmSize: vm.?vmSize ?? (environmentName == 'production'
    ? (catalog.roles[vm.role].?productionVmSize ?? catalog.roles[vm.role].vmSize)
    : catalog.roles[vm.role].vmSize)
  dataDiskSizesGB: vm.?dataDiskSizesGB ?? catalog.roles[vm.role].dataDiskSizesGB
  category: catalog.roles[vm.role].category
  subnets: network.subnetPairs[catalog.roles[vm.role].network]
  nicAddresses: [
    vm.nic1IpAddresses
    vm.nic2IpAddresses
  ]
  tags: union(commonTags, {
    'Service Name': catalog.roles[vm.role].serviceName
  })
})

module availabilitySets 'br/public:avm/res/compute/availability-set:0.2.4' = [
  for role in roleIds: {
    name: 'as-${environmentCode}-${catalog.roles[role].category}${deploymentNumber}-${catalog.roles[role].availabilitySuffix}'
    params: {
      name: '${namePrefix}-as-sap-${environmentName}-${catalog.roles[role].category}${deploymentNumber}-${catalog.roles[role].availabilitySuffix}-001'
      location: location
      skuName: 'Aligned'
      platformFaultDomainCount: 2
      platformUpdateDomainCount: 20
      enableTelemetry: false
      tags: union(commonTags, {
        'Service Name': catalog.roles[role].serviceName
      })
    }
  }
]

@batchSize(4)
module vms 'br/public:avm/res/compute/virtual-machine:0.22.3' = [
  for vm in instances: {
    name: 'vm-${vm.name}'
    params: {
      name: vm.name
      location: location
      osType: 'Linux'
      vmSize: vm.vmSize
      imageReference: image
      plan: marketplacePlan
      licenseType: 'SLES_BYOS'
      adminUsername: adminUsername
      disablePasswordAuthentication: true
      publicKeys: [
        {
          path: '/home/${adminUsername}/.ssh/authorized_keys'
          keyData: sshPublicKey
        }
      ]
      managedIdentities: {
        systemAssigned: true
        userAssignedResourceIds: bootstrap.mode == 'custom-script' ? [bootstrap.managedIdentityResourceId] : []
      }
      securityType: 'Standard'
      encryptionAtHost: encryptionAtHost
      availabilityZone: -1
      availabilitySetResourceId: availabilitySets[indexOf(roleIds, vm.role)].outputs.resourceId
      bootDiagnostics: true
      provisionVMAgent: true
      patchMode: 'ImageDefault'
      osDisk: {
        name: '${vm.name}-osdisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Detach'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      dataDisks: map(vm.dataDiskSizesGB, (sizeGB, lun) => {
        name: '${vm.name}-datadisk-${padLeft(lun, 2, '0')}'
        lun: lun
        diskSizeGB: sizeGB
        createOption: 'Empty'
        caching: 'None'
        deleteOption: 'Detach'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        tags: vm.tags
      })
      nicConfigurations: map(range(0, 2), nicIndex => {
        name: '${vm.name}-nic-${nicIndex + 1}'
        deleteOption: 'Detach'
        enableAcceleratedNetworking: vm.category == 'han'
        enableIPForwarding: false
        dnsServers: network.?dnsServers ?? []
        tags: vm.tags
        ipConfigurations: map(vm.nicAddresses[nicIndex], (address, ipIndex) => {
          name: 'ipconfig${padLeft(ipIndex, 2, '0')}'
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: empty(address) ? 'Dynamic' : 'Static'
          privateIPAddress: empty(address) ? null : address
          subnetResourceId: resourceId(
            network.resourceGroupName,
            'Microsoft.Network/virtualNetworks/subnets',
            network.virtualNetworkName,
            nicIndex == 0 ? vm.subnets.nic1 : vm.subnets.nic2
          )
        })
      })
      extensionCustomScriptConfig: bootstrap.mode == 'custom-script'
        ? {
            name: 'reviewed-bootstrap'
            typeHandlerVersion: '2.1'
            autoUpgradeMinorVersion: true
            forceUpdateTag: bootstrap.sha256
            supressFailures: false
            settings: {
              fileUris: [
                bootstrap.scriptUri
              ]
              commandToExecute: 'echo "${bootstrap.sha256}  bootstrap.sh" | sha256sum --check --status && /bin/bash ./bootstrap.sh --role ${vm.role} --environment ${environmentName}'
            }
            protectedSettings: {
              managedIdentityResourceId: bootstrap.managedIdentityResourceId
            }
            tags: vm.tags
          }
        : null
      enableTelemetry: false
      tags: vm.tags
    }
  }
]

@description('Non-secret VM identities, managed identities and private NIC configurations. This is infrastructure state, not SAP readiness.')
output virtualMachineResources array = [
  for (vm, index) in instances: {
    role: vm.role
    name: vms[index].outputs.name
    resourceId: vms[index].outputs.resourceId
    systemAssignedIdentityPrincipalId: vms[index].outputs.?systemAssignedMIPrincipalId
    nicConfigurations: vms[index].outputs.nicConfigurations
  }
]
