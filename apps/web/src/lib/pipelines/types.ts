export const STAGE_CATEGORIES = [
  "intake",
  "screening",
  "interview",
  "reference",
  "offer",
  "pre_hire",
  "hired",
  "closed",
  "custom",
] as const;

export type StageCategory = (typeof STAGE_CATEGORIES)[number];

export const STAGE_CATEGORY_LABELS: Record<StageCategory, string> = {
  intake: "Intake",
  screening: "Screening",
  interview: "Interview",
  reference: "Reference",
  offer: "Offer",
  pre_hire: "Pre-hire",
  hired: "Hired",
  closed: "Closed",
  custom: "Custom",
};

export const STAGE_COLOR_PRESETS = [
  "#64748B",
  "#0EA5E9",
  "#06B6D4",
  "#8B5CF6",
  "#F59E0B",
  "#10B981",
  "#14B8A6",
  "#0F6B4C",
  "#DC2626",
  "#78716C",
] as const;

export type PipelineTemplateStageInput = {
  id?: string;
  key: string;
  name: string;
  sortOrder: number;
  color: string;
  slaDays: number | null;
  category: StageCategory;
  notes: string;
};

export type PipelineTemplateStage = PipelineTemplateStageInput & {
  id: string;
};

export type PipelineTemplate = {
  id: string;
  tenantId: string;
  name: string;
  description: string | null;
  isDefault: boolean;
  archivedAt: string | null;
  createdAt: string;
  updatedAt: string;
  stageCount?: number;
};

export function slugifyStageKey(name: string): string {
  return (
    name
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 48) || "stage"
  );
}

export function isHexColor(value: string): boolean {
  return /^#[0-9A-Fa-f]{6}$/.test(value);
}
