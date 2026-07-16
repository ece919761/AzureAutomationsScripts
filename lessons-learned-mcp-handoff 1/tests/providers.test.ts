import { describe, it, expect, beforeEach } from "vitest";
import { RepresentativeProvider } from "../src/providers/representativeProvider.js";
import { JiraDataCenterProvider } from "../src/providers/jiraDataCenterProvider.js";

describe("RepresentativeProvider", () => {
  let provider: RepresentativeProvider;

  beforeEach(() => {
    provider = new RepresentativeProvider();
  });

  it("returns a seeded record by key", async () => {
    const record = await provider.get("LL-1001");
    expect(record).not.toBeNull();
    expect(record?.summary).toContain("Torque spec");
  });

  it("returns null for an unknown key", async () => {
    expect(await provider.get("LL-9999")).toBeNull();
  });

  it("searches by free text and orders by relevance", async () => {
    const results = await provider.search("supplier delay");
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].key).toBe("LL-1002");
    expect(results[0].score).toBeGreaterThan(0);
  });

  it("respects the search limit", async () => {
    const results = await provider.search("", 2);
    expect(results.length).toBeLessThanOrEqual(2);
  });

  it("creates a new record with a generated key and Open status", async () => {
    const created = await provider.create({
      summary: "New lesson",
      description: "Something we learned",
      category: "Manufacturing"
    });
    expect(created.key).toMatch(/^LL-\d+$/);
    expect(created.status).toBe("Open");
    expect(await provider.get(created.key)).not.toBeNull();
  });

  it("updates mutable fields and bumps updatedAt", async () => {
    const before = await provider.get("LL-1003");
    const updated = await provider.update("LL-1003", { status: "Closed" });
    expect(updated?.status).toBe("Closed");
    expect(updated?.updatedAt).not.toBe(before?.updatedAt);
  });

  it("returns null when updating an unknown key", async () => {
    expect(await provider.update("LL-0000", { status: "Closed" })).toBeNull();
  });
});

describe("JiraDataCenterProvider (stub)", () => {
  it("throws if required config is missing", () => {
    expect(() => new JiraDataCenterProvider({})).toThrow(/JIRA_BASE_URL/);
  });

  it("constructs with config but throws NotImplemented on calls", async () => {
    const provider = new JiraDataCenterProvider({
      baseUrl: "https://jira.example.local",
      projectKey: "LL"
    });
    await expect(provider.get("LL-1")).rejects.toThrow(/stub/i);
    await expect(
      provider.create({ summary: "x", description: "y", category: "z" })
    ).rejects.toThrow(/stub/i);
  });
});
