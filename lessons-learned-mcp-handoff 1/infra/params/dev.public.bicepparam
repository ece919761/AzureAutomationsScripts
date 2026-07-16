// Option B — MVP: public secured Container Apps ingress, Entra OAuth, representative provider.
// Use: az deployment sub create -f infra/main.bicep -p infra/params/dev.public.bicepparam -l eastus
using '../main.bicep'

param location = 'eastus'
param environmentName = 'harman-ll-dev'
param deploymentMode = 'public'
param providerMode = 'representative'
param authMode = 'oauth'
param namingPrefix = 'harman-ll'

// Optional: set an explicit resource group name. Empty = rg-<environmentName>.
param resourceGroupName = ''

// Fill these from the API app registration created for the MCP endpoint.
param entraTenantId = '' // defaults to the deployment tenant when empty
param mcpApiClientId = ''
param mcpApiAudience = '' // defaults to api://<mcpApiClientId>

// Jira params unused while providerMode=representative.
param jiraBaseUrl = ''
param jiraProjectKey = ''

param containerImageTag = 'latest'
