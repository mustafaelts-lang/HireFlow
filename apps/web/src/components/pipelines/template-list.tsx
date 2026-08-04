import Link from "next/link";

import {
  archivePipelineTemplate,
  deletePipelineTemplate,
  duplicatePipelineTemplate,
  restorePipelineTemplate,
  setDefaultPipelineTemplate,
} from "@/actions/pipelines";
import type { PipelineTemplate } from "@/lib/pipelines/types";

type TemplateListProps = {
  templates: PipelineTemplate[];
  canWrite: boolean;
  canDelete: boolean;
  showArchived: boolean;
};

export function TemplateList({
  templates,
  canWrite,
  canDelete,
  showArchived,
}: TemplateListProps) {
  if (templates.length === 0) {
    return (
      <section className="app-panel">
        <p className="muted">
          {showArchived
            ? "No archived templates."
            : "No active pipeline templates yet."}
        </p>
        {canWrite && !showArchived ? (
          <Link
            href="/pipelines/new"
            className="auth-button inline-link-button"
          >
            Create template
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
              <th>Name</th>
              <th>Stages</th>
              <th>Status</th>
              <th>Updated</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {templates.map((template) => (
              <tr key={template.id}>
                <td>
                  <Link
                    href={`/pipelines/${template.id}`}
                    className="auth-link"
                  >
                    {template.name}
                  </Link>
                  {template.isDefault ? (
                    <span className="badge">Default</span>
                  ) : null}
                  {template.description ? (
                    <div className="muted small">{template.description}</div>
                  ) : null}
                </td>
                <td>{template.stageCount ?? "—"}</td>
                <td>{template.archivedAt ? "Archived" : "Active"}</td>
                <td>{new Date(template.updatedAt).toLocaleDateString()}</td>
                <td>
                  <div className="row-actions">
                    <Link
                      href={`/pipelines/${template.id}`}
                      className="text-button"
                    >
                      {canWrite && !template.archivedAt ? "Edit" : "View"}
                    </Link>

                    {canWrite && !template.archivedAt ? (
                      <>
                        <form action={duplicatePipelineTemplate}>
                          <input
                            type="hidden"
                            name="templateId"
                            value={template.id}
                          />
                          <button type="submit" className="text-button">
                            Duplicate
                          </button>
                        </form>

                        {!template.isDefault ? (
                          <form action={setDefaultPipelineTemplate}>
                            <input
                              type="hidden"
                              name="templateId"
                              value={template.id}
                            />
                            <button type="submit" className="text-button">
                              Make default
                            </button>
                          </form>
                        ) : null}

                        {!template.isDefault ? (
                          <form action={archivePipelineTemplate}>
                            <input
                              type="hidden"
                              name="templateId"
                              value={template.id}
                            />
                            <button type="submit" className="text-button">
                              Archive
                            </button>
                          </form>
                        ) : null}
                      </>
                    ) : null}

                    {canWrite && template.archivedAt ? (
                      <form action={restorePipelineTemplate}>
                        <input
                          type="hidden"
                          name="templateId"
                          value={template.id}
                        />
                        <button type="submit" className="text-button">
                          Restore
                        </button>
                      </form>
                    ) : null}

                    {canDelete && !template.isDefault ? (
                      <form action={deletePipelineTemplate}>
                        <input
                          type="hidden"
                          name="templateId"
                          value={template.id}
                        />
                        <button type="submit" className="text-button danger">
                          Delete
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
