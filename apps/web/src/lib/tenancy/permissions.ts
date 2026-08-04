import type { TenantRole } from "@/lib/tenancy/roles";

export type TenantPermission =
  | "tenant.settings.read"
  | "tenant.settings.write"
  | "tenant.users.read"
  | "tenant.users.manage";

const ROLE_PERMISSIONS: Record<TenantRole, readonly TenantPermission[]> = {
  tenant_owner: [
    "tenant.settings.read",
    "tenant.settings.write",
    "tenant.users.read",
    "tenant.users.manage",
  ],
  company_admin: [
    "tenant.settings.read",
    "tenant.settings.write",
    "tenant.users.read",
    "tenant.users.manage",
  ],
  recruiter: ["tenant.settings.read", "tenant.users.read"],
  hiring_manager: [],
};

export function hasPermission(
  role: TenantRole,
  permission: TenantPermission,
): boolean {
  return ROLE_PERMISSIONS[role].includes(permission);
}
