import type { TaskStatusLike } from "./isCurrent";

/*
 * A project's rhythm (design/today-history-contract.md, решение 7 в
 * history-review-decisions.md): two optional numbers the owner sets on a
 * project -- "at least N closed a week" and "at most M open" -- and a muted
 * label on the planning board when the project is off them. Counts only:
 * tasks have no sizes. No red, no pushes; what to do about it is decided at
 * the review.
 *
 * Closings are read from `Task.doneAt`, which holds exactly the closings that
 * still count (a closing taken back clears it; see the model) -- so the rhythm
 * agrees with «Сделано» by construction.
 */

const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;

/** How far back the closing average looks: two weeks, averaged per week. */
export const RHYTHM_WINDOW_DAYS = 14;

export interface RhythmSettings {
  rhythmClosedPerWeek: number | null;
  rhythmMaxOpen: number | null;
  createdAt: Date;
}

export interface RhythmStats {
  /** Closings (that count) within the last `RHYTHM_WINDOW_DAYS`. */
  closedInWindow: number;
  /** Pending + blocked. */
  open: number;
  /** The latest closing that counts, ever. */
  lastClosedAt: Date | null;
}

export type RhythmSignal = "silence" | "overflow";

export interface Rhythm {
  closedPerWeek: number | null;
  maxOpen: number | null;
  closedAvg: number;
  open: number;
  lastClosedAt: Date | null;
  silentWeeks: number;
  signal: RhythmSignal | null;
}

/** The numbers [computeRhythm] needs, from a project's tasks as they stand. */
export function rhythmStats(
  tasks: readonly { status: TaskStatusLike; doneAt: Date | null }[],
  now: Date,
): RhythmStats {
  const windowStart = now.getTime() - RHYTHM_WINDOW_DAYS * DAY_MS;
  let closedInWindow = 0;
  let open = 0;
  let lastClosedAt: Date | null = null;
  for (const task of tasks) {
    if (task.status !== "done") {
      open += 1;
      continue;
    }
    if (task.doneAt == null) continue;
    if (task.doneAt.getTime() >= windowStart && task.doneAt.getTime() <= now.getTime()) {
      closedInWindow += 1;
    }
    if (lastClosedAt === null || task.doneAt.getTime() > lastClosedAt.getTime()) {
      lastClosedAt = task.doneAt;
    }
  }
  return { closedInWindow, open, lastClosedAt };
}

/**
 * The project's `rhythm`, or null when it has none (neither number set).
 *
 * - `closedAvg`: closings of the last two weeks per week;
 * - `silentWeeks`: whole weeks since the last closing -- or since the project
 *   was created, when nothing in it was ever closed;
 * - `signal`: `overflow` when more are open than the ceiling, else `silence`
 *   when the average is under the norm, else null. Overflow wins when both
 *   hold: a project drowning in tasks is the louder problem, and the review
 *   step offers "почистить" for it.
 */
export function computeRhythm(project: RhythmSettings, stats: RhythmStats, now: Date): Rhythm | null {
  // `?? null`: a row read without the columns (an older shape) has no rhythm.
  const closedPerWeek = project.rhythmClosedPerWeek ?? null;
  const maxOpen = project.rhythmMaxOpen ?? null;
  if (closedPerWeek === null && maxOpen === null) return null;

  const closedAvg = stats.closedInWindow / (RHYTHM_WINDOW_DAYS / 7);
  const since = stats.lastClosedAt ?? project.createdAt;
  const silentWeeks = Math.max(0, Math.floor((now.getTime() - since.getTime()) / WEEK_MS));

  let signal: RhythmSignal | null = null;
  if (maxOpen !== null && stats.open > maxOpen) signal = "overflow";
  else if (closedPerWeek !== null && closedAvg < closedPerWeek) signal = "silence";

  return {
    closedPerWeek,
    maxOpen,
    closedAvg,
    open: stats.open,
    lastClosedAt: stats.lastClosedAt,
    silentWeeks,
    signal,
  };
}
