import { SignOutButton } from "@/components/auth/sign-out-button";
import { createClient } from "@/lib/supabase/server";

export default async function AppLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-brand">HireFlow</div>
        <div className="app-header-meta">
          <span>{user?.email}</span>
          <SignOutButton />
        </div>
      </header>
      <main className="app-main">{children}</main>
    </div>
  );
}
