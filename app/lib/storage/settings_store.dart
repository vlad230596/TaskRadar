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

  /// The scope the board was last showing, or null if none was ever chosen
  /// (F7).
  ///
  /// An **id**, not a `Scope`: this file must not know what a scope is, and the
  /// id is the only part of it that is stable. The scope it names can also be
  /// gone by the time it is read -- deleted, or renamed beyond recognition --
  /// so the reader resolves it against the real list and falls back to the
  /// first scope. See `../providers/scope_providers.dart`.
  Future<String?> readSelectedScopeId();

  /// Remembers which scope the board is showing. May throw.
  Future<void> writeSelectedScopeId(String scopeId);

  /// The mode the app was in when it was last closed (F12), as the mode's own
  /// wire name -- `plan` / `work` / `history`.
  ///
  /// A **string**, not the enum, for the same reason the scope is an id: this
  /// file must not know what a mode is, and a stored `index` would silently
  /// point at a different mode the day a fourth one is inserted anywhere but
  /// the end. Null, or a name this build does not recognise, reads as "нечего
  /// восстанавливать" and lands on planning.
  Future<String?> readAppMode();

  /// Remembers the mode. May throw.
  Future<void> writeAppMode(String mode);

  /// How the planning mode was drawing projects -- `list` or `tiles` (F12).
  ///
  /// Remembered because the spec makes the two **equal**, not a default plus a
  /// novelty: someone who prefers tiles prefers them every morning, and a
  /// toggle that resets on every launch is a toggle that says the other view is
  /// the real one.
  Future<String?> readPlanLayout();

  /// Remembers the planning layout. May throw.
  Future<void> writePlanLayout(String layout);
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

  /// F7. A plain string; an unknown or deleted id reads as "nothing saved"
  /// wherever it is resolved, which is the same answer a missing key gives.
  static const String selectedScopeKey = 'board.scopeId';

  /// F12. The three-mode shell's last mode and the planning layout. Both are
  /// wire names rather than enum indices -- see the interface.
  static const String appModeKey = 'shell.mode';
  static const String planLayoutKey = 'plan.layout';

  final Future<SharedPreferences> Function() _preferences;

  /// The three string preferences all behave identically: a missing key, an
  /// empty value and an unreadable platform channel are the same answer
  /// ("nothing saved"), because every caller resolves that answer against what
  /// actually exists and falls back to a default. Written once rather than
  /// three times so a fourth preference cannot accidentally get a fourth
  /// behaviour.
  Future<String?> _readString(String key) async {
    try {
      final preferences = await _preferences();
      final value = preferences.getString(key);
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (error) {
      debugPrint('Could not read $key: $error');
      return null;
    }
  }

  Future<void> _writeString(String key, String value) async {
    final preferences = await _preferences();
    await preferences.setString(key, value);
  }

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

  /// An empty string is not an id, and treating it as one would send the board
  /// looking for a scope that cannot exist. A missing platform channel costs
  /// the default (the first scope), not a crash -- same contract as the
  /// reminder hour.
  @override
  Future<String?> readSelectedScopeId() => _readString(selectedScopeKey);

  @override
  Future<void> writeSelectedScopeId(String scopeId) =>
      _writeString(selectedScopeKey, scopeId);

  @override
  Future<String?> readAppMode() => _readString(appModeKey);

  @override
  Future<void> writeAppMode(String mode) => _writeString(appModeKey, mode);

  @override
  Future<String?> readPlanLayout() => _readString(planLayoutKey);

  @override
  Future<void> writePlanLayout(String layout) =>
      _writeString(planLayoutKey, layout);
}
