import Link from "next/link";

type AuthShellProps = {
  title: string;
  subtitle: string;
  children: React.ReactNode;
};

export function AuthShell({ title, subtitle, children }: AuthShellProps) {
  return (
    <div className="auth-shell">
      <div className="auth-panel">
        <div className="auth-brand">
          <Link href="/login" className="auth-brand-mark">
            HireFlow
          </Link>
          <p className="auth-brand-tagline">Recruiting operations, clearly</p>
        </div>
        <div className="auth-card">
          <h1 className="auth-title">{title}</h1>
          <p className="auth-subtitle">{subtitle}</p>
          {children}
        </div>
      </div>
    </div>
  );
}
