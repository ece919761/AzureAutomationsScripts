import { describe, it, expect } from "vitest";
import { RepresentativeProvider } from "../src/providers/representativeProvider.js";
import { createLessonLearned, getLessonLearned } from "../src/tools/handlers.js";

/**
 * Smoke test: exercises the write path then reads it back through the tool
 * handlers against the representative store (requirements Section 7).
 */
describe("smoke: create -> get", () => {
  it("creates a lesson and retrieves it by the returned key", async () => {
    const provider = new RepresentativeProvider();

    const createResult = await createLessonLearned(provider, {
      summary: "Fixture seating error at station 40",
      description: "Operator seated the fixture backwards; added an asymmetric locating pin.",
      category: "Manufacturing",
      reporter: "qa-agent",
      severity: "Medium"
    });
    expect(createResult.isError).toBeFalsy();

    const created = JSON.parse(createResult.content[0].text) as { record: { key: string } };
    const key = created.record.key;

    const getResult = await getLessonLearned(provider, { issueKey: key });
    expect(getResult.isError).toBeFalsy();

    const fetched = JSON.parse(getResult.content[0].text) as { key: string; summary: string };
    expect(fetched.key).toBe(key);
    expect(fetched.summary).toContain("Fixture seating error");
  });
});
