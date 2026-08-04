import { SignOutButton } from "@/components/auth/sign-out-button";
import { AppNav } from "@/components/app/app-nav";
import { requireTenantContext } from "@/lib/tenancy/require-tenant";

export default async function AppLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const context = await requireTenantContext();

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-brand">HireFlow</div>
        <div className="app-header-meta">
          <span>{context.email}</span>
          <SignOutButton />
        </div>
      </header>
      <AppNav
        organizationName={context.membership.tenant.name}
        role={context.membership.role}
      />
      <main className="app-main">{children}</main>
    </div>
  );
}
