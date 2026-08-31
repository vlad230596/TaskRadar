export type TaskStatusLike = "pending" | "done" | "blocked";

export interface HasStatus {
  status: TaskStatusLike;
}

/**
 * Computes the `isCurrent` flag for a project's tasks.
 *
 * Semantics: exactly the FIRST task (in the given order, which callers must
 * already have sorted by `position` ascending) whose status is `pending` is
 * current. Tasks with status `done` or `blocked` are transparently skipped
 * while scanning for that first pending task — a blocked/done task ahead of a
 * pending one does not "consume" the current slot, and nothing before the
 * winning task is ever marked current. If no task is `pending`, none are
 * current.
 *
 * Pure function: takes an already-ordered array and returns a new array with
 * `isCurrent` attached, so it can be unit tested without touching the DB.
 */
export function annotateIsCurrent<T extends HasStatus>(
  tasksInPositionOrder: readonly T[],
): (T & { isCurrent: boolean })[] {
  let currentAssigned = false;

  return tasksInPositionOrder.map((task) => {
    if (!currentAssigned && task.status === "pending") {
      currentAssigned = true;
      return { ...task, isCurrent: true };
    }
    return { ...task, isCurrent: false };
  });
}
