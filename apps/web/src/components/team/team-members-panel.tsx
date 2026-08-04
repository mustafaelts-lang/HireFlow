import { revokeInvite, revokeMember, updateMemberRole } from "@/actions/team";
import {
  ROLE_LABELS,
  TENANT_ROLES,
  type TenantRole,
} from "@/lib/tenancy/roles";

export type TeamMemberRow = {
  id: string;
  role: TenantRole;
  status: string;
  email: string;
  fullName: string | null;
  isSelf: boolean;
};

export type TeamInviteRow = {
  id: string;
  email: string;
  role: TenantRole;
  status: string;
  expiresAt: string;
  token: string;
};

type TeamMembersPanelProps = {
  members: TeamMemberRow[];
  invites: TeamInviteRow[];
  canManage: boolean;
  siteOrigin: string;
};

export function TeamMembersPanel({
  members,
  invites,
  canManage,
  siteOrigin,
}: TeamMembersPanelProps) {
  return (
    <div className="team-panels">
      <section className="app-panel">
        <h2>Members</h2>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                {canManage ? <th>Actions</th> : null}
              </tr>
            </thead>
            <tbody>
              {members.map((member) => (
                <tr key={member.id}>
                  <td>{member.fullName || "—"}</td>
                  <td>{member.email}</td>
                  <td>
                    {canManage && !member.isSelf ? (
                      <form action={updateMemberRole} className="inline-form">
                        <input
                          type="hidden"
                          name="membershipId"
                          value={member.id}
                        />
                        <select name="role" defaultValue={member.role}>
                          {TENANT_ROLES.map((role) => (
                            <option key={role} value={role}>
                              {ROLE_LABELS[role]}
                            </option>
                          ))}
                        </select>
                        <button type="submit" className="text-button">
                          Update
                        </button>
                      </form>
                    ) : (
                      ROLE_LABELS[member.role]
                    )}
                  </td>
                  <td>{member.status}</td>
                  {canManage ? (
                    <td>
                      {!member.isSelf && (
                        <form action={revokeMember}>
                          <input
                            type="hidden"
                            name="membershipId"
                            value={member.id}
                          />
                          <button type="submit" className="text-button danger">
                            Remove
                          </button>
                        </form>
                      )}
                    </td>
                  ) : null}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="app-panel">
        <h2>Pending invites</h2>
        {invites.length === 0 ? (
          <p className="muted">No pending invites.</p>
        ) : (
          <div className="data-table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Email</th>
                  <th>Role</th>
                  <th>Expires</th>
                  <th>Link</th>
                  {canManage ? <th>Actions</th> : null}
                </tr>
              </thead>
              <tbody>
                {invites.map((invite) => (
                  <tr key={invite.id}>
                    <td>{invite.email}</td>
                    <td>{ROLE_LABELS[invite.role]}</td>
                    <td>{new Date(invite.expiresAt).toLocaleDateString()}</td>
                    <td>
                      <code className="invite-code">
                        {`${siteOrigin}/invites/${invite.token}`}
                      </code>
                    </td>
                    {canManage ? (
                      <td>
                        <form action={revokeInvite}>
                          <input
                            type="hidden"
                            name="inviteId"
                            value={invite.id}
                          />
                          <button type="submit" className="text-button danger">
                            Revoke
                          </button>
                        </form>
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
