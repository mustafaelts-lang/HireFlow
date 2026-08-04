import type { Metadata } from "next";

import { requireTenantContext } from "@/lib/tenancy/require-tenant";
import { ROLE_LABELS } from "@/lib/tenancy/roles";

export const metadata: Metadata = {
  title: "Dashboard",
};

export default async function DashboardPage() {
  const context = await requireTenantContext();
  const { tenant, role } = context.membership;

  return (
    <section className="app-panel">
      <h1>Welcome to {tenant.name}</h1>
      <p>
        Signed in as <strong>{context.email}</strong> with role{" "}
        <strong>{ROLE_LABELS[role]}</strong>. Jobs and candidates arrive in
        later sprints — this workspace confirms multi-tenant isolation.
      </p>
    </section>
  );
}
