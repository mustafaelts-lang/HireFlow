import Link from "next/link";

import { hasPipelinePermission } from "@/lib/pipelines/permissions";
import { hasPermission } from "@/lib/tenancy/permissions";
import { ROLE_LABELS, type TenantRole } from "@/lib/tenancy/roles";

type AppNavProps = {
  organizationName: string;
  role: TenantRole;
};

export function AppNav({ organizationName, role }: AppNavProps) {
  const canReadSettings = hasPermission(role, "tenant.settings.read");
  const canReadUsers = hasPermission(role, "tenant.users.read");
  const canReadPipelines = hasPipelinePermission(role, "pipelines.read");

  return (
    <nav className="app-nav">
      <Link href="/dashboard">Dashboard</Link>
      {canReadPipelines ? <Link href="/pipelines">Pipelines</Link> : null}
      {canReadSettings ? (
        <Link href="/settings/organization">Organization</Link>
      ) : null}
      {canReadUsers ? <Link href="/settings/team">Team</Link> : null}
      <span className="app-nav-meta">
        {organizationName} · {ROLE_LABELS[role]}
      </span>
    </nav>
  );
}
