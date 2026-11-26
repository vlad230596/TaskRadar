import { TaskStatusLike } from "./isCurrent";

/**
 * A journal row about to be written, without the bits only the database knows
 * (its id, its task, and `at`, which is the transaction's own clock).
 */
export interface TaskEventDraft {
  kind: "created" | "status" | "focused" | "unfocused" | "reopened";
  fromStatus: TaskStatusLike | null;
  toStatus: TaskStatusLike | null;
  /** `focused` / `unfocused`: whose working set (null: the default contour's). */
  contourId?: string | null;
}

/** What a `PATCH /tasks/:id` does beyond writing the fields it was given. */
export interface TaskMovement {
  /** Journal rows to append, in order, inside the same transaction. */
  events: TaskEventDraft[];
  /** Whether this change also takes the task out of the working set. */
  leavesFocus: boolean;
  /**
   * `doneAt` to write: the moment of closing on the way into done, null on
   * the way out, undefined when the task neither enters nor leaves done.
   */
  doneAt?: Date | null;
  /**
   * The way out of done: the task's last closing that still counts must be
   * revoked (`TaskEvent.revokedAt`) -- closed and changed one's mind is not
   * a closing (design/today-history-contract.md).
   */
  revokesClosing: boolean;
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
  before: { status: TaskStatusLike; focusedAt: Date | null; focusContourId?: string | null },
  nextStatus: TaskStatusLike | undefined,
  now: Date = new Date(),
): TaskMovement {
  if (nextStatus === undefined || nextStatus === before.status) {
    return { events: [], leavesFocus: false, revokesClosing: false };
  }

  const events: TaskEventDraft[] = [
    { kind: "status", fromStatus: before.status, toStatus: nextStatus },
  ];

  /*
   * The `unfocused` written on closing says whose set the task left, so that
   * «Вернуть» can put it back there (POST /tasks/:id/reopen). The route
   * stamps both rows with one `at`: that is how reopen tells the exit that
   * belongs to this closing from any earlier one.
   */
  const leavesFocus = nextStatus === "done" && before.focusedAt !== null;
  if (leavesFocus) {
    events.push({
      kind: "unfocused",
      fromStatus: null,
      toStatus: null,
      contourId: before.focusContourId ?? null,
    });
  }

  if (nextStatus === "done") return { events, leavesFocus, doneAt: now, revokesClosing: false };
  if (before.status === "done") return { events, leavesFocus, doneAt: null, revokesClosing: true };
  return { events, leavesFocus, revokesClosing: false };
}

/** What `POST /tasks/:id/reopen` does, decided from the journal. */
export interface ReopenPlan {
  /** The status the task goes back to. */
  status: TaskStatusLike;
  /**
   * The contour whose working set the task goes back into, or null when it
   * was not in one when it was closed (or is in one already).
   */
  refocusContourId: string | null;
  /** `reopened`, then `focused` when it goes back into a set. */
  events: TaskEventDraft[];
}

/**
 * «Вернуть» (design/today-history-contract.md): a task closed by mistake goes
 * back to how it was.
 *
 * - The status it had before its last closing that counts ([closing]); pending
 *   when the journal has none (a task created as done, or closed before the
 *   journal) -- "done" is never the answer, the point is to leave it.
 * - The working set it left with that closing ([exit], the `unfocused`
 *   written in the same transaction), with that row's contour -- or the
 *   default contour ([defaultContourId]) for a row from before contours were
 *   recorded or a contour since deleted. No exit: it was not in a set.
 * - Its place in the project needs nothing: closing never moved it.
 */
export function planReopen(
  task: { focusedAt: Date | null },
  closing: { fromStatus: TaskStatusLike | null } | null,
  exit: { contourId: string | null } | null,
  defaultContourId: string,
): ReopenPlan {
  const from = closing?.fromStatus;
  const status: TaskStatusLike = from === "pending" || from === "blocked" ? from : "pending";
  const refocusContourId =
    exit !== null && task.focusedAt === null ? (exit.contourId ?? defaultContourId) : null;

  const events: TaskEventDraft[] = [{ kind: "reopened", fromStatus: "done", toStatus: status }];
  if (refocusContourId !== null) {
    events.push({ kind: "focused", fromStatus: null, toStatus: null, contourId: refocusContourId });
  }
  return { status, refocusContourId, events };
}
