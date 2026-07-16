# Copilot Studio → On-Prem Jira Integration
### Requirements Specification
**Azure-Hosted MCP Server — Option B (MVP) evolving to Option C (Hardened)**

| Field | Value |
|---|---|
| **Author** | Brian Skvarch — Sr Cloud Solution Architect |
| **Date** | July 7, 2026 |
| **Version / Status** | Draft v0.1 — for engineering hand-off |
| **Intended audience** | Engineering agent building deployment scripting; solution/security reviewers |
| **Customer** | Harman — Automotive Division, Quality department |
| **Source** | Requirements distilled from the June 18, 2026 discovery meeting transcript |

---

## Contents

1. Purpose & Intended Use
2. Critical Caveat — Representative MCP Server
3. Background & Context
4. Scope
5. Target Architecture
6. Functional Requirements
7. Representative MCP Server — Application Requirements
8. Security Requirements
9. Deployment & Infrastructure Requirements
10. Copilot Studio Integration Requirements
11. Assumptions, Dependencies & Prerequisites
12. Open Questions — To Be Provided by the Customer
13. Acceptance Criteria (Definition of Done)
14. Phased Delivery Plan
15. References

---

## 1. Purpose & Intended Use

This document specifies the requirements for building deployment scripting (infrastructure-as-code plus application scaffolding) that stands up an Azure-hosted Model Context Protocol (MCP) server and integrates it with Microsoft Copilot Studio. It is written to be handed directly to an engineering agent that will generate the scripts, application, and pipelines.

**Two-stage target.** The scripting must deliver a working minimum-viable topology first (**Option B** — a secured, Azure-hosted MCP endpoint that Copilot Studio can reach), then evolve to a hardened, private topology (**Option C** — no public exposure, fronted by API Management with private networking to on-prem over the existing ExpressRoute). The migration from B to C must be a configuration toggle, not a rewrite.

**Definition of MCP.** MCP is an open protocol; the server is the middle-tier component that sits between Copilot Studio agents and the target system and exposes callable tools. This project builds and deploys that server and its hosting.

---

## 2. Critical Caveat — Representative MCP Server

**A licensed Jira on-prem MCP is not available for this engagement.** Therefore the server that gets deployed must be a **representative (reference) implementation** whose purpose is to demonstrate the end-to-end architecture and the MCP flow — Copilot Studio → Azure-hosted MCP endpoint → tool invocation → structured response — rather than the exact Jira REST request/response payloads.

Requirements that follow from this:

- **Representative tools & data.** The server exposes tools shaped like the customer's lessons-learned use case, backed by a seeded mock data store (no real Jira calls).
- **Provider abstraction (the seam).** A single provider interface with two implementations: a `RepresentativeProvider` (default) and a `JiraDataCenterProvider` stub (documented, with clearly marked TODOs and configuration for base URL, project key, and credential reference).
- **Config-driven swap.** Selecting the provider is an environment/setting change (`providerMode = representative | jira`), never a code change or re-architecture. The customer can plug in the real Jira integration behind the same seam.
- **Architecture parity.** Everything except the provider body — transport, auth, hosting, networking, observability — must be identical to what a production deployment would use, so the demo faithfully proves the pattern.

---

## 3. Background & Context

Harman's automotive Quality department is building a lessons-learned tracking system in an on-premises Jira instance and wants Copilot Studio agents to both read from it and write to it (create new lessons-learned entries). Relevant facts from discovery:

- **Reads are already handled.** Jira data is exported on a schedule to Excel/CSV and published to SharePoint; an existing agent reads from SharePoint. Live reads are not the blocker.
- **The blocker is secure write-back (POST).** The prebuilt Jira Data Center connector supports GET only — it cannot create issues.
- **Hard security constraint.** On-prem Jira must not be exposed directly to the internet; this is a non-negotiable customer security requirement.
- **Existing connectivity.** ExpressRoute connectivity between Azure and Harman on-prem is already established (private network path).
- **Chosen direction.** Host the MCP server in Azure (Option B), then harden to a private topology (Option C). This document scopes that build.

---

## 4. Scope

### 4.1 In scope

- Representative MCP server application (containerized) with the provider seam described in Section 2.
- Azure infrastructure to host the server, secured, for both Option B and Option C.
- Copilot Studio integration wiring (adding the MCP server as an agent tool) and the configuration steps.
- Deployment scripting: modular IaC, per-environment and per-mode parameters, and a CI/CD pipeline.
- A README/runbook covering deploy, Copilot Studio connection, and provider swap.

### 4.2 Out of scope

- The real Jira MCP/connector implementation and production Jira credentials (license-constrained; delivered later by the customer behind the seam).
- The read/analysis path (already solved via the SharePoint export).
- Authoring the Copilot Studio agent's conversational content/persona.
- Provisioning of Harman's network, ExpressRoute, or landing zone (assumed present; referenced as parameters).

---

## 5. Target Architecture

### 5.1 Option B — MVP (secured public endpoint)

Copilot Studio (a cloud service) reaches the MCP server over a secured public HTTPS endpoint. The server runs in Azure and, when the real provider is later enabled, reaches on-prem Jira privately over the existing ExpressRoute.

**Data flow:** Copilot Studio agent (generative orchestration on) → HTTPS + Entra ID OAuth 2.0 → MCP server (Container App, Streamable HTTP transport) → provider (representative store; future: Jira over ExpressRoute) → structured tool response → agent.

| Component | Azure service | Role |
|---|---|---|
| MCP host | Azure Container Apps (Linux container) | Runs the representative MCP server; managed HTTPS public ingress |
| Image registry | Azure Container Registry (ACR) | Stores the server image; pulled via managed identity |
| Identity | User-assigned Managed Identity | Azure-to-Azure auth (Key Vault, ACR) — no secrets in code |
| Secrets | Azure Key Vault | Config/secrets (representative settings today; Jira PAT later) |
| Auth | Microsoft Entra ID app registration | Protects the MCP endpoint (OAuth 2.0); exposes an API scope |
| Telemetry | Application Insights + Log Analytics | Traces, logs, correlation IDs, health |

> Azure Container Apps is the recommended host; Azure App Service (Linux) is an acceptable alternative provided it supports the same requirements (Linux container, streamable HTTP, managed identity, and VNet injection for Option C).

### 5.2 Option C — Hardened (no public exposure)

Public exposure of the backend is removed. The MCP host runs on an internal, VNet-injected ingress and is fronted by Azure API Management, which enforces token validation, keys, IP allow-listing, and rate limits. Supporting services move behind private endpoints, and the path to on-prem Jira runs over the existing ExpressRoute.

| Added / changed | Azure service | Role |
|---|---|---|
| Network | Virtual Network + subnets | Isolation for compute, private endpoints, APIM, gateway |
| Ingress | Internal Container Apps environment | Private-only ingress (no public endpoint) |
| API gateway | Azure API Management | JWT validation, subscription keys, IP allow-list, throttling |
| Private access | Private Endpoints + Private DNS | Key Vault and ACR reachable only inside the VNet |
| Optional edge | App Gateway + WAF, or Copilot Studio VNet support | Secured entry / fully private outbound path from the agent |
| On-prem path | ExpressRoute (existing) + route/peering | Private connectivity to on-prem Jira (customer-provided) |

### 5.3 Migration path B → C

**Requirement:** a single parameter `deploymentMode = public | private` must toggle the topology. `public` deploys Option B (public managed ingress, no APIM/private endpoints). `private` deploys Option C (internal ingress, APIM, private endpoints, VNet). The application code is identical across both modes; only infrastructure and configuration change.

---

## 6. Functional Requirements

| ID | Requirement |
|---|---|
| **FR-1** | The MCP server MUST use the Streamable HTTP transport. SSE MUST NOT be used (deprecated in Copilot Studio after Aug 2025). |
| **FR-2** | The server MUST expose representative tools for the lessons-learned use case (see Section 7), including a write/create tool. |
| **FR-3** | The server MUST back tools with a seeded representative data store when `providerMode=representative` (no external calls). |
| **FR-4** | The server MUST implement a provider interface with a Representative implementation (default) and a JiraDataCenter stub, selected by config. |
| **FR-5** | The server MUST expose a health/readiness endpoint for the host's probes. |
| **FR-6** | Tool names, descriptions, and input schemas MUST be clear and specific (the Copilot Studio orchestrator relies on them to decide when to call each tool). |
| **FR-7** | The Copilot Studio agent MUST connect to the server as an MCP tool with generative orchestration enabled and successfully invoke read and create tools end to end. |
| **FR-8** | All tool inputs MUST be validated; errors MUST return structured, non-sensitive messages (never leak secrets or stack traces). |

---

## 7. Representative MCP Server — Application Requirements

**Runtime.** A maintainable, containerized stack with an official MCP SDK — recommended: TypeScript/Node (`@modelcontextprotocol/sdk`, StreamableHTTPServerTransport) or C#/.NET (MCP C# SDK on ASP.NET). Linux container; Dockerfile included.

**Tools** (fields modeled on a Jira "general issue" of mostly text fields; representative, not the real schema):

| Tool | Inputs | Output |
|---|---|---|
| `get_lesson_learned` | issueKey (string) | One lesson-learned record (key, summary, description, category, status, dates) |
| `search_lessons_learned` | query (string), limit (int, optional) | List of matching records (representative relevance) |
| `create_lesson_learned` | summary, description, category, and optional text fields | New record key + echo of stored fields (the WRITE path) |
| `update_lesson_learned` (optional) | issueKey + fields to change | Updated record |

Additional application requirements:

- **Provider seam.** Interface (e.g., `ILessonsProvider`) with `RepresentativeProvider` and `JiraDataCenterProvider` (stub). The stub documents where Jira REST calls go and reads its base URL / project key / credential reference from config.
- **Auth middleware.** OAuth 2.0 resource-server validation for the target auth mode, plus OAuth discovery endpoints (RFC 8414 authorization-server metadata, RFC 9728 protected-resource metadata, PKCE) so Copilot Studio's native OAuth 2.0 option can auto-configure.
- **Config.** All settings via environment variables / Key Vault references; nothing sensitive in source. Includes `providerMode` and `authMode`.
- **Tests.** Unit tests for each tool and both providers, plus a smoke test that exercises create + get against the representative store.

---

## 8. Security Requirements

- **No inbound internet exposure of on-prem Jira.** Option B exposes only the secured Azure MCP endpoint; Option C removes public exposure entirely via internal ingress + APIM + private endpoints.
- **Endpoint authentication.** Entra ID OAuth 2.0 is the target for the MCP endpoint. An API key is acceptable ONLY for the initial spike and MUST be replaced by OAuth before the Option C sign-off.
- **Managed identity.** Azure-to-Azure access (Key Vault, ACR) uses a user-assigned managed identity. No connection strings or keys in code or the repo.
- **Secrets.** All secrets (including the future Jira PAT) live in Azure Key Vault; the future Jira service account MUST be least-privilege, scoped to the lessons-learned project.
- **Transport.** TLS 1.2+ end to end. Certificates managed by the platform (Container Apps ingress / APIM).
- **Network hardening (Option C).** Private endpoints for Key Vault and ACR with Private DNS; APIM policies for JWT validation, subscription keys, IP allow-listing, and rate limiting; on-prem reached only over the existing ExpressRoute.
- **Governance.** The Power Platform environment's DLP policy MUST permit the MCP tool. Audit logging enabled; secrets never written to logs.

---

## 9. Deployment & Infrastructure Requirements

### 9.1 Tooling & deliverables

- **IaC.** Modular Bicep with Azure Developer CLI (azd) is the recommended stack; Terraform is an acceptable alternative. Modules per concern (network, registry, identity, secrets, compute, apim, monitoring).
- **Parameterization.** Separate parameter files per environment and per deployment mode. Deployments MUST be idempotent and environment-agnostic, with a working teardown.
- **CI/CD.** A pipeline (GitHub Actions or Azure DevOps) that builds the container image, pushes to ACR, and deploys the selected mode.
- **Outputs.** Deployment MUST output the MCP endpoint URL (for Copilot Studio), the APIM gateway URL (Option C), identity/client IDs, and key resource IDs.

### 9.2 Resources by mode

**Option B (public):** Resource Group, ACR, Container Apps environment + app, user-assigned Managed Identity, Key Vault, Log Analytics + Application Insights, Entra ID app registration (API scope), managed public HTTPS ingress.

**Option C (private, adds/changes):** Virtual Network + subnets, internal Container Apps environment, Azure API Management, Private Endpoints + Private DNS zones (Key Vault, ACR), optional Application Gateway + WAF or Copilot Studio VNet support, and route/peering to the existing ExpressRoute.

### 9.3 Parameters the scripting MUST expose

| Parameter | Example / values | Notes |
|---|---|---|
| `deploymentMode` | public \| private | Toggles Option B vs Option C topology |
| `providerMode` | representative \| jira | Selects the MCP data provider (default: representative) |
| `authMode` | oauth \| apikey | Endpoint auth; oauth is the target |
| `location` / `envName` / `namingPrefix` | eastus / dev / harman-ll | Region, environment, resource naming |
| `tenantId` / `appClientId` / `apiScope` | GUIDs / api://… | Entra ID identity + exposed scope |
| `jiraBaseUrl` / `jiraProjectKey` / `jiraPatSecretName` | (customer-provided) | Consumed only when `providerMode=jira`; PAT via Key Vault |
| vnet address space / subnets / existing VNet ref | 10.x.0.0/16 or existing | Option C networking |
| `expressRouteGatewayRef` | (customer-provided) | Route to on-prem; Harman-provided |
| `containerImageTag` / SKU sizes | v0.1.0 / demo tiers | Image version and cost tiers |

---

## 10. Copilot Studio Integration Requirements

- In the target agent, add the server via **Tools → Add a tool → New tool → Model Context Protocol**; provide the deployed endpoint URL and configure authentication (None / API key / OAuth 2.0).
- **Generative orchestration MUST be turned on** — it is required for MCP tools.
- Transport MUST be Streamable HTTP (see FR-1).
- Document the exact connection steps and the Entra ID configuration needed for the OAuth 2.0 option (app registration, scope, redirect/discovery).
- Confirm the environment's DLP policy permits the tool before the demo.

---

## 11. Assumptions, Dependencies & Prerequisites

- ExpressRoute connectivity between Azure and Harman on-prem is established and routable.
- Harman provides the Azure subscription/landing zone, Entra tenant, and the RBAC needed to create the resources and app registration.
- A Power Platform environment with Copilot Studio and generative orchestration is available.
- On-prem Jira is Jira Data Center/Server exposing a REST API (relevant only to the future real provider).
- An on-premises data gateway may already exist (a Confluence setup was mentioned) — informational; may be reusable for a connector-based alternative later.
- Network/security teams are available for private DNS, ExpressRoute routing, and security sign-off.

---

## 12. Open Questions — To Be Provided by the Customer

These do not block the representative build, but they are required before wiring the real Jira provider. Capture answers as parameters.

1. Jira flavor and REST API version (Data Center vs Server; API v2/v3).
2. Jira service-account authentication method (personal access token, OAuth, or basic).
3. Issue schema: which project and issue type is the "general issue" for lessons learned, and which fields are required to create one.
4. Whether the existing on-premises data gateway can be reused.
5. Power Platform environment details and whether VNet support is licensed/available in-region.
6. Azure landing-zone owner, target region, and naming/tagging standards.
7. Security approval process and sign-off owner.

---

## 13. Acceptance Criteria (Definition of Done)

### 13.1 Option B

- A single deploy provisions the public-secured topology (`deploymentMode=public`).
- The representative MCP server is reachable at a secured HTTPS URL.
- A Copilot Studio agent connects to it and successfully calls `create_lesson_learned` and `get_lesson_learned` end to end against the representative backend.
- Telemetry is visible in Application Insights; secrets are in Key Vault; managed identity is used.

### 13.2 Option C

- The same functional behavior with `deploymentMode=private` and no public exposure of the backend.
- APIM/private endpoint and Entra ID OAuth are enforced; Key Vault and ACR are reachable only via private endpoints.
- The path to on-prem over the existing ExpressRoute is documented and ready for the real provider.

### 13.3 Cross-cutting

- The provider seam is documented and swappable via config, with the Jira stub present.
- IaC is idempotent, parameterized, and environment-agnostic; teardown works.
- A README/runbook covers deploy, Copilot Studio connection, and provider swap.

---

## 14. Phased Delivery Plan

| Phase | Outcome |
|---|---|
| **0 — Scaffold** | Repo, representative MCP app, local run, unit + smoke tests |
| **1 — Option B** | IaC for public-secured topology; deploy; Copilot Studio integration; end-to-end read + write demo |
| **2 — Option C** | VNet, APIM, private endpoints; hardened auth; documented private path to on-prem; re-test |
| **3 — Handover** | Finalize provider seam; README/runbook; customer plugs in real Jira behind the seam |

---

## 15. References

- [Extend your agent with Model Context Protocol — Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/agent-extend-action-mcp)
- [Connect your agent to an existing MCP server — Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/mcp-add-existing-server-to-agent)
- [Custom connectors overview (on-premises data gateway for private APIs) — Microsoft Learn](https://learn.microsoft.com/en-us/connectors/custom-connectors/)
- [Virtual Network support for agent calls to private endpoints — Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-network-isolation-vnet)

---

*Confidential — for internal engineering hand-off.*
