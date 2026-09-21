import { TaskStatusLike } from "./isCurrent";

/*
 * The arithmetic behind the history mode (F11).
 *
 * WHY THE SERVER COUNTS AND NOT THE CLIENT
 *
 * The history screen shows three numbers-shaped things -- closings per day, the
 * tasks that have hung longest, and what moved in each project -- and every one
 * of them is a fold over the journal. The obvious alternative, shipping the
 * journal to the client and folding it there, gets worse every week the tool is
 * used: the phone would download every transition ever recorded to draw seven
 * bars. So the aggregates are computed here and the wire carries the answers.
 *
 * Everything in this file is pure and takes rows that have already been read,
 * which is what lets the route be a query plus a call and the tests be a table
 * of dates rather than a database.
 */

const DAY_MS = 86_400_000;

/** The ranges the history screen offers: a week, a month, everything. */
export const HISTORY_RANGES = ["7d", "30d", "all"] as const;
export type HistoryRange = (typeof HISTORY_RANGES)[number];

/**
 * The first instant included in a range, or `null` for "all" -- which is not a
 * date at all and must not be turned into one here, because the earliest thing
 * the journal holds is a fact about the data, not about the request.
 */
export function historyRangeStart(
  range: HistoryRange,
  now: Date,
  tzOffsetMinutes: number,
): Date | null {
  if (range === "all") return null;
  const days = range === "7d" ? 7 : 30;
  // Midnight of the local day `days - 1` days back -- not "now minus N×24h".
  // The difference is the first bar: an instant-based cut-off drops everything
  // closed earlier that morning, so the leftmost column is a stump whose height
  // depends on what time of day the screen was opened.
  const startIndex = dayIndex(now, tzOffsetMinutes) - (days - 1);
  return new Date(startIndex * DAY_MS - tzOffsetMinutes * 60_000);
}

/**
 * Which local day a timestamp falls on, as `YYYY-MM-DD`.
 *
 * `tzOffsetMinutes` is the client's own offset, sent with the request, and that
 * is the only workable answer to a question this product cannot dodge: a task
 * closed at 01:00 in Moscow belongs to that day on the screen, not to the
 * previous one because the server stores UTC. Storing the offset alongside each
 * event would be more precise across a move between timezones, and is not worth
 * a column -- the bars are read as "my week", and "my week" is the week of
 * wherever the person is standing when they look.
 */
export function localDayKey(at: Date, tzOffsetMinutes: number): string {
  return new Date(dayIndex(at, tzOffsetMinutes) * DAY_MS).toISOString().slice(0, 10);
}

function dayIndex(at: Date, tzOffsetMinutes: number): number {
  return Math.floor((at.getTime() + tzOffsetMinutes * 60_000) / DAY_MS);
}

export interface DayCount {
  /** `YYYY-MM-DD` in the client's timezone. */
  date: string;
  count: number;
}

/**
 * Counts timestamps per local day, oldest first.
 *
 * `from` non-null fills in the days nothing happened on, up to `to`. That is
 * the difference between a bar chart and a list: a week with two closings has
 * to draw five empty columns, and a client that has to invent the gaps itself
 * is a client that will get the timezone boundary wrong differently than the
 * server did.
 *
 * `from` null (the "all" range) returns only the days that have something on
 * them. A zero-filled axis from the first closing to today is mostly emptiness
 * and grows forever, and the screen that wants contiguous bars is the week.
 */
export function countByDay(
  timestamps: readonly Date[],
  tzOffsetMinutes: number,
  from: Date | null,
  to: Date,
): DayCount[] {
  const counts = new Map<string, number>();
  for (const at of timestamps) {
    const key = localDayKey(at, tzOffsetMinutes);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }

  if (from === null) {
    return [...counts.entries()]
      .map(([date, count]) => ({ date, count }))
      .sort((a, b) => a.date.localeCompare(b.date));
  }

  const days: DayCount[] = [];
  for (let index = dayIndex(from, tzOffsetMinutes); index <= dayIndex(to, tzOffsetMinutes); index++) {
    const date = new Date(index * DAY_MS).toISOString().slice(0, 10);
    days.push({ date, count: counts.get(date) ?? 0 });
  }
  return days;
}

/** Milliseconds spent in each status. Every status is present, zero included. */
export interface StatusSpans {
  pending: number;
  done: number;
  blocked: number;
}

/** The shape `replayStatusTime` needs from a journal row. */
export interface StatusEventLike {
  kind: "created" | "status" | "focused" | "unfocused";
  toStatus: TaskStatusLike | null;
  at: Date;
}

/**
 * Replays a task's journal into "how long it has spent in each status".
 *
 * This is the whole reason `task_events` exists: it is the one question
 * `tasks.updatedAt` structurally cannot answer, because the eleven days a task
 * spent blocked stop existing the moment it stops being blocked.
 *
 * `events` must be in ascending `at` order (the `[taskId, at]` index is what
 * makes that cheap). Focus events are walked past: entering the working set is
 * not a change of status, and treating it as one would make picking a task up
 * look like a transition on the chart.
 *
 * TOTAL BY CONSTRUCTION, and deliberately so. A journal with nothing usable in
 * it -- which is what a task carried over from before this table existed would
 * have, had the migration not backfilled -- attributes the task's whole life so
 * far to the status it has now, starting at `createdAt`. That is the same
 * approximation the backfill makes, and it means no caller ever has to handle
 * "this task has no history": the worst case is a first interval longer than it
 * really was, not a hole.
 */
export function replayStatusTime(
  task: { createdAt: Date; status: TaskStatusLike },
  events: readonly StatusEventLike[],
  now: Date,
): { byStatus: StatusSpans; currentSince: Date } {
  const byStatus: StatusSpans = { pending: 0, done: 0, blocked: 0 };

  let status: TaskStatusLike | null = null;
  let since = task.createdAt;

  for (const event of events) {
    if (event.kind !== "created" && event.kind !== "status") continue;
    if (event.toStatus === null) continue;

    if (status !== null) {
      byStatus[status] += Math.max(0, event.at.getTime() - since.getTime());
    }
    status = event.toStatus;
    since = event.at;
  }

  // The open interval: from the last transition to now. The journal's final
  // status and the task row's agree by construction -- every route that writes
  // one writes the other, in one transaction -- so this only has to choose when
  // the journal says nothing at all, and then the row is all there is.
  byStatus[status ?? task.status] += Math.max(0, now.getTime() - since.getTime());

  return { byStatus, currentSince: since };
}
