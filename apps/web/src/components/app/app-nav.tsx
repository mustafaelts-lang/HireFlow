import Link from "next/link";

import { ROLE_LABELS, type TenantRole } from "@/lib/tenancy/roles";
import { hasPermission } from "@/lib/tenancy/permissions";

type AppNavProps = {
  organizationName: string;
  role: TenantRole;
};

export function AppNav({ organizationName, role }: AppNavProps) {
  const canReadSettings = hasPermission(role, "tenant.settings.read");
  const canReadUsers = hasPermission(role, "tenant.users.read");

  return (
    <nav className="app-nav">
      <Link href="/dashboard">Dashboard</Link>
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
