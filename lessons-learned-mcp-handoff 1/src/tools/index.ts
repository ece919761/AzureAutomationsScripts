import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { ILessonsProvider } from "../providers/ILessonsProvider.js";
import {
  createLessonLearned,
  getLessonLearned,
  searchLessonsLearned,
  updateLessonLearned
} from "./handlers.js";

/**
 * Registers the representative lessons-learned tools on the MCP server.
 * Tool names, descriptions, and input schemas are deliberately clear and
 * specific — the Copilot Studio orchestrator uses them to decide when to call
 * each tool (FR-6).
 */
export function registerTools(server: McpServer, provider: ILessonsProvider): void {
  server.tool(
    "get_lesson_learned",
    "Retrieve a single lessons-learned record by its issue key (for example 'LL-1001'). Use when the user references a specific record ID.",
    {
      issueKey: z
        .string()
        .min(1)
        .describe("The unique key of the lessons-learned record, e.g. 'LL-1001'.")
    },
    async (args) => getLessonLearned(provider, args)
  );

  server.tool(
    "search_lessons_learned",
    "Search lessons-learned records by free-text query (matches summary, description, and category). Use to find related prior lessons.",
    {
      query: z.string().min(1).describe("Free-text search terms, e.g. 'torque spec supplier delay'."),
      limit: z
        .number()
        .int()
        .positive()
        .max(50)
        .optional()
        .describe("Maximum number of results to return (default 10).")
    },
    async (args) => searchLessonsLearned(provider, args)
  );

  server.tool(
    "create_lesson_learned",
    "Create a new lessons-learned record. This is the write-back path — use when the user wants to log a new lesson learned.",
    {
      summary: z.string().min(1).describe("Short one-line title of the lesson learned."),
      description: z.string().min(1).describe("Full description: what happened, root cause, and corrective action."),
      category: z
        .string()
        .min(1)
        .describe("Category, e.g. 'Manufacturing', 'Supplier Quality', 'Validation'."),
      reporter: z.string().optional().describe("Name or ID of the person reporting the lesson."),
      component: z.string().optional().describe("Affected component or subsystem."),
      severity: z.string().optional().describe("Severity or impact level.")
    },
    async (args) => createLessonLearned(provider, args)
  );

  server.tool(
    "update_lesson_learned",
    "Update fields on an existing lessons-learned record identified by its issue key.",
    {
      issueKey: z.string().min(1).describe("The key of the record to update, e.g. 'LL-1001'."),
      summary: z.string().optional().describe("New summary."),
      description: z.string().optional().describe("New description."),
      category: z.string().optional().describe("New category."),
      status: z.string().optional().describe("New status, e.g. 'Open', 'In Progress', 'Closed'.")
    },
    async (args) => updateLessonLearned(provider, args)
  );
}
