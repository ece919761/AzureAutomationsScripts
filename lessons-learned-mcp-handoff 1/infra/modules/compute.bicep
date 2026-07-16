@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Unique token for globally-unique names.')
param resourceToken string

@description('Resource naming prefix.')
param namingPrefix string

@description('Option C when true: internal (VNet-injected) ingress, no public endpoint.')
param isPrivate bool

@description('Container image reference. azd overrides this after building.')
param containerImage string

@description('ACR login server for image pulls.')
param registryLoginServer string

@description('User-assigned managed identity resource id.')
param identityId string

@description('User-assigned managed identity client id (for token federation in-app).')
param identityClientId string

@description('Log Analytics customer id.')
param logAnalyticsCustomerId string

@description('Log Analytics shared key.')
@secure()
param logAnalyticsSharedKey string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Container Apps infrastructure subnet id (required when isPrivate).')
param infraSubnetId string = ''

@description('MCP data provider mode.')
param providerMode string

@description('MCP endpoint auth mode.')
param authMode string

@description('Entra tenant id used to validate tokens.')
param entraTenantId string

@description('API app registration client id.')
param mcpApiClientId string

@description('Token audience expected by the API.')
param mcpApiAudience string

@description('Jira base URL (providerMode=jira only).')
param jiraBaseUrl string

@description('Jira project key (providerMode=jira only).')
param jiraProjectKey string

var placeholderImage = 'mcr.microsoft.com/k8se/quickstart:latest'
var image = empty(containerImage) || containerImage == 'latest' ? placeholderImage : containerImage
var appName = 'ca-${namingPrefix}-${resourceToken}'
var targetPort = 8080
var publicBaseUrl = 'https://${appName}.${managedEnv.properties.defaultDomain}'

resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${namingPrefix}-${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    vnetConfiguration: isPrivate
      ? {
          internal: true
          infrastructureSubnetId: infraSubnetId
        }
      : null
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  // azd matches services to resources by this tag.
  tags: union(tags, { 'azd-service-name': 'mcp' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        // Always external:true. In private mode the ENVIRONMENT is internal
        // (internal load balancer, no public IP), so the app remains fully
        // VNet-private while being served on the env's primary ingress route
        // (<app>.<defaultDomain>). The internal envoy does NOT route the
        // external:false (.internal.) FQDN in a VNet-injected internal env,
        // which returns "Error 404 - This Container App ... does not exist".
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryLoginServer
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mcp'
          image: image
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            { name: 'PORT', value: string(targetPort) }
            { name: 'NODE_ENV', value: 'production' }
            { name: 'PROVIDER_MODE', value: providerMode }
            { name: 'AUTH_MODE', value: authMode }
            { name: 'PUBLIC_BASE_URL', value: publicBaseUrl }
            { name: 'ENTRA_TENANT_ID', value: entraTenantId }
            { name: 'MCP_API_CLIENT_ID', value: mcpApiClientId }
            { name: 'MCP_API_AUDIENCE', value: mcpApiAudience }
            { name: 'JIRA_BASE_URL', value: jiraBaseUrl }
            { name: 'JIRA_PROJECT_KEY', value: jiraProjectKey }
            { name: 'AZURE_CLIENT_ID', value: identityClientId }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
          probes: [
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: targetPort
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 6
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: targetPort
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

output appName string = app.name
output appFqdn string = app.properties.configuration.ingress.fqdn
output publicBaseUrl string = publicBaseUrl
output environmentId string = managedEnv.id
output envDefaultDomain string = managedEnv.properties.defaultDomain
output envStaticIp string = managedEnv.properties.staticIp
