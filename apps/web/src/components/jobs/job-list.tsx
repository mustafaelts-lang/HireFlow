import Link from "next/link";

import { archiveJob, publishJob, restoreJob } from "@/actions/jobs";
import { JOB_STATUS_LABELS, type JobRecord } from "@/lib/jobs/types";

type JobListProps = {
  jobs: JobRecord[];
  canWrite: boolean;
  showArchived: boolean;
};

export function JobList({ jobs, canWrite, showArchived }: JobListProps) {
  if (jobs.length === 0) {
    return (
      <section className="app-panel">
        <p className="muted">
          {showArchived ? "No archived jobs." : "No jobs yet."}
        </p>
        {canWrite && !showArchived ? (
          <Link href="/jobs/new" className="auth-button inline-link-button">
            Create job
          </Link>
        ) : null}
      </section>
    );
  }

  return (
    <section className="app-panel">
      <div className="data-table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Title</th>
              <th>Status</th>
              <th>Department</th>
              <th>Pipeline</th>
              <th>Updated</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {jobs.map((job) => (
              <tr key={job.id}>
                <td>
                  <Link href={`/jobs/${job.id}`} className="auth-link">
                    {job.title}
                  </Link>
                  {job.location ? (
                    <div className="muted small">{job.location}</div>
                  ) : null}
                </td>
                <td>
                  <span className={`status-pill status-${job.status}`}>
                    {JOB_STATUS_LABELS[job.status]}
                  </span>
                </td>
                <td>{job.department || "—"}</td>
                <td>{job.pipelineTemplateName || "—"}</td>
                <td>{new Date(job.updatedAt).toLocaleDateString()}</td>
                <td>
                  <div className="row-actions">
                    <Link href={`/jobs/${job.id}`} className="text-button">
                      Open
                    </Link>
                    {canWrite && !job.archivedAt && job.status === "draft" ? (
                      <form action={publishJob}>
                        <input type="hidden" name="jobId" value={job.id} />
                        <button type="submit" className="text-button">
                          Publish
                        </button>
                      </form>
                    ) : null}
                    {canWrite && !job.archivedAt ? (
                      <form action={archiveJob}>
                        <input type="hidden" name="jobId" value={job.id} />
                        <button type="submit" className="text-button">
                          Archive
                        </button>
                      </form>
                    ) : null}
                    {canWrite && job.archivedAt ? (
                      <form action={restoreJob}>
                        <input type="hidden" name="jobId" value={job.id} />
                        <button type="submit" className="text-button">
                          Restore
                        </button>
                      </form>
                    ) : null}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
