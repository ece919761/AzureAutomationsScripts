@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Unique token for globally-unique names.')
param resourceToken string

@description('Resource naming prefix.')
param namingPrefix string

@description('Managed identity principal id granted Key Vault Secrets User.')
param identityPrincipalId string

@description('Optional deployer principal id granted Key Vault Secrets Officer for data-plane setup.')
param deployerPrincipalId string = ''

@description('Whether to lock the vault behind a private endpoint (Option C).')
param isPrivate bool

@description('Private endpoint subnet id (required when isPrivate).')
param privateEndpointSubnetId string = ''

@description('VNet id for the private DNS zone link (required when isPrivate).')
param vnetId string = ''

@description('Name of the Jira PAT secret (created empty; customer sets the value).')
param jiraPatSecretName string

var keyVaultName = 'kv-${take(replace(namingPrefix, '-', ''), 8)}-${take(resourceToken, 10)}'
var secretsUserRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
)
var secretsOfficerRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer
)

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: isPrivate ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: isPrivate ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Placeholder Jira PAT secret (empty). The customer sets the real value later;
// the app reads it via a Key Vault reference when providerMode=jira.
resource jiraPat 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: jiraPatSecretName
  properties: {
    value: 'REPLACE_ME'
    attributes: {
      enabled: false
    }
  }
}

resource identitySecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, identityPrincipalId, secretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: secretsUserRoleId
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource deployerSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, secretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: secretsOfficerRoleId
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// Private endpoint + DNS for Option C.
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (isPrivate) {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (isPrivate) {
  parent: privateDnsZone
  name: 'kv-dns-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (isPrivate) {
  name: 'pe-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'kv-plsc'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource peDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = if (isPrivate) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault-config'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output jiraPatSecretUri string = '${keyVault.properties.vaultUri}secrets/${jiraPatSecretName}'
