"use client";

import { useActionState, useState } from "react";
import Link from "next/link";

import {
  createPipelineTemplate,
  updatePipelineTemplate,
  type PipelineActionState,
} from "@/actions/pipelines";
import { StageEditor } from "@/components/pipelines/stage-editor";
import type { PipelineTemplateStageInput } from "@/lib/pipelines/types";
import { STAGE_COLOR_PRESETS } from "@/lib/pipelines/types";

const initialState: PipelineActionState = {};

const DEFAULT_STAGES: PipelineTemplateStageInput[] = [
  {
    key: "applied",
    name: "Applied",
    sortOrder: 1,
    color: STAGE_COLOR_PRESETS[0],
    slaDays: 2,
    category: "intake",
    notes: "",
  },
  {
    key: "cv_screening",
    name: "CV Screening",
    sortOrder: 2,
    color: STAGE_COLOR_PRESETS[1],
    slaDays: 3,
    category: "screening",
    notes: "",
  },
  {
    key: "interview",
    name: "Interview",
    sortOrder: 3,
    color: STAGE_COLOR_PRESETS[3],
    slaDays: 7,
    category: "interview",
    notes: "",
  },
  {
    key: "offer",
    name: "Offer",
    sortOrder: 4,
    color: STAGE_COLOR_PRESETS[5],
    slaDays: 5,
    category: "offer",
    notes: "",
  },
  {
    key: "hired",
    name: "Hired",
    sortOrder: 5,
    color: STAGE_COLOR_PRESETS[7],
    slaDays: null,
    category: "hired",
    notes: "",
  },
];

type TemplateFormProps = {
  mode: "create" | "edit";
  templateId?: string;
  initialName?: string;
  initialDescription?: string;
  initialIsDefault?: boolean;
  initialStages?: PipelineTemplateStageInput[];
  readOnly?: boolean;
};

export function TemplateForm({
  mode,
  templateId,
  initialName = "",
  initialDescription = "",
  initialIsDefault = false,
  initialStages,
  readOnly = false,
}: TemplateFormProps) {
  const action =
    mode === "create" ? createPipelineTemplate : updatePipelineTemplate;
  const [state, formAction, pending] = useActionState(action, initialState);
  const [stages, setStages] = useState<PipelineTemplateStageInput[]>(
    initialStages ?? DEFAULT_STAGES,
  );

  return (
    <form action={formAction} className="template-form">
      {templateId ? (
        <input type="hidden" name="templateId" value={templateId} />
      ) : null}
      <input type="hidden" name="stages" value={JSON.stringify(stages)} />

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
          <h1>{mode === "create" ? "Create template" : "Edit template"}</h1>
          <Link href="/pipelines" className="auth-link">
            Back to templates
          </Link>
        </div>

        <div className="settings-form">
          <label className="auth-field">
            <span>Name</span>
            <input
              name="name"
              defaultValue={initialName}
              required
              disabled={readOnly}
              placeholder="Engineering hiring pipeline"
            />
          </label>

          <label className="auth-field">
            <span>Description</span>
            <textarea
              name="description"
              defaultValue={initialDescription}
              disabled={readOnly}
              rows={3}
              placeholder="When to use this pipeline"
            />
          </label>

          <label className="checkbox-field">
            <input
              type="checkbox"
              name="isDefault"
              defaultChecked={initialIsDefault}
              disabled={readOnly}
            />
            <span>Set as organization default template</span>
          </label>
        </div>
      </section>

      <section className="app-panel">
        <StageEditor stages={stages} onChange={setStages} readOnly={readOnly} />
      </section>

      {!readOnly ? (
        <div className="form-actions">
          <button type="submit" className="auth-button" disabled={pending}>
            {pending
              ? "Saving…"
              : mode === "create"
                ? "Create template"
                : "Save changes"}
          </button>
        </div>
      ) : null}
    </form>
  );
}
