// =============================================================================
// Microsoft Fabric Private Link lab — all resources (resource-group scope).
//
// Compiled to azuredeploy.json for the "Deploy to Azure" button and
// `az deployment group create`. Also invoked by infra/main.bicep (subscription
// scope) for `azd provision` / `az deployment sub create`.
//
// Hub (Fabric side) and on-prem (simulated) live in ONE resource group but in two
// regions, connected by a VNet-to-VNet VPN. On-prem clients resolve Fabric private
// endpoints via an on-prem DNS forwarder -> Azure DNS Private Resolver.
// =============================================================================

@description('Short prefix for resource names (lowercase alphanumeric).')
@minLength(3)
@maxLength(10)
param namePrefix string = 'fabpl'

@description('Hub region (Fabric capacity + private endpoint + resolver).')
param hubLocation string = 'eastus2'

@description('On-premises (simulated) region.')
param onpremLocation string = 'eastus'

@description('Entra tenant id for the Fabric Private Link service.')
param tenantId string = tenant().tenantId

@description('Fabric capacity administrator (a real Entra user UPN, or SP object id). Required.')
param fabricCapacityAdmin string

@description('Fabric capacity SKU.')
@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
])
param capacitySku string = 'F2'

@description('Local administrator username for the VMs.')
param adminUsername string = 'azureadmin'

@description('Local administrator password for the VMs.')
@secure()
param adminPassword string

@description('Pre-shared key for the VNet-to-VNet VPN connections.')
@secure()
param vpnSharedKey string

@description('Deploy the Fabric tenant Private Link service + private endpoint. Requires tenant Azure Private Link enabled in the Fabric admin portal first.')
param deployFabricPrivateLink bool = true

@description('Deploy Azure Bastion in both VNets (break-glass admin access).')
param deployBastion bool = false

@description('Deny all Internet outbound on the VM/client/DNS subnets (stricter posture).')
param lockdownOutbound bool = false

@description('VM size for the lab VMs.')
param vmSize string = 'Standard_D2s_v3'

@description('Static IP for the DNS Private Resolver inbound endpoint (inside snet-dnspr-inbound).')
param resolverInboundIp string = '10.10.3.4'

@description('Static IP for the on-premises DNS server VM (inside snet-dns).')
param onpremDnsServerIp string = '10.20.1.4'

@description('Public parent domains conditionally forwarded from on-prem to the resolver. Use broad parents (powerbi.com, fabric.microsoft.com) so the FULL Fabric/Power BI name resolution — portal, APIs, and OneLake (onelake.dfs/blob.fabric.microsoft.com, workspace FQDNs) — is sent to the private resolver. Narrow app.* forwarders leak OneLake to public DNS because its public CNAME chain resolves fully before the privatelink hop is re-queried.')
param forwarderDomains array = [
  'analysis.windows.net'
  'pbidedicated.windows.net'
  'prod.powerquery.microsoft.com'
  'powerbi.com'
  'fabric.microsoft.com'
]

// ----------------------------------------------------------------------------
// Address plan
// ----------------------------------------------------------------------------
var hubAddressSpace = '10.10.0.0/16'
var spokeAddressSpace = '10.30.0.0/16'
var onpremAddressSpace = '10.20.0.0/16'

// Distinct, non-reserved private BGP ASNs are required on each gateway for the
// VNet-to-VNet BGP session that propagates the spoke prefix from the hub to on-premises
// through gateway transit. Azure reserves 8074/8075/12076/65515/65517-65520; usable
// private ranges are 64512-65514 and 65521-65534.
var hubAsn = 65521
var onpremAsn = 65522

var lockdownRules = [
  {
    name: 'AllowAzureCloudOutbound'
    properties: {
      priority: 200
      direction: 'Outbound'
      access: 'Allow'
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: 'AzureCloud'
      destinationPortRange: '*'
    }
  }
  {
    name: 'DenyInternetOutbound'
    properties: {
      priority: 4096
      direction: 'Outbound'
      access: 'Deny'
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: 'Internet'
      destinationPortRange: '*'
    }
  }
]
// AzureCloud is allowed before Internet is denied so the VM guest agent can still pull
// extension handlers from Azure Storage; general Internet egress is blocked.
var vmNsgRules = lockdownOutbound ? lockdownRules : []

// Build the on-prem DNS forwarder command. The PowerShell script is embedded at compile
// time (base64), written to disk on the VM, and run with the resolver IP + domain list.
var dnsScriptB64 = loadFileAsBase64('../scripts/setup-dns-forwarder.ps1')
var domainsCsv = join(forwarderDomains, ',')
var dnsForwarderCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "[IO.File]::WriteAllBytes(\'C:\\setup-dns-forwarder.ps1\',[Convert]::FromBase64String(\'${dnsScriptB64}\')); & \'C:\\setup-dns-forwarder.ps1\' -ResolverIp \'${resolverInboundIp}\' -Domains \'${domainsCsv}\'"'

// ----------------------------------------------------------------------------
// Network security groups
// ----------------------------------------------------------------------------
module nsgOnpremDns 'modules/nsg.bicep' = {
  name: 'nsg-onprem-dns'
  params: {
    name: 'nsg-${namePrefix}-onprem-dns'
    location: onpremLocation
    securityRules: vmNsgRules
  }
}

module nsgOnpremClient 'modules/nsg.bicep' = {
  name: 'nsg-onprem-client'
  params: {
    name: 'nsg-${namePrefix}-onprem-client'
    location: onpremLocation
    securityRules: vmNsgRules
  }
}

// ----------------------------------------------------------------------------
// Hub VNet — shared services only (VPN gateway + DNS Private Resolver).
// In hub-and-spoke, workloads (the Fabric private endpoint) live in a spoke.
// ----------------------------------------------------------------------------
module hubVnet 'modules/network.bicep' = {
  name: 'vnet-hub'
  params: {
    name: 'vnet-${namePrefix}-hub'
    location: hubLocation
    addressPrefixes: [
      hubAddressSpace
    ]
    subnets: [
      {
        name: 'snet-dnspr-inbound'
        addressPrefix: '10.10.3.0/28'
        delegation: 'Microsoft.Network/dnsResolvers'
      }
      {
        name: 'GatewaySubnet'
        addressPrefix: '10.10.255.0/27'
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.10.254.0/26'
      }
    ]
  }
}

// ----------------------------------------------------------------------------
// Spoke VNet — Fabric workload. Holds the Fabric private endpoint; peered to the
// hub and uses the hub's VPN gateway (gateway transit) to reach on-premises.
// ----------------------------------------------------------------------------
module spokeVnet 'modules/network.bicep' = {
  name: 'vnet-spoke-fabric'
  params: {
    name: 'vnet-${namePrefix}-spoke-fabric'
    location: hubLocation
    addressPrefixes: [
      spokeAddressSpace
    ]
    subnets: [
      {
        name: 'snet-pe'
        addressPrefix: '10.30.1.0/24'
        disablePeNetworkPolicies: true
      }
    ]
  }
}

// ----------------------------------------------------------------------------
// On-prem VNet (simulated). VNet DNS points at the on-prem DNS server VM.
// ----------------------------------------------------------------------------
module onpremVnet 'modules/network.bicep' = {
  name: 'vnet-onprem'
  params: {
    name: 'vnet-${namePrefix}-onprem'
    location: onpremLocation
    addressPrefixes: [
      onpremAddressSpace
    ]
    dnsServers: [
      onpremDnsServerIp
    ]
    subnets: [
      {
        name: 'snet-dns'
        addressPrefix: '10.20.1.0/24'
        nsgId: nsgOnpremDns.outputs.id
      }
      {
        name: 'snet-client'
        addressPrefix: '10.20.2.0/24'
        nsgId: nsgOnpremClient.outputs.id
      }
      {
        name: 'GatewaySubnet'
        addressPrefix: '10.20.255.0/27'
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.20.254.0/26'
      }
    ]
  }
}

// ----------------------------------------------------------------------------
// Private DNS zones (linked to the hub VNet) + DNS Private Resolver
// ----------------------------------------------------------------------------
module privateDns 'modules/privatedns.bicep' = {
  name: 'private-dns'
  params: {
    vnetId: hubVnet.outputs.id
  }
}

module resolver 'modules/dnsresolver.bicep' = {
  name: 'dns-resolver'
  params: {
    name: 'dnspr-${namePrefix}'
    location: hubLocation
    vnetId: hubVnet.outputs.id
    inboundSubnetId: hubVnet.outputs.subnetIds['snet-dnspr-inbound']
    inboundIp: resolverInboundIp
  }
}

// ----------------------------------------------------------------------------
// Fabric capacity + tenant Private Link + private endpoint
// ----------------------------------------------------------------------------
module fabric 'modules/fabric.bicep' = {
  name: 'fabric'
  params: {
    capacityName: toLower('${namePrefix}cap${uniqueString(resourceGroup().id)}')
    location: hubLocation
    skuName: capacitySku
    adminMembers: [
      fabricCapacityAdmin
    ]
    deployPrivateLink: deployFabricPrivateLink
    tenantId: tenantId
    privateLinkServiceName: 'pls-${namePrefix}-fabric'
    privateEndpointName: 'pe-${namePrefix}-fabric-tenant'
    peSubnetId: spokeVnet.outputs.subnetIds['snet-pe']
    privateDnsZoneConfigs: privateDns.outputs.zoneConfigs
  }
}

// ----------------------------------------------------------------------------
// VMs
// ----------------------------------------------------------------------------
// On-prem DNS server: NIC DNS set to Azure DNS (168.63.129.16) so it can bootstrap and
// install the extension before its own DNS role is ready; serves on-prem clients after.
module onpremDnsVm 'modules/windowsvm.bicep' = {
  name: 'vm-onprem-dns'
  params: {
    name: 'vm-onprem-dns'
    location: onpremLocation
    subnetId: onpremVnet.outputs.subnetIds['snet-dns']
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    privateIp: onpremDnsServerIp
    nicDnsServers: [
      '168.63.129.16'
    ]
    customScriptCommand: dnsForwarderCommand
  }
}

// On-prem client: uses the VNet DNS (the DNS server VM). Created after the DNS VM so the
// forwarder is configured before the client boots.
module onpremClientVm 'modules/windowsvm.bicep' = {
  name: 'vm-onprem-cli'
  params: {
    name: 'vm-onprem-cli'
    location: onpremLocation
    subnetId: onpremVnet.outputs.subnetIds['snet-client']
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
  }
  dependsOn: [
    onpremDnsVm
  ]
}

// On-prem user workstation: the end-user that accesses Fabric privately over the VPN.
// Inherits the VNet DNS (the DNS server VM at 10.20.1.4), so its Fabric lookups go through
// the DNS server's conditional forwarders -> resolver -> private endpoint.
module onpremUserVm 'modules/windowsvm.bicep' = {
  name: 'vm-onprem-user'
  params: {
    name: 'vm-onprem-user'
    location: onpremLocation
    subnetId: onpremVnet.outputs.subnetIds['snet-client']
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
  }
  dependsOn: [
    onpremDnsVm
  ]
}

// ----------------------------------------------------------------------------
// VPN gateways + VNet-to-VNet connections
// ----------------------------------------------------------------------------
module hubGateway 'modules/vpngateway.bicep' = {
  name: 'vpngw-hub'
  params: {
    name: 'vpngw-${namePrefix}-hub'
    location: hubLocation
    gatewaySubnetId: hubVnet.outputs.subnetIds.GatewaySubnet
    asn: hubAsn
  }
}

module onpremGateway 'modules/vpngateway.bicep' = {
  name: 'vpngw-onprem'
  params: {
    name: 'vpngw-${namePrefix}-onprem'
    location: onpremLocation
    gatewaySubnetId: onpremVnet.outputs.subnetIds.GatewaySubnet
    asn: onpremAsn
  }
}

// Hub <-> spoke peering with gateway transit. Created after the hub gateway exists so the
// spoke's useRemoteGateways setting is valid.
module hubSpokePeering 'modules/peering.bicep' = {
  name: 'peering-hub-spoke'
  params: {
    hubVnetName: hubVnet.outputs.name
    hubVnetId: hubVnet.outputs.id
    spokeVnetName: spokeVnet.outputs.name
    spokeVnetId: spokeVnet.outputs.id
  }
  dependsOn: [
    hubGateway
  ]
}

module connections 'modules/connections.bicep' = {
  name: 'vpn-connections'
  params: {
    hubGatewayId: hubGateway.outputs.gatewayId
    onpremGatewayId: onpremGateway.outputs.gatewayId
    hubLocation: hubLocation
    onpremLocation: onpremLocation
    sharedKey: vpnSharedKey
  }
}

// ----------------------------------------------------------------------------
// Optional Bastion hosts
// ----------------------------------------------------------------------------
module hubBastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion-hub'
  params: {
    name: 'bas-${namePrefix}-hub'
    location: hubLocation
    bastionSubnetId: hubVnet.outputs.subnetIds.AzureBastionSubnet
  }
}

module onpremBastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion-onprem'
  params: {
    name: 'bas-${namePrefix}-onprem'
    location: onpremLocation
    bastionSubnetId: onpremVnet.outputs.subnetIds.AzureBastionSubnet
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------
output hubVnetId string = hubVnet.outputs.id
output spokeVnetId string = spokeVnet.outputs.id
output onpremVnetId string = onpremVnet.outputs.id
output resolverInboundIp string = resolver.outputs.inboundIp
output fabricCapacityName string = fabric.outputs.capacityName
output fabricCapacityId string = fabric.outputs.capacityId
output onpremDnsServerIp string = onpremDnsServerIp
@description('Run on the on-prem client VM to confirm private resolution.')
output verifyCommand string = 'nslookup <tenant-object-id-without-hyphens>-api.privatelink.analysis.windows.net'
