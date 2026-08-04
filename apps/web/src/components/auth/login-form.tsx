"use client";

import Link from "next/link";
import { useActionState } from "react";

import { signIn, type AuthActionState } from "@/actions/auth";

const initialState: AuthActionState = {};

type LoginFormProps = {
  nextPath?: string;
  authError?: string;
};

export function LoginForm({
  nextPath = "/dashboard",
  authError,
}: LoginFormProps) {
  const [state, formAction, pending] = useActionState(signIn, initialState);

  return (
    <form action={formAction} className="auth-form">
      <input type="hidden" name="next" value={nextPath} />

      {(authError || state.error) && (
        <p className="auth-alert auth-alert-error" role="alert">
          {authError || state.error}
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

      <label className="auth-field">
        <span>Password</span>
        <input
          name="password"
          type="password"
          autoComplete="current-password"
          required
          placeholder="••••••••"
        />
      </label>

      <div className="auth-row">
        <Link href="/forgot-password" className="auth-link">
          Forgot password?
        </Link>
      </div>

      <button type="submit" className="auth-button" disabled={pending}>
        {pending ? "Signing in…" : "Sign in"}
      </button>

      <p className="auth-footer">
        No account yet?{" "}
        <Link href="/signup" className="auth-link">
          Create one
        </Link>
      </p>
    </form>
  );
}
