// =============================================================================
// PRODUCTION: Microsoft Fabric tenant Private Link landing (no on-prem, existing capacity)
// -----------------------------------------------------------------------------
// Deploys ONLY what is needed to make an EXISTING Fabric capacity / tenant reachable
// privately from your real corporate network:
//   - one "services" VNet with a private-endpoint subnet (+ optional DNS resolver subnet)
//   - an Azure DNS Private Resolver inbound endpoint (so your on-prem DNS can forward
//     Fabric queries privately)            [optional, on by default]
//   - the three Fabric/Power BI private DNS zones (+ VNet links)
//   - the tenant Private Link service + tenant private endpoint (groupId 'tenant')
//   - an optional peering to your existing connectivity hub (ExpressRoute/VPN)
//
// It does NOT create: a Fabric capacity (you select an existing one), any simulated
// on-prem network, VPN gateways, VMs, or VNet-to-VNet connections — those belong to the
// lab template (infra/). Connectivity to on-prem is your existing ExpressRoute/Site-to-Site
// VPN, peered to this VNet.
// =============================================================================
targetScope = 'resourceGroup'

@description('Short prefix for resource names (lowercase alphanumeric).')
@minLength(3)
@maxLength(10)
param namePrefix string = 'fabpl'

@description('Capacity mode. false = reference an EXISTING capacity (set existingFabricCapacityResourceId). true = CREATE a new capacity (set fabricCapacityAdmins, optionally newFabricCapacityName/Sku).')
param createFabricCapacity bool = false

@description('EXISTING mode: resource ID of your Fabric capacity (Microsoft.Fabric/capacities). Required when createFabricCapacity = false.')
param existingFabricCapacityResourceId string = ''

@description('CREATE mode: capacity SKU. Required tier is Fabric (e.g. F2, F4, F8, F64).')
param newFabricCapacitySku string = 'F2'

@description('CREATE mode: capacity name (3-63 lowercase alphanumeric). Empty = auto-generate from namePrefix.')
param newFabricCapacityName string = ''

@description('CREATE mode: capacity administrators (Entra user UPNs or service-principal object ids). Required when createFabricCapacity = true.')
param fabricCapacityAdmins array = []

@description('Entra tenant id used for the Private Link service. Defaults to the deployment tenant.')
param tenantId string = tenant().tenantId

@description('Azure region for the VNet, resolver, private endpoint, and (when created) the capacity. Empty = the resource group region.')
param location string = ''

@description('Address space for the services VNet. Must not overlap your existing networks.')
param vnetAddressSpace string = '10.40.0.0/16'

@description('Private-endpoint subnet prefix (inside vnetAddressSpace).')
param peSubnetPrefix string = '10.40.1.0/24'

@description('DNS Private Resolver inbound subnet prefix (/28 or larger, inside vnetAddressSpace).')
param resolverSubnetPrefix string = '10.40.2.0/28'

@description('Deploy an Azure DNS Private Resolver inbound endpoint (so on-prem DNS can conditionally forward Fabric names privately).')
param deployDnsResolver bool = true

@description('Static IP for the resolver inbound endpoint (must be inside resolverSubnetPrefix).')
param resolverInboundIp string = '10.40.2.4'

@description('Optional: resource ID of your EXISTING connectivity hub VNet (with ExpressRoute/VPN gateway) to peer this VNet to. Empty = no peering (peer it yourself).')
param peerToHubVnetResourceId string = ''

@description('When peering to the hub, use the hub\'s remote gateway (ExpressRoute/VPN) for on-prem reachability. Requires the hub side to allow gateway transit and have a gateway.')
param useRemoteGateways bool = true

// ---------------------------------------------------------------------------
// Fabric capacity — either reference an existing one or create a new one.
// effectiveLocation defaults to the resource group region (the tenant Private Link
// service is global, so the VNet/PE region is independent of the capacity region).
// ---------------------------------------------------------------------------
var effectiveLocation = empty(location) ? resourceGroup().location : location

// Safe placeholder so split()/index access never fails in CREATE mode (where the
// existing reference is not deployed and existingFabricCapacityResourceId is empty).
var existingCapIdSafe = empty(existingFabricCapacityResourceId) ? '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/placeholder/providers/Microsoft.Fabric/capacities/placeholder' : existingFabricCapacityResourceId
var existingCapParts = split(existingCapIdSafe, '/')

resource existingCapacity 'Microsoft.Fabric/capacities@2023-11-01' existing = if (!createFabricCapacity) {
  name: last(existingCapParts)
  scope: resourceGroup(existingCapParts[2], existingCapParts[4])
}

resource newCapacity 'Microsoft.Fabric/capacities@2023-11-01' = if (createFabricCapacity) {
  name: empty(newFabricCapacityName) ? toLower('${namePrefix}cap${uniqueString(resourceGroup().id)}') : newFabricCapacityName
  location: effectiveLocation
  sku: {
    name: newFabricCapacitySku
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: fabricCapacityAdmins
    }
  }
}

// ---------------------------------------------------------------------------
// Services VNet (PE subnet + optional resolver subnet)
// ---------------------------------------------------------------------------
var vnetName = 'vnet-${namePrefix}-fabric'

module vnet '../infra/modules/network.bicep' = {
  name: 'vnet-fabric'
  params: {
    name: vnetName
    location: effectiveLocation
    addressPrefixes: [
      vnetAddressSpace
    ]
    subnets: concat(
      [
        {
          name: 'snet-pe'
          addressPrefix: peSubnetPrefix
          disablePeNetworkPolicies: true
        }
      ],
      deployDnsResolver ? [
        {
          name: 'snet-dnspr-inbound'
          addressPrefix: resolverSubnetPrefix
          delegation: 'Microsoft.Network/dnsResolvers'
        }
      ] : []
    )
  }
}

// ---------------------------------------------------------------------------
// DNS Private Resolver inbound endpoint (optional)
// ---------------------------------------------------------------------------
module resolver '../infra/modules/dnsresolver.bicep' = if (deployDnsResolver) {
  name: 'dns-resolver'
  params: {
    name: 'dnspr-${namePrefix}'
    location: effectiveLocation
    vnetId: vnet.outputs.id
    inboundSubnetId: vnet.outputs.subnetIds['snet-dnspr-inbound']
    inboundIp: resolverInboundIp
  }
}

// ---------------------------------------------------------------------------
// Private DNS zones (3) + links to the services VNet
// ---------------------------------------------------------------------------
module privateDns '../infra/modules/privatedns.bicep' = {
  name: 'private-dns'
  params: {
    vnetId: vnet.outputs.id
  }
}

// ---------------------------------------------------------------------------
// Tenant Private Link service + private endpoint (groupId 'tenant') + DNS zone group
// ---------------------------------------------------------------------------
module fabricPrivateLink 'modules/fabric-privatelink.bicep' = {
  name: 'fabric-privatelink'
  params: {
    privateLinkServiceName: 'pls-${namePrefix}-fabric'
    privateEndpointName: 'pe-${namePrefix}-fabric-tenant'
    location: effectiveLocation
    tenantId: tenantId
    peSubnetId: vnet.outputs.subnetIds['snet-pe']
    privateDnsZoneConfigs: privateDns.outputs.zoneConfigs
  }
}

// ---------------------------------------------------------------------------
// Optional peering to your existing connectivity hub (ExpressRoute / VPN)
// Creates the local (services -> hub) side only. The hub admin must create the
// reciprocal hub -> services peering with allowGatewayTransit = true.
// ---------------------------------------------------------------------------
resource servicesVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource peeringToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = if (!empty(peerToHubVnetResourceId)) {
  parent: servicesVnet
  name: 'to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: peerToHubVnetResourceId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: useRemoteGateways
  }
  dependsOn: [
    vnet
  ]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output servicesVnetId string = vnet.outputs.id
output peSubnetId string = vnet.outputs.subnetIds['snet-pe']
output privateEndpointId string = fabricPrivateLink.outputs.privateEndpointId
output resolverInboundIp string = deployDnsResolver ? resolverInboundIp : ''
output fabricCapacityMode string = createFabricCapacity ? 'created' : 'existing'
output fabricCapacityName string = createFabricCapacity ? newCapacity.name : existingCapacity.name
output fabricCapacityId string = createFabricCapacity ? newCapacity.id : existingCapacity.id
@description('Conditional-forwarder domains to add on your on-prem DNS, pointing at resolverInboundIp.')
output onPremForwarderDomains array = [
  'analysis.windows.net'
  'pbidedicated.windows.net'
  'prod.powerquery.microsoft.com'
  'powerbi.com'
  'fabric.microsoft.com'
]
