import type {
  CreateLessonInput,
  LessonLearned,
  SearchResult,
  UpdateLessonInput
} from "../types.js";

/**
 * The single provider seam. All tools talk to this interface only, so the data
 * source can be swapped from the representative store to real Jira via config
 * (providerMode) — never a code change (requirements Section 2 & FR-4).
 */
export interface ILessonsProvider {
  /** Human-readable mode name, surfaced on the health endpoint. */
  readonly mode: string;

  /** Fetch a single record by key, or null if not found. */
  get(issueKey: string): Promise<LessonLearned | null>;

  /** Search records; returns lightweight results ordered by relevance. */
  search(query: string, limit?: number): Promise<SearchResult[]>;

  /** Create a new record (the write-back path) and return the stored entity. */
  create(input: CreateLessonInput): Promise<LessonLearned>;

  /** Update mutable fields; null if the target key does not exist. */
  update(issueKey: string, input: UpdateLessonInput): Promise<LessonLearned | null>;
}
