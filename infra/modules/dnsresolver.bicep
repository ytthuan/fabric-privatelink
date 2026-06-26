// Azure DNS Private Resolver with an inbound endpoint.
// The inbound endpoint gives on-premises DNS servers a private IP to forward Fabric
// queries to; it resolves the private DNS zones linked to this VNet.
// Inbound-only: an outbound endpoint is not needed for on-premises -> Azure resolution.
// Grounded in:
// https://learn.microsoft.com/azure/dns/dns-private-resolver-get-started-bicep
@description('Resolver name.')
param name string

@description('Azure region. Must match the VNet region.')
param location string

@description('Hub VNet resource id.')
param vnetId string

@description('Inbound endpoint subnet id (delegated to Microsoft.Network/dnsResolvers).')
param inboundSubnetId string

@description('Static private IP for the inbound endpoint (must be inside the inbound subnet).')
param inboundIp string

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: name
  location: location
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource inbound 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: resolver
  name: 'inbound'
  location: location
  properties: {
    ipConfigurations: [
      {
        privateIpAllocationMethod: 'Static'
        privateIpAddress: inboundIp
        subnet: {
          id: inboundSubnetId
        }
      }
    ]
  }
}

output resolverId string = resolver.id
@description('Configured static inbound endpoint IP (use as the on-prem conditional-forwarder target).')
output inboundIp string = inboundIp
