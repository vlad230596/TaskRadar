import { TaskStatusLike } from "./isCurrent";

/**
 * A journal row about to be written, without the bits only the database knows
 * (its id, its task, and `at`, which is the transaction's own clock).
 */
export interface TaskEventDraft {
  kind: "created" | "status" | "focused" | "unfocused";
  fromStatus: TaskStatusLike | null;
  toStatus: TaskStatusLike | null;
}

/** What a `PATCH /tasks/:id` does beyond writing the fields it was given. */
export interface TaskMovement {
  /** Journal rows to append, in order, inside the same transaction. */
  events: TaskEventDraft[];
  /** Whether this change also takes the task out of the working set. */
  leavesFocus: boolean;
}

/**
 * Decides what a status change has to record, given the task as it stands.
 *
 * Pure, and separate from the route for the reason `isCurrent` is: these are
 * the rules the history mode is built on, and they are worth stating in one
 * place that can be read and tested without a database.
 *
 * THE RULES
 *
 * **A status that did not change records nothing.** The client sends the whole
 * editable shape when the user corrects a title, so `status: "pending"` arrives
 * on a task that is already pending on most edits. Journalling those would fill
 * the "life of this task" section with rows saying nothing happened, and --
 * worse -- `replayStatusTime` would report the task moved when it sat still.
 * Only a real transition is movement.
 *
 * **Finishing a task takes it out of the working set.** The set answers "what
 * am I doing now" (F11), and a done task is not that. The alternative is for
 * the phone to send a second request after "Сделано", which is the same
 * half-done pair the sandbox filing route exists to avoid: pressing done with
 * no signal on the second call leaves a finished task sitting in the set, and
 * the one screen that is supposed to show only live work shows a corpse. The
 * exit is not silent -- it appends `unfocused`, so the journal explains the
 * empty `focusedAt` instead of the task leaving the set for no recorded reason.
 *
 * `blocked` deliberately does NOT leave the set: blocking is usually temporary
 * ("жду кабель, спросить завтра" -- README), and a task you are waiting on is
 * still a task you are working on.
 */
export function planStatusChange(
  before: { status: TaskStatusLike; focusedAt: Date | null },
  nextStatus: TaskStatusLike | undefined,
): TaskMovement {
  if (nextStatus === undefined || nextStatus === before.status) {
    return { events: [], leavesFocus: false };
  }

  const events: TaskEventDraft[] = [
    { kind: "status", fromStatus: before.status, toStatus: nextStatus },
  ];

  const leavesFocus = nextStatus === "done" && before.focusedAt !== null;
  if (leavesFocus) {
    events.push({ kind: "unfocused", fromStatus: null, toStatus: null });
  }

  return { events, leavesFocus };
}
