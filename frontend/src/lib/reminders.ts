// Helpers for the `blocked` task reminder date (see README: "у задачи
// блокера... поставить, когда её стоит напомнить"). `remindAt` is a
// day-granularity value -- it's set via a plain <input type="date"> (see
// TaskListItem's toDateInputValue) and there's no meaningful time-of-day
// component to it at all.
//
// It still travels over the wire as a full ISO timestamp though (the date
// input's "YYYY-MM-DD" value round-trips through the backend as UTC midnight
// of that calendar date). That matters for comparing it to "today":
// constructing `new Date(remindAt)` and reading back local getDate()/
// getMonth() would shift the *effective* calendar date backward or forward
// depending on the viewer's timezone offset relative to UTC (e.g. a stored
// "2026-08-18T00:00:00.000Z" reads back as 2026-08-17 in any timezone west
// of UTC). Comparing raw timestamps has the same problem in the other
// direction: a remindAt of 2026-08-18T23:00:00Z is chronologically "in the
// future" versus a "now" of 2026-08-18T08:00:00Z by 15 hours, but it's the
// same calendar day and should already read as due.
//
// So we sidestep both traps: take the YYYY-MM-DD prefix of the ISO string
// as-is (that's exactly the calendar date the user picked, regardless of
// timezone, since it was UTC midnight of that date), and compare it as a
// string against "today" computed from *local* wall-clock date parts (since
// "today" means the user's actual today, not UTC's).

function isoDatePart(iso: string): string {
  return iso.slice(0, 10);
}

function todayDatePart(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/**
 * True once the reminder's calendar date has arrived or passed -- a
 * reminder dated exactly today counts as due, not just strictly-past ones.
 */
export function isReminderDue(remindAtIso: string): boolean {
  return isoDatePart(remindAtIso) <= todayDatePart();
}

/** Formats a remindAt as "DD.MM", matching the rest of the app's date display. */
export function formatReminderDate(remindAtIso: string): string {
  const [, month, day] = isoDatePart(remindAtIso).split("-");
  return `${day}.${month}`;
}
