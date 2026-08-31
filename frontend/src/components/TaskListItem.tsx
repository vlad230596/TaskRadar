import { useState } from "react";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { api } from "../lib/api";
import type { Task, TaskStatus } from "../lib/types";
import { isReminderDue } from "../lib/reminders";
import "./TaskList.css";

interface TaskListItemProps {
  task: Task;
  onUpdated: (task: Task) => void;
  onDelete: () => void;
}

const STATUS_ORDER: TaskStatus[] = ["pending", "blocked", "done"];

const STATUS_LABEL: Record<TaskStatus, string> = {
  pending: "Ожидает",
  blocked: "Блок",
  done: "Готово",
};

function toDateInputValue(iso: string | null): string {
  return iso ? iso.slice(0, 10) : "";
}

/**
 * One task row on the project detail page: draggable (via the handle, so
 * dragging never fights with clicking into the title/description to edit
 * them), with inline title/description editing and status/remindAt controls.
 *
 * Edits are NOT optimistic: the UI only reflects a change once the server
 * confirms it. That keeps this component simple and safe (no "optimistic
 * update that never reconciles on error" risk) at the cost of a small delay
 * before a status button visually flips. Drag-reorder is the one place that
 * *is* optimistic, handled up in TaskList.
 */
export function TaskListItem({ task, onUpdated, onDelete }: TaskListItemProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: task.id,
  });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  const [editingTitle, setEditingTitle] = useState(false);
  const [titleDraft, setTitleDraft] = useState(task.title);
  const [editingDescription, setEditingDescription] = useState(false);
  const [descriptionDraft, setDescriptionDraft] = useState(task.description ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function patchTask(
    body: Partial<Pick<Task, "title" | "description" | "status" | "remindAt">>,
  ): Promise<boolean> {
    setSaving(true);
    setError(null);
    try {
      const updated = await api.patch<Task>(`/tasks/${task.id}`, body);
      onUpdated(updated);
      return true;
    } catch {
      setError("Не удалось сохранить изменения.");
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function commitTitle() {
    const trimmed = titleDraft.trim();
    if (!trimmed) {
      setTitleDraft(task.title);
      setEditingTitle(false);
      return;
    }
    if (trimmed === task.title) {
      setEditingTitle(false);
      return;
    }
    if (await patchTask({ title: trimmed })) setEditingTitle(false);
  }

  async function commitDescription() {
    const trimmed = descriptionDraft.trim();
    const current = task.description ?? "";
    if (trimmed === current) {
      setEditingDescription(false);
      return;
    }
    if (await patchTask({ description: trimmed || null })) setEditingDescription(false);
  }

  async function handleStatusChange(status: TaskStatus) {
    if (status === task.status) return;
    const body: Partial<Pick<Task, "status" | "remindAt">> = { status };
    // Deliberate choice: leaving "blocked" clears any reminder date. A
    // remindAt only makes sense while the task is actually blocked; keeping
    // a stale date around invisibly (it's hidden once status != blocked)
    // would silently resurface an old reminder if the task is blocked again
    // later without the user noticing it was never cleared.
    if (status !== "blocked") body.remindAt = null;
    await patchTask(body);
  }

  async function handleRemindAtChange(value: string) {
    await patchTask({ remindAt: value ? value : null });
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`task-item${isDragging ? " task-item--dragging" : ""}${
        task.isCurrent ? " task-item--current" : ""
      }`}
    >
      <button
        className="task-item__handle"
        type="button"
        aria-label="Перетащить задачу"
        {...attributes}
        {...listeners}
      >
        ⠿
      </button>

      <div className="task-item__body">
        <div className="task-item__row">
          {editingTitle ? (
            <input
              className="task-item__title-input"
              value={titleDraft}
              autoFocus
              disabled={saving}
              onChange={(event) => setTitleDraft(event.target.value)}
              onBlur={() => void commitTitle()}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                  void commitTitle();
                }
                if (event.key === "Escape") {
                  setTitleDraft(task.title);
                  setEditingTitle(false);
                }
              }}
            />
          ) : (
            <span
              className="task-item__title"
              onClick={() => {
                setTitleDraft(task.title);
                setEditingTitle(true);
              }}
              title="Нажмите, чтобы изменить"
            >
              {task.title}
            </span>
          )}

          <div className="task-item__status-group">
            {STATUS_ORDER.map((status) => (
              <button
                key={status}
                type="button"
                className={`task-item__status-btn task-item__status-btn--${status}${
                  task.status === status ? " task-item__status-btn--active" : ""
                }`}
                disabled={saving}
                onClick={() => void handleStatusChange(status)}
              >
                {STATUS_LABEL[status]}
              </button>
            ))}
          </div>

          <button className="task-item__delete" type="button" onClick={onDelete} aria-label="Удалить задачу">
            ✕
          </button>
        </div>

        {task.status === "blocked" && (
          <label
            className={`task-item__reminder${
              task.remindAt && isReminderDue(task.remindAt) ? " task-item__reminder--due" : ""
            }`}
          >
            {task.remindAt && isReminderDue(task.remindAt) ? "❗ Напомнить:" : "Напомнить:"}
            <input
              type="date"
              value={toDateInputValue(task.remindAt)}
              disabled={saving}
              onChange={(event) => void handleRemindAtChange(event.target.value)}
            />
          </label>
        )}

        {editingDescription ? (
          <textarea
            className="task-item__description-input"
            value={descriptionDraft}
            autoFocus
            disabled={saving}
            onChange={(event) => setDescriptionDraft(event.target.value)}
            onBlur={() => void commitDescription()}
            onKeyDown={(event) => {
              if (event.key === "Escape") {
                setDescriptionDraft(task.description ?? "");
                setEditingDescription(false);
              }
            }}
          />
        ) : task.description ? (
          <p
            className="task-item__description"
            onClick={() => {
              setDescriptionDraft(task.description ?? "");
              setEditingDescription(true);
            }}
          >
            {task.description}
          </p>
        ) : (
          <button
            className="task-item__add-description"
            type="button"
            onClick={() => {
              setDescriptionDraft("");
              setEditingDescription(true);
            }}
          >
            + описание
          </button>
        )}

        {error && <p className="task-item__error">{error}</p>}
      </div>
    </div>
  );
}
