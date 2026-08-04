"use client";

import { useActionState, useMemo, useState } from "react";

import {
  createOrganization,
  type OrganizationActionState,
} from "@/actions/organization";
import { slugifyOrganizationName } from "@/lib/tenancy/slug";

const initialState: OrganizationActionState = {};

export function CreateOrganizationForm() {
  const [name, setName] = useState("");
  const [slugTouched, setSlugTouched] = useState(false);
  const [slug, setSlug] = useState("");
  const [state, formAction, pending] = useActionState(
    createOrganization,
    initialState,
  );

  const computedSlug = useMemo(
    () => (slugTouched ? slug : slugifyOrganizationName(name)),
    [name, slug, slugTouched],
  );

  return (
    <form action={formAction} className="auth-form">
      {state.error && (
        <p className="auth-alert auth-alert-error" role="alert">
          {state.error}
        </p>
      )}

      <label className="auth-field">
        <span>Organization name</span>
        <input
          name="name"
          value={name}
          onChange={(event) => setName(event.target.value)}
          required
          placeholder="Acme Recruiting"
        />
      </label>

      <label className="auth-field">
        <span>URL slug</span>
        <input
          name="slug"
          value={computedSlug}
          onChange={(event) => {
            setSlugTouched(true);
            setSlug(event.target.value);
          }}
          required
          placeholder="acme-recruiting"
        />
      </label>

      <label className="auth-field">
        <span>Timezone</span>
        <input name="timezone" defaultValue="UTC" placeholder="UTC" />
      </label>

      <label className="auth-field">
        <span>Locale</span>
        <input name="locale" defaultValue="en-US" placeholder="en-US" />
      </label>

      <button type="submit" className="auth-button" disabled={pending}>
        {pending ? "Creating…" : "Create organization"}
      </button>
    </form>
  );
}
