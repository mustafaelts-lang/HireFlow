import type { Metadata } from "next";

import { AuthShell } from "@/components/auth/auth-shell";
import { LoginForm } from "@/components/auth/login-form";

export const metadata: Metadata = {
  title: "Sign in",
};

type LoginPageProps = {
  searchParams: Promise<{
    next?: string;
    error?: string;
  }>;
};

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const params = await searchParams;
  const nextPath =
    params.next && params.next.startsWith("/") ? params.next : "/dashboard";
  const authError =
    params.error === "auth_callback"
      ? "Authentication link is invalid or expired. Please try again."
      : undefined;

  return (
    <AuthShell
      title="Sign in"
      subtitle="Access your HireFlow workspace with email and password."
    >
      <LoginForm nextPath={nextPath} authError={authError} />
    </AuthShell>
  );
}
