"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { hasJobPermission, type JobPermission } from "@/lib/jobs/permissions";
import {
  isEmploymentType,
  isJobStatus,
  type JobStatus,
} from "@/lib/jobs/types";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";
import { createClient } from "@/lib/supabase/server";

export type JobActionState = {
  error?: string;
  success?: string;
};

function getString(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

async function requireJobPermission(permission: JobPermission) {
  const context = await requireTenantContext();
  if (!hasJobPermission(context.membership.role, permission)) {
    redirect("/jobs");
  }
  return context;
}

function parseOpenings(raw: string) {
  const value = Number(raw || "1");
  if (!Number.isInteger(value) || value < 1) {
    return null;
  }
  return value;
}

function revalidateJobPaths(jobId?: string) {
  revalidatePath("/jobs");
  if (jobId) {
    revalidatePath(`/jobs/${jobId}`);
  }
}

export async function createJob(
  _prev: JobActionState,
  formData: FormData,
): Promise<JobActionState> {
  const context = await requireJobPermission("jobs.write");
  const tenantId = context.membership.tenantId;

  const title = getString(formData, "title");
  const department = getString(formData, "department");
  const location = getString(formData, "location");
  const employmentType = getString(formData, "employmentType");
  const description = getString(formData, "description");
  const openings = parseOpenings(getString(formData, "openings"));
  const requestingDepartment = getString(formData, "requestingDepartment");
  const requestedByName = getString(formData, "requestedByName");
  const requestedAt = getString(formData, "requestedAt");
  const hiringManagerName = getString(formData, "hiringManagerName");
  const hiringManagerEmail = getString(formData, "hiringManagerEmail");
  const pipelineTemplateId = getString(formData, "pipelineTemplateId");

  if (!title) {
    return { error: "Job title is required." };
  }
  if (!pipelineTemplateId) {
    return { error: "Select a pipeline template." };
  }
  if (openings === null) {
    return { error: "Openings must be a whole number of at least 1." };
  }
  if (employmentType && !isEmploymentType(employmentType)) {
    return { error: "Invalid employment type." };
  }

  const supabase = await createClient();
  const { data: job, error } = await supabase
    .from("jobs")
    .insert({
      tenant_id: tenantId,
      title,
      department: department || null,
      location: location || null,
      employment_type: employmentType || null,
      description: description || null,
      status: "draft",
      openings,
      requesting_department: requestingDepartment || null,
      requested_by_name: requestedByName || null,
      requested_at: requestedAt ? new Date(requestedAt).toISOString() : null,
      hiring_manager_name: hiringManagerName || null,
      hiring_manager_email: hiringManagerEmail || null,
      pipeline_template_id: pipelineTemplateId,
      apply_enabled: false,
      created_by: context.userId,
    })
    .select("id")
    .single();

  if (error || !job) {
    return { error: error?.message ?? "Failed to create job." };
  }

  const { error: syncError } = await supabase.rpc(
    "sync_job_stages_from_template",
    {
      p_tenant_id: tenantId,
      p_job_id: job.id,
      p_template_id: pipelineTemplateId,
    },
  );

  if (syncError) {
    await supabase
      .from("jobs")
      .delete()
      .eq("id", job.id)
      .eq("tenant_id", tenantId);
    return { error: syncError.message };
  }

  revalidateJobPaths(job.id);
  redirect(`/jobs/${job.id}`);
}

export async function updateJob(
  _prev: JobActionState,
  formData: FormData,
): Promise<JobActionState> {
  const context = await requireJobPermission("jobs.write");
  const tenantId = context.membership.tenantId;
  const jobId = getString(formData, "jobId");

  const title = getString(formData, "title");
  const department = getString(formData, "department");
  const location = getString(formData, "location");
  const employmentType = getString(formData, "employmentType");
  const description = getString(formData, "description");
  const openings = parseOpenings(getString(formData, "openings"));
  const requestingDepartment = getString(formData, "requestingDepartment");
  const requestedByName = getString(formData, "requestedByName");
  const requestedAt = getString(formData, "requestedAt");
  const hiringManagerName = getString(formData, "hiringManagerName");
  const hiringManagerEmail = getString(formData, "hiringManagerEmail");
  const pipelineTemplateId = getString(formData, "pipelineTemplateId");

  if (!jobId) {
    return { error: "Job id is required." };
  }
  if (!title) {
    return { error: "Job title is required." };
  }
  if (!pipelineTemplateId) {
    return { error: "Select a pipeline template." };
  }
  if (openings === null) {
    return { error: "Openings must be a whole number of at least 1." };
  }
  if (employmentType && !isEmploymentType(employmentType)) {
    return { error: "Invalid employment type." };
  }

  const supabase = await createClient();
  const { data: existing, error: existingError } = await supabase
    .from("jobs")
    .select("id, status, archived_at, pipeline_template_id")
    .eq("id", jobId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (existingError || !existing) {
    return { error: existingError?.message ?? "Job not found." };
  }
  if (existing.archived_at) {
    return { error: "Archived jobs cannot be edited." };
  }

  const templateChanged = existing.pipeline_template_id !== pipelineTemplateId;
  if (templateChanged && existing.status !== "draft") {
    return {
      error: "Pipeline template can only be changed while the job is in draft.",
    };
  }

  const { error: updateError } = await supabase
    .from("jobs")
    .update({
      title,
      department: department || null,
      location: location || null,
      employment_type: employmentType || null,
      description: description || null,
      openings,
      requesting_department: requestingDepartment || null,
      requested_by_name: requestedByName || null,
      requested_at: requestedAt ? new Date(requestedAt).toISOString() : null,
      hiring_manager_name: hiringManagerName || null,
      hiring_manager_email: hiringManagerEmail || null,
      pipeline_template_id: pipelineTemplateId,
    })
    .eq("id", jobId)
    .eq("tenant_id", tenantId);

  if (updateError) {
    return { error: updateError.message };
  }

  if (templateChanged) {
    const { error: syncError } = await supabase.rpc(
      "sync_job_stages_from_template",
      {
        p_tenant_id: tenantId,
        p_job_id: jobId,
        p_template_id: pipelineTemplateId,
      },
    );
    if (syncError) {
      return { error: syncError.message };
    }
  }

  revalidateJobPaths(jobId);
  return { success: "Job saved." };
}

export async function publishJob(formData: FormData) {
  const context = await requireJobPermission("jobs.write");
  const jobId = getString(formData, "jobId");
  if (!jobId) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("publish_job", {
    p_tenant_id: context.membership.tenantId,
    p_job_id: jobId,
  });

  if (error) {
    throw new Error(error.message);
  }

  revalidateJobPaths(jobId);
}

async function setJobStatus(jobId: string, status: JobStatus) {
  const context = await requireJobPermission("jobs.write");
  const tenantId = context.membership.tenantId;
  const supabase = await createClient();

  const patch: Record<string, unknown> = {
    status,
    updated_at: new Date().toISOString(),
  };

  if (status === "open") {
    patch.apply_enabled = true;
  } else if (
    status === "on_hold" ||
    status === "closed" ||
    status === "filled"
  ) {
    patch.apply_enabled = false;
  }

  const { error } = await supabase
    .from("jobs")
    .update(patch)
    .eq("id", jobId)
    .eq("tenant_id", tenantId)
    .is("archived_at", null);

  if (error) {
    throw new Error(error.message);
  }

  await supabase.from("audit_events").insert({
    tenant_id: tenantId,
    actor_user_id: context.userId,
    action: `job.status.${status}`,
    entity_type: "job",
    entity_id: jobId,
  });

  revalidateJobPaths(jobId);
}

export async function holdJob(formData: FormData) {
  const jobId = getString(formData, "jobId");
  if (jobId) {
    await setJobStatus(jobId, "on_hold");
  }
}

export async function reopenJob(formData: FormData) {
  const jobId = getString(formData, "jobId");
  if (!jobId) {
    return;
  }
  // Re-open uses publish rules (token + description checks).
  const context = await requireJobPermission("jobs.write");
  const supabase = await createClient();
  const { error } = await supabase.rpc("publish_job", {
    p_tenant_id: context.membership.tenantId,
    p_job_id: jobId,
  });
  if (error) {
    throw new Error(error.message);
  }
  revalidateJobPaths(jobId);
}

export async function closeJob(formData: FormData) {
  const jobId = getString(formData, "jobId");
  if (jobId) {
    await setJobStatus(jobId, "closed");
  }
}

export async function fillJob(formData: FormData) {
  const jobId = getString(formData, "jobId");
  if (jobId) {
    await setJobStatus(jobId, "filled");
  }
}

export async function archiveJob(formData: FormData) {
  const context = await requireJobPermission("jobs.write");
  const jobId = getString(formData, "jobId");
  if (!jobId) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("jobs")
    .update({
      archived_at: new Date().toISOString(),
      apply_enabled: false,
      status: "closed",
    })
    .eq("id", jobId)
    .eq("tenant_id", context.membership.tenantId);

  if (error) {
    throw new Error(error.message);
  }

  revalidateJobPaths(jobId);
}

export async function restoreJob(formData: FormData) {
  const context = await requireJobPermission("jobs.write");
  const jobId = getString(formData, "jobId");
  if (!jobId) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("jobs")
    .update({
      archived_at: null,
      status: "draft",
      apply_enabled: false,
    })
    .eq("id", jobId)
    .eq("tenant_id", context.membership.tenantId);

  if (error) {
    throw new Error(error.message);
  }

  revalidateJobPaths(jobId);
}

export async function deleteJob(formData: FormData) {
  const context = await requireJobPermission("jobs.delete");
  const jobId = getString(formData, "jobId");
  if (!jobId) {
    return;
  }

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("jobs")
    .select("status")
    .eq("id", jobId)
    .eq("tenant_id", context.membership.tenantId)
    .maybeSingle();

  if (existing && isJobStatus(existing.status) && existing.status !== "draft") {
    throw new Error("Only draft jobs can be deleted. Archive instead.");
  }

  const { error } = await supabase
    .from("jobs")
    .delete()
    .eq("id", jobId)
    .eq("tenant_id", context.membership.tenantId);

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/jobs");
  redirect("/jobs");
}
