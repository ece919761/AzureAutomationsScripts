import type { AppConfig } from "../config.js";
import type { ILessonsProvider } from "./ILessonsProvider.js";
import { RepresentativeProvider } from "./representativeProvider.js";
import { JiraDataCenterProvider } from "./jiraDataCenterProvider.js";

/**
 * Config-driven provider selection (the swap point). Default is representative.
 */
export function createProvider(config: AppConfig): ILessonsProvider {
  if (config.providerMode === "jira") {
    return new JiraDataCenterProvider({
      baseUrl: config.jira.baseUrl,
      projectKey: config.jira.projectKey,
      pat: config.jira.pat
    });
  }
  return new RepresentativeProvider();
}

export { RepresentativeProvider } from "./representativeProvider.js";
export { JiraDataCenterProvider } from "./jiraDataCenterProvider.js";
export type { ILessonsProvider } from "./ILessonsProvider.js";
