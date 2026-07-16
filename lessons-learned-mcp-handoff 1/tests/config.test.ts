import { describe, it, expect } from "vitest";
import { loadConfig } from "../src/config.js";

const base = {
  PROVIDER_MODE: "representative",
  AUTH_MODE: "oauth",
  ENTRA_TENANT_ID: "00000000-0000-0000-0000-000000000000",
  MCP_API_CLIENT_ID: "11111111-1111-1111-1111-111111111111"
} as NodeJS.ProcessEnv;

describe("loadConfig", () => {
  it("derives the audience from the client id when not set", () => {
    const config = loadConfig(base);
    expect(config.oauth.audience).toBe("api://11111111-1111-1111-1111-111111111111");
  });

  it("throws when oauth is selected without tenant/audience", () => {
    expect(() => loadConfig({ AUTH_MODE: "oauth" } as NodeJS.ProcessEnv)).toThrow(/ENTRA_TENANT_ID/);
  });

  it("throws when apikey is selected without a key", () => {
    expect(() => loadConfig({ AUTH_MODE: "apikey" } as NodeJS.ProcessEnv)).toThrow(/MCP_API_KEY/);
  });

  it("accepts apikey mode with a key", () => {
    const config = loadConfig({ AUTH_MODE: "apikey", MCP_API_KEY: "secret" } as NodeJS.ProcessEnv);
    expect(config.authMode).toBe("apikey");
    expect(config.apiKey).toBe("secret");
  });

  it("rejects an invalid provider mode", () => {
    expect(() => loadConfig({ ...base, PROVIDER_MODE: "bogus" } as NodeJS.ProcessEnv)).toThrow(
      /Invalid PROVIDER_MODE/
    );
  });
});
