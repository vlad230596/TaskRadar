import { useState, type FormEvent } from "react";
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, arrayMove, sortableKeyboardCoordinates, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { api } from "../lib/api";
import type { Task } from "../lib/types";
import { TaskListItem } from "./TaskListItem";
import "./TaskList.css";

interface TaskListProps {
  projectId: string;
  tasks: Task[];
  onTasksChange: (tasks: Task[]) => void;
}

export function TaskList({ projectId, tasks, onTasksChange }: TaskListProps) {
  const [newTitle, setNewTitle] = useState("");
  const [adding, setAdding] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  // Touch/pointer setup for drag-and-drop reordering, reasoned from dnd-kit's
  // docs (no physical touchscreen available to test this on):
  //
  // - PointerSensor alone (not PointerSensor + TouchSensor) is dnd-kit's own
  //   recommendation once you're using it: the two sensors independently
  //   attach listeners for what's substantially the same events on modern
  //   browsers, and combining them is called out in dnd-kit's docs/issues as
  //   a source of double drag-starts. PointerSensor already receives touch
  //   input via the Pointer Events spec.
  // - The activation `distance` threshold is what stops an ordinary tap
  //   (status button, title-edit, etc.) from being misread as a drag -- but
  //   it only matters here because dragging is scoped to a dedicated handle
  //   (`task-item__handle`) with `touch-action: none`, not the whole row.
  //   That scoping is what makes a *small* distance threshold safe on touch:
  //   the browser still owns scrolling everywhere else on the card, so there
  //   is no swipe-to-scroll-vs-drag ambiguity for the sensor to resolve.
  // - Raised from 4px to 8px specifically for touch: a finger's contact
  //   point wobbles more than a mouse cursor between touchstart and the
  //   first touchmove, so 4px risked the handle occasionally starting a
  //   drag on what was meant as a plain press. 8px is dnd-kit's own example
  //   default and still reads as instant, not delayed, for mouse users.
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  async function handleAdd(event: FormEvent) {
    event.preventDefault();
    const title = newTitle.trim();
    if (!title) return;
    setAdding(true);
    setAddError(null);
    try {
      const task = await api.post<Task>(`/projects/${projectId}/tasks`, { title });
      onTasksChange([...tasks, task]);
      setNewTitle("");
    } catch {
      setAddError("Не удалось добавить задачу.");
    } finally {
      setAdding(false);
    }
  }

  function handleUpdated(updated: Task) {
    onTasksChange(tasks.map((task) => (task.id === updated.id ? updated : task)));
  }

  async function handleDelete(taskId: string) {
    if (!window.confirm("Удалить задачу без возможности восстановления?")) return;
    try {
      await api.delete(`/tasks/${taskId}`);
      onTasksChange(tasks.filter((task) => task.id !== taskId));
    } catch {
      setActionError("Не удалось удалить задачу.");
    }
  }

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = tasks.findIndex((task) => task.id === active.id);
    const newIndex = tasks.findIndex((task) => task.id === over.id);
    if (oldIndex === -1 || newIndex === -1) return;

    // Optimistic: reorder locally right away so the drag feels instant, then
    // ask the server to persist the same neighbours. If that request fails,
    // refetch from the server so the list never keeps showing an order the
    // backend didn't actually accept.
    const reordered = arrayMove(tasks, oldIndex, newIndex);
    onTasksChange(reordered);
    setActionError(null);

    const movedId = String(active.id);
    const beforeTaskId = reordered[newIndex - 1]?.id ?? null;
    const afterTaskId = reordered[newIndex + 1]?.id ?? null;

    api
      .patch<Task>(`/tasks/${movedId}/position`, { beforeTaskId, afterTaskId })
      .catch(async () => {
        setActionError("Не удалось сохранить новый порядок задач — список обновлён с сервера.");
        try {
          const fresh = await api.get<Task[]>(`/projects/${projectId}/tasks`);
          onTasksChange(fresh);
        } catch {
          // Couldn't even refetch; the banner above already explains the
          // order on screen may be stale.
        }
      });
  }

  return (
    <div className="task-list">
      <form className="task-list__add" onSubmit={(event) => void handleAdd(event)}>
        <input
          type="text"
          placeholder="Новая задача…"
          value={newTitle}
          onChange={(event) => setNewTitle(event.target.value)}
          disabled={adding}
        />
        <button type="submit" disabled={adding || !newTitle.trim()}>
          Добавить
        </button>
      </form>

      {addError && <p className="task-list__error">{addError}</p>}
      {actionError && <p className="task-list__error">{actionError}</p>}

      {tasks.length === 0 ? (
        <p className="task-list__empty">Задач пока нет.</p>
      ) : (
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={tasks.map((task) => task.id)} strategy={verticalListSortingStrategy}>
            <div className="task-list__items">
              {tasks.map((task) => (
                <TaskListItem
                  key={task.id}
                  task={task}
                  onUpdated={handleUpdated}
                  onDelete={() => void handleDelete(task.id)}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      )}
    </div>
  );
}
