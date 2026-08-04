import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { acceptInvite } from "@/actions/team";
import { AuthShell } from "@/components/auth/auth-shell";
import { unwrapRelation } from "@/lib/supabase/relations";
import { createClient } from "@/lib/supabase/server";
import {
  ROLE_LABELS,
  TENANT_ROLES,
  type TenantRole,
} from "@/lib/tenancy/roles";

export const metadata: Metadata = {
  title: "Accept invite",
};

type InvitePageProps = {
  params: Promise<{ token: string }>;
  searchParams: Promise<{ error?: string }>;
};

function isTenantRole(value: string): value is TenantRole {
  return (TENANT_ROLES as readonly string[]).includes(value);
}

export default async function AcceptInvitePage({
  params,
  searchParams,
}: InvitePageProps) {
  const { token } = await params;
  const { error } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(`/invites/${token}`)}`);
  }

  const { data: invite } = await supabase
    .from("tenant_invites")
    .select("email, role, status, expires_at, tenants ( name )")
    .eq("token", token)
    .maybeSingle();

  const tenant = unwrapRelation(
    invite?.tenants as { name: string } | { name: string }[] | null,
  );
  const tenantName = tenant?.name ?? "the organization";
  const roleLabel =
    invite?.role && isTenantRole(invite.role)
      ? ROLE_LABELS[invite.role]
      : "member";

  async function acceptAction() {
    "use server";
    await acceptInvite(token);
  }

  return (
    <AuthShell
      title="Join organization"
      subtitle={`You’ve been invited to ${tenantName} as ${roleLabel}.`}
    >
      {error ? (
        <p className="auth-alert auth-alert-error" role="alert">
          {error}
        </p>
      ) : null}

      {invite?.status === "pending" ? (
        <form action={acceptAction} className="auth-form">
          <p className="muted">
            Signed in as <strong>{user.email}</strong>. The invite email must
            match this account.
          </p>
          <button type="submit" className="auth-button">
            Accept invite
          </button>
        </form>
      ) : (
        <div className="auth-form">
          <p className="auth-alert auth-alert-error" role="alert">
            This invite is unavailable or already used.
          </p>
          <Link href="/dashboard" className="auth-link">
            Go to dashboard
          </Link>
        </div>
      )}
    </AuthShell>
  );
}
