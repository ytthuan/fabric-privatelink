// Bidirectional hub <-> spoke VNet peering with gateway transit.
// The hub side enables gateway transit; the spoke side consumes the hub's VPN gateway
// (useRemoteGateways) so on-premises traffic can reach the spoke through the hub.
// Requires the hub VPN gateway to already exist (enforce via dependsOn at the call site).
@description('Hub VNet name.')
param hubVnetName string

@description('Hub VNet resource id.')
param hubVnetId string

@description('Spoke VNet name.')
param spokeVnetName string

@description('Spoke VNet resource id.')
param spokeVnetId string

resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: '${hubVnetName}/to-${spokeVnetName}'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}

resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: '${spokeVnetName}/to-${hubVnetName}'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
  }
  dependsOn: [
    hubToSpoke
  ]
}
