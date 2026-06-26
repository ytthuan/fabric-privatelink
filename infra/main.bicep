// =============================================================================
// Subscription-scope entry point for `azd provision` and `az deployment sub create`.
// Creates the resource group, then deploys all resources via resources.bicep.
// (The "Deploy to Azure" button uses the compiled, resource-group-scoped
// azuredeploy.json instead, because the portal button does not support
// subscription-scoped templates.)
// =============================================================================
targetScope = 'subscription'

@description('Environment name (azd). Used to name the resource group and tag resources.')
@minLength(1)
@maxLength(20)
param environmentName string = 'fabricpl'

@description('Primary (hub) region. Maps to azd AZURE_LOCATION.')
param location string = 'eastus2'

@description('On-premises (simulated) region.')
param onpremLocation string = 'eastus'

@description('Optional explicit resource group name. Defaults to rg-<environmentName>.')
param resourceGroupName string = 'rg-${environmentName}'

@description('Fabric capacity administrator UPN (a real Entra user) or SP object id. Required.')
param fabricCapacityAdmin string

@description('Local administrator username for the VMs.')
param adminUsername string = 'azureadmin'

@description('Local administrator password for the VMs.')
@secure()
param adminPassword string

@description('Pre-shared key for the VNet-to-VNet VPN connections.')
@secure()
param vpnSharedKey string

@description('Fabric capacity SKU.')
param capacitySku string = 'F2'

@description('Deploy the Fabric tenant Private Link service + private endpoint.')
param deployFabricPrivateLink bool = true

@description('Deploy Azure Bastion in both VNets.')
param deployBastion bool = false

@description('Deny all Internet outbound on the VM subnets.')
param lockdownOutbound bool = false

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

module resources 'resources.bicep' = {
  name: 'fabric-privatelink-resources'
  scope: rg
  params: {
    hubLocation: location
    onpremLocation: onpremLocation
    fabricCapacityAdmin: fabricCapacityAdmin
    adminUsername: adminUsername
    adminPassword: adminPassword
    vpnSharedKey: vpnSharedKey
    capacitySku: capacitySku
    deployFabricPrivateLink: deployFabricPrivateLink
    deployBastion: deployBastion
    lockdownOutbound: lockdownOutbound
  }
}

output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_LOCATION string = location
output FABRIC_CAPACITY_NAME string = resources.outputs.fabricCapacityName
output RESOLVER_INBOUND_IP string = resources.outputs.resolverInboundIp
output ONPREM_DNS_SERVER_IP string = resources.outputs.onpremDnsServerIp
