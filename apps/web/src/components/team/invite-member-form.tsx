"use client";

import { useActionState } from "react";

import { inviteTeamMember, type TeamActionState } from "@/actions/team";
import { INVITABLE_ROLES, ROLE_LABELS } from "@/lib/tenancy/roles";

const initialState: TeamActionState = {};

export function InviteMemberForm() {
  const [state, formAction, pending] = useActionState(
    inviteTeamMember,
    initialState,
  );

  return (
    <form action={formAction} className="settings-form">
      {state.error && (
        <p className="auth-alert auth-alert-error" role="alert">
          {state.error}
        </p>
      )}
      {state.success && (
        <p className="auth-alert auth-alert-success" role="status">
          {state.success}
        </p>
      )}
      {state.inviteUrl && (
        <p className="invite-link">
          Invite link: <code>{state.inviteUrl}</code>
        </p>
      )}

      <label className="auth-field">
        <span>Email</span>
        <input
          name="email"
          type="email"
          required
          placeholder="teammate@company.com"
        />
      </label>

      <label className="auth-field">
        <span>Role</span>
        <select name="role" defaultValue="recruiter" required>
          {INVITABLE_ROLES.map((role) => (
            <option key={role} value={role}>
              {ROLE_LABELS[role]}
            </option>
          ))}
        </select>
      </label>

      <button type="submit" className="auth-button" disabled={pending}>
        {pending ? "Sending invite…" : "Invite member"}
      </button>
    </form>
  );
}
