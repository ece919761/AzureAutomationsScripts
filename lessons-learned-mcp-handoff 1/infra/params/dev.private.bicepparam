// Option C — Hardened: internal ingress + APIM + private endpoints + VNet.
// Same app image as Option B; only infra/config change (requirements S5.3).
// Use: az deployment sub create -f infra/main.bicep -p infra/params/dev.private.bicepparam -l eastus
using '../main.bicep'

param location = 'eastus'
param environmentName = 'harman-ll-dev'
param deploymentMode = 'private'
param providerMode = 'representative'
param authMode = 'oauth'
param namingPrefix = 'harman-ll'

// Optional: set an explicit resource group name. Empty = rg-<environmentName>.
param resourceGroupName = ''

param entraTenantId = ''
param mcpApiClientId = ''
param mcpApiAudience = ''

// When switching to the real provider, set providerMode = 'jira' and supply:
param jiraBaseUrl = ''
param jiraProjectKey = ''

param vnetAddressSpace = '10.20.0.0/16'
param containerImageTag = 'latest'
