targetScope = 'subscription'

// ===========================================================================
// Lessons-Learned MCP server — main deployment
//
// One template, two topologies, toggled by `deploymentMode`:
//   public  = Option B (MVP): Container Apps managed public HTTPS ingress.
//   private = Option C (hardened): internal ingress + APIM + private endpoints.
//
// The application image is identical across both modes; only infra/config
// change (requirements Section 5.3).
// ===========================================================================

@minLength(1)
@description('Primary Azure region for all resources.')
param location string

@minLength(1)
@maxLength(64)
@description('Environment name (azd). Used for the resource group and tagging.')
param environmentName string

@allowed(['public', 'private'])
@description('public = Option B; private = Option C.')
param deploymentMode string = 'public'

@allowed(['representative', 'jira'])
@description('MCP data provider. Default representative (no external calls).')
param providerMode string = 'representative'

@allowed(['oauth', 'apikey'])
@description('MCP endpoint auth. oauth (Entra ID) is the target.')
param authMode string = 'oauth'

@description('Short prefix used in resource names, e.g. harman-ll.')
param namingPrefix string = 'harman-ll'

@description('Entra tenant used to validate MCP tokens (defaults to the deployment tenant).')
param entraTenantId string = tenant().tenantId

@description('Application (client) ID of the API app registration protecting the MCP endpoint.')
param mcpApiClientId string = ''

@description('Audience the MCP API expects in tokens, e.g. api://<client-id>.')
param mcpApiAudience string = ''

@description('Jira base URL (consumed only when providerMode=jira).')
param jiraBaseUrl string = ''

@description('Jira project key (consumed only when providerMode=jira).')
param jiraProjectKey string = ''

@description('Key Vault secret name that will hold the Jira PAT (created empty; customer sets the value).')
param jiraPatSecretName string = 'jira-pat'

@description('VNet address space for Option C.')
param vnetAddressSpace string = '10.20.0.0/16'

@description('Container image tag/reference to deploy. azd overrides this.')
param containerImageTag string = 'latest'

@description('Object ID of the deploying user/service principal for Key Vault data-plane RBAC (optional).')
param principalId string = ''

@description('Explicit resource group name. When empty, defaults to rg-<environmentName>. The group is created by this deployment.')
param resourceGroupName string = ''

var isPrivate = deploymentMode == 'private'
var tags = {
  'azd-env-name': environmentName
  project: namingPrefix
  deploymentMode: deploymentMode
}
var rgName = empty(resourceGroupName) ? 'rg-${environmentName}' : resourceGroupName
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    namingPrefix: namingPrefix
  }
}

module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity'
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    namingPrefix: namingPrefix
  }
}

module registry 'modules/registry.bicep' = {
  scope: rg
  name: 'registry'
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    principalId: identity.outputs.principalId
  }
}

module network 'modules/network.bicep' = if (isPrivate) {
  scope: rg
  name: 'network'
  params: {
    location: location
    tags: tags
    namingPrefix: namingPrefix
    resourceToken: resourceToken
    vnetAddressSpace: vnetAddressSpace
  }
}

module secrets 'modules/secrets.bicep' = {
  scope: rg
  name: 'secrets'
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    namingPrefix: namingPrefix
    identityPrincipalId: identity.outputs.principalId
    deployerPrincipalId: principalId
    isPrivate: isPrivate
    privateEndpointSubnetId: isPrivate ? network!.outputs.privateEndpointSubnetId : ''
    vnetId: isPrivate ? network!.outputs.vnetId : ''
    jiraPatSecretName: jiraPatSecretName
  }
}

module compute 'modules/compute.bicep' = {
  scope: rg
  name: 'compute'
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    namingPrefix: namingPrefix
    isPrivate: isPrivate
    containerImage: containerImageTag
    registryLoginServer: registry.outputs.loginServer
    identityId: identity.outputs.id
    identityClientId: identity.outputs.clientId
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: monitoring.outputs.logAnalyticsSharedKey
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    infraSubnetId: isPrivate ? network!.outputs.containerAppsSubnetId : ''
    providerMode: providerMode
    authMode: authMode
    entraTenantId: entraTenantId
    mcpApiClientId: mcpApiClientId
    mcpApiAudience: empty(mcpApiAudience) && !empty(mcpApiClientId) ? 'api://${mcpApiClientId}' : mcpApiAudience
    jiraBaseUrl: jiraBaseUrl
    jiraProjectKey: jiraProjectKey
  }
}

module apim 'modules/apim.bicep' = if (isPrivate) {
  scope: rg
  name: 'apim'
  params: {
    location: location
    tags: tags
    namingPrefix: namingPrefix
    resourceToken: resourceToken
    backendUrl: 'https://${compute.outputs.appFqdn}'
    entraTenantId: entraTenantId
    mcpApiAudience: empty(mcpApiAudience) && !empty(mcpApiClientId) ? 'api://${mcpApiClientId}' : mcpApiAudience
    mcpApiClientId: mcpApiClientId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    apimSubnetId: network!.outputs.apimSubnetId
  }
}

// Private DNS for the internal Container Apps environment. The zone name and
// records are derived from the env's own defaultDomain + staticIp so a clean
// rebuild (which yields a new domain/IP) is always self-correcting.
module privateDns 'modules/privatedns.bicep' = if (isPrivate) {
  scope: rg
  name: 'privatedns'
  params: {
    tags: tags
    envDefaultDomain: compute.outputs.envDefaultDomain
    envStaticIp: compute.outputs.envStaticIp
    vnetId: network!.outputs.vnetId
  }
}

// --------------------------------------------------------------------------
// Outputs — consumed by azd, Copilot Studio wiring, and the runbook.
// --------------------------------------------------------------------------
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output MCP_BACKEND_FQDN string = compute.outputs.appFqdn
@description('The endpoint to register in Copilot Studio (APIM gateway in private mode, Container App URL in public mode).')
output MCP_ENDPOINT_URL string = isPrivate ? '${apim!.outputs.gatewayUrl}/mcp/mcp' : 'https://${compute.outputs.appFqdn}/mcp'
output APIM_GATEWAY_URL string = isPrivate ? apim!.outputs.gatewayUrl : ''
output MCP_MANAGED_IDENTITY_CLIENT_ID string = identity.outputs.clientId
output KEY_VAULT_NAME string = secrets.outputs.keyVaultName
output DEPLOYMENT_MODE string = deploymentMode
output PROVIDER_MODE string = providerMode
output AUTH_MODE string = authMode
