import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/storage/settings_store.dart';

/// In-memory [SettingsStore].
///
/// Same reasoning as the other fakes here: the real one goes through
/// `shared_preferences`, a platform channel the `flutter test` VM does not have.
/// `SharedPreferences.setMockInitialValues` exists, but it is a global on that
/// channel -- it leaks between tests in one file and cannot express a *failing*
/// write, which the settings screen has to survive.
class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore({this.time});

  /// What [readReminderTime] returns. Null is "nothing saved yet", which is what
  /// a first launch and an unreadable store look like alike.
  ReminderTime? time;

  /// What [readSelectedScopeId] returns (F7). Null is "no scope chosen yet",
  /// which is what a first launch looks like.
  String? selectedScopeId;

  /// What [readAppMode] returns (F12). Null is a first launch, which lands on
  /// planning.
  String? appMode;

  /// What [readPlanLayout] returns (F12). Null is a first launch, which is the
  /// list.
  String? planLayout;

  /// When set, every write throws it.
  Object? writeFailure;

  int readCount = 0;
  final List<ReminderTime> writes = <ReminderTime>[];
  final List<String> scopeWrites = <String>[];
  final List<String> modeWrites = <String>[];
  final List<String> layoutWrites = <String>[];

  @override
  Future<ReminderTime?> readReminderTime() async {
    readCount++;
    return time;
  }

  @override
  Future<void> writeReminderTime(ReminderTime value) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    writes.add(value);
    time = value;
  }

  @override
  Future<String?> readSelectedScopeId() async {
    readCount++;
    return selectedScopeId;
  }

  @override
  Future<void> writeSelectedScopeId(String scopeId) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    scopeWrites.add(scopeId);
    selectedScopeId = scopeId;
  }

  @override
  Future<String?> readAppMode() async {
    readCount++;
    return appMode;
  }

  @override
  Future<void> writeAppMode(String mode) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    modeWrites.add(mode);
    appMode = mode;
  }

  @override
  Future<String?> readPlanLayout() async {
    readCount++;
    return planLayout;
  }

  @override
  Future<void> writePlanLayout(String layout) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    layoutWrites.add(layout);
    planLayout = layout;
  }
}
