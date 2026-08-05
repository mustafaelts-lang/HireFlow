import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { JobForm } from "@/components/jobs/job-form";
import { hasJobPermission } from "@/lib/jobs/permissions";
import { listActivePipelineTemplatesForSelect } from "@/lib/jobs/queries";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

export const metadata: Metadata = {
  title: "Create job",
};

export default async function NewJobPage() {
  const context = await requireTenantContext();
  if (!hasJobPermission(context.membership.role, "jobs.write")) {
    redirect("/jobs");
  }

  const templates = await listActivePipelineTemplatesForSelect(
    context.membership.tenantId,
  );

  if (templates.length === 0) {
    return (
      <section className="app-panel">
        <h1>Create job</h1>
        <p className="muted">
          You need an active pipeline template before creating a job.
        </p>
        <Link href="/pipelines/new" className="auth-link">
          Create a pipeline template
        </Link>
      </section>
    );
  }

  return <JobForm mode="create" templates={templates} />;
}
