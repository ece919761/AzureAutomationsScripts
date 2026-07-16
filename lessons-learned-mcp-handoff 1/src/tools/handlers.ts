import type { ILessonsProvider } from "../providers/ILessonsProvider.js";
import type { CreateLessonInput, UpdateLessonInput } from "../types.js";

/**
 * Pure tool handlers, decoupled from the MCP transport so they can be unit
 * tested directly. `registerTools` wires these to the MCP server with schemas.
 * Errors are returned as structured, non-sensitive tool results (FR-8).
 */

export interface ToolResult {
  // Index signature keeps this compatible with the SDK's CallToolResult shape.
  [key: string]: unknown;
  content: { type: "text"; text: string }[];
  isError?: boolean;
}

export function ok(data: unknown): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

export function fail(message: string): ToolResult {
  return { content: [{ type: "text", text: message }], isError: true };
}

export async function getLessonLearned(
  provider: ILessonsProvider,
  args: { issueKey: string }
): Promise<ToolResult> {
  const record = await provider.get(args.issueKey);
  return record ? ok(record) : fail(`No lessons-learned record found for key '${args.issueKey}'.`);
}

export async function searchLessonsLearned(
  provider: ILessonsProvider,
  args: { query: string; limit?: number }
): Promise<ToolResult> {
  const results = await provider.search(args.query, args.limit);
  return ok({ count: results.length, results });
}

export async function createLessonLearned(
  provider: ILessonsProvider,
  args: CreateLessonInput
): Promise<ToolResult> {
  const record = await provider.create(args);
  return ok({ created: true, record });
}

export async function updateLessonLearned(
  provider: ILessonsProvider,
  args: { issueKey: string } & UpdateLessonInput
): Promise<ToolResult> {
  const { issueKey, ...fields } = args;
  const record = await provider.update(issueKey, fields);
  return record
    ? ok({ updated: true, record })
    : fail(`No lessons-learned record found for key '${issueKey}'.`);
}
