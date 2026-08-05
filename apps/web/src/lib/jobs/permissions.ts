import type { TenantRole } from "@/lib/tenancy/roles";

export type JobPermission = "jobs.read" | "jobs.write" | "jobs.delete";

const JOB_PERMISSIONS: Record<TenantRole, readonly JobPermission[]> = {
  tenant_owner: ["jobs.read", "jobs.write", "jobs.delete"],
  company_admin: ["jobs.read", "jobs.write", "jobs.delete"],
  recruiter: ["jobs.read", "jobs.write"],
  hiring_manager: ["jobs.read"],
};

export function hasJobPermission(
  role: TenantRole,
  permission: JobPermission,
): boolean {
  return JOB_PERMISSIONS[role].includes(permission);
}
