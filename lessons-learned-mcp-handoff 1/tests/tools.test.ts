import { describe, it, expect, beforeEach } from "vitest";
import { RepresentativeProvider } from "../src/providers/representativeProvider.js";
import {
  createLessonLearned,
  getLessonLearned,
  searchLessonsLearned,
  updateLessonLearned
} from "../src/tools/handlers.js";

function parse(text: string): unknown {
  return JSON.parse(text);
}

describe("tool handlers", () => {
  let provider: RepresentativeProvider;

  beforeEach(() => {
    provider = new RepresentativeProvider();
  });

  it("get_lesson_learned returns the record", async () => {
    const result = await getLessonLearned(provider, { issueKey: "LL-1001" });
    expect(result.isError).toBeFalsy();
    expect((parse(result.content[0].text) as { key: string }).key).toBe("LL-1001");
  });

  it("get_lesson_learned returns a structured error for unknown key", async () => {
    const result = await getLessonLearned(provider, { issueKey: "LL-9999" });
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("No lessons-learned record found");
  });

  it("search_lessons_learned returns a count and results", async () => {
    const result = await searchLessonsLearned(provider, { query: "EMC grounding" });
    const body = parse(result.content[0].text) as { count: number; results: unknown[] };
    expect(body.count).toBeGreaterThan(0);
    expect(body.results.length).toBe(body.count);
  });

  it("create_lesson_learned creates and echoes the record", async () => {
    const result = await createLessonLearned(provider, {
      summary: "Calibration drift on torque tool",
      description: "Tool drifted out of spec between PM cycles.",
      category: "Manufacturing"
    });
    const body = parse(result.content[0].text) as { created: boolean; record: { key: string } };
    expect(body.created).toBe(true);
    expect(body.record.key).toMatch(/^LL-\d+$/);
  });

  it("update_lesson_learned updates an existing record", async () => {
    const result = await updateLessonLearned(provider, { issueKey: "LL-1001", status: "Reopened" });
    const body = parse(result.content[0].text) as { updated: boolean; record: { status: string } };
    expect(body.updated).toBe(true);
    expect(body.record.status).toBe("Reopened");
  });

  it("update_lesson_learned errors on unknown key", async () => {
    const result = await updateLessonLearned(provider, { issueKey: "LL-0000", status: "Closed" });
    expect(result.isError).toBe(true);
  });
});
