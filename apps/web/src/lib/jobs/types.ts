export const JOB_STATUSES = [
  "draft",
  "open",
  "on_hold",
  "closed",
  "filled",
] as const;

export type JobStatus = (typeof JOB_STATUSES)[number];

export const JOB_STATUS_LABELS: Record<JobStatus, string> = {
  draft: "Draft",
  open: "Open",
  on_hold: "On hold",
  closed: "Closed",
  filled: "Filled",
};

export const EMPLOYMENT_TYPES = [
  "full_time",
  "part_time",
  "contract",
  "intern",
] as const;

export type EmploymentType = (typeof EMPLOYMENT_TYPES)[number];

export const EMPLOYMENT_TYPE_LABELS: Record<EmploymentType, string> = {
  full_time: "Full time",
  part_time: "Part time",
  contract: "Contract",
  intern: "Intern",
};

export type JobStage = {
  id: string;
  key: string;
  name: string;
  sortOrder: number;
  color: string;
  slaDays: number | null;
  category: string;
  notes: string | null;
  /** Exactly one stage per job is the system Applied entry stage. */
  isAppliedEntry: boolean;
};

export type JobRecord = {
  id: string;
  tenantId: string;
  title: string;
  department: string | null;
  location: string | null;
  employmentType: EmploymentType | null;
  description: string | null;
  status: JobStatus;
  openings: number;
  requestingDepartment: string | null;
  requestedByName: string | null;
  requestedAt: string | null;
  hiringManagerName: string | null;
  hiringManagerEmail: string | null;
  publishedAt: string | null;
  publicApplyToken: string | null;
  applyEnabled: boolean;
  pipelineTemplateId: string | null;
  pipelineTemplateName?: string | null;
  archivedAt: string | null;
  createdAt: string;
  updatedAt: string;
};

export function isJobStatus(value: string): value is JobStatus {
  return (JOB_STATUSES as readonly string[]).includes(value);
}

export function isEmploymentType(value: string): value is EmploymentType {
  return (EMPLOYMENT_TYPES as readonly string[]).includes(value);
}

export function buildPublicApplyPath(token: string) {
  return `/apply/${token}`;
}
