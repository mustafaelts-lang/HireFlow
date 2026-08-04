"use client";

import Link from "next/link";
import { useActionState } from "react";

import { requestPasswordReset, type AuthActionState } from "@/actions/auth";

const initialState: AuthActionState = {};

export function ForgotPasswordForm() {
  const [state, formAction, pending] = useActionState(
    requestPasswordReset,
    initialState,
  );

  return (
    <form action={formAction} className="auth-form">
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
        <span>Email</span>
        <input
          name="email"
          type="email"
          autoComplete="email"
          required
          placeholder="you@company.com"
        />
      </label>

      <button type="submit" className="auth-button" disabled={pending}>
        {pending ? "Sending…" : "Send reset link"}
      </button>

      <p className="auth-footer">
        Remembered your password?{" "}
        <Link href="/login" className="auth-link">
          Back to sign in
        </Link>
      </p>
    </form>
  );
}
