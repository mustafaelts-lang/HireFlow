"use client";

import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  type DragEndEvent,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

import {
  STAGE_CATEGORIES,
  STAGE_CATEGORY_LABELS,
  STAGE_COLOR_PRESETS,
  slugifyStageKey,
  type PipelineTemplateStageInput,
  type StageCategory,
} from "@/lib/pipelines/types";

type StageEditorProps = {
  stages: PipelineTemplateStageInput[];
  onChange: (stages: PipelineTemplateStageInput[]) => void;
  readOnly?: boolean;
};

function SortableStageRow({
  stage,
  index,
  readOnly,
  onChange,
  onRemove,
}: {
  stage: PipelineTemplateStageInput;
  index: number;
  readOnly?: boolean;
  onChange: (next: PipelineTemplateStageInput) => void;
  onRemove: () => void;
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: stage.key || `stage-${index}`, disabled: readOnly });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.7 : 1,
  };

  return (
    <div ref={setNodeRef} style={style} className="stage-row">
      <button
        type="button"
        className="stage-handle"
        aria-label="Drag to reorder"
        disabled={readOnly}
        {...attributes}
        {...listeners}
      >
        ⋮⋮
      </button>

      <div
        className="stage-swatch"
        style={{ background: stage.color }}
        aria-hidden
      />

      <div className="stage-fields">
        <label className="auth-field">
          <span>Name</span>
          <input
            value={stage.name}
            disabled={readOnly}
            onChange={(event) => {
              const name = event.target.value;
              onChange({
                ...stage,
                name,
                key: stage.id ? stage.key : slugifyStageKey(name),
              });
            }}
          />
        </label>

        <label className="auth-field">
          <span>Category</span>
          <select
            value={stage.category}
            disabled={readOnly}
            onChange={(event) =>
              onChange({
                ...stage,
                category: event.target.value as StageCategory,
              })
            }
          >
            {STAGE_CATEGORIES.map((category) => (
              <option key={category} value={category}>
                {STAGE_CATEGORY_LABELS[category]}
              </option>
            ))}
          </select>
        </label>

        <label className="auth-field">
          <span>Color</span>
          <div className="color-row">
            <input
              type="color"
              value={stage.color}
              disabled={readOnly}
              onChange={(event) =>
                onChange({ ...stage, color: event.target.value.toUpperCase() })
              }
            />
            <select
              value={
                (STAGE_COLOR_PRESETS as readonly string[]).includes(stage.color)
                  ? stage.color
                  : ""
              }
              disabled={readOnly}
              onChange={(event) => {
                if (event.target.value) {
                  onChange({ ...stage, color: event.target.value });
                }
              }}
            >
              <option value="">Custom</option>
              {STAGE_COLOR_PRESETS.map((color) => (
                <option key={color} value={color}>
                  {color}
                </option>
              ))}
            </select>
          </div>
        </label>

        <label className="auth-field">
          <span>SLA (days)</span>
          <input
            type="number"
            min={0}
            value={stage.slaDays ?? ""}
            disabled={readOnly}
            placeholder="Optional"
            onChange={(event) =>
              onChange({
                ...stage,
                slaDays:
                  event.target.value === "" ? null : Number(event.target.value),
              })
            }
          />
        </label>

        <label className="auth-field stage-notes">
          <span>Notes</span>
          <input
            value={stage.notes}
            disabled={readOnly}
            placeholder="Internal guidance"
            onChange={(event) =>
              onChange({ ...stage, notes: event.target.value })
            }
          />
        </label>

        <label className="auth-field">
          <span>Applied entry</span>
          <input
            type="radio"
            name="applied-entry-stage"
            checked={Boolean(stage.isAppliedEntry)}
            disabled={readOnly}
            onChange={() => onChange({ ...stage, isAppliedEntry: true })}
          />
        </label>
      </div>

      {!readOnly ? (
        <button type="button" className="text-button danger" onClick={onRemove}>
          Remove
        </button>
      ) : null}
    </div>
  );
}

export function StageEditor({ stages, onChange, readOnly }: StageEditorProps) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) {
      return;
    }
    const oldIndex = stages.findIndex(
      (stage, index) => (stage.key || `stage-${index}`) === active.id,
    );
    const newIndex = stages.findIndex(
      (stage, index) => (stage.key || `stage-${index}`) === over.id,
    );
    if (oldIndex < 0 || newIndex < 0) {
      return;
    }
    onChange(
      arrayMove(stages, oldIndex, newIndex).map((stage, index) => ({
        ...stage,
        sortOrder: index + 1,
      })),
    );
  }

  function addStage() {
    const nextOrder = stages.length + 1;
    onChange([
      ...stages,
      {
        key: `stage_${nextOrder}_${Date.now().toString(36)}`,
        name: `Stage ${nextOrder}`,
        sortOrder: nextOrder,
        color: STAGE_COLOR_PRESETS[nextOrder % STAGE_COLOR_PRESETS.length],
        slaDays: null,
        category: "custom",
        notes: "",
        isAppliedEntry: false,
      },
    ]);
  }

  return (
    <div className="stage-editor">
      <div className="stage-editor-header">
        <h2>Stages</h2>
        {!readOnly ? (
          <button type="button" className="secondary-button" onClick={addStage}>
            Add stage
          </button>
        ) : null}
      </div>

      <DndContext
        sensors={sensors}
        collisionDetection={closestCenter}
        onDragEnd={handleDragEnd}
      >
        <SortableContext
          items={stages.map((stage, index) => stage.key || `stage-${index}`)}
          strategy={verticalListSortingStrategy}
        >
          <div className="stage-list">
            {stages.map((stage, index) => (
              <SortableStageRow
                key={stage.key || `stage-${index}`}
                stage={stage}
                index={index}
                readOnly={readOnly}
                onChange={(next) => {
                  if (next.isAppliedEntry) {
                    onChange(
                      stages.map((item, itemIndex) =>
                        itemIndex === index
                          ? next
                          : { ...item, isAppliedEntry: false },
                      ),
                    );
                    return;
                  }
                  const copy = [...stages];
                  copy[index] = next;
                  onChange(copy);
                }}
                onRemove={() =>
                  onChange(stages.filter((_, itemIndex) => itemIndex !== index))
                }
              />
            ))}
          </div>
        </SortableContext>
      </DndContext>
    </div>
  );
}
