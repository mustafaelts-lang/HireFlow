import type { TenantRole } from "@/lib/tenancy/roles";
import {
  hasPermission as hasTenantPermission,
  type TenantPermission,
} from "@/lib/tenancy/permissions";

export type PipelinePermission =
  "pipelines.read" | "pipelines.write" | "pipelines.delete";

const PIPELINE_PERMISSIONS: Record<TenantRole, readonly PipelinePermission[]> =
  {
    tenant_owner: ["pipelines.read", "pipelines.write", "pipelines.delete"],
    company_admin: ["pipelines.read", "pipelines.write", "pipelines.delete"],
    recruiter: ["pipelines.read", "pipelines.write"],
    hiring_manager: ["pipelines.read"],
  };

export function hasPipelinePermission(
  role: TenantRole,
  permission: PipelinePermission,
): boolean {
  return PIPELINE_PERMISSIONS[role].includes(permission);
}

/** Bridge into shared permission helper surface for nav/pages. */
export type AppPermission = TenantPermission | PipelinePermission;

export function hasAppPermission(
  role: TenantRole,
  permission: AppPermission,
): boolean {
  if (
    permission === "pipelines.read" ||
    permission === "pipelines.write" ||
    permission === "pipelines.delete"
  ) {
    return hasPipelinePermission(role, permission);
  }
  return hasTenantPermission(role, permission);
}
