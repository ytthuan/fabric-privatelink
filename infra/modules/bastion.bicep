// Optional Azure Bastion host for browser-based RDP to a VM without a public IP.
// Disabled by default (access is intended over the VPN); enable as a break-glass option.
@description('Bastion host name.')
param name string

@description('Azure region.')
param location string

@description('AzureBastionSubnet resource id.')
param bastionSubnetId string

resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${name}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: name
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconf'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

output bastionId string = bastion.id
