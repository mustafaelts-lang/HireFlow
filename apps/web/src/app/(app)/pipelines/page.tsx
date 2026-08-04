import type { Metadata } from "next";
import Link from "next/link";

import { TemplateList } from "@/components/pipelines/template-list";
import { hasPipelinePermission } from "@/lib/pipelines/permissions";
import { listPipelineTemplates } from "@/lib/pipelines/queries";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

export const metadata: Metadata = {
  title: "Pipeline templates",
};

type PipelinesPageProps = {
  searchParams: Promise<{ archived?: string }>;
};

export default async function PipelinesPage({
  searchParams,
}: PipelinesPageProps) {
  const params = await searchParams;
  const showArchived = params.archived === "1";
  const context = await requireTenantContext();
  const role = context.membership.role;
  const canWrite = hasPipelinePermission(role, "pipelines.write");
  const canDelete = hasPipelinePermission(role, "pipelines.delete");

  if (!hasPipelinePermission(role, "pipelines.read")) {
    return (
      <section className="app-panel">
        <h1>Pipeline templates</h1>
        <p className="muted">You do not have access to pipeline templates.</p>
      </section>
    );
  }

  const templates = await listPipelineTemplates(context.membership.tenantId, {
    includeArchived: showArchived,
  });

  const visible = showArchived
    ? templates.filter((item) => item.archivedAt)
    : templates.filter((item) => !item.archivedAt);

  return (
    <div className="stack-lg">
      <section className="app-panel">
        <div className="panel-header-row">
          <div>
            <h1>Pipeline templates</h1>
            <p className="muted">
              Define reusable hiring pipelines for your organization. Jobs will
              attach to these templates later.
            </p>
          </div>
          <div className="row-actions">
            <Link
              href={showArchived ? "/pipelines" : "/pipelines?archived=1"}
              className="text-button"
            >
              {showArchived ? "Show active" : "Show archived"}
            </Link>
            {canWrite ? (
              <Link
                href="/pipelines/new"
                className="auth-button inline-link-button"
              >
                Create template
              </Link>
            ) : null}
          </div>
        </div>
      </section>

      <TemplateList
        templates={visible}
        canWrite={canWrite}
        canDelete={canDelete}
        showArchived={showArchived}
      />
    </div>
  );
}
