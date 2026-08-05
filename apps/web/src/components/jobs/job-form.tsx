"use client";

import { useActionState } from "react";
import Link from "next/link";

import { createJob, updateJob, type JobActionState } from "@/actions/jobs";
import {
  EMPLOYMENT_TYPES,
  EMPLOYMENT_TYPE_LABELS,
  type JobRecord,
} from "@/lib/jobs/types";

const initialState: JobActionState = {};

type TemplateOption = {
  id: string;
  name: string;
  is_default: boolean;
};

type JobFormProps = {
  mode: "create" | "edit";
  templates: TemplateOption[];
  job?: JobRecord;
  readOnly?: boolean;
};

export function JobForm({
  mode,
  templates,
  job,
  readOnly = false,
}: JobFormProps) {
  const action = mode === "create" ? createJob : updateJob;
  const [state, formAction, pending] = useActionState(action, initialState);
  const defaultTemplateId =
    job?.pipelineTemplateId ??
    templates.find((item) => item.is_default)?.id ??
    templates[0]?.id ??
    "";

  const requestedAtValue = job?.requestedAt ? job.requestedAt.slice(0, 10) : "";

  return (
    <form action={formAction} className="template-form">
      {job ? <input type="hidden" name="jobId" value={job.id} /> : null}

      {state.error ? (
        <p className="auth-alert auth-alert-error" role="alert">
          {state.error}
        </p>
      ) : null}
      {state.success ? (
        <p className="auth-alert auth-alert-success" role="status">
          {state.success}
        </p>
      ) : null}

      <section className="app-panel">
        <div className="panel-header-row">
          <h1>{mode === "create" ? "Create job" : "Edit job"}</h1>
          <Link href="/jobs" className="auth-link">
            Back to jobs
          </Link>
        </div>

        <div className="settings-form job-form-grid">
          <label className="auth-field">
            <span>Title</span>
            <input
              name="title"
              defaultValue={job?.title ?? ""}
              required
              disabled={readOnly}
              placeholder="Senior Software Engineer"
            />
          </label>

          <label className="auth-field">
            <span>Department</span>
            <input
              name="department"
              defaultValue={job?.department ?? ""}
              disabled={readOnly}
              placeholder="Engineering"
            />
          </label>

          <label className="auth-field">
            <span>Location</span>
            <input
              name="location"
              defaultValue={job?.location ?? ""}
              disabled={readOnly}
              placeholder="Remote / Berlin"
            />
          </label>

          <label className="auth-field">
            <span>Employment type</span>
            <select
              name="employmentType"
              defaultValue={job?.employmentType ?? ""}
              disabled={readOnly}
            >
              <option value="">Select type</option>
              {EMPLOYMENT_TYPES.map((type) => (
                <option key={type} value={type}>
                  {EMPLOYMENT_TYPE_LABELS[type]}
                </option>
              ))}
            </select>
          </label>

          <label className="auth-field">
            <span>Openings</span>
            <input
              name="openings"
              type="number"
              min={1}
              defaultValue={job?.openings ?? 1}
              disabled={readOnly}
              required
            />
          </label>

          <label className="auth-field">
            <span>Pipeline template</span>
            <select
              name="pipelineTemplateId"
              defaultValue={defaultTemplateId}
              disabled={readOnly || (job ? job.status !== "draft" : false)}
              required
            >
              {templates.length === 0 ? (
                <option value="">No active templates</option>
              ) : (
                templates.map((template) => (
                  <option key={template.id} value={template.id}>
                    {template.name}
                    {template.is_default ? " (Default)" : ""}
                  </option>
                ))
              )}
            </select>
          </label>

          <label className="auth-field full-width">
            <span>Job description</span>
            <textarea
              name="description"
              defaultValue={job?.description ?? ""}
              disabled={readOnly}
              rows={8}
              placeholder="Role overview, responsibilities, requirements…"
            />
          </label>
        </div>
      </section>

      <section className="app-panel">
        <h2>Requisition details</h2>
        <div className="settings-form job-form-grid">
          <label className="auth-field">
            <span>Requesting department</span>
            <input
              name="requestingDepartment"
              defaultValue={job?.requestingDepartment ?? ""}
              disabled={readOnly}
            />
          </label>
          <label className="auth-field">
            <span>Requested by</span>
            <input
              name="requestedByName"
              defaultValue={job?.requestedByName ?? ""}
              disabled={readOnly}
            />
          </label>
          <label className="auth-field">
            <span>Requested on</span>
            <input
              name="requestedAt"
              type="date"
              defaultValue={requestedAtValue}
              disabled={readOnly}
            />
          </label>
          <label className="auth-field">
            <span>Hiring manager name</span>
            <input
              name="hiringManagerName"
              defaultValue={job?.hiringManagerName ?? ""}
              disabled={readOnly}
            />
          </label>
          <label className="auth-field">
            <span>Hiring manager email</span>
            <input
              name="hiringManagerEmail"
              type="email"
              defaultValue={job?.hiringManagerEmail ?? ""}
              disabled={readOnly}
            />
          </label>
        </div>
      </section>

      {!readOnly ? (
        <div className="form-actions">
          <button
            type="submit"
            className="auth-button"
            disabled={pending || templates.length === 0}
          >
            {pending
              ? "Saving…"
              : mode === "create"
                ? "Create job"
                : "Save changes"}
          </button>
        </div>
      ) : null}
    </form>
  );
}
