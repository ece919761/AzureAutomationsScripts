import type {
  CreateLessonInput,
  LessonLearned,
  SearchResult,
  UpdateLessonInput
} from "../types.js";
import type { ILessonsProvider } from "./ILessonsProvider.js";
import { seedLessons } from "./seedData.js";

/**
 * Default provider: an in-memory, seeded store. No external calls. Proves the
 * end-to-end MCP flow (including the write path) without touching Jira.
 */
export class RepresentativeProvider implements ILessonsProvider {
  readonly mode = "representative";
  private readonly store = new Map<string, LessonLearned>();
  private sequence = 1000;

  constructor(seed: LessonLearned[] = seedLessons) {
    for (const lesson of seed) {
      this.store.set(lesson.key, { ...lesson });
      const numeric = Number(lesson.key.replace(/\D/g, ""));
      if (!Number.isNaN(numeric) && numeric > this.sequence) this.sequence = numeric;
    }
  }

  async get(issueKey: string): Promise<LessonLearned | null> {
    return this.store.get(issueKey) ?? null;
  }

  async search(query: string, limit = 10): Promise<SearchResult[]> {
    const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
    const scored: SearchResult[] = [];
    for (const lesson of this.store.values()) {
      const haystack = `${lesson.summary} ${lesson.description} ${lesson.category}`.toLowerCase();
      const hits = terms.reduce((acc, term) => acc + (haystack.includes(term) ? 1 : 0), 0);
      if (terms.length === 0 || hits > 0) {
        scored.push({
          key: lesson.key,
          summary: lesson.summary,
          category: lesson.category,
          status: lesson.status,
          score: terms.length === 0 ? 1 : hits / terms.length
        });
      }
    }
    return scored.sort((a, b) => b.score - a.score).slice(0, Math.max(1, limit));
  }

  async create(input: CreateLessonInput): Promise<LessonLearned> {
    const now = new Date().toISOString();
    const key = `LL-${++this.sequence}`;
    const record: LessonLearned = {
      key,
      summary: input.summary,
      description: input.description,
      category: input.category,
      status: "Open",
      createdAt: now,
      updatedAt: now
    };
    this.store.set(key, record);
    return { ...record };
  }

  async update(issueKey: string, input: UpdateLessonInput): Promise<LessonLearned | null> {
    const existing = this.store.get(issueKey);
    if (!existing) return null;
    const updated: LessonLearned = {
      ...existing,
      summary: input.summary ?? existing.summary,
      description: input.description ?? existing.description,
      category: input.category ?? existing.category,
      status: input.status ?? existing.status,
      updatedAt: new Date().toISOString()
    };
    this.store.set(issueKey, updated);
    return { ...updated };
  }
}
