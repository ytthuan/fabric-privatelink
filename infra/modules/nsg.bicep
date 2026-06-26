// Reusable Network Security Group.
// Default rules already deny inbound from the Internet; pass securityRules to harden further
// (for example a deny-Internet-outbound rule when lockdownOutbound is desired).
@description('NSG name.')
param name string

@description('Azure region.')
param location string

@description('Optional explicit security rules.')
param securityRules array = []

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: name
  location: location
  properties: {
    securityRules: securityRules
  }
}

output id string = nsg.id
output name string = nsg.name
