import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminders.dart';

/// Tests for the port of `frontend/src/lib/reminders.ts`.
///
/// ## What these tests are actually defending
///
/// The rule under test is one line long, which is exactly why it needs tests:
/// there are two shorter-looking ways to write it and both are wrong, in
/// opposite directions. `reminders.dart` explains them; this file pins them
/// down by spelling out what each wrong version would answer and asserting that
/// the real one answers differently.
///
/// Writing the wrong implementations out here, rather than just asserting the
/// right answer, is deliberate. A test that only says
/// `expect(isReminderDue(x), isFalse)` passes for a naive implementation on a
/// machine whose timezone happens not to expose the bug -- and the machine this
/// project is developed on (UTC+3) is one of those for the westward case. The
/// naive versions below take the offset as an explicit parameter, so the trap
/// is reproduced as *data* and the assertions hold on any machine.
void main() {
  /// Trap 1, written out: `new Date(remindAt)` (or `DateTime.parse`) followed
  /// by reading **local** date parts, for a viewer whose UTC offset is
  /// [offset].
  bool naiveFromLocalDateParts(
    String remindAt,
    String today,
    Duration offset,
  ) {
    final shifted = DateTime.parse(remindAt).toUtc().add(offset);
    final date =
        '${shifted.year.toString().padLeft(4, '0')}-'
        '${shifted.month.toString().padLeft(2, '0')}-'
        '${shifted.day.toString().padLeft(2, '0')}';
    return date.compareTo(today) <= 0;
  }

  /// Trap 2, written out: comparing the two values as moments in time.
  bool naiveFromInstants(String remindAt, DateTime nowInstant) =>
      !DateTime.parse(remindAt).toUtc().isAfter(nowInstant.toUtc());

  group('the calendar date is taken as a string, never as an instant', () {
    test('a UTC-midnight remindAt yields the date the user picked', () {
      expect(reminderCalendarDate('2026-08-18T00:00:00.000Z'), '2026-08-18');
    });

    test('the prefix does not move, whatever the offset would do to it', () {
      const remindAt = '2026-08-18T00:00:00.000Z';

      for (var offsetHours = -12; offsetHours <= 14; offsetHours++) {
        final asInstant = DateTime.parse(
          remindAt,
        ).toUtc().add(Duration(hours: offsetHours));

        // The shift that causes the bug: west of UTC the stored instant lands
        // on the *previous* calendar day.
        if (offsetHours < 0) {
          expect(asInstant.day, 17, reason: 'UTC$offsetHours sees the 17th');
        }

        // ...while the value this app actually uses never moves.
        expect(reminderCalendarDate(remindAt), '2026-08-18');
      }
    });

    test('a non-midnight timestamp is still read by its UTC date prefix', () {
      // Belt and braces: this one differs from the local date on any machine
      // more than half an hour away from UTC, so on most machines it fails
      // outright if somebody reintroduces a `.toLocal()`.
      expect(reminderCalendarDate('2026-08-18T23:30:00.000Z'), '2026-08-18');
    });
  });

  group('trap 1: a viewer west of UTC', () {
    // A reminder for the 18th, seen on the 17th by someone in UTC-5. It is
    // tomorrow's problem and must not be badged as due.
    const remindAt = '2026-08-18T00:00:00.000Z';
    const today = '2026-08-17';
    const newYork = Duration(hours: -5);

    test('is not due yet', () {
      expect(isReminderDue(remindAt, now: DateTime(2026, 8, 17, 19, 5)), isFalse);
    });

    test('...and the naive version would say it is', () {
      expect(
        naiveFromLocalDateParts(remindAt, today, newYork),
        isTrue,
        reason:
            'parsing shifts the effective date back to the 17th, which then '
            'reads as "today" and lights up the badge a day early',
      );
    });

    test('and it becomes due the next day, in that same timezone', () {
      expect(isReminderDue(remindAt, now: DateTime(2026, 8, 18, 0, 5)), isTrue);
    });
  });

  group('trap 2: the same calendar day, later in the day', () {
    // Not the shape the backend stores today, but the shape a future change to
    // the date picker could easily produce -- and the comparison must not
    // depend on the time-of-day component either way.
    const remindAt = '2026-08-18T23:00:00.000Z';

    test('is due, because the calendar date has arrived', () {
      expect(isReminderDue(remindAt, now: DateTime(2026, 8, 18, 8)), isTrue);
    });

    test('...and comparing instants would say it is 15 hours away', () {
      expect(
        naiveFromInstants(remindAt, DateTime.utc(2026, 8, 18, 8)),
        isFalse,
        reason:
            'chronologically later, same calendar day: the raw comparison is '
            'the other half of the trap',
      );
    });
  });

  group('the day boundary', () {
    test('a reminder dated today is due, not "tomorrow"', () {
      expect(
        isReminderDue('2026-08-18T00:00:00.000Z', now: DateTime(2026, 8, 18)),
        isTrue,
      );
    });

    test('yesterday is still due -- overdue does not mean gone', () {
      expect(
        isReminderDue('2026-08-17T00:00:00.000Z', now: DateTime(2026, 8, 18)),
        isTrue,
      );
    });

    test('tomorrow is not', () {
      expect(
        isReminderDue('2026-08-19T00:00:00.000Z', now: DateTime(2026, 8, 18)),
        isFalse,
      );
    });

    test('a year and a month boundary are ordinary string comparisons', () {
      expect(
        isReminderDue('2025-12-31T00:00:00.000Z', now: DateTime(2026, 1, 1)),
        isTrue,
      );
      expect(
        isReminderDue('2026-01-01T00:00:00.000Z', now: DateTime(2025, 12, 31)),
        isFalse,
      );
      expect(
        isReminderDue('2026-09-02T00:00:00.000Z', now: DateTime(2026, 9, 10)),
        isTrue,
        reason: 'zero padding is what makes lexicographic order chronological',
      );
    });
  });

  group('localTodayCalendarDate', () {
    test('zero-pads, so it can be compared as a string', () {
      expect(localTodayCalendarDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('reads only the date parts, not the time', () {
      expect(
        localTodayCalendarDate(DateTime(2026, 3, 9, 23, 59, 59)),
        '2026-03-09',
      );
    });
  });

  group('formatReminderDate', () {
    test('is DD.MM', () {
      expect(formatReminderDate('2026-08-18T00:00:00.000Z'), '18.08');
      expect(formatReminderDate('2026-01-05T00:00:00.000Z'), '05.01');
    });

    test('works on a bare YYYY-MM-DD too', () {
      // `ProjectSummary.nextReminderAt` is already a date prefix, and the card
      // formats it with this function.
      expect(formatReminderDate('2026-11-30'), '30.11');
    });

    test('shows an unreadable value instead of hiding it', () {
      expect(formatReminderDate('не-дата'), 'не-дата');
    });
  });

  group('a malformed remindAt', () {
    test('has no calendar date', () {
      expect(reminderCalendarDate('не-дата'), isNull);
      expect(reminderCalendarDate(''), isNull);
      expect(reminderCalendarDate('2026-08'), isNull);
      expect(
        reminderCalendarDate('2026-02-31T00:00:00.000Z'),
        isNull,
        reason: 'DateTime would roll this into March; a date nobody picked',
      );
    });

    test('is never due', () {
      // The alternative -- letting the string comparison decide -- would make
      // the answer depend on where the garbage sorts against a date, and a red
      // "act on this today" badge is the wrong reaction to unreadable data.
      expect(isReminderDue('не-дата', now: DateTime(2026, 8, 18)), isFalse);
      expect(isReminderDue('', now: DateTime(2026, 8, 18)), isFalse);
    });
  });
}
