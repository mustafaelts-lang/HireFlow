import { createClient } from "@/lib/supabase/server";
import { unwrapRelation } from "@/lib/supabase/relations";
import {
  isEmploymentType,
  isJobStatus,
  type JobRecord,
  type JobStage,
} from "@/lib/jobs/types";

type JobRow = {
  id: string;
  tenant_id: string;
  title: string;
  department: string | null;
  location: string | null;
  employment_type: string | null;
  description: string | null;
  status: string;
  openings: number;
  requesting_department: string | null;
  requested_by_name: string | null;
  requested_at: string | null;
  hiring_manager_name: string | null;
  hiring_manager_email: string | null;
  published_at: string | null;
  public_apply_token: string | null;
  apply_enabled: boolean;
  pipeline_template_id: string | null;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
  pipeline_templates?: { name: string } | { name: string }[] | null;
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

function mapJob(row: JobRow): JobRecord | null {
  if (!isJobStatus(row.status)) {
    return null;
  }

  const employmentType =
    row.employment_type && isEmploymentType(row.employment_type)
      ? row.employment_type
      : null;

  const template = unwrapRelation(row.pipeline_templates ?? null);

  return {
    id: row.id,
    tenantId: row.tenant_id,
    title: row.title,
    department: row.department,
    location: row.location,
    employmentType,
    description: row.description,
    status: row.status,
    openings: row.openings,
    requestingDepartment: row.requesting_department,
    requestedByName: row.requested_by_name,
    requestedAt: row.requested_at,
    hiringManagerName: row.hiring_manager_name,
    hiringManagerEmail: row.hiring_manager_email,
    publishedAt: row.published_at,
    publicApplyToken: row.public_apply_token,
    applyEnabled: row.apply_enabled,
    pipelineTemplateId: row.pipeline_template_id,
    pipelineTemplateName: template?.name ?? null,
    archivedAt: row.archived_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapStage(row: StageRow): JobStage {
  return {
    id: row.id,
    key: row.key,
    name: row.name,
    sortOrder: row.sort_order,
    color: row.color,
    slaDays: row.sla_days,
    category: row.category,
    notes: row.notes,
    isAppliedEntry: Boolean(row.is_applied_entry),
  };
}

export async function listJobs(
  tenantId: string,
  options?: { includeArchived?: boolean; status?: string },
): Promise<JobRecord[]> {
  const supabase = await createClient();
  let query = supabase
    .from("jobs")
    .select(
      "id, tenant_id, title, department, location, employment_type, description, status, openings, requesting_department, requested_by_name, requested_at, hiring_manager_name, hiring_manager_email, published_at, public_apply_token, apply_enabled, pipeline_template_id, archived_at, created_at, updated_at, pipeline_templates ( name )",
    )
    .eq("tenant_id", tenantId)
    .order("updated_at", { ascending: false });

  if (!options?.includeArchived) {
    query = query.is("archived_at", null);
  }

  if (options?.status) {
    query = query.eq("status", options.status);
  }

  const { data, error } = await query;
  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as JobRow[])
    .map(mapJob)
    .filter((item): item is JobRecord => item !== null);
}

export async function getJob(
  tenantId: string,
  jobId: string,
): Promise<{ job: JobRecord; stages: JobStage[] } | null> {
  const supabase = await createClient();
  const { data: jobRow, error: jobError } = await supabase
    .from("jobs")
    .select(
      "id, tenant_id, title, department, location, employment_type, description, status, openings, requesting_department, requested_by_name, requested_at, hiring_manager_name, hiring_manager_email, published_at, public_apply_token, apply_enabled, pipeline_template_id, archived_at, created_at, updated_at, pipeline_templates ( name )",
    )
    .eq("tenant_id", tenantId)
    .eq("id", jobId)
    .maybeSingle();

  if (jobError) {
    throw new Error(jobError.message);
  }
  if (!jobRow) {
    return null;
  }

  const job = mapJob(jobRow as JobRow);
  if (!job) {
    return null;
  }

  const { data: stageRows, error: stagesError } = await supabase
    .from("job_stages")
    .select(
      "id, key, name, sort_order, color, sla_days, category, notes, is_applied_entry",
    )
    .eq("tenant_id", tenantId)
    .eq("job_id", jobId)
    .order("sort_order", { ascending: true });

  if (stagesError) {
    throw new Error(stagesError.message);
  }

  return {
    job,
    stages: ((stageRows ?? []) as StageRow[]).map(mapStage),
  };
}

export async function listActivePipelineTemplatesForSelect(tenantId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("pipeline_templates")
    .select("id, name, is_default")
    .eq("tenant_id", tenantId)
    .is("archived_at", null)
    .order("is_default", { ascending: false })
    .order("name", { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return data ?? [];
}
