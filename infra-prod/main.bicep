// =============================================================================
// PRODUCTION entry point (subscription scope) for `azd provision` / `az deployment sub create`.
// Creates the resource group, then deploys the Fabric tenant Private Link landing
// (resources.bicep) against an EXISTING Fabric capacity. No on-prem network is created.
//
// For the portal "Deploy to Azure" button or `az deployment group create`, use the compiled,
// resource-group-scoped azuredeploy.json instead (built from resources.bicep).
// =============================================================================
targetScope = 'subscription'

@description('Environment name (azd). Used to name the resource group and tag resources.')
@minLength(1)
@maxLength(20)
param environmentName string = 'fabricpl-prod'

@description('Resource group region. Also used for resources unless overridden in the template.')
param location string

@description('Optional explicit resource group name. Defaults to rg-<environmentName>.')
param resourceGroupName string = 'rg-${environmentName}'

@description('Capacity mode. false = use existing capacity (set existingFabricCapacityResourceId). true = create a new capacity (set fabricCapacityAdmins).')
param createFabricCapacity bool = false

@description('EXISTING mode: resource ID of your Fabric capacity. Required when createFabricCapacity = false.')
param existingFabricCapacityResourceId string = ''

@description('CREATE mode: capacity SKU (F2, F4, F8, F64, ...).')
param newFabricCapacitySku string = 'F2'

@description('CREATE mode: capacity name (empty = auto-generate).')
param newFabricCapacityName string = ''

@description('CREATE mode: capacity administrators (Entra UPNs or SP object ids). Required when createFabricCapacity = true.')
param fabricCapacityAdmins array = []

@description('Short prefix for resource names.')
param namePrefix string = 'fabpl'

@description('Entra tenant id for the Private Link service. Defaults to the deployment tenant.')
param tenantId string = tenant().tenantId

@description('Services VNet address space. Must not overlap your existing networks.')
param vnetAddressSpace string = '10.40.0.0/16'

@description('Private-endpoint subnet prefix.')
param peSubnetPrefix string = '10.40.1.0/24'

@description('DNS Private Resolver inbound subnet prefix.')
param resolverSubnetPrefix string = '10.40.2.0/28'

@description('Deploy the DNS Private Resolver inbound endpoint.')
param deployDnsResolver bool = true

@description('Static IP for the resolver inbound endpoint.')
param resolverInboundIp string = '10.40.2.4'

@description('Optional: existing hub VNet resource ID (ExpressRoute/VPN) to peer to.')
param peerToHubVnetResourceId string = ''

@description('Use the hub remote gateway when peering.')
param useRemoteGateways bool = true

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

module resources 'resources.bicep' = {
  name: 'fabric-pl-prod'
  scope: rg
  params: {
    namePrefix: namePrefix
    createFabricCapacity: createFabricCapacity
    existingFabricCapacityResourceId: existingFabricCapacityResourceId
    newFabricCapacitySku: newFabricCapacitySku
    newFabricCapacityName: newFabricCapacityName
    fabricCapacityAdmins: fabricCapacityAdmins
    tenantId: tenantId
    location: location
    vnetAddressSpace: vnetAddressSpace
    peSubnetPrefix: peSubnetPrefix
    resolverSubnetPrefix: resolverSubnetPrefix
    deployDnsResolver: deployDnsResolver
    resolverInboundIp: resolverInboundIp
    peerToHubVnetResourceId: peerToHubVnetResourceId
    useRemoteGateways: useRemoteGateways
  }
}

output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_LOCATION string = location
output RESOLVER_INBOUND_IP string = resources.outputs.resolverInboundIp
output PRIVATE_ENDPOINT_ID string = resources.outputs.privateEndpointId
output FABRIC_CAPACITY_MODE string = resources.outputs.fabricCapacityMode
output FABRIC_CAPACITY_NAME string = resources.outputs.fabricCapacityName
