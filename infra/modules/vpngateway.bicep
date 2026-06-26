// Route-based VPN gateway with its public IP. Used on both sides of the VNet-to-VNet link.
// NOTE: VPN gateways take a long time to provision. The public IP is the tunnel endpoint
// (expected) and does not expose the data plane.
@description('Gateway name.')
param name string

@description('Azure region.')
param location string

@description('GatewaySubnet resource id.')
param gatewaySubnetId string

@description('Gateway SKU.')
param skuName string = 'VpnGw1'

@description('BGP Autonomous System Number. Must be non-reserved (64512-65514 or 65521-65534) and differ between the two gateways for the VNet-to-VNet BGP session.')
param asn int = 65521

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

resource gateway 'Microsoft.Network/virtualNetworkGateways@2023-11-01' = {
  name: name
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: true
    activeActive: false
    sku: {
      name: skuName
      tier: skuName
    }
    bgpSettings: {
      asn: asn
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
  }
}

output gatewayId string = gateway.id
output gatewayName string = gateway.name
