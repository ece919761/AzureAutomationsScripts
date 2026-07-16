import express, { type Request, type Response } from "express";
import { randomUUID } from "node:crypto";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { loadConfig } from "./config.js";
import { initTelemetry, log } from "./logging.js";
import { createProvider } from "./providers/index.js";
import { registerTools } from "./tools/index.js";
import { createAuthMiddleware } from "./auth/oauth.js";
import { discoveryRouter } from "./auth/discovery.js";
import type { ILessonsProvider } from "./providers/ILessonsProvider.js";

const SERVER_NAME = "lessons-learned-mcp";
const SERVER_VERSION = "0.1.0";

/** Build a fresh MCP server instance (stateless: one per request). */
function buildMcpServer(provider: ILessonsProvider): McpServer {
  const server = new McpServer({ name: SERVER_NAME, version: SERVER_VERSION });
  registerTools(server, provider);
  return server;
}

export function createApp(provider: ILessonsProvider, config = loadConfig()) {
  const app = express();
  app.use(express.json());

  // Correlation id on every request (propagated to logs / responses).
  app.use((req, res, next) => {
    const correlationId = req.header("x-correlation-id") ?? randomUUID();
    res.setHeader("x-correlation-id", correlationId);
    (req as Request & { correlationId?: string }).correlationId = correlationId;
    next();
  });

  // Health / readiness for the host's probes (FR-5).
  app.get("/health", (_req, res) => {
    res.status(200).json({ status: "ok", server: SERVER_NAME, providerMode: provider.mode });
  });
  app.get("/ready", (_req, res) => {
    res.status(200).json({ status: "ready" });
  });

  // OAuth discovery endpoints (public, unauthenticated).
  app.use(discoveryRouter(config));

  // Streamable HTTP MCP endpoint (FR-1), protected by the configured auth mode.
  const auth = createAuthMiddleware(config);

  app.post("/mcp", auth, async (req: Request, res: Response) => {
    const server = buildMcpServer(provider);
    // enableJsonResponse=true makes the transport reply with a single
    // application/json response instead of an SSE (text/event-stream) stream.
    // SSE works direct-to-container, but APIM buffers/mangles streamed
    // responses, so JSON responses are required behind the private gateway.
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true
    });
    res.on("close", () => {
      void transport.close();
      void server.close();
    });
    try {
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    } catch (error) {
      log("error", "mcp request failed", {
        error: (error as Error).message,
        correlationId: (req as Request & { correlationId?: string }).correlationId
      });
      if (!res.headersSent) {
        res
          .status(500)
          .json({ jsonrpc: "2.0", error: { code: -32603, message: "Internal server error" }, id: null });
      }
    }
  });

  // Stateless transport does not support GET/DELETE sessions.
  const methodNotAllowed = (_req: Request, res: Response) =>
    res
      .status(405)
      .json({ jsonrpc: "2.0", error: { code: -32000, message: "Method not allowed." }, id: null });
  app.get("/mcp", methodNotAllowed);
  app.delete("/mcp", methodNotAllowed);

  return app;
}

/** Entry point. */
function main(): void {
  const config = loadConfig();
  initTelemetry(config.appInsightsConnectionString);
  const provider = createProvider(config);
  const app = createApp(provider, config);
  app.listen(config.port, () => {
    log("info", "MCP server listening", {
      port: config.port,
      providerMode: provider.mode,
      authMode: config.authMode,
      deploymentEnv: config.nodeEnv
    });
  });
}

// Only start the HTTP listener when run directly (not when imported by tests).
if (process.env.NODE_ENV !== "test" && process.argv[1]?.endsWith("server.js")) {
  main();
}
