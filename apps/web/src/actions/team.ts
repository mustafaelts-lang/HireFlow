"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { setActiveTenantCookie } from "@/lib/tenancy/cookie";
import {
  INVITABLE_ROLES,
  ROLE_LABELS,
  type InvitableRole,
  type TenantRole,
} from "@/lib/tenancy/roles";
import { requireTenantPermission } from "@/lib/tenancy/require-tenant";
import { createClient } from "@/lib/supabase/server";

export type TeamActionState = {
  error?: string;
  success?: string;
  inviteUrl?: string;
};

function getString(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

function getSiteOrigin() {
  return (
    process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") ??
    "http://localhost:3000"
  );
}

function isInvitableRole(value: string): value is InvitableRole {
  return (INVITABLE_ROLES as readonly string[]).includes(value);
}

export async function inviteTeamMember(
  _prevState: TeamActionState,
  formData: FormData,
): Promise<TeamActionState> {
  const context = await requireTenantPermission("tenant.users.manage");
  const email = getString(formData, "email").toLowerCase();
  const role = getString(formData, "role");

  if (!email) {
    return { error: "Email is required." };
  }

  if (!isInvitableRole(role)) {
    return { error: "Select a valid role." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("invite_team_member", {
    p_tenant_id: context.membership.tenantId,
    p_email: email,
    p_role: role,
  });

  if (error) {
    return { error: error.message };
  }

  const token =
    data && typeof data === "object" && "token" in data
      ? String((data as { token: string }).token)
      : null;

  if (!token) {
    return { error: "Invite created, but token was missing." };
  }

  const inviteUrl = `${getSiteOrigin()}/invites/${token}`;

  revalidatePath("/settings/team");

  return {
    success: `Invite created for ${email} as ${ROLE_LABELS[role as TenantRole]}. Share the invite link below.`,
    inviteUrl,
  };
}

export async function revokeInvite(formData: FormData): Promise<void> {
  const context = await requireTenantPermission("tenant.users.manage");
  const inviteId = getString(formData, "inviteId");

  if (!inviteId) {
    return;
  }

  const supabase = await createClient();
  await supabase.rpc("revoke_tenant_invite", {
    p_tenant_id: context.membership.tenantId,
    p_invite_id: inviteId,
  });

  revalidatePath("/settings/team");
}

export async function updateMemberRole(formData: FormData): Promise<void> {
  const context = await requireTenantPermission("tenant.users.manage");
  const membershipId = getString(formData, "membershipId");
  const role = getString(formData, "role");

  if (!membershipId || !role) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_member_role", {
    p_tenant_id: context.membership.tenantId,
    p_membership_id: membershipId,
    p_role: role,
  });

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/settings/team");
}

export async function revokeMember(formData: FormData): Promise<void> {
  const context = await requireTenantPermission("tenant.users.manage");
  const membershipId = getString(formData, "membershipId");

  if (!membershipId) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("revoke_member", {
    p_tenant_id: context.membership.tenantId,
    p_membership_id: membershipId,
  });

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/settings/team");
}

export async function acceptInvite(token: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(`/invites/${token}`)}`);
  }

  const { data, error } = await supabase.rpc("accept_tenant_invite", {
    p_token: token,
  });

  if (error) {
    redirect(`/invites/${token}?error=${encodeURIComponent(error.message)}`);
  }

  const tenantId = typeof data === "string" ? data : String(data);
  await setActiveTenantCookie(tenantId);
  redirect("/dashboard");
}
