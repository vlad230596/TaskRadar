import { isLater, LaterRule } from "./today";

export type TaskStatusLike = "pending" | "done" | "blocked";

export interface HasStatus {
  status: TaskStatusLike;
  /** The task's date; read only when a [LaterRule] is given. */
  remindAt?: Date | null;
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
 * «Позже» (design/today-history-contract.md) is skipped the same way when
 * [later] is given: a task dated beyond the owner's horizon is not for now, so
 * it does not hold the slot of the task that is. If every pending task is
 * «Позже», none is current. The server's "today" for this is UTC (these
 * routes carry no zone); at the horizon's edge that can be a day off, which
 * the contract accepts.
 *
 * Pure function: takes an already-ordered array and returns a new array with
 * `isCurrent` attached, so it can be unit tested without touching the DB.
 */
export function annotateIsCurrent<T extends HasStatus>(
  tasksInPositionOrder: readonly T[],
  later?: LaterRule,
): (T & { isCurrent: boolean })[] {
  let currentAssigned = false;
  const notLater = (task: T) =>
    later === undefined ||
    !isLater({ status: task.status, remindAt: task.remindAt ?? null }, later.today, later.horizonDays);

  return tasksInPositionOrder.map((task) => {
    if (!currentAssigned && task.status === "pending" && notLater(task)) {
      currentAssigned = true;
      return { ...task, isCurrent: true };
    }
    return { ...task, isCurrent: false };
  });
}
