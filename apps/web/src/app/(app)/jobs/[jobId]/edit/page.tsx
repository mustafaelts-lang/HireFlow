import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { JobForm } from "@/components/jobs/job-form";
import { hasJobPermission } from "@/lib/jobs/permissions";
import {
  getJob,
  listActivePipelineTemplatesForSelect,
} from "@/lib/jobs/queries";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

type EditJobPageProps = {
  params: Promise<{ jobId: string }>;
};

export const metadata: Metadata = {
  title: "Edit job",
};

export default async function EditJobPage({ params }: EditJobPageProps) {
  const { jobId } = await params;
  const context = await requireTenantContext();
  const role = context.membership.role;

  if (!hasJobPermission(role, "jobs.write")) {
    redirect(`/jobs/${jobId}`);
  }

  const detail = await getJob(context.membership.tenantId, jobId);
  if (!detail) {
    notFound();
  }

  if (detail.job.archivedAt) {
    redirect(`/jobs/${jobId}`);
  }

  const templates = await listActivePipelineTemplatesForSelect(
    context.membership.tenantId,
  );

  return <JobForm mode="edit" templates={templates} job={detail.job} />;
}
