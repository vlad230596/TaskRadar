/// The buttons on a reminder notification, as data: which buttons a
/// notification carries, how a press is recognised again when it comes back
/// from the OS, and what «Завтра» means in dates.
///
/// Pure Dart, like `reminder_schedule.dart` next to it: no plugin, no clock of
/// its own. The side that executes a press lives in
/// `lib/notifications/notification_actions_runner.dart` (no app running) and
/// `lib/providers/notification_action_providers.dart` (app running).
///
/// ## Why two buttons
///
/// The owner's brief: at most three, preferably two. «Выполнено» is the one a
/// reminder is for; «Завтра» is the honest «not now» -- it moves the reminder
/// instead of only dismissing it, so the task comes back rather than being
/// forgotten. A body tap still opens the task (F4), which covers everything
/// else.
library;

import 'reminder_schedule.dart';
import 'reminders.dart';

/// One button on a reminder notification.
///
/// [id] is what the OS hands back on a press (Android's action id, and part of
/// a Windows toast button's argument string) -- stored in notifications that
/// may already be sitting in the shade when a new build is installed, so the
/// ids never change.
enum ReminderAction {
  /// Marks the task done.
  done('done', 'Выполнено'),

  /// A date reminder: the same time of day, tomorrow.
  tomorrow('tomorrow', 'Завтра'),

  /// A place reminder: quiet for that place until tomorrow. A place has no
  /// date to move, so this is a different action with the same label.
  placeTomorrow('place_tomorrow', 'Завтра');

  const ReminderAction(this.id, this.label);

  final String id;
  final String label;

  static ReminderAction? byId(String? id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// The buttons of a date (or date-and-time) reminder.
const List<ReminderAction> dateReminderActions = <ReminderAction>[
  ReminderAction.done,
  ReminderAction.tomorrow,
];

/// The buttons of a place reminder.
const List<ReminderAction> placeReminderActions = <ReminderAction>[
  ReminderAction.done,
  ReminderAction.placeTomorrow,
];

/// The prefix of a button argument that carries its own payload.
///
/// Windows hands back a toast button press as one string -- the button's
/// `arguments` -- with no separate payload and no notification id. So a
/// Windows button carries both: `action:<id>|task:<taskId>`. Android keeps
/// the two apart (`actionId` + `payload`) and never sees this form.
const String actionArgumentPrefix = 'action:';

/// The self-contained argument string of a button (see [actionArgumentPrefix]).
String actionArgument(ReminderAction action, String payload) =>
    '$actionArgumentPrefix${action.id}|$payload';

/// A button press, recognised: what to do, to which task.
class NotificationActionRequest {
  const NotificationActionRequest(this.action, this.taskId);

  final ReminderAction action;
  final String taskId;

  /// Reads a press back from what the OS returned, or null when it is not one
  /// of ours -- a body tap, a bench notification (`bench:` payload), a button
  /// id from some future build, a malformed string. Null is always safe: the
  /// caller does nothing.
  ///
  /// Two shapes are accepted: Android's ([actionId] is a bare id, the task is
  /// in [payload]) and the self-contained Windows argument, which may arrive
  /// in either field (the Windows plugin fills both with it).
  static NotificationActionRequest? parse({String? actionId, String? payload}) {
    for (final candidate in <String?>[actionId, payload]) {
      if (candidate == null || !candidate.startsWith(actionArgumentPrefix)) {
        continue;
      }
      final rest = candidate.substring(actionArgumentPrefix.length);
      final bar = rest.indexOf('|');
      if (bar < 0) return null;
      final action = ReminderAction.byId(rest.substring(0, bar));
      final taskId = taskIdFromPayload(rest.substring(bar + 1));
      if (action == null || taskId == null) return null;
      return NotificationActionRequest(action, taskId);
    }

    final action = ReminderAction.byId(actionId);
    final taskId = taskIdFromPayload(payload);
    if (action == null || taskId == null) return null;
    return NotificationActionRequest(action, taskId);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationActionRequest &&
      other.action == action &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(action, taskId);

  @override
  String toString() => 'NotificationActionRequest(${action.id}, $taskId)';
}

/// Where «Завтра» moves a date reminder: tomorrow's calendar date relative
/// to [now] (the device's local wall clock), and the time of day it already
/// had -- null for a reminder that only had a day, which then fires at the
/// settings hour as before.
///
/// Tomorrow from *now*, not from the reminder's own date: an inexact alarm
/// can arrive hours late, and a notification can sit in the shade overnight;
/// «Завтра» pressed on the 18th about a reminder for the 17th means the 19th.
/// `DateTime(y, m, d + 1)` rolls over months and years by itself.
({String date, String? time}) postponeToTomorrow({
  required String? remindTime,
  required DateTime now,
}) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  return (
    date: calendarDateForApi(tomorrow),
    time: reminderTimeFromString(remindTime)?.format(),
  );
}

/// Until when «Завтра» keeps a place quiet: the next local midnight.
///
/// The ordinary cooldown (`geofenceCooldown`) still applies on top, so a press
/// late in the evening does not let the same zone ring again a few minutes
/// after midnight.
DateTime placeSnoozeUntil(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1);

/// How long «Выполнено» keeps a task's place quiet when the app is not
/// running to unregister its zone. The next sync in the app removes the zone
/// for good (a done task has none); this only covers the days until then.
const Duration placeQuietAfterDone = Duration(days: 7);
