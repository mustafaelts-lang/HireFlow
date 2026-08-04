import type { Metadata } from "next";

import { OrganizationSettingsForm } from "@/components/organization/organization-settings-form";
import { hasPermission } from "@/lib/tenancy/permissions";
import { requireTenantPermission } from "@/lib/tenancy/require-tenant";

export const metadata: Metadata = {
  title: "Organization settings",
};

export default async function OrganizationSettingsPage() {
  const context = await requireTenantPermission("tenant.settings.read");
  const canEdit = hasPermission(
    context.membership.role,
    "tenant.settings.write",
  );
  const { tenant } = context.membership;

  return (
    <section className="app-panel">
      <h1>Organization settings</h1>
      <p className="muted">
        Manage company profile for <strong>{tenant.name}</strong>. Every record
        in HireFlow is scoped to this organization.
      </p>
      <OrganizationSettingsForm
        name={tenant.name}
        slug={tenant.slug}
        timezone={tenant.timezone}
        locale={tenant.locale}
        canEdit={canEdit}
      />
    </section>
  );
}
