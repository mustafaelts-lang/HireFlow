"use server";

import { redirect } from "next/navigation";

import { setActiveTenantCookie } from "@/lib/tenancy/cookie";
import { listActiveMemberships } from "@/lib/tenancy/get-tenant-context";
import { requireUser } from "@/lib/tenancy/require-tenant";
import { isValidSlug, slugifyOrganizationName } from "@/lib/tenancy/slug";
import { createClient } from "@/lib/supabase/server";

export type OrganizationActionState = {
  error?: string;
  success?: string;
};

function getString(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

export async function createOrganization(
  _prevState: OrganizationActionState,
  formData: FormData,
): Promise<OrganizationActionState> {
  const user = await requireUser();
  const existing = await listActiveMemberships(user.id);

  if (existing.length > 0) {
    redirect("/dashboard");
  }

  const name = getString(formData, "name");
  const slugInput = getString(formData, "slug");
  const timezone = getString(formData, "timezone") || "UTC";
  const locale = getString(formData, "locale") || "en-US";
  const slug = slugInput || slugifyOrganizationName(name);

  if (!name) {
    return { error: "Organization name is required." };
  }

  if (!isValidSlug(slug)) {
    return {
      error:
        "Slug must be lowercase letters, numbers, and hyphens (min 2 characters).",
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_tenant", {
    p_name: name,
    p_slug: slug,
    p_owner_user_id: user.id,
    p_timezone: timezone,
    p_locale: locale,
  });

  if (error) {
    if (error.message.toLowerCase().includes("duplicate")) {
      return { error: "That organization slug is already taken." };
    }
    return { error: error.message };
  }

  const tenantId = typeof data === "string" ? data : String(data);
  await setActiveTenantCookie(tenantId);
  redirect("/dashboard");
}

export async function updateOrganizationSettings(
  _prevState: OrganizationActionState,
  formData: FormData,
): Promise<OrganizationActionState> {
  const { requireTenantPermission } =
    await import("@/lib/tenancy/require-tenant");
  const context = await requireTenantPermission("tenant.settings.write");

  const name = getString(formData, "name");
  const timezone = getString(formData, "timezone") || "UTC";
  const locale = getString(formData, "locale") || "en-US";

  if (!name) {
    return { error: "Organization name is required." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_tenant_settings", {
    p_tenant_id: context.membership.tenantId,
    p_name: name,
    p_timezone: timezone,
    p_locale: locale,
  });

  if (error) {
    return { error: error.message };
  }

  return { success: "Organization settings saved." };
}
