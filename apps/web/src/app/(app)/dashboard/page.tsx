import type { Metadata } from "next";

import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Dashboard",
};

export default async function DashboardPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <section className="app-panel">
      <h1>Welcome back</h1>
      <p>
        You’re signed in as <strong>{user?.email}</strong>. Recruiting features
        will land in later sprints — this shell confirms authentication works.
      </p>
    </section>
  );
}
