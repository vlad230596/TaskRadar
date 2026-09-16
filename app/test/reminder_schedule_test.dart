import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Unit tests for the pure half of F1.
///
/// Everything here runs with an injected `now` and an injected [tz.Location], so
/// these are the cases that would otherwise only be discovered by waiting until
/// tomorrow morning in a particular timezone.
void main() {
  // The whole IANA database, loaded once. Pure Dart -- no platform channel, so
  // this works in the test VM exactly as it does on a device.
  setUpAll(tz_data.initializeTimeZones);

  /// UTC-7 in summer, UTC-8 in winter: the zone where the naive
  /// `DateTime.parse(remindAt).toLocal()` reading of a UTC-midnight date lands
  /// on the *previous* day.
  late final tz.Location la = tz.getLocation('America/Los_Angeles');

  /// UTC+3 all year: the zone this tool is actually used in, and the one where
  /// the naive reading happens to work, which is exactly why it is not enough
  /// to test only there.
  late final tz.Location moscow = tz.getLocation('Europe/Moscow');

  group('calendarDateFromRemindAt', () {
    test('reads the date prefix of a UTC-midnight timestamp', () {
      expect(
        calendarDateFromRemindAt('2026-09-18T00:00:00.000Z'),
        const CalendarDate(2026, 9, 18),
      );
    });

    test('ignores the time component entirely', () {
      // Whatever time of day the server ever starts sending, the calendar date
      // the user picked is the prefix. This is the property the whole file
      // rests on.
      expect(
        calendarDateFromRemindAt('2026-09-18T23:59:59.999Z'),
        const CalendarDate(2026, 9, 18),
      );
      expect(
        calendarDateFromRemindAt('2026-09-18'),
        const CalendarDate(2026, 9, 18),
      );
    });

    test('rejects what it cannot read instead of guessing', () {
      expect(calendarDateFromRemindAt(''), isNull);
      expect(calendarDateFromRemindAt('не-дата'), isNull);
      expect(calendarDateFromRemindAt('2026-9-18T00:00:00Z'), isNull);
      expect(calendarDateFromRemindAt('18.09.2026'), isNull);
      expect(calendarDateFromRemindAt('2026-13-01T00:00:00Z'), isNull);
    });

    test('rejects a date that does not exist rather than rolling it over', () {
      // DateTime.utc(2026, 2, 31) silently becomes 3 March. Arming an alarm on
      // a day the user never picked is worse than arming none.
      expect(calendarDateFromRemindAt('2026-02-31T00:00:00.000Z'), isNull);
      expect(calendarDateFromRemindAt('2026-04-31T00:00:00.000Z'), isNull);
      // ...but a real leap day is fine.
      expect(
        calendarDateFromRemindAt('2028-02-29T00:00:00.000Z'),
        const CalendarDate(2028, 2, 29),
      );
    });
  });

  group('reminderFireTime', () {
    test('fires at the configured local hour of the picked date', () {
      final fireAt = reminderFireTime(
        remindAt: '2026-09-18T00:00:00.000Z',
        at: ReminderTime.defaultMorning,
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 16, 12),
      );

      expect(fireAt, isNotNull);
      expect(fireAt!.location, moscow);
      expect(fireAt.year, 2026);
      expect(fireAt.month, 9);
      expect(fireAt.day, 18);
      expect(fireAt.hour, 9);
      expect(fireAt.minute, 0);
    });

    test(
      'west of UTC, a UTC-midnight remindAt still means the date the user picked',
      () {
        // The trap from frontend/src/lib/reminders.ts, in alarm form.
        // DateTime.parse('2026-09-18T00:00:00.000Z').toLocal() in Los Angeles is
        // 2026-09-17 17:00, so a naive implementation would arm the alarm for
        // the morning of the 17th -- a day early, every time, for every user
        // west of Greenwich.
        final fireAt = reminderFireTime(
          remindAt: '2026-09-18T00:00:00.000Z',
          at: ReminderTime.defaultMorning,
          location: la,
          now: tz.TZDateTime(la, 2026, 9, 16, 12),
        );

        expect(fireAt!.day, 18, reason: 'not the 17th');
        expect(fireAt.hour, 9);
      },
    );

    test('resolves the offset for the target date, not for today', () {
      // 1 November 2026 is when the US leaves DST. A reminder set in October for
      // 5 November must still fire at 09:00 wall clock, i.e. at UTC-8, not at
      // the UTC-7 that is in force on the day the alarm is armed. A fixed-offset
      // shortcut passes every other test in this file and fails this one.
      final fireAt = reminderFireTime(
        remindAt: '2026-11-05T00:00:00.000Z',
        at: ReminderTime.defaultMorning,
        location: la,
        now: tz.TZDateTime(la, 2026, 10, 25, 12),
      );

      expect(fireAt!.hour, 9);
      expect(fireAt.timeZoneOffset, const Duration(hours: -8));
    });

    group('day boundaries', () {
      test('midnight is the earliest instant of the picked date', () {
        final fireAt = reminderFireTime(
          remindAt: '2026-09-18T00:00:00.000Z',
          at: const ReminderTime(0, 0),
          location: moscow,
          now: tz.TZDateTime(moscow, 2026, 9, 17, 23, 59),
        );

        expect(fireAt!.day, 18);
        expect(fireAt.hour, 0);
      });

      test('23:59 stays on the picked date and does not spill into the next', () {
        final fireAt = reminderFireTime(
          remindAt: '2026-09-18T00:00:00.000Z',
          at: const ReminderTime(23, 59),
          location: moscow,
          now: tz.TZDateTime(moscow, 2026, 9, 18, 8),
        );

        expect(fireAt!.day, 18);
        expect(fireAt.hour, 23);
        expect(fireAt.minute, 59);
      });

      test('a reminder for today is armed while the hour is still ahead', () {
        final fireAt = reminderFireTime(
          remindAt: '2026-09-18T00:00:00.000Z',
          at: ReminderTime.defaultMorning,
          location: moscow,
          now: tz.TZDateTime(moscow, 2026, 9, 18, 8, 59),
        );

        expect(fireAt, isNotNull);
      });
    });

    group('the past is never scheduled', () {
      test('an earlier date', () {
        expect(
          reminderFireTime(
            remindAt: '2026-09-10T00:00:00.000Z',
            at: ReminderTime.defaultMorning,
            location: moscow,
            now: tz.TZDateTime(moscow, 2026, 9, 18, 8),
          ),
          isNull,
        );
      });

      test('today, once the configured hour has gone by', () {
        expect(
          reminderFireTime(
            remindAt: '2026-09-18T00:00:00.000Z',
            at: ReminderTime.defaultMorning,
            location: moscow,
            now: tz.TZDateTime(moscow, 2026, 9, 18, 9, 1),
          ),
          isNull,
        );
      });

      test('exactly now counts as past, not as due', () {
        // An alarm for "this very instant" is a notification the user did not
        // ask for at a moment they were not expecting one.
        expect(
          reminderFireTime(
            remindAt: '2026-09-18T00:00:00.000Z',
            at: ReminderTime.defaultMorning,
            location: moscow,
            now: tz.TZDateTime(moscow, 2026, 9, 18, 9),
          ),
          isNull,
        );
      });

      test('"past" is judged in the local zone, not in UTC', () {
        // 2026-09-18 08:00 in Moscow is 2026-09-18 05:00 UTC; the 09:00 Moscow
        // alarm is still ahead. A check performed against a UTC "now" with a
        // local fire time (or the other way round) gets this backwards.
        expect(
          reminderFireTime(
            remindAt: '2026-09-18T00:00:00.000Z',
            at: ReminderTime.defaultMorning,
            location: moscow,
            now: tz.TZDateTime(moscow, 2026, 9, 18, 8),
          ),
          isNotNull,
        );
      });
    });

    test('a malformed date yields no alarm rather than an exception', () {
      expect(
        reminderFireTime(
          remindAt: 'не-дата',
          at: ReminderTime.defaultMorning,
          location: moscow,
          now: tz.TZDateTime(moscow, 2026, 9, 18),
        ),
        isNull,
      );
    });
  });

  group('notificationIdForTask', () {
    test('is deterministic', () {
      expect(notificationIdForTask('tsk_1'), notificationIdForTask('tsk_1'));
    });

    test('pins the algorithm, not just its determinism', () {
      // A golden value. Determinism within one run is also true of
      // `String.hashCode`, which is NOT stable across VM versions -- and an id
      // that changes after a Flutter upgrade would turn every existing alarm
      // into an orphan that no resync can find or cancel. This test fails if
      // anyone swaps the hash for a "nicer" one.
      expect(notificationIdForTask('tsk_1'), 1645408545);
    });

    test('separates ids that differ by one character', () {
      expect(
        notificationIdForTask('tsk_1'),
        isNot(notificationIdForTask('tsk_2')),
      );
    });

    test('stays inside the positive 31-bit range, above the reserved ids', () {
      for (final id in <String>[
        '',
        'a',
        'tsk_1',
        'cm3n9x1qv0000abcd1234efgh',
        'задача-с-кириллицей',
      ]) {
        final notificationId = notificationIdForTask(id);
        expect(notificationId, greaterThanOrEqualTo(reservedNotificationIds));
        expect(notificationId, lessThan(0x80000000));
      }
    });
  });

  group('payloads', () {
    test('round-trip', () {
      expect(taskIdFromPayload(reminderPayload('tsk_1')), 'tsk_1');
    });

    test('anything that is not ours is not claimed', () {
      expect(taskIdFromPayload(null), isNull);
      expect(taskIdFromPayload('bench:soon'), isNull);
      expect(taskIdFromPayload('task:'), isNull);
    });
  });

  group('buildReminderSchedule', () {
    TaskReminder reminder(String id, String remindAt) => TaskReminder(
      taskId: id,
      taskTitle: 'Задача $id',
      remindAt: remindAt,
      projectName: 'Проект',
    );

    test('arms the future ones, earliest first', () {
      final schedule = buildReminderSchedule(
        reminders: <TaskReminder>[
          reminder('c', '2026-09-25T00:00:00.000Z'),
          reminder('a', '2026-09-19T00:00:00.000Z'),
          reminder('b', '2026-09-20T00:00:00.000Z'),
        ],
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 18, 12),
      );

      expect(
        schedule.reminders.map((r) => r.taskId),
        <String>['a', 'b', 'c'],
      );
      expect(schedule.skipped, isEmpty);
    });

    test('uses the project name as the title and the task as the body', () {
      final schedule = buildReminderSchedule(
        reminders: <TaskReminder>[
          const TaskReminder(
            taskId: 'a',
            taskTitle: 'Жду кабель',
            remindAt: '2026-09-19T00:00:00.000Z',
            projectName: 'Кухня',
          ),
        ],
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 18, 12),
      );

      expect(schedule.reminders.single.title, 'Кухня');
      expect(schedule.reminders.single.body, 'Жду кабель');
      expect(schedule.reminders.single.payload, 'task:a');
    });

    test('reports why each skipped reminder was skipped', () {
      final schedule = buildReminderSchedule(
        reminders: <TaskReminder>[
          reminder('past', '2026-09-01T00:00:00.000Z'),
          reminder('broken', 'не-дата'),
          reminder('future', '2026-09-19T00:00:00.000Z'),
        ],
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 18, 12),
      );

      expect(schedule.reminders.single.taskId, 'future');
      expect(
        schedule.skipped.map((s) => '${s.reminder.taskId}:${s.reason.name}'),
        <String>['past:inThePast', 'broken:malformedDate'],
      );
    });

    test('the same task twice produces one alarm and no complaint', () {
      final schedule = buildReminderSchedule(
        reminders: <TaskReminder>[
          reminder('a', '2026-09-19T00:00:00.000Z'),
          reminder('a', '2026-09-19T00:00:00.000Z'),
        ],
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 18, 12),
      );

      expect(schedule.reminders, hasLength(1));
      expect(schedule.skipped, isEmpty);
    });

    test('an id collision loses a reminder visibly, not silently', () {
      // These two ids really do hash onto the same notification id (found by
      // brute force over the FNV-1a mapping in notificationIdForTask). The
      // point of the test is not that collisions are likely -- they are not --
      // but that when one happens the second reminder is reported as dropped
      // instead of quietly overwriting the first one's alarm.
      const collidingA = 'tsk_291268';
      const collidingB = 'tsk_562964';
      expect(
        notificationIdForTask(collidingA),
        notificationIdForTask(collidingB),
        reason: 'the fixture is stale if this fails',
      );

      final schedule = buildReminderSchedule(
        reminders: <TaskReminder>[
          reminder(collidingA, '2026-09-19T00:00:00.000Z'),
          reminder(collidingB, '2026-09-20T00:00:00.000Z'),
        ],
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 18, 12),
      );

      expect(schedule.reminders.single.taskId, collidingA);
      expect(schedule.skipped.single.reason, SkipReason.idCollision);
      expect(schedule.skipped.single.reminder.taskId, collidingB);
    });

    test('the configured hour moves every alarm', () {
      final schedule = buildReminderSchedule(
        reminders: <TaskReminder>[reminder('a', '2026-09-19T00:00:00.000Z')],
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 18, 12),
        at: const ReminderTime(7, 30),
      );

      expect(schedule.reminders.single.fireAt.hour, 7);
      expect(schedule.reminders.single.fireAt.minute, 30);
    });

    test('an empty input is an empty schedule, not an error', () {
      final schedule = buildReminderSchedule(
        reminders: const <TaskReminder>[],
        location: moscow,
        now: tz.TZDateTime(moscow, 2026, 9, 18, 12),
      );

      expect(schedule.reminders, isEmpty);
      expect(schedule.byId, isEmpty);
    });
  });
}
