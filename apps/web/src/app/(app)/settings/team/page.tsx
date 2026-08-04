import type { Metadata } from "next";

import { InviteMemberForm } from "@/components/team/invite-member-form";
import {
  TeamMembersPanel,
  type TeamInviteRow,
  type TeamMemberRow,
} from "@/components/team/team-members-panel";
import { unwrapRelation } from "@/lib/supabase/relations";
import { createClient } from "@/lib/supabase/server";
import { hasPermission } from "@/lib/tenancy/permissions";
import { requireTenantPermission } from "@/lib/tenancy/require-tenant";
import type { TenantRole } from "@/lib/tenancy/roles";
import { TENANT_ROLES } from "@/lib/tenancy/roles";

export const metadata: Metadata = {
  title: "Team members",
};

function isTenantRole(value: string): value is TenantRole {
  return (TENANT_ROLES as readonly string[]).includes(value);
}

function getSiteOrigin() {
  return (
    process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") ??
    "http://localhost:3000"
  );
}

type UserRow = {
  email: string;
  full_name: string | null;
};

export default async function TeamSettingsPage() {
  const context = await requireTenantPermission("tenant.users.read");
  const canManage = hasPermission(
    context.membership.role,
    "tenant.users.manage",
  );
  const tenantId = context.membership.tenantId;
  const supabase = await createClient();

  const { data: membershipRows, error: membersError } = await supabase
    .from("tenant_memberships")
    .select("id, role, status, user_id, users ( email, full_name )")
    .eq("tenant_id", tenantId)
    .neq("status", "revoked")
    .order("created_at", { ascending: true });

  if (membersError) {
    throw new Error(membersError.message);
  }

  const members: TeamMemberRow[] =
    membershipRows
      ?.map((row) => {
        const user = unwrapRelation(row.users as UserRow | UserRow[] | null);
        if (!user || !isTenantRole(row.role)) {
          return null;
        }
        return {
          id: row.id,
          role: row.role,
          status: row.status,
          email: user.email,
          fullName: user.full_name,
          isSelf: row.user_id === context.userId,
        };
      })
      .filter((item): item is TeamMemberRow => item !== null) ?? [];

  let invites: TeamInviteRow[] = [];
  if (canManage) {
    const { data: inviteRows, error: invitesError } = await supabase
      .from("tenant_invites")
      .select("id, email, role, status, expires_at, token")
      .eq("tenant_id", tenantId)
      .eq("status", "pending")
      .order("created_at", { ascending: false });

    if (invitesError) {
      throw new Error(invitesError.message);
    }

    invites =
      inviteRows
        ?.map((row) => {
          if (!isTenantRole(row.role)) {
            return null;
          }
          return {
            id: row.id,
            email: row.email,
            role: row.role,
            status: row.status,
            expiresAt: row.expires_at,
            token: row.token,
          };
        })
        .filter((item): item is TeamInviteRow => item !== null) ?? [];
  }

  return (
    <div className="stack-lg">
      <section className="app-panel">
        <h1>Team members</h1>
        <p className="muted">
          Invite colleagues by email. Roles: Owner, Admin, Recruiter, Hiring
          Manager.
        </p>
        {canManage ? <InviteMemberForm /> : null}
      </section>

      <TeamMembersPanel
        members={members}
        invites={invites}
        canManage={canManage}
        siteOrigin={getSiteOrigin()}
      />
    </div>
  );
}
