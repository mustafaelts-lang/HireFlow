"use client";

import { useActionState } from "react";

import {
  updateOrganizationSettings,
  type OrganizationActionState,
} from "@/actions/organization";

const initialState: OrganizationActionState = {};

type OrganizationSettingsFormProps = {
  name: string;
  slug: string;
  timezone: string;
  locale: string;
  canEdit: boolean;
};

export function OrganizationSettingsForm({
  name,
  slug,
  timezone,
  locale,
  canEdit,
}: OrganizationSettingsFormProps) {
  const [state, formAction, pending] = useActionState(
    updateOrganizationSettings,
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

      <label className="auth-field">
        <span>Organization name</span>
        <input name="name" defaultValue={name} required disabled={!canEdit} />
      </label>

      <label className="auth-field">
        <span>Slug</span>
        <input value={slug} disabled readOnly />
      </label>

      <label className="auth-field">
        <span>Timezone</span>
        <input name="timezone" defaultValue={timezone} disabled={!canEdit} />
      </label>

      <label className="auth-field">
        <span>Locale</span>
        <input name="locale" defaultValue={locale} disabled={!canEdit} />
      </label>

      {canEdit && (
        <button type="submit" className="auth-button" disabled={pending}>
          {pending ? "Saving…" : "Save settings"}
        </button>
      )}
    </form>
  );
}
