// Virtual network with inline subnets.
// Subnets are defined inline (not as separate child resources) so the VNet is created
// atomically, which avoids ordering races when subnets carry NSGs, delegations, or
// private-endpoint network policy settings.
@description('VNet name.')
param name string

@description('Azure region.')
param location string

@description('Address space, e.g. ["10.10.0.0/16"].')
param addressPrefixes array

@description('''
Subnet definitions. Each item:
{
  name: string
  addressPrefix: string
  nsgId: string?            // associate an NSG
  delegation: string?       // service name, e.g. "Microsoft.Network/dnsResolvers"
  disablePeNetworkPolicies: bool?  // set true for private endpoint subnets
}
''')
param subnets array

@description('Custom DNS servers for the VNet. Empty = Azure-provided DNS.')
param dnsServers array = []

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    dhcpOptions: empty(dnsServers) ? null : {
      dnsServers: dnsServers
    }
    subnets: [
      for s in subnets: {
        name: s.name
        properties: {
          addressPrefix: s.addressPrefix
          networkSecurityGroup: (contains(s, 'nsgId') && !empty(s.nsgId)) ? {
            id: s.nsgId
          } : null
          delegations: (contains(s, 'delegation') && !empty(s.delegation)) ? [
            {
              name: 'delegation'
              properties: {
                serviceName: s.delegation
              }
            }
          ] : null
          privateEndpointNetworkPolicies: (contains(s, 'disablePeNetworkPolicies') && bool(s.disablePeNetworkPolicies)) ? 'Disabled' : 'Enabled'
        }
      }
    ]
  }
}

output id string = vnet.id
output name string = vnet.name
@description('Map of subnet name -> resource id.')
output subnetIds object = toObject(vnet.properties.subnets, s => s.name, s => s.id)
