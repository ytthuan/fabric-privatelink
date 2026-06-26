// Tenant-level Fabric / Power BI Private Link service + private endpoint (+ DNS zone group).
// Production variant: does NOT create a Fabric capacity. The private endpoint targets the
// tenant Private Link service (Microsoft.PowerBI/privateLinkServicesForPowerBI, groupId 'tenant'),
// which fronts the whole Fabric/Power BI tenant — portal, APIs, OneLake, all workspaces/capacities.
//
// Grounded in: https://learn.microsoft.com/fabric/security/security-private-links-use
@description('Private Link service (privateLinkServicesForPowerBI) resource name.')
param privateLinkServiceName string

@description('Private endpoint name.')
param privateEndpointName string

@description('Location for the private endpoint (the PLS and DNS zones are global).')
param location string

@description('Entra tenant id used for the Private Link service.')
param tenantId string

@description('Private endpoint subnet id.')
param peSubnetId string

@description('Private DNS zone configs [{ name, id }] for the endpoint DNS zone group.')
param privateDnsZoneConfigs array = []

resource plService 'Microsoft.PowerBI/privateLinkServicesForPowerBI@2020-06-01' = {
  name: privateLinkServiceName
  location: 'global'
  properties: {
    tenantId: tenantId
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
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

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (!empty(privateDnsZoneConfigs)) {
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

output privateLinkServiceId string = plService.id
output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
