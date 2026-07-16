import { Router } from "express";
import type { AppConfig } from "../config.js";

/**
 * OAuth discovery endpoints so Copilot Studio's native OAuth 2.0 option can
 * auto-configure against this resource server:
 *
 *  - RFC 9728 protected-resource metadata  (/.well-known/oauth-protected-resource)
 *  - RFC 8414 authorization-server metadata (/.well-known/oauth-authorization-server)
 *    — delegated to the Entra ID tenant, which is the authorization server.
 *
 * PKCE is enforced by Entra ID at the authorization server; this resource
 * server only validates the resulting access tokens.
 */
export function discoveryRouter(config: AppConfig): Router {
  const router = Router();
  const issuer = `https://login.microsoftonline.com/${config.oauth.tenantId}/v2.0`;

  // RFC 9728 — Protected Resource Metadata
  router.get("/.well-known/oauth-protected-resource", (_req, res) => {
    res.json({
      resource: config.oauth.audience || config.publicBaseUrl,
      authorization_servers: config.authMode === "oauth" ? [issuer] : [],
      scopes_supported: ["mcp.tools"],
      bearer_methods_supported: ["header"],
      resource_documentation: `${config.publicBaseUrl}/health`
    });
  });

  // RFC 8414 — point clients at the Entra authorization-server metadata.
  router.get("/.well-known/oauth-authorization-server", (_req, res) => {
    if (config.authMode !== "oauth") {
      res.status(404).json({ error: "oauth not enabled" });
      return;
    }
    res.json({
      issuer,
      authorization_endpoint: `${issuer}/authorize`,
      token_endpoint: `${issuer}/token`,
      jwks_uri: `https://login.microsoftonline.com/${config.oauth.tenantId}/discovery/v2.0/keys`,
      code_challenge_methods_supported: ["S256"],
      grant_types_supported: ["authorization_code", "client_credentials"],
      response_types_supported: ["code"],
      metadata_source: `${issuer}/.well-known/openid-configuration`
    });
  });

  return router;
}
