import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { JobDetailActions } from "@/components/jobs/job-detail";
import { hasJobPermission } from "@/lib/jobs/permissions";
import { getJob } from "@/lib/jobs/queries";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

type JobDetailPageProps = {
  params: Promise<{ jobId: string }>;
};

function getSiteOrigin() {
  return (
    process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") ??
    "http://localhost:3000"
  );
}

export async function generateMetadata({
  params,
}: JobDetailPageProps): Promise<Metadata> {
  const { jobId } = await params;
  return { title: `Job ${jobId.slice(0, 8)}` };
}

export default async function JobDetailPage({ params }: JobDetailPageProps) {
  const { jobId } = await params;
  const context = await requireTenantContext();
  const role = context.membership.role;

  if (!hasJobPermission(role, "jobs.read")) {
    redirect("/dashboard");
  }

  const detail = await getJob(context.membership.tenantId, jobId);
  if (!detail) {
    notFound();
  }

  return (
    <JobDetailActions
      job={detail.job}
      stages={detail.stages}
      canWrite={hasJobPermission(role, "jobs.write")}
      canDelete={hasJobPermission(role, "jobs.delete")}
      siteOrigin={getSiteOrigin()}
    />
  );
}
