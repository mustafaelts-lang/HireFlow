import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { EMPLOYMENT_TYPE_LABELS, isEmploymentType } from "@/lib/jobs/types";

type PublicApplyPageProps = {
  params: Promise<{ token: string }>;
};

export const metadata: Metadata = {
  title: "Apply",
};

export default async function PublicApplyPage({
  params,
}: PublicApplyPageProps) {
  const { token } = await params;
  const supabase = await createClient();

  const { data: job } = await supabase
    .from("jobs")
    .select(
      "id, title, department, location, employment_type, description, status, apply_enabled, archived_at",
    )
    .eq("public_apply_token", token)
    .maybeSingle();

  if (!job || job.archived_at || job.status !== "open" || !job.apply_enabled) {
    notFound();
  }

  const employmentLabel =
    job.employment_type && isEmploymentType(job.employment_type)
      ? EMPLOYMENT_TYPE_LABELS[job.employment_type]
      : null;

  return (
    <div className="auth-shell">
      <div className="auth-panel" style={{ width: "min(100%, 42rem)" }}>
        <div className="auth-brand">
          <div className="auth-brand-mark">HireFlow</div>
          <p className="auth-brand-tagline">Public application</p>
        </div>
        <div className="auth-card">
          <h1 className="auth-title">{job.title}</h1>
          <p className="auth-subtitle">
            {[job.department, job.location, employmentLabel]
              .filter(Boolean)
              .join(" · ") || "Open role"}
          </p>
          <div className="job-description public-apply-body">
            {job.description || "No description provided."}
          </div>
          <p className="auth-alert auth-alert-success" role="status">
            This role is open. Candidate application intake (resume + consent)
            ships in the next slice — the publish link and job visibility are
            live.
          </p>
        </div>
      </div>
    </div>
  );
}
