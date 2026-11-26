import { localDayKey } from "./history";
import type { TaskStatusLike } from "./isCurrent";

/*
 * «Сегодня», «С прошлых дней» and «Позже» (design/today-history-contract.md).
 *
 * A task's date (`remindAt`, a calendar day stored as UTC midnight, plus an
 * optional `remindTime`) now means "when the owner will get to it". Three
 * lists fall out of comparing it with today -- the owner's local today:
 *
 * - today: open (pending or blocked) and dated today;
 * - the tail («С прошлых дней»): open and dated before today. Nothing moves
 *   on by itself; a task stays in the tail until the owner sorts it out;
 * - later («Позже»): open and dated beyond today + the owner's horizon. Such
 *   a task is folded at the bottom of its project, and it is never the
 *   current task nor a goal's next step -- it is not for now.
 *
 * Days are compared as `YYYY-MM-DD` strings, which order like the dates they
 * name. The app runs the same rules on its cache offline; these are the
 * reference.
 */

const DAY_MS = 86_400_000;

/** `User.laterHorizonDays` by default: the horizon a user who never set one has. */
export const DEFAULT_LATER_HORIZON_DAYS = 10;

/** The calendar day a stored date names (its `YYYY-MM-DD` prefix), or null. */
export function dayOf(date: Date | null | undefined): string | null {
  return date ? date.toISOString().slice(0, 10) : null;
}

/** [day] plus [days] calendar days. */
export function addDays(day: string, days: number): string {
  return new Date(Date.parse(`${day}T00:00:00.000Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

/** The owner's today at [now], for a client [tzOffsetMinutes] east of UTC. */
export function localToday(now: Date, tzOffsetMinutes = 0): string {
  return localDayKey(now, tzOffsetMinutes);
}

export interface DatedTaskLike {
  status: TaskStatusLike;
  remindAt: Date | null;
}

/** «Позже»: open, and dated after [today] + [horizonDays]. */
export function isLater(task: DatedTaskLike, today: string, horizonDays: number): boolean {
  const day = dayOf(task.remindAt);
  return task.status !== "done" && day !== null && day > addDays(today, horizonDays);
}

/** What [isLater] needs to know besides the task. */
export interface LaterRule {
  today: string;
  horizonDays: number;
}

export interface TodayTaskLike extends DatedTaskLike {
  remindTime: string | null;
  doneAt: Date | null;
  position: number;
}

export interface TodayView<T> {
  /** The owner's today, `YYYY-MM-DD`. */
  date: string;
  /** Open, dated today: timed ones first by time, then the rest in board order. */
  today: T[];
  /** Closed today (local day of `doneAt`), dated today or earlier; by `doneAt`. */
  doneToday: T[];
  /** Open, dated before today; oldest date first, then board order. */
  tail: T[];
}

/**
 * The three lists of the «Работа» screen's day block.
 *
 * [boardOrder] is where tasks of one day go relative to each other -- scope,
 * then project, then position, as the board draws them. It is the caller's,
 * because only the caller knows the scopes' and projects' order; by default
 * just `position`.
 *
 * `doneToday` asks for `doneAt` on the local [today] (closing at 00:30 counts
 * for the day it happened in the owner's zone, hence [tzOffsetMinutes]) and a
 * date no later than today -- a task dated next week and closed early is not
 * part of today's «N из M».
 */
export function todayView<T extends TodayTaskLike>(
  tasks: readonly T[],
  today: string,
  tzOffsetMinutes = 0,
  boardOrder: (a: T, b: T) => number = (a, b) => a.position - b.position,
): TodayView<T> {
  const dueToday: T[] = [];
  const doneToday: T[] = [];
  const tail: T[] = [];

  for (const task of tasks) {
    const day = dayOf(task.remindAt);
    if (day === null) continue;
    if (task.status === "done") {
      if (
        task.doneAt !== null &&
        day <= today &&
        localDayKey(task.doneAt, tzOffsetMinutes) === today
      ) {
        doneToday.push(task);
      }
    } else if (day === today) {
      dueToday.push(task);
    } else if (day < today) {
      tail.push(task);
    }
  }

  dueToday.sort((a, b) => {
    if (a.remindTime !== null && b.remindTime !== null) {
      return a.remindTime.localeCompare(b.remindTime) || boardOrder(a, b);
    }
    if (a.remindTime !== null) return -1;
    if (b.remindTime !== null) return 1;
    return boardOrder(a, b);
  });
  doneToday.sort((a, b) => a.doneAt!.getTime() - b.doneAt!.getTime());
  tail.sort((a, b) => dayOf(a.remindAt)!.localeCompare(dayOf(b.remindAt)!) || boardOrder(a, b));

  return { date: today, today: dueToday, doneToday, tail };
}
