/**
 * System-level application lifecycle state.
 * Separate from pipeline stage (`current_stage` / future `current_job_stage_id`).
 * Do not derive these values from arbitrary stage names.
 */
export type ApplicationLifecycleStatus =
  | "active"
  | "hired"
  | "disqualified"
  | "withdrawn"
  | "transferred";

export interface Application {
  id: string;
  tenantId: string;
  jobId: string;
  candidateId: string;
  /** Pipeline stage key (legacy text). Stage ID foundation is a later hardening step. */
  currentStage: string;
  status: ApplicationLifecycleStatus;
  createdAt: string;
  updatedAt: string;
}
