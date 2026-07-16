@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Unique token for globally-unique names.')
param resourceToken string

@description('Resource naming prefix.')
param namingPrefix string

// User-assigned managed identity used for all Azure-to-Azure auth
// (ACR pull, Key Vault secret access). No secrets in code (requirements S8).
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${namingPrefix}-${resourceToken}'
  location: location
  tags: tags
}

output id string = uami.id
output principalId string = uami.properties.principalId
output clientId string = uami.properties.clientId
output name string = uami.name
