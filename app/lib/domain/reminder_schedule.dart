/// Everything about "which alarm should exist, with which id, at which instant",
/// with no plugin, no platform channel and no clock of its own.
///
/// This file is the part of F1 that can actually be proven correct on a laptop:
/// `now` and the timezone are parameters, so the interesting cases (the day
/// boundary, a date that has already passed, a DST transition) are ordinary unit
/// tests rather than something you find out about on a Tuesday morning when the
/// notification arrives at the wrong hour. The side-effecting half lives in
/// `lib/notifications/`.
library;

import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

/// A task that wants to be reminded about.
///
/// Deliberately *not* the `Task` model. F2 will hand this layer real board data
/// and F1 hands it synthetic rows from the bench screen; both only need these
/// four fields, and depending on the full model would mean the bench had to
/// fabricate `position`, `isCurrent` and timestamps to say "remind me on the
/// 18th".
///
/// [remindAt] is the raw server string, not a `DateTime`, on purpose -- see
/// [calendarDateFromRemindAt].
class TaskReminder {
  const TaskReminder({
    required this.taskId,
    required this.taskTitle,
    required this.remindAt,
    this.projectName,
  });

  final String taskId;
  final String taskTitle;

  /// ISO timestamp exactly as the backend sent it, e.g.
  /// `2026-09-18T00:00:00.000Z`.
  final String remindAt;

  /// Shown in the notification body so the reminder is actionable from the
  /// lock screen ("TaskRadar: Жду кабель" says much less than "TaskRadar /
  /// Кухня: Жду кабель").
  final String? projectName;
}

/// The hour of the local morning reminders fire at.
///
/// A reminder has day granularity -- the user picked a date in a date picker,
/// there is no time-of-day in the data at all -- so the hour is a *setting*,
/// not information derived from the task. F4 adds the settings UI and persists
/// it; F1 keeps it in memory with the default below.
class ReminderTime {
  const ReminderTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23, 'hour must be 0..23'),
      assert(minute >= 0 && minute <= 59, 'minute must be 0..59');

  /// 09:00 local. Early enough to catch the morning, late enough not to be the
  /// thing that wakes anyone up.
  static const ReminderTime defaultMorning = ReminderTime(9, 0);

  final int hour;
  final int minute;

  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'ReminderTime(${format()})';
}

/// A calendar date with no time and no zone: the thing the user actually picked.
class CalendarDate {
  const CalendarDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// Reads the calendar date out of a `remindAt` the way -- and only the way --
/// `frontend/src/lib/reminders.ts` does: by taking the `YYYY-MM-DD` prefix of
/// the string verbatim.
///
/// ## Why not `DateTime.parse`
///
/// `remindAt` is a *date*, stored as UTC midnight of that date. The obvious
/// `DateTime.parse(remindAt).toLocal()` shifts the effective calendar date by
/// the viewer's UTC offset: `2026-09-18T00:00:00.000Z` reads back as the 17th
/// anywhere west of UTC, so the alarm for "remind me on the 18th" would be armed
/// for the morning of the 17th. `.toUtc()` avoids that but then quietly breaks
/// the day *after* a future date-picker change (a `remindAt` written as local
/// midnight would round-trip to the previous day east of UTC instead).
///
/// The prefix has neither problem: it is the literal date the user chose, and it
/// is then combined with a *local* wall-clock hour by [reminderFireTime], which
/// is exactly what "remind me on the 18th at 09:00 my time" means.
///
/// Returns null for anything that is not at least `YYYY-MM-DD` with plausible
/// field values -- a malformed row should cost one missing reminder, not the
/// whole resync.
CalendarDate? calendarDateFromRemindAt(String remindAt) {
  if (remindAt.length < 10) return null;

  final match = _datePrefix.firstMatch(remindAt.substring(0, 10));
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);

  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Reject 2026-02-31 and friends: DateTime would silently roll them over into
  // March, which would arm an alarm on a day the user never picked.
  final probe = DateTime.utc(year, month, day);
  if (probe.month != month || probe.day != day) return null;

  return CalendarDate(year, month, day);
}

final RegExp _datePrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// The instant an alarm for [remindAt] should fire, or null if it should not be
/// armed at all.
///
/// Null means one of two things, and both are deliberate:
///
/// - the date could not be read (see [calendarDateFromRemindAt]);
/// - the moment is not in the future relative to [now].
///
/// The second case covers a reminder dated *today* once the configured hour has
/// already gone by. Firing it immediately was the alternative, and it is worse:
/// the notification would pop up at whatever random second the app happened to
/// resync (a screen unlock, a background sync), which trains the user to swipe
/// TaskRadar notifications away without reading them. An overdue reminder is
/// surfaced by the board badge instead -- that is what `isReminderDue` in
/// `reminders.ts` is for.
tz.TZDateTime? reminderFireTime({
  required String remindAt,
  required ReminderTime at,
  required tz.Location location,
  required tz.TZDateTime now,
}) {
  final date = calendarDateFromRemindAt(remindAt);
  if (date == null) return null;

  // Wall-clock construction in [location]: this is where the calendar date and
  // the local hour are finally joined, and the tz package resolves the offset
  // *for that date*, so a reminder three weeks out across a DST boundary still
  // lands at 09:00 local rather than 08:00 or 10:00. (On a spring-forward day a
  // nonexistent wall-clock time is normalised forward by the tz package; for a
  // 09:00 default that cannot happen, and for an exotic configured hour an
  // alarm an hour off beats no alarm.)
  final fireAt = tz.TZDateTime(
    location,
    date.year,
    date.month,
    date.day,
    at.hour,
    at.minute,
  );

  if (!fireAt.isAfter(now)) return null;

  return fireAt;
}

/// Notification ids below this are reserved for notifications the app posts for
/// reasons other than a task reminder -- currently only the bench screen's two
/// manual test alarms.
///
/// [notificationIdForTask] maps into `[reservedNotificationIds, 2^31)` so a task
/// can never collide with one of them. Without this the bench's "in 2 minutes"
/// alarm could be silently replaced by a resync, and the tester would conclude
/// the platform ate it.
const int reservedNotificationIds = 16;

/// Notification ids are a Java `int` on Android. Staying inside the positive
/// half keeps them printable and unambiguous in `adb shell dumpsys alarm`.
const int _idCeiling = 0x80000000;

/// A stable, content-derived notification id for a task.
///
/// Stability is the whole point: Android keys a scheduled alarm by id, so
/// re-scheduling the same task must produce the same id or every resync would
/// add a duplicate alarm rather than replace one. That rules out
/// `String.hashCode` (the Dart VM does not promise it is stable across runs or
/// versions) and anything involving a counter or insertion order.
///
/// FNV-1a over the UTF-8 bytes instead: tiny, deterministic, specified
/// elsewhere, and trivially reproducible if a future tool ever needs to compute
/// the same id.
///
/// ## The collision we are accepting
///
/// 31 bits of id space and a hash with no cryptographic pretensions means two
/// different task ids can land on the same notification id. By the birthday
/// bound the chance is about `n^2 / 2^32`: ~0.001% at 100 reminders, ~0.1% at
/// 1000. This is a single-user tool whose reminder set is in the dozens, so the
/// expected number of collisions over the life of the project is effectively
/// zero -- but "effectively zero" is not "impossible", so the consequence is
/// made visible rather than left to chance: [buildReminderSchedule] detects the
/// clash, keeps the earlier reminder and reports the other as
/// [SkipReason.idCollision], which the bench screen displays. The failure mode
/// is therefore "one reminder is visibly missing", not "one reminder silently
/// overwrote another".
int notificationIdForTask(String taskId) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(taskId)) {
    hash ^= byte;
    // Dart ints are 64-bit here (no web target), so the product has to be
    // masked back down to 32 bits by hand.
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return reservedNotificationIds + hash % (_idCeiling - reservedNotificationIds);
}

/// Payload prefix marking a notification as "this app scheduled it for a task".
///
/// Two jobs. F4 will parse the task id back out of it to deep-link the tap.
/// Already today it is how the scheduler recognises *its own* pending alarms
/// when it sweeps the queue, so a resync cannot cancel a notification some other
/// part of the app (or the bench) put there.
const String reminderPayloadPrefix = 'task:';

/// Builds the payload for a task reminder.
String reminderPayload(String taskId) => '$reminderPayloadPrefix$taskId';

/// Extracts the task id from a reminder payload, or null if the payload is not
/// one of ours.
String? taskIdFromPayload(String? payload) {
  if (payload == null || !payload.startsWith(reminderPayloadPrefix)) return null;
  final taskId = payload.substring(reminderPayloadPrefix.length);
  return taskId.isEmpty ? null : taskId;
}

/// One alarm that should exist, fully resolved: id, text, instant.
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.taskId,
    required this.title,
    required this.body,
    required this.fireAt,
  });

  final int id;
  final String taskId;
  final String title;
  final String body;
  final tz.TZDateTime fireAt;

  String get payload => reminderPayload(taskId);

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.id == id &&
      other.taskId == taskId &&
      other.title == title &&
      other.body == body &&
      other.fireAt == fireAt;

  @override
  int get hashCode => Object.hash(id, taskId, title, body, fireAt);

  @override
  String toString() => 'ScheduledReminder(#$id, $taskId, $fireAt)';
}

/// Why a reminder did not become an alarm.
enum SkipReason {
  /// `remindAt` was not a readable calendar date.
  malformedDate,

  /// The moment has gone by -- either an older date, or today after the
  /// configured hour.
  inThePast,

  /// Its notification id was already taken by another task in the same batch.
  /// See the collision note on [notificationIdForTask].
  idCollision,
}

/// A reminder that was asked for and not armed, with the reason, so the bench
/// (and later any diagnostics screen) can say *why* the queue is shorter than
/// the task list.
class SkippedReminder {
  const SkippedReminder(this.reminder, this.reason);

  final TaskReminder reminder;
  final SkipReason reason;

  @override
  String toString() => 'SkippedReminder(${reminder.taskId}, $reason)';
}

/// The full answer to "given these reminders, what should the alarm queue look
/// like?".
class ReminderSchedule {
  const ReminderSchedule({required this.reminders, required this.skipped});

  static const ReminderSchedule empty = ReminderSchedule(
    reminders: <ScheduledReminder>[],
    skipped: <SkippedReminder>[],
  );

  /// Alarms to arm, earliest first.
  final List<ScheduledReminder> reminders;

  /// Reminders that were asked for but will not fire.
  final List<SkippedReminder> skipped;

  Map<int, ScheduledReminder> get byId => <int, ScheduledReminder>{
    for (final reminder in reminders) reminder.id: reminder,
  };
}

/// Turns the reminders that *should* exist into the alarms that *can* exist.
///
/// Pure: no clock, no timezone lookup, no plugin. `now` and `location` are
/// injected so a test can stand on any date in any zone.
ReminderSchedule buildReminderSchedule({
  required Iterable<TaskReminder> reminders,
  required tz.Location location,
  required tz.TZDateTime now,
  ReminderTime at = ReminderTime.defaultMorning,
}) {
  final scheduled = <int, ScheduledReminder>{};
  final skipped = <SkippedReminder>[];

  for (final reminder in reminders) {
    final fireAt = reminderFireTime(
      remindAt: reminder.remindAt,
      at: at,
      location: location,
      now: now,
    );

    if (fireAt == null) {
      skipped.add(
        SkippedReminder(
          reminder,
          calendarDateFromRemindAt(reminder.remindAt) == null
              ? SkipReason.malformedDate
              : SkipReason.inThePast,
        ),
      );
      continue;
    }

    final id = notificationIdForTask(reminder.taskId);
    final existing = scheduled[id];
    if (existing != null) {
      // Same task listed twice is not a collision, it is a duplicate input --
      // keeping one is the right answer and there is nothing to report.
      if (existing.taskId != reminder.taskId) {
        skipped.add(SkippedReminder(reminder, SkipReason.idCollision));
      }
      continue;
    }

    scheduled[id] = ScheduledReminder(
      id: id,
      taskId: reminder.taskId,
      title: reminder.projectName ?? 'TaskRadar',
      body: reminder.taskTitle,
      fireAt: fireAt,
    );
  }

  final ordered = scheduled.values.toList()
    // Earliest first, then by id, so the order is total and two runs over the
    // same input produce byte-identical output -- which is what makes the
    // bench's "pending" list readable and the tests exact.
    ..sort((a, b) {
      final byTime = a.fireAt.compareTo(b.fireAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  return ReminderSchedule(
    reminders: List<ScheduledReminder>.unmodifiable(ordered),
    skipped: List<SkippedReminder>.unmodifiable(skipped),
  );
}
