// Microsoft Fabric F2 capacity, plus the tenant-level Private Link service and a private
// endpoint that routes Fabric traffic privately.
//
// Grounded in:
//  - Capacity: https://learn.microsoft.com/azure/templates/microsoft.fabric/capacities
//  - Tenant Private Link: https://learn.microsoft.com/fabric/security/security-private-links-use
//    "Use Microsoft.PowerBI/privateLinkServicesForPowerBI as the type, even for Fabric."
//    Private endpoint target subresource (groupId) = 'tenant'.
@description('Fabric capacity name (3-63 lowercase alphanumeric).')
param capacityName string

@description('Azure region for the capacity.')
param location string

@description('Capacity SKU name.')
param skuName string = 'F2'

@description('Capacity administrators (Entra user UPNs or service principal object ids). Required.')
param adminMembers array

@description('Deploy the tenant Private Link service + private endpoint. Requires tenant Azure Private Link to be enabled in the Fabric admin portal first.')
param deployPrivateLink bool = true

@description('Entra tenant id used for the Private Link service.')
param tenantId string

@description('Private Link service (privateLinkServicesForPowerBI) resource name.')
param privateLinkServiceName string

@description('Private endpoint name.')
param privateEndpointName string

@description('Private endpoint subnet id.')
param peSubnetId string

@description('Private DNS zone configs [{ name, id }] for the endpoint DNS zone group.')
param privateDnsZoneConfigs array = []

resource capacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  sku: {
    name: skuName
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: adminMembers
    }
  }
}

resource plService 'Microsoft.PowerBI/privateLinkServicesForPowerBI@2020-06-01' = if (deployPrivateLink) {
  name: privateLinkServiceName
  location: 'global'
  properties: {
    tenantId: tenantId
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (deployPrivateLink) {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-conn'
        properties: {
          privateLinkServiceId: plService.id
          groupIds: [
            'tenant'
          ]
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (deployPrivateLink && !empty(privateDnsZoneConfigs)) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for z in privateDnsZoneConfigs: {
        name: z.name
        properties: {
          privateDnsZoneId: z.id
        }
      }
    ]
  }
}

output capacityId string = capacity.id
output capacityName string = capacity.name
output privateLinkServiceId string = deployPrivateLink ? plService.id : ''
output privateEndpointId string = deployPrivateLink ? privateEndpoint.id : ''
