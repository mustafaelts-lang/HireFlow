export type AssessmentTemplateVersionStatus = "draft" | "published";

export type AssessmentFieldType =
  | "text"
  | "long_text"
  | "yes_no"
  | "single_select"
  | "multi_select"
  | "numeric_rating"
  | "number";

export type InterviewAssessmentStatus = "draft" | "finalized";

/**
 * Structured field configuration (options, min/max, etc.).
 * Finalized answers persist a copy of this config for History Never Lies.
 */
export type AssessmentFieldConfig = Record<string, unknown>;

export interface AssessmentTemplate {
  id: string;
  tenantId: string;
  name: string;
  description: string | null;
}

export interface AssessmentTemplateVersion {
  id: string;
  tenantId: string;
  templateId: string;
  versionNumber: number;
  status: AssessmentTemplateVersionStatus;
  publishedAt: string | null;
  publishedBy: string | null;
}

export interface AssessmentTemplateField {
  id: string;
  tenantId: string;
  templateVersionId: string;
  key: string;
  label: string;
  fieldType: AssessmentFieldType;
  fieldConfig: AssessmentFieldConfig;
  sortOrder: number;
  isRequired: boolean;
}

export interface InterviewAssessment {
  id: string;
  tenantId: string;
  /** Required — assessments belong to the application. */
  applicationId: string;
  /** Optional scheduling/session context. */
  interviewId: string | null;
  templateVersionId: string;
  status: InterviewAssessmentStatus;
  createdBy: string;
  finalizedAt: string | null;
  finalizedBy: string | null;
}

export interface InterviewAssessmentAnswer {
  id: string;
  tenantId: string;
  assessmentId: string;
  templateFieldId: string | null;
  fieldKey: string;
  fieldLabel: string;
  fieldType: AssessmentFieldType;
  /** Immutable snapshot of options/scales/config at answer time. */
  fieldConfig: AssessmentFieldConfig;
  value: unknown;
}
