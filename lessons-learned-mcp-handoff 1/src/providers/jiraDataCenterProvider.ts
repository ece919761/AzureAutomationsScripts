import type {
  CreateLessonInput,
  LessonLearned,
  SearchResult,
  UpdateLessonInput
} from "../types.js";
import type { ILessonsProvider } from "./ILessonsProvider.js";

export interface JiraProviderOptions {
  baseUrl?: string;
  projectKey?: string;
  /**
   * The Jira PAT itself is NOT held here in production — it is injected from
   * Key Vault as an env var. Passed through only so the seam is complete.
   */
  pat?: string;
}

/**
 * ===========================================================================
 * STUB — Jira Data Center provider.
 *
 * This is the seam where the customer plugs in the real Jira integration. The
 * architecture around it (transport, auth, hosting, networking, observability)
 * is identical to production; only the body below changes. Selecting this
 * provider is a config change (PROVIDER_MODE=jira), never a re-architecture.
 *
 * When implementing, target the Jira Data Center/Server REST API and reach it
 * privately over the existing ExpressRoute (see requirements Section 5 & 12).
 * ===========================================================================
 */
export class JiraDataCenterProvider implements ILessonsProvider {
  readonly mode = "jira";

  constructor(options: JiraProviderOptions) {
    if (!options.baseUrl || !options.projectKey) {
      throw new Error(
        "JiraDataCenterProvider requires JIRA_BASE_URL and JIRA_PROJECT_KEY when PROVIDER_MODE=jira."
      );
    }
  }

  async get(_issueKey: string): Promise<LessonLearned | null> {
    // TODO(customer): GET {baseUrl}/rest/api/2/issue/{issueKey}
    // Map the Jira issue fields -> LessonLearned. Auth via Bearer PAT.
    throw new NotImplemented("get");
  }

  async search(_query: string, _limit?: number): Promise<SearchResult[]> {
    // TODO(customer): POST {baseUrl}/rest/api/2/search with a JQL query scoped
    // to {projectKey}. Map issues -> SearchResult[].
    throw new NotImplemented("search");
  }

  async create(_input: CreateLessonInput): Promise<LessonLearned> {
    // TODO(customer): POST {baseUrl}/rest/api/2/issue with fields.project.key
    // = {projectKey}, issuetype, summary, description, and custom fields.
    // This is the write-back path the prebuilt connector cannot do.
    throw new NotImplemented("create");
  }

  async update(_issueKey: string, _input: UpdateLessonInput): Promise<LessonLearned | null> {
    // TODO(customer): PUT {baseUrl}/rest/api/2/issue/{issueKey} with the
    // changed fields, then re-fetch and map.
    throw new NotImplemented("update");
  }
}

class NotImplemented extends Error {
  constructor(operation: string) {
    super(
      `JiraDataCenterProvider.${operation}() is a stub. Implement the Jira REST call behind this seam ` +
        `before enabling PROVIDER_MODE=jira.`
    );
    this.name = "NotImplemented";
  }
}
