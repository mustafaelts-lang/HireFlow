/**
 * System-level application lifecycle state.
 * Separate from pipeline stage (`currentJobStageId`).
 * Do not derive these values from arbitrary stage names.
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
