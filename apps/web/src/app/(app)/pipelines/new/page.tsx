import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { TemplateForm } from "@/components/pipelines/template-form";
import { hasPipelinePermission } from "@/lib/pipelines/permissions";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

export const metadata: Metadata = {
  title: "Create pipeline template",
};

export default async function NewPipelineTemplatePage() {
  const context = await requireTenantContext();
  if (!hasPipelinePermission(context.membership.role, "pipelines.write")) {
    redirect("/pipelines");
  }

  return <TemplateForm mode="create" />;
}
