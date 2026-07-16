# Lessons-Learned MCP Server (Copilot Studio → on-prem Jira)

Representative, Azure-hosted **Model Context Protocol (MCP)** server that Microsoft
Copilot Studio calls as a tool. It proves the end-to-end pattern —
`Copilot Studio → Entra OAuth → MCP server → provider → structured response` —
for Harman's lessons-learned write-back use case, with a **provider seam** so the
real Jira integration can be plugged in later via config, not a rewrite.

> Built to the spec in
> [Resources/Copilot-Studio-to-OnPrem-Jira-Integration-Requirements.md](Resources/Copilot-Studio-to-OnPrem-Jira-Integration-Requirements.md).
> The deployed server is **representative** (seeded mock store); it does not call
> real Jira. See requirements Section 2.

## Two topologies, one image

| Mode | `deploymentMode` | What you get |
|---|---|---|
| **Option B — MVP** | `public` | Container Apps managed **public HTTPS** ingress, Entra OAuth, App Insights |
| **Option C — Hardened** | `private` | **Internal** ingress + **APIM** (JWT/keys/IP/throttle) + **private endpoints** (Key Vault, ACR) + VNet |

The application container is identical across both; only infrastructure and
configuration change (requirements Section 5.3).

## Config toggles (never code changes)

| Env var | Values | Meaning |
|---|---|---|
| `PROVIDER_MODE` | `representative` \| `jira` | Data source (default representative) |
| `AUTH_MODE` | `oauth` \| `apikey` | Endpoint auth (oauth is the target) |
| `deploymentMode` (Bicep) | `public` \| `private` | Option B vs Option C topology |

## Repository layout

```
src/
  server.ts                 Express + Streamable HTTP MCP endpoint, health, discovery
  config.ts                 Env-driven config incl. the two seam toggles
  logging.ts                App Insights init + JSON logs
  providers/                The seam
    ILessonsProvider.ts     Interface all tools depend on
    representativeProvider.ts  Seeded in-memory store (default)
    jiraDataCenterProvider.ts  Stub with TODOs for the real Jira REST calls
    index.ts                createProvider(config) factory
  tools/
    handlers.ts             Pure, unit-testable tool logic
    index.ts                Registers tools with zod schemas (FR-6)
  auth/
    oauth.ts                Entra OAuth 2.0 resource-server validation (jose)
    discovery.ts            RFC 8414 / RFC 9728 metadata for Copilot Studio
tests/                      providers, tools, config, create→get smoke
infra/                      Bicep (main + modules) + params + azd parameters
  modules/                  monitoring, identity, registry, network, secrets, compute, apim
.github/workflows/deploy.yml  build → test → azd provision/deploy
Dockerfile, azure.yaml, .env.example
```

## Local development

```powershell
npm install
Copy-Item .env.example .env      # then fill in values (or set AUTH_MODE=apikey for a quick local run)
npm run dev                      # starts on http://localhost:8080
```

Health check: `GET http://localhost:8080/health`.
Discovery: `GET http://localhost:8080/.well-known/oauth-protected-resource`.

Quick local smoke without Entra (spike only):

```powershell
$env:AUTH_MODE="apikey"; $env:MCP_API_KEY="dev-key"; npm run dev
# then POST MCP JSON-RPC to /mcp with header:  x-api-key: dev-key
```

Test / typecheck / build:

```powershell
npm test
npm run typecheck
npm run build
```

## Prerequisites for Azure

- Azure subscription + rights to create the resource group and role assignments.
- [Azure Developer CLI (azd)](https://aka.ms/azd) and Docker installed.
- An **Entra ID app registration** for the API (protects the MCP endpoint):
  - Expose an API → set Application ID URI `api://<client-id>` and a scope (e.g. `mcp.tools`).
  - Note the **tenant id**, **client id**, and **audience** (`api://<client-id>`).

## Deploy — Option B (public MVP)

```powershell
azd auth login
azd env new harman-ll-dev
azd env set DEPLOYMENT_MODE public
azd env set AUTH_MODE oauth
azd env set ENTRA_TENANT_ID <tenant-guid>
azd env set MCP_API_CLIENT_ID <api-app-client-id>
azd env set MCP_API_AUDIENCE api://<api-app-client-id>
azd up
```

`azd up` provisions the infra (with a placeholder image), builds the container,
pushes to ACR, and deploys it to the Container App. On completion azd prints
outputs including **`MCP_ENDPOINT_URL`** — the URL to register in Copilot Studio.

> First provision may show the initial revision as unhealthy until the real
> image is deployed in the same `azd up` run — this is expected.

## Deploy — Option C (hardened, private)

```powershell
azd env set DEPLOYMENT_MODE private
azd up
```

Adds VNet, internal ingress, APIM (JWT validation + subscription keys + rate
limit), and private endpoints for Key Vault and ACR. `MCP_ENDPOINT_URL` now
points at the **APIM gateway**.

### Direct Bicep (without azd)

```powershell
az deployment sub create -l eastus -f infra/main.bicep -p infra/params/dev.public.bicepparam
# or dev.private.bicepparam for Option C
```

## Connect Copilot Studio

1. Open the target agent → **Tools → Add a tool → New tool → Model Context Protocol**.
2. Endpoint URL = the deployed `MCP_ENDPOINT_URL`. Transport = **Streamable HTTP** (FR-1).
3. Authentication = **OAuth 2.0**; the server publishes discovery metadata
   (`/.well-known/oauth-protected-resource`) so it can auto-configure against the
   Entra app registration (tenant, scope, PKCE).
4. **Turn on generative orchestration** — required for MCP tools (FR-7).
5. Confirm the Power Platform environment **DLP policy permits the tool** before demoing.
6. Ask the agent to create and then read a lesson learned to exercise
   `create_lesson_learned` + `get_lesson_learned` end to end.

## Tools exposed

| Tool | Purpose |
|---|---|
| `get_lesson_learned` | Fetch one record by key |
| `search_lessons_learned` | Free-text search |
| `create_lesson_learned` | **Write path** — create a new record |
| `update_lesson_learned` | Update fields on a record |

## Swapping in real Jira (handover)

1. Implement the REST calls in
   [src/providers/jiraDataCenterProvider.ts](src/providers/jiraDataCenterProvider.ts)
   (marked `TODO(customer)`), mapping Jira issue fields ↔ `LessonLearned`.
2. Put the Jira PAT in Key Vault (secret `jira-pat`, created disabled by the IaC)
   and enable it; reference it as a Container App secret/env var.
3. Set `PROVIDER_MODE=jira` and supply `JIRA_BASE_URL` / `JIRA_PROJECT_KEY`.
4. In Option C, on-prem Jira is reached privately over the existing ExpressRoute.
   No app code or architecture changes — only config.

## CI/CD

[.github/workflows/deploy.yml](.github/workflows/deploy.yml) runs typecheck +
tests + a Docker build on every push/PR, and on `main` (or manual dispatch)
provisions and deploys via azd using federated (OIDC) auth. Configure repo
**variables** (`AZURE_ENV_NAME`, `AZURE_LOCATION`, `AZURE_SUBSCRIPTION_ID`,
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `DEPLOYMENT_MODE`, `AUTH_MODE`,
`ENTRA_TENANT_ID`, `MCP_API_CLIENT_ID`, `MCP_API_AUDIENCE`).

## Teardown

```powershell
azd down --purge
```

## Security notes

- On-prem Jira is never exposed to the internet; Option C removes all public
  backend exposure (internal ingress + APIM + private endpoints).
- Azure-to-Azure auth uses a **user-assigned managed identity** (ACR pull, Key
  Vault). No secrets in code or the repo.
- Endpoint auth is **Entra OAuth 2.0**; `apikey` mode exists only for local spikes.
- TLS is terminated by the platform (Container Apps ingress / APIM).
