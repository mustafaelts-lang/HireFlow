import type { Metadata } from "next";

import { CreateOrganizationForm } from "@/components/organization/create-organization-form";
import { AuthShell } from "@/components/auth/auth-shell";

export const metadata: Metadata = {
  title: "Create organization",
};

export default function CreateOrganizationPage() {
  return (
    <AuthShell
      title="Create your organization"
      subtitle="You’re the first user, so you’ll become the Organization Owner."
    >
      <CreateOrganizationForm />
    </AuthShell>
  );
}
