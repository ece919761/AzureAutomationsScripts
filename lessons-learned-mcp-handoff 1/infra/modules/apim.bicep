@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Resource naming prefix.')
param namingPrefix string

@description('Unique token for globally-unique names.')
param resourceToken string

@description('Backend MCP server URL (Container App internal FQDN).')
param backendUrl string

@description('Entra tenant id used for JWT validation.')
param entraTenantId string

@description('Audience the API expects in tokens.')
param mcpApiAudience string

@description('API app registration client id (bare GUID) accepted as a second audience.')
param mcpApiClientId string = ''

@description('Application Insights connection string for gateway telemetry.')
param appInsightsConnectionString string

@description('Resource ID of the dedicated APIM subnet used for VNet injection.')
param apimSubnetId string

@description('Publisher email for the APIM instance.')
param publisherEmail string = 'admin@harman.com'

@description('Publisher org name for the APIM instance.')
param publisherName string = 'Harman Quality'

var apimName = 'apim-${namingPrefix}-${resourceToken}'
#disable-next-line no-hardcoded-env-urls
var openIdConfig = 'https://login.microsoftonline.com/${entraTenantId}/v2.0/.well-known/openid-configuration'

// Multi-line strings are literal in Bicep (no interpolation), so the dynamic
// values are injected via replace() of the placeholders below.
var policyTemplate = '''
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Access token is missing or invalid.">
      <openid-config url="__OPENID_CONFIG__" />
      <audiences>
        <audience>__AUDIENCE1__</audience>
        <audience>__AUDIENCE2__</audience>
      </audiences>
    </validate-jwt>
    <rate-limit calls="120" renewal-period="60" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
// A v2 token's audience can be either the App ID URI (api://<guid>) or the
// bare client id (<guid>) depending on how the caller requests it. Accept both.
var audience2 = empty(mcpApiClientId) ? mcpApiAudience : mcpApiClientId
var policyXml = replace(replace(replace(policyTemplate, '__OPENID_CONFIG__', openIdConfig), '__AUDIENCE1__', mcpApiAudience), '__AUDIENCE2__', audience2)

// stv2 VNet injection (External mode) requires a Standard, static public IP
// with a DNS label. Copilot Studio reaches this public gateway; APIM then
// forwards to the internal Container App over the VNet.
resource apimPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${apimName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: apimName
    }
  }
}

// Developer SKU with External VNet injection: public gateway (reachable by
// Copilot Studio) fronting a private backend. For production, use Premium or
// Standard v2 — the JWT policy and API shape are unchanged.
resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'External'
    publicIpAddressId: apimPip.id
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
  }
}

resource apimAppInsights 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      connectionString: appInsightsConnectionString
    }
  }
}

resource mcpApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'mcp'
  properties: {
    displayName: 'Lessons-Learned MCP'
    path: 'mcp'
    protocols: ['https']
    // Auth is enforced by the Entra JWT policy below, not by an APIM
    // subscription key. Copilot Studio sends only the OAuth bearer token, so
    // subscription keys are disabled to avoid a second, unshippable credential.
    subscriptionRequired: false
    serviceUrl: backendUrl
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
  }
}

resource mcpPost 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: mcpApi
  name: 'post-mcp'
  properties: {
    displayName: 'MCP JSON-RPC'
    method: 'POST'
    urlTemplate: '/mcp'
  }
}

// The MCP Streamable HTTP transport also uses GET (server event stream) and
// DELETE (session termination) on the same path. Without these operations APIM
// returns 404 for those methods and the MCP handshake fails.
resource mcpGet 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: mcpApi
  name: 'get-mcp'
  properties: {
    displayName: 'MCP stream (GET)'
    method: 'GET'
    urlTemplate: '/mcp'
  }
}

resource mcpDelete 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: mcpApi
  name: 'delete-mcp'
  properties: {
    displayName: 'MCP session end (DELETE)'
    method: 'DELETE'
    urlTemplate: '/mcp'
  }
}

// Gateway policy: enforce Entra JWT validation, then forward to the backend.
// The backend also validates the token (defense in depth).
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: mcpApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: policyXml
  }
}

output gatewayUrl string = apim.properties.gatewayUrl
output apimName string = apim.name
