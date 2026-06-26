// Windows Server 2022 VM with a private-only NIC. Optionally runs a Custom Script
// Extension (used for the on-premises DNS forwarder). No public IP is ever attached.
@description('VM name (also used as computer name; keep <= 15 chars).')
param name string

@description('Azure region.')
param location string

@description('Subnet resource id for the NIC.')
param subnetId string

@description('Admin username.')
param adminUsername string

@description('Admin password.')
@secure()
param adminPassword string

@description('VM size.')
param vmSize string = 'Standard_D2s_v3'

@description('Static private IP. Empty = dynamic.')
param privateIp string = ''

@description('Per-NIC DNS servers. Set to ["168.63.129.16"] for the DNS server VM so it can resolve while it bootstraps. Empty = inherit from VNet.')
param nicDnsServers array = []

@description('Inline command for a Windows Custom Script Extension. Empty = no extension.')
param customScriptCommand string = ''

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${name}-nic'
  location: location
  properties: {
    dnsSettings: empty(nicDnsServers) ? null : {
      dnsServers: nicDnsServers
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: empty(privateIp) ? 'Dynamic' : 'Static'
          privateIPAddress: empty(privateIp) ? null : privateIp
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: name
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource customScript 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (!empty(customScriptCommand)) {
  parent: vm
  name: 'setup-dns'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: customScriptCommand
    }
  }
}

output vmId string = vm.id
output vmName string = vm.name
output nicId string = nic.id
