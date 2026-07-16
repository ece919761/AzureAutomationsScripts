@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Resource naming prefix.')
param namingPrefix string

@description('Unique token for globally-unique names.')
param resourceToken string

@description('VNet address space, e.g. 10.20.0.0/16.')
param vnetAddressSpace string

// Subnet layout (Option C):
//  - container-apps : delegated to Container Apps environment (internal ingress)
//  - private-endpoints : Key Vault / ACR private endpoints
//  - apim : API Management (internal/stv2)
var containerAppsSubnetName = 'snet-container-apps'
var privateEndpointSubnetName = 'snet-private-endpoints'
var apimSubnetName = 'snet-apim'

// NSG required for APIM stv2 VNet injection (External mode). These inbound
// rules are the minimum the APIM control plane and load balancer require.
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-apim-${namingPrefix}-${resourceToken}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Client-443-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-APIM-Management-3443-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'Allow-AzureLB-6390-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${namingPrefix}-${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressSpace]
    }
    subnets: [
      {
        name: containerAppsSubnetName
        properties: {
          addressPrefix: cidrSubnet(vnetAddressSpace, 23, 0)
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: cidrSubnet(vnetAddressSpace, 24, 4)
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: apimSubnetName
        properties: {
          addressPrefix: cidrSubnet(vnetAddressSpace, 24, 5)
          networkSecurityGroup: {
            id: apimNsg.id
          }
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output containerAppsSubnetId string = '${vnet.id}/subnets/${containerAppsSubnetName}'
output privateEndpointSubnetId string = '${vnet.id}/subnets/${privateEndpointSubnetName}'
output apimSubnetId string = '${vnet.id}/subnets/${apimSubnetName}'
