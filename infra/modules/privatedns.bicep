// Private DNS zones required for Microsoft Fabric / Power BI tenant-level Private Link,
// each linked to the hub VNet so the DNS Private Resolver (in that VNet) can resolve them.
// Zone list grounded in:
// https://learn.microsoft.com/fabric/security/security-private-links-use (Step 5)
// The tenant private endpoint registers A records into these three zones only.
@description('Hub VNet resource id to link the zones to.')
param vnetId string

@description('''
Private DNS zone names. Default = the three tenant-level Fabric/Power BI zones.
''')
param zoneNames array = [
  'privatelink.analysis.windows.net'
  'privatelink.pbidedicated.windows.net'
  'privatelink.prod.powerquery.microsoft.com'
]

resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for z in zoneNames: {
    name: z
    location: 'global'
  }
]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (z, i) in zoneNames: {
    parent: zones[i]
    name: 'link-${uniqueString(vnetId)}'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnetId
      }
    }
  }
]

@description('Array of { name, id } for each zone, for a private endpoint DNS zone group.')
output zoneConfigs array = [
  for (z, i) in zoneNames: {
    name: replace(z, '.', '-')
    id: zones[i].id
  }
]
