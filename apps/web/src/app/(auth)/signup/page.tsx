import type { Metadata } from "next";

import { AuthShell } from "@/components/auth/auth-shell";
import { SignupForm } from "@/components/auth/signup-form";

export const metadata: Metadata = {
  title: "Create account",
};

export default function SignupPage() {
  return (
    <AuthShell
      title="Create account"
      subtitle="Start with a recruiter account. Company setup comes later."
    >
      <SignupForm />
    </AuthShell>
  );
}
