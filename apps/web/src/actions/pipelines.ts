"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  hasPipelinePermission,
  type PipelinePermission,
} from "@/lib/pipelines/permissions";
import {
  isHexColor,
  slugifyStageKey,
  STAGE_CATEGORIES,
  type PipelineTemplateStageInput,
  type StageCategory,
} from "@/lib/pipelines/types";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";
import { createClient } from "@/lib/supabase/server";

export type PipelineActionState = {
  error?: string;
  success?: string;
};

function getString(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

async function requirePipelinePermission(permission: PipelinePermission) {
  const context = await requireTenantContext();
  if (!hasPipelinePermission(context.membership.role, permission)) {
    redirect("/pipelines");
  }
  return context;
}

function isStageCategory(value: string): value is StageCategory {
  return (STAGE_CATEGORIES as readonly string[]).includes(value);
}

function parseStagesJson(raw: string): PipelineTemplateStageInput[] {
  const parsed = JSON.parse(raw) as PipelineTemplateStageInput[];
  if (!Array.isArray(parsed)) {
    throw new Error("Invalid stages payload.");
  }
  return parsed;
}

function validateStages(stages: PipelineTemplateStageInput[]): string | null {
  if (stages.length < 1) {
    return "At least one stage is required.";
  }

  const keys = new Set<string>();
  const orders = new Set<number>();

  for (const [index, stage] of stages.entries()) {
    if (!stage.name?.trim()) {
      return `Stage ${index + 1} needs a name.`;
    }
    const key = (stage.key || slugifyStageKey(stage.name)).trim();
    if (!key) {
      return `Stage ${index + 1} needs a key.`;
    }
    if (keys.has(key)) {
      return `Duplicate stage key: ${key}`;
    }
    keys.add(key);

    if (!isStageCategory(stage.category)) {
      return `Stage ${stage.name} has an invalid category.`;
    }
    if (!isHexColor(stage.color)) {
      return `Stage ${stage.name} needs a valid hex color.`;
    }
    if (
      stage.slaDays !== null &&
      stage.slaDays !== undefined &&
      (Number.isNaN(stage.slaDays) || stage.slaDays < 0)
    ) {
      return `Stage ${stage.name} has an invalid SLA.`;
    }
    if (orders.has(stage.sortOrder)) {
      return "Stage order must be unique.";
    }
    orders.add(stage.sortOrder);
  }

  return null;
}

function normalizeStages(
  stages: PipelineTemplateStageInput[],
): PipelineTemplateStageInput[] {
  return stages
    .map((stage, index) => ({
      ...stage,
      name: stage.name.trim(),
      key: (stage.key || slugifyStageKey(stage.name)).trim(),
      sortOrder: index + 1,
      notes: stage.notes?.trim() ?? "",
      slaDays:
        stage.slaDays === null ||
        stage.slaDays === undefined ||
        Number.isNaN(Number(stage.slaDays))
          ? null
          : Number(stage.slaDays),
    }))
    .sort((a, b) => a.sortOrder - b.sortOrder);
}

export async function createPipelineTemplate(
  _prev: PipelineActionState,
  formData: FormData,
): Promise<PipelineActionState> {
  const context = await requirePipelinePermission("pipelines.write");
  const name = getString(formData, "name");
  const description = getString(formData, "description");
  const makeDefault = getString(formData, "isDefault") === "on";
  const stagesRaw = getString(formData, "stages");

  if (!name) {
    return { error: "Template name is required." };
  }

  let stages: PipelineTemplateStageInput[];
  try {
    stages = normalizeStages(parseStagesJson(stagesRaw));
  } catch {
    return { error: "Could not read stages." };
  }

  const validationError = validateStages(stages);
  if (validationError) {
    return { error: validationError };
  }

  const supabase = await createClient();
  const tenantId = context.membership.tenantId;

  const { data: template, error } = await supabase
    .from("pipeline_templates")
    .insert({
      tenant_id: tenantId,
      name,
      description: description || null,
      is_default: false,
      created_by: context.userId,
    })
    .select("id")
    .single();

  if (error || !template) {
    return { error: error?.message ?? "Failed to create template." };
  }

  const { error: stagesError } = await supabase
    .from("pipeline_template_stages")
    .insert(
      stages.map((stage) => ({
        tenant_id: tenantId,
        template_id: template.id,
        key: stage.key,
        name: stage.name,
        sort_order: stage.sortOrder,
        color: stage.color,
        sla_days: stage.slaDays,
        category: stage.category,
        notes: stage.notes || null,
      })),
    );

  if (stagesError) {
    await supabase
      .from("pipeline_templates")
      .delete()
      .eq("id", template.id)
      .eq("tenant_id", tenantId);
    return { error: stagesError.message };
  }

  if (makeDefault) {
    const { error: defaultError } = await supabase.rpc(
      "set_default_pipeline_template",
      {
        p_tenant_id: tenantId,
        p_template_id: template.id,
      },
    );
    if (defaultError) {
      return { error: defaultError.message };
    }
  }

  revalidatePath("/pipelines");
  redirect(`/pipelines/${template.id}`);
}

export async function updatePipelineTemplate(
  _prev: PipelineActionState,
  formData: FormData,
): Promise<PipelineActionState> {
  const context = await requirePipelinePermission("pipelines.write");
  const templateId = getString(formData, "templateId");
  const name = getString(formData, "name");
  const description = getString(formData, "description");
  const makeDefault = getString(formData, "isDefault") === "on";
  const stagesRaw = getString(formData, "stages");
  const tenantId = context.membership.tenantId;

  if (!templateId) {
    return { error: "Template id is required." };
  }
  if (!name) {
    return { error: "Template name is required." };
  }

  let stages: PipelineTemplateStageInput[];
  try {
    stages = normalizeStages(parseStagesJson(stagesRaw));
  } catch {
    return { error: "Could not read stages." };
  }

  const validationError = validateStages(stages);
  if (validationError) {
    return { error: validationError };
  }

  const supabase = await createClient();

  const { data: existing, error: existingError } = await supabase
    .from("pipeline_templates")
    .select("id, is_default, archived_at")
    .eq("id", templateId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (existingError || !existing) {
    return { error: existingError?.message ?? "Template not found." };
  }
  if (existing.archived_at) {
    return { error: "Archived templates cannot be edited. Restore first." };
  }

  const { error: updateError } = await supabase
    .from("pipeline_templates")
    .update({
      name,
      description: description || null,
    })
    .eq("id", templateId)
    .eq("tenant_id", tenantId);

  if (updateError) {
    return { error: updateError.message };
  }

  const { error: deleteStagesError } = await supabase
    .from("pipeline_template_stages")
    .delete()
    .eq("template_id", templateId)
    .eq("tenant_id", tenantId);

  if (deleteStagesError) {
    return { error: deleteStagesError.message };
  }

  const { error: insertStagesError } = await supabase
    .from("pipeline_template_stages")
    .insert(
      stages.map((stage) => ({
        tenant_id: tenantId,
        template_id: templateId,
        key: stage.key,
        name: stage.name,
        sort_order: stage.sortOrder,
        color: stage.color,
        sla_days: stage.slaDays,
        category: stage.category,
        notes: stage.notes || null,
      })),
    );

  if (insertStagesError) {
    return { error: insertStagesError.message };
  }

  if (makeDefault && !existing.is_default) {
    const { error: defaultError } = await supabase.rpc(
      "set_default_pipeline_template",
      {
        p_tenant_id: tenantId,
        p_template_id: templateId,
      },
    );
    if (defaultError) {
      return { error: defaultError.message };
    }
  }

  if (!makeDefault && existing.is_default) {
    return {
      error:
        "This is the default template. Set another template as default before unchecking.",
    };
  }

  revalidatePath("/pipelines");
  revalidatePath(`/pipelines/${templateId}`);
  return { success: "Template saved." };
}

export async function duplicatePipelineTemplate(formData: FormData) {
  const context = await requirePipelinePermission("pipelines.write");
  const templateId = getString(formData, "templateId");
  if (!templateId) {
    return;
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("duplicate_pipeline_template", {
    p_tenant_id: context.membership.tenantId,
    p_template_id: templateId,
    p_name: null,
  });

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/pipelines");
  redirect(`/pipelines/${data}`);
}

export async function archivePipelineTemplate(formData: FormData) {
  const context = await requirePipelinePermission("pipelines.write");
  const templateId = getString(formData, "templateId");
  const tenantId = context.membership.tenantId;
  if (!templateId) {
    return;
  }

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("pipeline_templates")
    .select("is_default")
    .eq("id", templateId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (existing?.is_default) {
    throw new Error("Cannot archive the default template.");
  }

  const { error } = await supabase
    .from("pipeline_templates")
    .update({ archived_at: new Date().toISOString(), is_default: false })
    .eq("id", templateId)
    .eq("tenant_id", tenantId);

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/pipelines");
}

export async function restorePipelineTemplate(formData: FormData) {
  const context = await requirePipelinePermission("pipelines.write");
  const templateId = getString(formData, "templateId");
  if (!templateId) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("pipeline_templates")
    .update({ archived_at: null })
    .eq("id", templateId)
    .eq("tenant_id", context.membership.tenantId);

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/pipelines");
}

export async function setDefaultPipelineTemplate(formData: FormData) {
  const context = await requirePipelinePermission("pipelines.write");
  const templateId = getString(formData, "templateId");
  if (!templateId) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_default_pipeline_template", {
    p_tenant_id: context.membership.tenantId,
    p_template_id: templateId,
  });

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/pipelines");
  revalidatePath(`/pipelines/${templateId}`);
}

export async function deletePipelineTemplate(formData: FormData) {
  const context = await requirePipelinePermission("pipelines.delete");
  const templateId = getString(formData, "templateId");
  if (!templateId) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("delete_pipeline_template", {
    p_tenant_id: context.membership.tenantId,
    p_template_id: templateId,
  });

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/pipelines");
  redirect("/pipelines");
}
