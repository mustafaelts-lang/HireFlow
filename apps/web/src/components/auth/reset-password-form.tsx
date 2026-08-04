"use client";

import { useActionState } from "react";

import { updatePassword, type AuthActionState } from "@/actions/auth";

const initialState: AuthActionState = {};

export function ResetPasswordForm() {
  const [state, formAction, pending] = useActionState(
    updatePassword,
    initialState,
  );

  return (
    <form action={formAction} className="auth-form">
      {state.error && (
        <p className="auth-alert auth-alert-error" role="alert">
          {state.error}
        </p>
      )}

      <label className="auth-field">
        <span>New password</span>
        <input
          name="password"
          type="password"
          autoComplete="new-password"
          required
          minLength={8}
          placeholder="At least 8 characters"
        />
      </label>

      <label className="auth-field">
        <span>Confirm password</span>
        <input
          name="confirmPassword"
          type="password"
          autoComplete="new-password"
          required
          minLength={8}
          placeholder="Repeat password"
        />
      </label>

      <button type="submit" className="auth-button" disabled={pending}>
        {pending ? "Updating…" : "Update password"}
      </button>
    </form>
  );
}
