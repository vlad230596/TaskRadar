import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/notifications/notification_gateway.dart';
import 'package:taskradar/notifications/reminder_scheduler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'support/fake_notification_gateway.dart';

/// Tests for "make the OS queue match this list".
///
/// The scheduler's contract is stated in terms of the queue *after* a sync, not
/// in terms of which plugin methods were called -- that is what makes it
/// possible to change how the resync is implemented (full re-arm, diff,
/// cancel-all-then-schedule) without rewriting the tests.
void main() {
  setUpAll(tz_data.initializeTimeZones);

  late final tz.Location moscow = tz.getLocation('Europe/Moscow');

  late FakeNotificationGateway gateway;

  /// A fixed "now": 18 September 2026, midday, Moscow.
  tz.TZDateTime now() => tz.TZDateTime(moscow, 2026, 9, 18, 12);

  ReminderScheduler scheduler() =>
      ReminderScheduler(gateway: gateway, location: moscow, now: now);

  TaskReminder reminder(String id, String remindAt) => TaskReminder(
    taskId: id,
    taskTitle: 'Задача $id',
    remindAt: remindAt,
    projectName: 'Проект',
  );

  setUp(() {
    gateway = FakeNotificationGateway();
  });

  group('bringing the queue to the target set', () {
    test('an empty queue gains one alarm per future reminder', () async {
      final report = await scheduler().sync(
        reminders: <TaskReminder>[
          reminder('a', '2026-09-19T00:00:00.000Z'),
          reminder('b', '2026-09-20T00:00:00.000Z'),
        ],
      );

      expect(
        gateway.queue.keys.toSet(),
        <int>{notificationIdForTask('a'), notificationIdForTask('b')},
      );
      expect(report.scheduledCount, 2);
      expect(report.pending, hasLength(2));
    });

    test('a task that lost its reminder loses its alarm', () async {
      await scheduler().sync(
        reminders: <TaskReminder>[
          reminder('a', '2026-09-19T00:00:00.000Z'),
          reminder('b', '2026-09-20T00:00:00.000Z'),
        ],
      );

      final report = await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      expect(gateway.queue.keys, <int>[notificationIdForTask('a')]);
      expect(report.cancelled, <int>[notificationIdForTask('b')]);
    });

    test('a moved date replaces the alarm instead of adding a second one', () async {
      await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );
      await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-25T00:00:00.000Z')],
      );

      // One entry, under the same (stable) id, now pointing at the new date.
      expect(gateway.queue, hasLength(1));
      final entry = gateway.queue[notificationIdForTask('a')]!;
      expect(entry.fireAt.day, 25);
      expect(gateway.cancelledIds, isEmpty, reason: 'replaced, not re-created');
    });

    test('every target is re-armed on every sync, unchanged or not', () async {
      // The self-healing property: the app never assumes an alarm it armed
      // earlier is still there. A reboot, a force-stop or an OEM battery sweep
      // empties the queue without telling anyone.
      final reminders = <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')];

      await scheduler().sync(reminders: reminders);
      gateway.queue.clear(); // the OS "forgot", as it does after a reboot
      await scheduler().sync(reminders: reminders);

      expect(gateway.scheduleCalls, hasLength(2));
      expect(gateway.queue, hasLength(1));
    });

    test('syncing an empty set clears our alarms', () async {
      await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      final report = await scheduler().sync(reminders: const <TaskReminder>[]);

      expect(gateway.queue, isEmpty);
      expect(report.cancelled, hasLength(1));
    });

    test('past and malformed reminders never reach the queue', () async {
      final report = await scheduler().sync(
        reminders: <TaskReminder>[
          reminder('past', '2026-09-01T00:00:00.000Z'),
          reminder('broken', 'не-дата'),
          reminder('future', '2026-09-19T00:00:00.000Z'),
        ],
      );

      expect(gateway.queue.keys, <int>[notificationIdForTask('future')]);
      expect(report.requested, 3);
      expect(report.skippedCount, 2);
    });
  });

  group('what the sweep is allowed to touch', () {
    test('notifications that are not task reminders are left alone', () async {
      // The bench's "in 2 minutes" test alarm, and anything a later iteration
      // schedules for another purpose. A resync that cancelled these would make
      // the F1 experiment unrunnable: the tester would conclude the OS ate the
      // alarm.
      gateway.seed(
        FakeScheduledNotification.stub(
          id: 2,
          location: moscow,
          payload: 'bench:soon',
        ),
      );

      await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      expect(gateway.queue.containsKey(2), isTrue);
      expect(gateway.cancelledIds, isEmpty);
    });

    test('a reminder left over from a previous run is cancelled', () async {
      gateway.seed(
        FakeScheduledNotification.stub(
          id: notificationIdForTask('gone'),
          location: moscow,
          payload: reminderPayload('gone'),
        ),
      );

      await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      expect(gateway.cancelledIds, <int>[notificationIdForTask('gone')]);
    });

    test('cancelAll takes everything, including the bench alarms', () async {
      gateway.seed(
        FakeScheduledNotification.stub(id: 2, location: moscow, payload: 'bench:soon'),
      );

      await scheduler().cancelAll();

      expect(gateway.queue, isEmpty);
      expect(gateway.cancelAllCount, 1);
    });
  });

  group('degradation', () {
    test('alarms are exact while the permission is there', () async {
      await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      expect(gateway.scheduleCalls.single.exact, isTrue);
    });

    test('a refused exact-alarm permission downgrades instead of failing', () async {
      gateway.permissionState = const NotificationPermissionState(
        notificationsEnabled: true,
        canScheduleExactAlarms: false,
      );

      final report = await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      expect(gateway.scheduleCalls.single.exact, isFalse);
      expect(report.scheduledCount, 1);
      expect(
        report.permissions.scheduleMode,
        NotificationScheduleMode.inexact,
      );
    });

    test('an unsupported platform reports itself and schedules nothing', () async {
      gateway.support = NotificationSupport.none;

      final report = await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      expect(gateway.scheduleCalls, isEmpty);
      expect(report.scheduledCount, 0);
      expect(report.summary, contains('не поддерживает'));
    });

    test('a platform failure becomes a report, not an exception', () async {
      // A sync is triggered from a lifecycle callback and (from F4) from a
      // background task. Throwing out of it would take down the caller.
      gateway.failure = StateError('platform channel exploded');

      final report = await scheduler().sync(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
      );

      expect(report.error, contains('platform channel exploded'));
      expect(report.summary, startsWith('Ошибка'));
    });
  });

  test('the report says enough to debug a phone with', () async {
    final report = await scheduler().sync(
      reminders: <TaskReminder>[
        reminder('a', '2026-09-19T00:00:00.000Z'),
        reminder('past', '2026-09-01T00:00:00.000Z'),
      ],
    );

    expect(report.summary, contains('Запрошено 2'));
    expect(report.summary, contains('запланировано 1'));
    expect(report.summary, contains('пропущено 1'));
  });
}
