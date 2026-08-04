import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { TemplateForm } from "@/components/pipelines/template-form";
import { hasPipelinePermission } from "@/lib/pipelines/permissions";
import { getPipelineTemplate } from "@/lib/pipelines/queries";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

type EditPipelinePageProps = {
  params: Promise<{ templateId: string }>;
};

export async function generateMetadata({
  params,
}: EditPipelinePageProps): Promise<Metadata> {
  const { templateId } = await params;
  return { title: `Pipeline template ${templateId.slice(0, 8)}` };
}

export default async function EditPipelineTemplatePage({
  params,
}: EditPipelinePageProps) {
  const { templateId } = await params;
  const context = await requireTenantContext();
  const role = context.membership.role;

  if (!hasPipelinePermission(role, "pipelines.read")) {
    redirect("/dashboard");
  }

  const detail = await getPipelineTemplate(
    context.membership.tenantId,
    templateId,
  );
  if (!detail) {
    notFound();
  }

  const canWrite =
    hasPipelinePermission(role, "pipelines.write") &&
    !detail.template.archivedAt;

  return (
    <TemplateForm
      mode="edit"
      templateId={detail.template.id}
      initialName={detail.template.name}
      initialDescription={detail.template.description ?? ""}
      initialIsDefault={detail.template.isDefault}
      initialStages={detail.stages}
      readOnly={!canWrite}
    />
  );
}
