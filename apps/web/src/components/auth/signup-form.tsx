"use client";

import Link from "next/link";
import { useActionState } from "react";

import { signUp, type AuthActionState } from "@/actions/auth";

const initialState: AuthActionState = {};

export function SignupForm() {
  const [state, formAction, pending] = useActionState(signUp, initialState);

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
        <span>Full name</span>
        <input
          name="fullName"
          type="text"
          autoComplete="name"
          placeholder="Alex Recruiter"
        />
      </label>

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
          autoComplete="new-password"
          required
          minLength={8}
          placeholder="At least 8 characters"
        />
      </label>

      <button type="submit" className="auth-button" disabled={pending}>
        {pending ? "Creating account…" : "Create account"}
      </button>

      <p className="auth-footer">
        Already have an account?{" "}
        <Link href="/login" className="auth-link">
          Sign in
        </Link>
      </p>
    </form>
  );
}
