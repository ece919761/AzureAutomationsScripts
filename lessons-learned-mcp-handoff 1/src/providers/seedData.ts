import type { LessonLearned } from "../types.js";

/**
 * Seed data for the representative store. Shaped like Harman's lessons-learned
 * use case but entirely synthetic — no real Jira data.
 */
export const seedLessons: LessonLearned[] = [
  {
    key: "LL-1001",
    summary: "Torque spec mismatch on bracket fastener during line trial",
    description:
      "Assembly line trial revealed the fastener torque spec in the work instruction did not match the engineering drawing. Corrected the WI and added a poka-yoke check.",
    category: "Manufacturing",
    status: "Closed",
    createdAt: "2026-02-11T14:20:00.000Z",
    updatedAt: "2026-03-02T09:05:00.000Z"
  },
  {
    key: "LL-1002",
    summary: "Supplier PPAP delay caused pilot slip",
    description:
      "A tier-2 supplier's PPAP submission was late, slipping the pilot build by two weeks. Added earlier PPAP milestone tracking to the APQP plan.",
    category: "Supplier Quality",
    status: "Closed",
    createdAt: "2026-01-28T11:00:00.000Z",
    updatedAt: "2026-02-15T16:40:00.000Z"
  },
  {
    key: "LL-1003",
    summary: "EMC test failure traced to grounding strap routing",
    description:
      "Radiated emissions exceeded limits at 120 MHz. Root cause was grounding strap routing near the harness. Updated the routing standard and design checklist.",
    category: "Validation",
    status: "In Progress",
    createdAt: "2026-03-19T08:30:00.000Z",
    updatedAt: "2026-04-01T13:15:00.000Z"
  }
];
