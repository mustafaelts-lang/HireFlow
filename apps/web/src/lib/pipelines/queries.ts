import { createClient } from "@/lib/supabase/server";
import { unwrapRelation } from "@/lib/supabase/relations";
import type {
  PipelineTemplate,
  PipelineTemplateStage,
  StageCategory,
} from "@/lib/pipelines/types";
import { STAGE_CATEGORIES } from "@/lib/pipelines/types";

function isStageCategory(value: string): value is StageCategory {
  return (STAGE_CATEGORIES as readonly string[]).includes(value);
}

type TemplateRow = {
  id: string;
  tenant_id: string;
  name: string;
  description: string | null;
  is_default: boolean;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
  pipeline_template_stages?: { count: number }[] | { count: number } | null;
};

type StageRow = {
  id: string;
  key: string;
  name: string;
  sort_order: number;
  color: string;
  sla_days: number | null;
  category: string;
  notes: string | null;
  is_applied_entry: boolean;
};

function mapTemplate(row: TemplateRow): PipelineTemplate {
  const countRel = unwrapRelation(row.pipeline_template_stages ?? null);
  return {
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    description: row.description,
    isDefault: row.is_default,
    archivedAt: row.archived_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    stageCount: countRel?.count,
  };
}

function mapStage(row: StageRow): PipelineTemplateStage | null {
  if (!isStageCategory(row.category)) {
    return null;
  }
  return {
    id: row.id,
    key: row.key,
    name: row.name,
    sortOrder: row.sort_order,
    color: row.color,
    slaDays: row.sla_days,
    category: row.category,
    notes: row.notes ?? "",
    isAppliedEntry: Boolean(row.is_applied_entry),
  };
}

export async function listPipelineTemplates(
  tenantId: string,
  options?: { includeArchived?: boolean },
): Promise<PipelineTemplate[]> {
  const supabase = await createClient();
  let query = supabase
    .from("pipeline_templates")
    .select(
      "id, tenant_id, name, description, is_default, archived_at, created_at, updated_at, pipeline_template_stages(count)",
    )
    .eq("tenant_id", tenantId)
    .order("is_default", { ascending: false })
    .order("updated_at", { ascending: false });

  if (!options?.includeArchived) {
    query = query.is("archived_at", null);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as TemplateRow[]).map(mapTemplate);
}

export async function getPipelineTemplate(
  tenantId: string,
  templateId: string,
): Promise<{
  template: PipelineTemplate;
  stages: PipelineTemplateStage[];
} | null> {
  const supabase = await createClient();
  const { data: templateRow, error: templateError } = await supabase
    .from("pipeline_templates")
    .select(
      "id, tenant_id, name, description, is_default, archived_at, created_at, updated_at",
    )
    .eq("tenant_id", tenantId)
    .eq("id", templateId)
    .maybeSingle();

  if (templateError) {
    throw new Error(templateError.message);
  }
  if (!templateRow) {
    return null;
  }

  const { data: stageRows, error: stagesError } = await supabase
    .from("pipeline_template_stages")
    .select(
      "id, key, name, sort_order, color, sla_days, category, notes, is_applied_entry",
    )
    .eq("tenant_id", tenantId)
    .eq("template_id", templateId)
    .order("sort_order", { ascending: true });

  if (stagesError) {
    throw new Error(stagesError.message);
  }

  return {
    template: mapTemplate(templateRow as TemplateRow),
    stages: ((stageRows ?? []) as StageRow[])
      .map(mapStage)
      .filter((item): item is PipelineTemplateStage => item !== null),
  };
}
