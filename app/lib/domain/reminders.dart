/// Port of `frontend/src/lib/reminders.ts`.
///
/// Helpers for the reminder date of a `blocked` task (see the README: a blocked
/// task can carry the day it is worth asking about again). `remindAt` has **day
/// granularity** -- it is picked in a date picker, there is no meaningful
/// time-of-day component to it at all.
///
/// ## The trap, carried over verbatim from the TypeScript
///
/// The value still travels over the wire as a full ISO timestamp: the picked
/// `YYYY-MM-DD` round-trips through the backend as **UTC midnight of that
/// calendar date**. That matters for comparing it to "today", and both of the
/// obvious ways to do the comparison are wrong -- in opposite directions:
///
/// 1. **Parse it and read local date parts.** `DateTime.parse(remindAt)`
///    followed by `.toLocal()` and `.day`/`.month` shifts the *effective*
///    calendar date backward or forward by the viewer's UTC offset. A stored
///    `2026-08-18T00:00:00.000Z` reads back as 2026-08-17 in any timezone west
///    of UTC, so a reminder for the 18th would light up a day early for a user
///    in New York.
///
/// 2. **Compare raw timestamps.** `DateTime.parse(remindAt).isBefore(now)` has
///    the same problem pointing the other way: a `remindAt` of
///    `2026-08-18T23:00:00Z` is chronologically 15 hours *after* a "now" of
///    `2026-08-18T08:00:00Z`, so it reads as "in the future" -- but it is the
///    same calendar day and should already count as due.
///
/// So this file sidesteps both. It takes the `YYYY-MM-DD` prefix of the ISO
/// string **as-is** (that is exactly the calendar date the user picked,
/// regardless of timezone, because it was stored as UTC midnight of that date)
/// and compares it as a string against "today" assembled from **local**
/// wall-clock date parts -- because "today" means the user's actual today, not
/// UTC's.
///
/// ## Relationship to `reminder_schedule.dart`
///
/// The prefix is not re-parsed here: [calendarDateFromRemindAt] in
/// `reminder_schedule.dart` already does exactly that (same rule, same
/// validation, same reasons) for the notification scheduler. Two copies of a
/// date parser is one copy too many, so this file composes that one. The split
/// of responsibilities is "the scheduler decides when an alarm fires, this file
/// decides what the board shows".
library;

import 'reminder_schedule.dart';

/// The calendar date of a `remindAt`, as `YYYY-MM-DD`, or null if the value is
/// not a readable date.
///
/// This is the string prefix, never a parsed instant -- see the file comment.
String? reminderCalendarDate(String remindAt) =>
    calendarDateFromRemindAt(remindAt)?.toString();

/// Today, as `YYYY-MM-DD`, from **local** wall-clock date parts.
///
/// [now] exists so tests can stand on a fixed day. Only its `year`/`month`/`day`
/// are read, which is what makes such a test deterministic: a caller passes
/// `DateTime(2026, 8, 17)` and gets `2026-08-17` on any machine, in any zone.
String localTodayCalendarDate([DateTime? now]) =>
    calendarDateForApi(now ?? DateTime.now());

/// The `YYYY-MM-DD` string to send as `remindAt`, taken from a [DateTime]'s
/// **local wall-clock** year/month/day and nothing else (F4).
///
/// ## Why this exists rather than `toIso8601String().substring(0, 10)`
///
/// This is the *writing* half of the trap this file is about, and it fails in
/// the mirror image of the reading half. `showDatePicker` hands back a local
/// `DateTime` at local midnight. Both obvious serialisations are wrong:
///
/// - `picked.toUtc().toIso8601String()` converts that local midnight to an
///   instant. East of UTC it lands on the **previous** day (Moscow's
///   `2026-10-01 00:00 +03:00` is `2026-09-30T21:00Z`), so picking the 1st
///   stores the 30th;
/// - `picked.toIso8601String()` sends a naked local timestamp with no offset,
///   which `z.coerce.date()` on the server reads as **UTC**, quietly shifting
///   the date the other way for anyone west of UTC.
///
/// Sending only the date parts sidesteps the instant entirely, which is right
/// because there is no instant here: the user picked a *day*. The server's
/// `z.coerce.date()` turns a bare `YYYY-MM-DD` into UTC midnight of that day --
/// exactly the representation [calendarDateFromRemindAt] reads back, so a value
/// written here round-trips to the same calendar date in every timezone on
/// earth. It is also byte-for-byte what the React client sent
/// (`toDateInputValue` plus an `<input type="date">`, whose value is a bare
/// date), so an existing row and a new one are indistinguishable.
String calendarDateForApi(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// A stored `remindAt` as the local-midnight [DateTime] a date picker wants for
/// its `initialDate`, or null when the value cannot be read.
///
/// Note what this is *not*: a conversion of the stored instant into local time.
/// It re-assembles the calendar date's parts as a local `DateTime`, which is the
/// only reading under which "the picker opens on the day the badge shows" is
/// true everywhere. `DateTime.parse(remindAt).toLocal()` would open the picker
/// on the previous day for every user west of UTC -- the same off-by-one this
/// file's header describes, arriving through the picker instead of the badge.
DateTime? remindAtAsLocalDay(String remindAt) {
  final date = calendarDateFromRemindAt(remindAt);
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day);
}

/// True once the reminder's calendar date has arrived or passed.
///
/// A reminder dated exactly today counts as due, not just strictly-past ones --
/// the point of the date is "come back to this on that day", and a badge that
/// only appears the day *after* would be useless.
///
/// A malformed `remindAt` is **not** due. The alternative (letting the string
/// comparison decide) would make the answer depend on where the garbage sorts
/// relative to a date, which is arbitrary; and a loud red "deal with this now"
/// badge is the wrong reaction to a value the app could not read. The scheduler
/// makes the same call for the same reason (`SkipReason.malformedDate`).
bool isReminderDue(String remindAt, {DateTime? now}) {
  final date = reminderCalendarDate(remindAt);
  if (date == null) return false;

  // String comparison, not date arithmetic: `YYYY-MM-DD` is zero-padded and
  // big-endian, so lexicographic order *is* chronological order.
  return date.compareTo(localTodayCalendarDate(now)) <= 0;
}

/// Formats a `remindAt` as `DD.MM`, matching the rest of the app's date display.
///
/// Falls back to the raw value when the date cannot be read. Showing the
/// unreadable string is deliberate: it is the only way a malformed row is ever
/// visible to the person who can fix it, whereas an empty string or a `??`
/// placeholder would hide the problem.
String formatReminderDate(String remindAt) {
  final date = calendarDateFromRemindAt(remindAt);
  if (date == null) return remindAt;

  return '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}';
}
