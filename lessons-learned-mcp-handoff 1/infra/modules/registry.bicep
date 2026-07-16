@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Unique token for globally-unique names.')
param resourceToken string

@description('Principal ID of the managed identity that pulls images.')
param principalId string

// AcrPull role definition id.
var acrPullRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  #disable-next-line BCP334
  name: 'acr${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// Grant the managed identity permission to pull images (no admin creds).
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, principalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output loginServer string = registry.properties.loginServer
output name string = registry.name
output id string = registry.id
