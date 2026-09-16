import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/reminder_schedule.dart';

/// The app's persisted preferences. Exactly one of them so far (F4): the hour
/// the morning reminders fire at.
///
/// ## Why a separate store rather than the board snapshot's machinery
///
/// `BoardSnapshotStore` exists to hold a *cache* whose every failure mode --
/// missing, truncated, corrupt, older schema -- has to collapse into "there is
/// no cache", which is why it carries a schema version, an atomic rename and a
/// delete-on-parse-failure. A preference has none of those problems: it is two
/// small integers written by this app, and an unreadable one has an obvious
/// answer (the default). Reusing the snapshot's file format for it would be
/// ceremony, and would put a user setting inside a file the app is entitled to
/// throw away.
///
/// ## Why `shared_preferences` and not `flutter_secure_storage`
///
/// The token lives in secure storage because reading it is an account takeover.
/// "Reminders fire at 08:30" is not a secret, and paying a Keystore round trip
/// (plus, on some OEM ROMs, its failure modes) for it would buy nothing. The
/// split is deliberate: the secure store holds credentials, this holds settings,
/// and no code has to decide which one a new value belongs in.
///
/// ## Why it is a class rather than three top-level functions
///
/// So tests can hand the providers an in-memory implementation
/// (`FakeSettingsStore`). `SharedPreferences` does offer
/// `setMockInitialValues`, but that is a global on a platform channel: it leaks
/// between tests in the same file and cannot express "the write failed", which
/// is a state the settings screen has to survive.
abstract interface class SettingsStore {
  /// The saved reminder hour, or null when nothing has been saved yet or the
  /// stored value is unusable.
  Future<ReminderTime?> readReminderTime();

  /// Persists the reminder hour. May throw; the caller decides what to do.
  Future<void> writeReminderTime(ReminderTime time);
}

/// [SettingsStore] on top of `shared_preferences`.
class PreferencesSettingsStore implements SettingsStore {
  PreferencesSettingsStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  /// Stored as two ints rather than one `"HH:mm"` string: a string would need
  /// parsing and therefore a malformed-value branch, and the two are already
  /// how [ReminderTime] is shaped.
  static const String hourKey = 'reminders.hour';
  static const String minuteKey = 'reminders.minute';

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<ReminderTime?> readReminderTime() async {
    try {
      final preferences = await _preferences();
      final hour = preferences.getInt(hourKey);
      final minute = preferences.getInt(minuteKey);
      if (hour == null || minute == null) return null;

      // Range-checked here rather than left to `ReminderTime`'s asserts, which
      // are compiled out of a release build: a file edited by hand, or written
      // by a future version with a different encoding, must not be able to arm
      // alarms at hour 47. Out of range reads as "nothing saved", i.e. the
      // default -- the same answer as a missing key, which is the only answer
      // that cannot make the app worse.
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        debugPrint('Discarding out-of-range reminder time $hour:$minute');
        return null;
      }

      return ReminderTime(hour, minute);
    } catch (error) {
      // A platform channel that is not there (the `flutter test` VM, a stripped
      // ROM) must cost the default hour, not a crash on the first frame.
      debugPrint('Could not read the reminder time: $error');
      return null;
    }
  }

  @override
  Future<void> writeReminderTime(ReminderTime time) async {
    final preferences = await _preferences();
    await preferences.setInt(hourKey, time.hour);
    await preferences.setInt(minuteKey, time.minute);
  }
}
