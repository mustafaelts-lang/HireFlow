import type { Metadata } from "next";
import Link from "next/link";

import { JobList } from "@/components/jobs/job-list";
import { hasJobPermission } from "@/lib/jobs/permissions";
import { listJobs } from "@/lib/jobs/queries";
import { JOB_STATUSES, JOB_STATUS_LABELS, isJobStatus } from "@/lib/jobs/types";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

export const metadata: Metadata = {
  title: "Jobs",
};

type JobsPageProps = {
  searchParams: Promise<{ archived?: string; status?: string }>;
};

export default async function JobsPage({ searchParams }: JobsPageProps) {
  const params = await searchParams;
  const showArchived = params.archived === "1";
  const statusFilter =
    params.status && isJobStatus(params.status) ? params.status : undefined;

  const context = await requireTenantContext();
  const role = context.membership.role;
  const canWrite = hasJobPermission(role, "jobs.write");

  if (!hasJobPermission(role, "jobs.read")) {
    return (
      <section className="app-panel">
        <h1>Jobs</h1>
        <p className="muted">You do not have access to jobs.</p>
      </section>
    );
  }

  const jobs = await listJobs(context.membership.tenantId, {
    includeArchived: showArchived,
    status: showArchived ? undefined : statusFilter,
  });

  const visible = showArchived
    ? jobs.filter((job) => job.archivedAt)
    : jobs.filter((job) => !job.archivedAt);

  return (
    <div className="stack-lg">
      <section className="app-panel">
        <div className="panel-header-row">
          <div>
            <h1>Jobs</h1>
            <p className="muted">
              Create requisitions, attach a pipeline template, and publish a
              public apply link.
            </p>
          </div>
          <div className="row-actions">
            <Link
              href={showArchived ? "/jobs" : "/jobs?archived=1"}
              className="text-button"
            >
              {showArchived ? "Show active" : "Show archived"}
            </Link>
            {canWrite ? (
              <Link href="/jobs/new" className="auth-button inline-link-button">
                Create job
              </Link>
            ) : null}
          </div>
        </div>

        {!showArchived ? (
          <div className="filter-row">
            <Link
              href="/jobs"
              className={!statusFilter ? "filter-chip active" : "filter-chip"}
            >
              All
            </Link>
            {JOB_STATUSES.map((status) => (
              <Link
                key={status}
                href={`/jobs?status=${status}`}
                className={
                  statusFilter === status ? "filter-chip active" : "filter-chip"
                }
              >
                {JOB_STATUS_LABELS[status]}
              </Link>
            ))}
          </div>
        ) : null}
      </section>

      <JobList jobs={visible} canWrite={canWrite} showArchived={showArchived} />
    </div>
  );
}
