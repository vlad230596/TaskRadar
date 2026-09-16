import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_schedule.dart';
import 'notification_gateway.dart';

/// Brings the OS alarm queue in line with a set of reminders.
///
/// ## The API shape, and why it is this one
///
/// One method, [sync], that takes **the complete list of reminders that should
/// exist** and makes the queue match it. Callers never say "add this" or
/// "cancel that". F2 will call it with `remindersFromBoard(board)` after every
/// successful `GET /board` and that is the entire integration; F1 calls it with
/// whatever the bench screen typed in.
///
/// ## Why a full re-arm instead of a diff
///
/// Every target is re-armed on every sync, even if nothing about it changed.
/// The set is a few dozen items, so the cost is irrelevant, and the alternative
/// -- tracking what we believe is armed and computing a delta -- means keeping a
/// second model of the OS's state that can drift from the real one. It *will*
/// drift: the OS drops alarms on reboot and on force-stop, some OEM ROMs clear
/// them when the app is "optimised", and a diff against a stale model would
/// then quietly decide there was nothing to do. Re-arming unconditionally is
/// self-healing; `zonedSchedule` with a stable id replaces rather than
/// duplicates, which is what makes it safe (see [notificationIdForTask]).
///
/// The one thing that *is* computed as a difference is cancellation, because
/// there is no other way to remove an alarm for a task that no longer has a
/// reminder. That sweep only touches pending notifications whose payload marks
/// them as ours ([PendingNotification.isReminder]), so a resync can never eat
/// the bench's manual test alarm or anything a later iteration schedules for a
/// different purpose.
class ReminderScheduler {
  ReminderScheduler({
    required NotificationGateway gateway,
    required tz.Location location,
    tz.TZDateTime Function()? now,
  }) : _gateway = gateway,
       _location = location,
       _now = now ?? (() => tz.TZDateTime.now(location));

  final NotificationGateway _gateway;
  final tz.Location _location;
  final tz.TZDateTime Function() _now;

  tz.Location get location => _location;

  /// Makes the OS queue match [reminders].
  ///
  /// Never throws: a failed resync must not take down whatever triggered it (a
  /// board refresh, a lifecycle callback). The failure is reported in
  /// [ReminderSyncReport.error] and shown on the bench.
  Future<ReminderSyncReport> sync({
    required Iterable<TaskReminder> reminders,
    ReminderTime at = ReminderTime.defaultMorning,
  }) async {
    final requested = reminders.toList(growable: false);

    if (!_gateway.support.schedulesReminders) {
      return ReminderSyncReport(
        requested: requested.length,
        schedule: ReminderSchedule.empty,
        cancelled: const <int>[],
        pending: const <PendingNotification>[],
        permissions: NotificationPermissionState.unknown,
        support: _gateway.support,
      );
    }

    try {
      final permissions = await _gateway.permissions();
      final mode = permissions.scheduleMode;

      final schedule = buildReminderSchedule(
        reminders: requested,
        location: _location,
        now: _now(),
        at: at,
      );
      final wanted = schedule.byId;

      // Removals first. Doing it before the re-arm rather than after means a
      // cancel can never race ahead of a schedule that just replaced the same
      // id -- ids are stable, so a task that is still wanted is simply not in
      // this list.
      final cancelled = <int>[];
      for (final entry in await _gateway.pending()) {
        if (!entry.isReminder || wanted.containsKey(entry.id)) continue;
        await _gateway.cancel(entry.id);
        cancelled.add(entry.id);
      }

      for (final reminder in schedule.reminders) {
        await _gateway.schedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          fireAt: reminder.fireAt,
          payload: reminder.payload,
          exact: mode == NotificationScheduleMode.exact,
        );
      }

      return ReminderSyncReport(
        requested: requested.length,
        schedule: schedule,
        cancelled: List<int>.unmodifiable(cancelled),
        pending: await _gateway.pending(),
        permissions: permissions,
        support: _gateway.support,
      );
    } catch (error, stackTrace) {
      debugPrint('Reminder sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return ReminderSyncReport(
        requested: requested.length,
        schedule: ReminderSchedule.empty,
        cancelled: const <int>[],
        pending: const <PendingNotification>[],
        permissions: NotificationPermissionState.unknown,
        support: _gateway.support,
        error: error.toString(),
      );
    }
  }

  /// What the OS currently has queued, ours and everyone else's.
  Future<List<PendingNotification>> pending() => _gateway.pending();

  /// Drops every queued notification, including the bench's manual ones.
  /// Exposed for the bench's "отменить всё" button and for a future sign-out.
  Future<void> cancelAll() => _gateway.cancelAll();
}

/// What one [ReminderScheduler.sync] did, in enough detail to debug a phone
/// with.
@immutable
class ReminderSyncReport {
  const ReminderSyncReport({
    required this.requested,
    required this.schedule,
    required this.cancelled,
    required this.pending,
    required this.permissions,
    required this.support,
    this.error,
  });

  /// How many reminders the caller asked for.
  final int requested;

  /// What was armed, and what was not (with reasons).
  final ReminderSchedule schedule;

  /// Ids removed because their task no longer has a reminder.
  final List<int> cancelled;

  /// The OS queue read back *after* the resync. This is the only trustworthy
  /// evidence that anything happened.
  final List<PendingNotification> pending;

  final NotificationPermissionState permissions;
  final NotificationSupport support;

  /// Set when the resync blew up; everything else is then empty.
  final String? error;

  int get scheduledCount => schedule.reminders.length;

  int get skippedCount => schedule.skipped.length;

  /// The single sentence the bench puts at the top.
  String get summary {
    if (error != null) return 'Ошибка синхронизации: $error';
    if (!support.schedulesReminders) {
      return 'Платформа не поддерживает планирование напоминаний.';
    }
    return 'Запрошено $requested · запланировано $scheduledCount · '
        'пропущено $skippedCount · отменено ${cancelled.length} · '
        'в очереди ОС ${pending.length}';
  }
}
