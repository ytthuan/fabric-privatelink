// Reciprocal VNet-to-VNet VPN connections between the hub and on-prem gateways.
// Both connections must share the same key. Gateway ids are passed in (created by the
// vpngateway modules), so these connections implicitly depend on both gateways existing
// and there is no module dependency cycle.
@description('Hub gateway resource id.')
param hubGatewayId string

@description('On-prem gateway resource id.')
param onpremGatewayId string

@description('Hub region.')
param hubLocation string

@description('On-prem region.')
param onpremLocation string

@description('Shared key used by both connections.')
@secure()
param sharedKey string

resource hubToOnprem 'Microsoft.Network/connections@2023-11-01' = {
  name: 'cn-hub-to-onprem'
  location: hubLocation
  properties: {
    connectionType: 'Vnet2Vnet'
    routingWeight: 0
    enableBgp: true
    sharedKey: sharedKey
    virtualNetworkGateway1: {
      id: hubGatewayId
      properties: {}
    }
    virtualNetworkGateway2: {
      id: onpremGatewayId
      properties: {}
    }
  }
}

resource onpremToHub 'Microsoft.Network/connections@2023-11-01' = {
  name: 'cn-onprem-to-hub'
  location: onpremLocation
  properties: {
    connectionType: 'Vnet2Vnet'
    routingWeight: 0
    enableBgp: true
    sharedKey: sharedKey
    virtualNetworkGateway1: {
      id: onpremGatewayId
      properties: {}
    }
    virtualNetworkGateway2: {
      id: hubGatewayId
      properties: {}
    }
  }
}

output hubToOnpremId string = hubToOnprem.id
output onpremToHubId string = onpremToHub.id
