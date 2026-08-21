/**
 * System-level application lifecycle state.
 * Separate from pipeline stage (`currentJobStageId`).
 * Do not derive these values from arbitrary stage names.
 *
 * Product surfaces (Company History, Application Header) show lifecycle status
 * as the current outcome. When status is disqualified/hired/withdrawn,
 * currentJobStageId is the last pipeline stage reached — not an active board
 * position. Hired UI tabs filter status='hired'; they are not Move Stage targets.
 */
export type ApplicationLifecycleStatus =
  | "active"
  | "hired"
  | "disqualified"
  | "withdrawn"
  | "transferred";

export type ApplicationStageEventType =
  | "initial"
  | "transition"
  | "migration_backfill";

export interface Application {
  id: string;
  tenantId: string;
  jobId: string;
  candidateId: string;
  /** Pipeline position source of truth (job_stages.id for this job). */
  currentJobStageId: string;
  status: ApplicationLifecycleStatus;
  createdAt: string;
  updatedAt: string;
}

export interface DisqualificationCategory {
  id: string;
  tenantId: string;
  key: string;
  label: string;
  sortOrder: number;
  isActive: boolean;
}

export interface ApplicationDisqualification {
  id: string;
  tenantId: string;
  applicationId: string;
  jobId: string;
  categoryId: string;
  detailedReason: string;
  actorUserId: string;
  occurredAt: string;
  fromJobStageId: string | null;
  fromStageKey: string;
  fromStageName: string;
  fromStageCategory: string;
}
