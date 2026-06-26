// Route-based VPN gateway with its public IP. Used on both sides of the VNet-to-VNet link.
// NOTE: VPN gateways take a long time to provision. The public IP is the tunnel endpoint
// (expected) and does not expose the data plane.
@description('Gateway name.')
param name string

@description('Azure region.')
param location string

@description('GatewaySubnet resource id.')
param gatewaySubnetId string

@description('Gateway SKU. Must be an AZ SKU (VpnGw1AZ-VpnGw5AZ); non-AZ VpnGw1-5 SKUs are no longer allowed for new VPN gateways. AZ SKUs require the associated Standard public IP to have zones configured (set on the pip below).')
param skuName string = 'VpnGw1AZ'

@description('BGP Autonomous System Number. Must be non-reserved (64512-65514 or 65521-65534) and differ between the two gateways for the VNet-to-VNet BGP session.')
param asn int = 65521

// AZ VPN gateway SKUs reject no-zone public IPs (VmssVpnGatewayPublicIpsMustHaveZonesConfigured),
// so the Standard public IP must declare zones. ['1','2','3'] makes it zone-redundant.
resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${name}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
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
