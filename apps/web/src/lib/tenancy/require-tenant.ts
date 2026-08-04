import { redirect } from "next/navigation";

import {
  resolveTenantContext,
  type TenantContext,
} from "@/lib/tenancy/get-tenant-context";
import {
  hasPermission,
  type TenantPermission,
} from "@/lib/tenancy/permissions";
import { createClient } from "@/lib/supabase/server";

export async function requireUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return user;
}

export async function requireTenantContext(): Promise<TenantContext> {
  const user = await requireUser();
  const context = await resolveTenantContext();

  if (!context) {
    redirect("/onboarding/organization");
  }

  if (context.userId !== user.id) {
    redirect("/login");
  }

  return context;
}

export async function requireTenantPermission(
  permission: TenantPermission,
): Promise<TenantContext> {
  const context = await requireTenantContext();

  if (!hasPermission(context.membership.role, permission)) {
    redirect("/dashboard");
  }

  return context;
}

export function assertSameTenant(
  contextTenantId: string,
  resourceTenantId: string,
) {
  if (contextTenantId !== resourceTenantId) {
    throw new Error("Cross-tenant access denied.");
  }
}
