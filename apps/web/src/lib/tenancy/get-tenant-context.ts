import { createClient } from "@/lib/supabase/server";
import { unwrapRelation } from "@/lib/supabase/relations";
import { getActiveTenantIdFromCookie } from "@/lib/tenancy/cookie";
import type { TenantRole } from "@/lib/tenancy/roles";
import { TENANT_ROLES } from "@/lib/tenancy/roles";

export type TenantMembership = {
  id: string;
  tenantId: string;
  role: TenantRole;
  status: "active" | "invited" | "revoked";
  tenant: {
    id: string;
    name: string;
    slug: string;
    timezone: string;
    locale: string;
    status: string;
  };
};

export type TenantContext = {
  userId: string;
  email: string;
  membership: TenantMembership;
  memberships: TenantMembership[];
};

function isTenantRole(value: string): value is TenantRole {
  return (TENANT_ROLES as readonly string[]).includes(value);
}

type TenantRow = {
  id: string;
  name: string;
  slug: string;
  timezone: string;
  locale: string;
  status: string;
};

type MembershipRow = {
  id: string;
  tenant_id: string;
  role: string;
  status: string;
  tenants: TenantRow | TenantRow[] | null;
};

function mapMembership(row: MembershipRow): TenantMembership | null {
  const tenant = unwrapRelation(row.tenants);
  if (!tenant || !isTenantRole(row.role)) {
    return null;
  }

  if (
    row.status !== "active" &&
    row.status !== "invited" &&
    row.status !== "revoked"
  ) {
    return null;
  }

  return {
    id: row.id,
    tenantId: row.tenant_id,
    role: row.role,
    status: row.status,
    tenant: {
      id: tenant.id,
      name: tenant.name,
      slug: tenant.slug,
      timezone: tenant.timezone,
      locale: tenant.locale,
      status: tenant.status,
    },
  };
}

export async function listActiveMemberships(
  userId: string,
): Promise<TenantMembership[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tenant_memberships")
    .select(
      "id, tenant_id, role, status, tenants ( id, name, slug, timezone, locale, status )",
    )
    .eq("user_id", userId)
    .eq("status", "active");

  if (error) {
    throw new Error(error.message);
  }

  return ((data ?? []) as MembershipRow[])
    .map(mapMembership)
    .filter((item): item is TenantMembership => item !== null);
}

export async function resolveTenantContext(): Promise<TenantContext | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return null;
  }

  const memberships = await listActiveMemberships(user.id);
  if (memberships.length === 0) {
    return null;
  }

  const cookieTenantId = await getActiveTenantIdFromCookie();
  const active =
    memberships.find((item) => item.tenantId === cookieTenantId) ??
    memberships[0];

  return {
    userId: user.id,
    email: user.email ?? "",
    membership: active,
    memberships,
  };
}
