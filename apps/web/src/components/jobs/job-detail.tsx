"use client";

import { useState } from "react";
import Link from "next/link";

import {
  archiveJob,
  closeJob,
  deleteJob,
  fillJob,
  holdJob,
  publishJob,
  reopenJob,
  restoreJob,
} from "@/actions/jobs";
import {
  JOB_STATUS_LABELS,
  buildPublicApplyPath,
  type JobRecord,
  type JobStage,
} from "@/lib/jobs/types";

type JobDetailProps = {
  job: JobRecord;
  stages: JobStage[];
  canWrite: boolean;
  canDelete: boolean;
  siteOrigin: string;
};

export function JobDetailActions({
  job,
  stages,
  canWrite,
  canDelete,
  siteOrigin,
}: JobDetailProps) {
  const [copied, setCopied] = useState(false);
  const applyPath =
    job.publicApplyToken != null
      ? buildPublicApplyPath(job.publicApplyToken)
      : null;
  const applyUrl = applyPath ? `${siteOrigin}${applyPath}` : null;

  async function copyApplyLink() {
    if (!applyUrl) {
      return;
    }
    await navigator.clipboard.writeText(applyUrl);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="stack-lg">
      <section className="app-panel">
        <div className="panel-header-row">
          <div>
            <p className="eyebrow">
              {JOB_STATUS_LABELS[job.status]}
              {job.archivedAt ? " · Archived" : ""}
            </p>
            <h1>{job.title}</h1>
            <p className="muted">
              {[job.department, job.location].filter(Boolean).join(" · ") ||
                "No department / location"}
            </p>
          </div>
          <div className="row-actions">
            <Link href="/jobs" className="text-button">
              Back
            </Link>
            {canWrite && !job.archivedAt ? (
              <Link href={`/jobs/${job.id}/edit`} className="text-button">
                Edit
              </Link>
            ) : null}
          </div>
        </div>

        <dl className="meta-grid">
          <div>
            <dt>Openings</dt>
            <dd>{job.openings}</dd>
          </div>
          <div>
            <dt>Pipeline</dt>
            <dd>{job.pipelineTemplateName ?? "—"}</dd>
          </div>
          <div>
            <dt>Hiring manager</dt>
            <dd>
              {job.hiringManagerName || "—"}
              {job.hiringManagerEmail ? (
                <div className="muted small">{job.hiringManagerEmail}</div>
              ) : null}
            </dd>
          </div>
          <div>
            <dt>Published</dt>
            <dd>
              {job.publishedAt
                ? new Date(job.publishedAt).toLocaleString()
                : "Not published"}
            </dd>
          </div>
        </dl>

        {applyUrl ? (
          <div className="apply-link-box">
            <div>
              <strong>Public apply link</strong>
              <div className="invite-code">{applyUrl}</div>
              <p className="muted small">
                Apply enabled: {job.applyEnabled ? "Yes" : "No"}
              </p>
            </div>
            <button
              type="button"
              className="secondary-button"
              onClick={copyApplyLink}
            >
              {copied ? "Copied" : "Copy link"}
            </button>
          </div>
        ) : (
          <p className="muted">
            Publish this job to generate a public apply link.
          </p>
        )}

        {canWrite ? (
          <div className="row-actions status-actions">
            {!job.archivedAt && job.status === "draft" ? (
              <form action={publishJob}>
                <input type="hidden" name="jobId" value={job.id} />
                <button type="submit" className="auth-button">
                  Publish
                </button>
              </form>
            ) : null}

            {!job.archivedAt && job.status === "open" ? (
              <form action={holdJob}>
                <input type="hidden" name="jobId" value={job.id} />
                <button type="submit" className="secondary-button">
                  Put on hold
                </button>
              </form>
            ) : null}

            {!job.archivedAt &&
            (job.status === "on_hold" ||
              job.status === "closed" ||
              job.status === "filled") ? (
              <form action={reopenJob}>
                <input type="hidden" name="jobId" value={job.id} />
                <button type="submit" className="secondary-button">
                  Reopen / publish
                </button>
              </form>
            ) : null}

            {!job.archivedAt &&
            (job.status === "open" || job.status === "on_hold") ? (
              <>
                <form action={closeJob}>
                  <input type="hidden" name="jobId" value={job.id} />
                  <button type="submit" className="secondary-button">
                    Close
                  </button>
                </form>
                <form action={fillJob}>
                  <input type="hidden" name="jobId" value={job.id} />
                  <button type="submit" className="secondary-button">
                    Mark filled
                  </button>
                </form>
              </>
            ) : null}

            {!job.archivedAt ? (
              <form action={archiveJob}>
                <input type="hidden" name="jobId" value={job.id} />
                <button type="submit" className="text-button">
                  Archive
                </button>
              </form>
            ) : (
              <form action={restoreJob}>
                <input type="hidden" name="jobId" value={job.id} />
                <button type="submit" className="text-button">
                  Restore to draft
                </button>
              </form>
            )}

            {canDelete && job.status === "draft" && !job.archivedAt ? (
              <form action={deleteJob}>
                <input type="hidden" name="jobId" value={job.id} />
                <button type="submit" className="text-button danger">
                  Delete
                </button>
              </form>
            ) : null}
          </div>
        ) : null}
      </section>

      <section className="app-panel">
        <h2>Description</h2>
        <p className="job-description">
          {job.description?.trim() || "No description yet."}
        </p>
      </section>

      <section className="app-panel">
        <h2>Pipeline stages</h2>
        <ol className="job-stage-list">
          {stages.map((stage) => (
            <li key={stage.id}>
              <span
                className="stage-dot"
                style={{ background: stage.color }}
                aria-hidden
              />
              <div>
                <strong>{stage.name}</strong>
                <div className="muted small">
                  {stage.category}
                  {stage.isAppliedEntry ? " · Applied entry" : ""}
                  {stage.slaDays != null ? ` · SLA ${stage.slaDays}d` : ""}
                </div>
              </div>
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
