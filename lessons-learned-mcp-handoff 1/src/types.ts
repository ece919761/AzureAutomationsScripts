/**
 * Domain types for the representative lessons-learned use case.
 * Fields are modeled on a Jira "general issue" (mostly text) — representative,
 * not the customer's real schema (see requirements Section 7).
 */

export interface LessonLearned {
  key: string;
  summary: string;
  description: string;
  category: string;
  status: string;
  createdAt: string;
  updatedAt: string;
}

export interface CreateLessonInput {
  summary: string;
  description: string;
  category: string;
  reporter?: string;
  component?: string;
  severity?: string;
}

export interface UpdateLessonInput {
  summary?: string;
  description?: string;
  category?: string;
  status?: string;
}

export interface SearchResult {
  key: string;
  summary: string;
  category: string;
  status: string;
  score: number;
}
