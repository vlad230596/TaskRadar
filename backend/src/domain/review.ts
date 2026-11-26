import { localDayKey } from "./history";
import { addDays } from "./today";

/*
 * The weekly review and the week bars (design/today-history-contract.md,
 * history-review-decisions.md): when a review is due, what period it covers,
 * whether it is the monthly one, and where the owner's weeks begin.
 *
 * Every function takes the client's `tzOffsetMinutes` (minutes EAST of UTC,
 * as `/history` has always taken it): "Monday 09:00" and "the first review of
 * a new month" are the owner's wall clock and calendar, which the server only
 * knows from the request. Without one (MCP), UTC.
 */

const MINUTE_MS = 60_000;
const DAY_MS = 86_400_000;
const WEEK_MS = 7 * DAY_MS;

/**
 * Reviews were introduced on this day. A user who has never reviewed is due
 * at the first review moment after the later of this and their creation --
 * "after registration or the migration" -- not on the first page load after
 * the release because a Monday 09:00 passed sometime last year.
 */
export const REVIEWS_INTRODUCED_AT = new Date("2026-11-27T00:00:00.000Z");

export interface ReviewSchedule {
  /** 1 = Monday .. 7 = Sunday. */
  reviewWeekday: number;
  /** "HH:MM", the owner's wall clock. */
  reviewTime: string;
}

/** ISO weekday (1 = Monday) of a `YYYY-MM-DD` day. */
function weekdayOf(day: string): number {
  const d = new Date(`${day}T00:00:00.000Z`).getUTCDay();
  return d === 0 ? 7 : d;
}

/** The instant at which the local wall clock reads [day] [time]. */
export function localInstant(day: string, time: string, tzOffsetMinutes: number): Date {
  return new Date(Date.parse(`${day}T${time}:00.000Z`) - tzOffsetMinutes * MINUTE_MS);
}

/** The first moment strictly after [after] that is the review's weekday and time, locally. */
export function nextReviewMoment(after: Date, schedule: ReviewSchedule, tzOffsetMinutes: number): Date {
  const day = localDayKey(after, tzOffsetMinutes);
  const ahead = (schedule.reviewWeekday - weekdayOf(day) + 7) % 7;
  let moment = localInstant(addDays(day, ahead), schedule.reviewTime, tzOffsetMinutes);
  if (moment.getTime() <= after.getTime()) moment = new Date(moment.getTime() + WEEK_MS);
  return moment;
}

export interface ReviewDue {
  /** The review moment has come and no review was made since. */
  due: boolean;
  /**
   * The moment the review falls (or fell) due: the first review moment after
   * the last review. In the past when `due` -- the app can say since when.
   */
  nextAt: Date;
  /** When the last review was finished, or null. */
  lastAt: Date | null;
}

/**
 * `reviewDue` of the contract. Due once the first review moment after the
 * last review (its `periodEnd`) has come; with no review yet, after the later
 * of the user's creation and `REVIEWS_INTRODUCED_AT`. Missing a week does not
 * stack anything up: the review stays due, once, and covers all the time
 * since the last one.
 */
export function reviewDue(
  user: ReviewSchedule & { createdAt: Date },
  lastReview: { periodEnd: Date } | null,
  now: Date,
  tzOffsetMinutes: number,
): ReviewDue {
  const lastAt = lastReview?.periodEnd ?? null;
  const anchor =
    lastAt ??
    new Date(Math.max(user.createdAt.getTime(), REVIEWS_INTRODUCED_AT.getTime()));
  const nextAt = nextReviewMoment(anchor, user, tzOffsetMinutes);
  return { due: nextAt.getTime() <= now.getTime(), nextAt, lastAt };
}

/** `YYYY-MM` of [at] on the owner's calendar. */
export function monthKey(at: Date, tzOffsetMinutes: number): string {
  return localDayKey(at, tzOffsetMinutes).slice(0, 7);
}

export interface ReviewPeriod {
  periodStart: Date;
  periodEnd: Date;
  monthly: boolean;
}

/**
 * What a review finished at [now] covers: from the last review's end (so
 * reviews tile time with no gap -- a skipped week is in the next one) or, for
 * the first review, the week before [now].
 *
 * Monthly: the first review in a new calendar month, by the local date of
 * the period's end -- i.e. the last review was in another month. The very
 * first review is not monthly: there is no earlier review to have been in
 * another month, and its week is all it looks back on.
 */
export function reviewPeriod(
  lastReview: { periodEnd: Date } | null,
  now: Date,
  tzOffsetMinutes: number,
): ReviewPeriod {
  const periodStart = lastReview?.periodEnd ?? new Date(now.getTime() - WEEK_MS);
  const monthly =
    lastReview !== null &&
    monthKey(lastReview.periodEnd, tzOffsetMinutes) !== monthKey(now, tzOffsetMinutes);
  return { periodStart, periodEnd: now, monthly };
}

/**
 * The calendar month before the one [at] falls in, on the owner's calendar:
 * `[start, end)` as instants, and its `YYYY-MM`. What the monthly review's
 * «за месяц» section covers.
 */
export function previousMonth(
  at: Date,
  tzOffsetMinutes: number,
): { month: string; start: Date; end: Date } {
  const [year, month] = monthKey(at, tzOffsetMinutes).split("-").map(Number) as [number, number];
  const prevYear = month === 1 ? year - 1 : year;
  const prevMonth = month === 1 ? 12 : month - 1;
  const pad = (n: number) => String(n).padStart(2, "0");
  const startDay = `${prevYear}-${pad(prevMonth)}-01`;
  const endDay = `${year}-${pad(month)}-01`;
  return {
    month: `${prevYear}-${pad(prevMonth)}`,
    start: localInstant(startDay, "00:00", tzOffsetMinutes),
    end: localInstant(endDay, "00:00", tzOffsetMinutes),
  };
}

/** The Monday (`YYYY-MM-DD`) of the owner's week that [at] falls in. */
export function weekStartOf(at: Date, tzOffsetMinutes: number): string {
  const day = localDayKey(at, tzOffsetMinutes);
  return addDays(day, 1 - weekdayOf(day));
}

export interface WeekRange {
  /** Monday, `YYYY-MM-DD`. */
  start: string;
  from: Date;
  /** Exclusive: the next Monday's local midnight. */
  to: Date;
}

/** The last [weeks] weeks up to and including the current one, newest first. */
export function recentWeeks(now: Date, tzOffsetMinutes: number, weeks: number): WeekRange[] {
  const current = weekStartOf(now, tzOffsetMinutes);
  return Array.from({ length: weeks }, (_, i) => {
    const start = addDays(current, -7 * i);
    return {
      start,
      from: localInstant(start, "00:00", tzOffsetMinutes),
      to: localInstant(addDays(start, 7), "00:00", tzOffsetMinutes),
    };
  });
}

/** Closings per project, most first (then by name): the `byProject` of every count. */
export function countByProject(
  closed: readonly { projectId: string; projectName: string }[],
): { projectId: string; name: string; closed: number }[] {
  const rows = new Map<string, { projectId: string; name: string; closed: number }>();
  for (const one of closed) {
    const row = rows.get(one.projectId) ?? { projectId: one.projectId, name: one.projectName, closed: 0 };
    row.closed += 1;
    rows.set(one.projectId, row);
  }
  return [...rows.values()].sort((a, b) => b.closed - a.closed || a.name.localeCompare(b.name));
}
