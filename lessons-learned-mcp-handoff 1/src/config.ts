/**
 * Central configuration. Everything comes from environment variables (or Key
 * Vault references injected as env vars in Azure). Nothing sensitive lives in
 * source. The two seam toggles — providerMode and authMode — are read here.
 */

export type ProviderMode = "representative" | "jira";
export type AuthMode = "oauth" | "apikey";

export interface AppConfig {
  port: number;
  nodeEnv: string;
  providerMode: ProviderMode;
  authMode: AuthMode;
  publicBaseUrl: string;
  oauth: {
    tenantId: string;
    audience: string;
    audiences: string[];
    clientId: string;
  };
  apiKey?: string;
  jira: {
    baseUrl?: string;
    projectKey?: string;
    pat?: string;
  };
  appInsightsConnectionString?: string;
}

class ConfigError extends Error {}

function pick(env: NodeJS.ProcessEnv, key: string): string | undefined {
  const value = env[key];
  return value && value.trim().length > 0 ? value.trim() : undefined;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const providerMode = (pick(env, "PROVIDER_MODE") ?? "representative") as ProviderMode;
  if (providerMode !== "representative" && providerMode !== "jira") {
    throw new ConfigError(`Invalid PROVIDER_MODE '${providerMode}' (expected 'representative' | 'jira').`);
  }

  const authMode = (pick(env, "AUTH_MODE") ?? "oauth") as AuthMode;
  if (authMode !== "oauth" && authMode !== "apikey") {
    throw new ConfigError(`Invalid AUTH_MODE '${authMode}' (expected 'oauth' | 'apikey').`);
  }

  const tenantId = pick(env, "ENTRA_TENANT_ID") ?? "";
  const clientId = pick(env, "MCP_API_CLIENT_ID") ?? "";
  const audience = pick(env, "MCP_API_AUDIENCE") ?? (clientId ? `api://${clientId}` : "");
  const apiKey = pick(env, "MCP_API_KEY");

  // Entra emits different audience formats depending on the token version:
  // v1.0 access tokens use the App ID URI (api://<clientId>), while v2.0 tokens
  // use the bare client-id GUID. Accept every equivalent form so the resource
  // server validates correctly regardless of requestedAccessTokenVersion.
  const audienceSet = new Set<string>();
  if (audience) {
    audienceSet.add(audience);
    audienceSet.add(audience.replace(/^api:\/\//, ""));
  }
  if (clientId) {
    audienceSet.add(clientId);
    audienceSet.add(`api://${clientId}`);
  }
  const audiences = [...audienceSet];

  if (authMode === "oauth" && (!tenantId || !audience)) {
    throw new ConfigError(
      "AUTH_MODE=oauth requires ENTRA_TENANT_ID and MCP_API_AUDIENCE (or MCP_API_CLIENT_ID)."
    );
  }
  if (authMode === "apikey" && !apiKey) {
    throw new ConfigError("AUTH_MODE=apikey requires MCP_API_KEY.");
  }

  return {
    port: Number(pick(env, "PORT") ?? "8080"),
    nodeEnv: pick(env, "NODE_ENV") ?? "development",
    providerMode,
    authMode,
    publicBaseUrl: pick(env, "PUBLIC_BASE_URL") ?? "http://localhost:8080",
    oauth: { tenantId, audience, audiences, clientId },
    apiKey,
    jira: {
      baseUrl: pick(env, "JIRA_BASE_URL"),
      projectKey: pick(env, "JIRA_PROJECT_KEY"),
      pat: pick(env, "JIRA_PAT")
    },
    appInsightsConnectionString: pick(env, "APPLICATIONINSIGHTS_CONNECTION_STRING")
  };
}
