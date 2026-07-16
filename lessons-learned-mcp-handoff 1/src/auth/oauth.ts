import type { NextFunction, Request, Response } from "express";
import { createRemoteJWKSet, jwtVerify } from "jose";
import type { AppConfig } from "../config.js";
import { log } from "../logging.js";

/**
 * OAuth 2.0 resource-server validation for the MCP endpoint.
 *
 * When authMode=oauth, incoming Bearer tokens are validated against the Entra
 * ID tenant's JWKS (issuer + audience checks). When authMode=apikey (spike
 * only), a static header is checked instead. On 401 we advertise the protected
 * resource metadata via WWW-Authenticate so clients can discover how to auth
 * (RFC 9728).
 */

const V2_ISSUER = (tenantId: string) => `https://login.microsoftonline.com/${tenantId}/v2.0`;
const JWKS_URI = (tenantId: string) =>
  `https://login.microsoftonline.com/${tenantId}/discovery/v2.0/keys`;

export function createAuthMiddleware(config: AppConfig) {
  if (config.authMode === "apikey") {
    return apiKeyMiddleware(config.apiKey ?? "");
  }
  return oauthMiddleware(config);
}

function apiKeyMiddleware(expectedKey: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const provided = req.header("x-api-key");
    if (!provided || provided !== expectedKey) {
      res.status(401).json(unauthorized("Missing or invalid API key."));
      return;
    }
    next();
  };
}

function oauthMiddleware(config: AppConfig) {
  const jwks = createRemoteJWKSet(new URL(JWKS_URI(config.oauth.tenantId)));
  const issuer = V2_ISSUER(config.oauth.tenantId);
  const resourceMetadataUrl = `${config.publicBaseUrl}/.well-known/oauth-protected-resource`;

  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const header = req.header("authorization");
    if (!header || !header.toLowerCase().startsWith("bearer ")) {
      res
        .status(401)
        .set("WWW-Authenticate", `Bearer resource_metadata="${resourceMetadataUrl}"`)
        .json(unauthorized("Missing bearer token."));
      return;
    }

    const token = header.slice(7).trim();
    try {
      const { payload } = await jwtVerify(token, jwks, {
        issuer,
        audience: config.oauth.audiences
      });
      (req as Request & { auth?: unknown }).auth = payload;
      next();
    } catch (error) {
      log("warn", "token validation failed", { error: (error as Error).message });
      res
        .status(401)
        .set("WWW-Authenticate", `Bearer resource_metadata="${resourceMetadataUrl}", error="invalid_token"`)
        .json(unauthorized("Invalid bearer token."));
    }
  };
}

function unauthorized(message: string) {
  // JSON-RPC style, non-sensitive body.
  return { jsonrpc: "2.0", error: { code: -32001, message }, id: null };
}
