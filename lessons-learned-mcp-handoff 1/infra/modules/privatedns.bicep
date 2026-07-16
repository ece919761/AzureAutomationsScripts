@description('Resource tags.')
param tags object

@description('Container Apps environment default domain, e.g. <name>.<region>.azurecontainerapps.io.')
param envDefaultDomain string

@description('Container Apps environment internal static IP (internal load balancer).')
param envStaticIp string

@description('VNet resource id to link the private DNS zone to.')
param vnetId string

// Private DNS zone matching the internal environment's default domain. Internal
// Container Apps in a custom VNet do NOT get automatic DNS in your subscription,
// so we resolve the env domain to its internal load balancer IP ourselves.
resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: envDefaultDomain
  location: 'global'
  tags: tags
}

// Wildcard covers external-style app FQDNs (<app>.<defaultDomain>).
resource wildcard 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: zone
  name: '*'
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: envStaticIp
      }
    ]
  }
}

// Wildcard for internal app FQDNs (<app>.internal.<defaultDomain>).
resource wildcardInternal 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: zone
  name: '*.internal'
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: envStaticIp
      }
    ]
  }
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: zone
  name: 'aca-dns-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

output zoneName string = zone.name
