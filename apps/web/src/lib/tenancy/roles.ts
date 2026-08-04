export const TENANT_ROLES = [
  "tenant_owner",
  "company_admin",
  "recruiter",
  "hiring_manager",
] as const;

export type TenantRole = (typeof TENANT_ROLES)[number];

export const INVITABLE_ROLES = [
  "company_admin",
  "recruiter",
  "hiring_manager",
] as const;

export type InvitableRole = (typeof INVITABLE_ROLES)[number];

export const ROLE_LABELS: Record<TenantRole, string> = {
  tenant_owner: "Owner",
  company_admin: "Admin",
  recruiter: "Recruiter",
  hiring_manager: "Hiring Manager",
};

export const ACTIVE_TENANT_COOKIE = "hf_tenant_id";
