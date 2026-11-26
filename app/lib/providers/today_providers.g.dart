// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'today_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// «Сегодня», the owner's server settings, «Сделано», «Недели» and the review
/// status (`design/today-history-contract.md`).

@ProviderFor(todayHistoryApi)
final todayHistoryApiProvider = TodayHistoryApiProvider._();

/// «Сегодня», the owner's server settings, «Сделано», «Недели» and the review
/// status (`design/today-history-contract.md`).

final class TodayHistoryApiProvider
    extends
        $FunctionalProvider<TodayHistoryApi, TodayHistoryApi, TodayHistoryApi>
    with $Provider<TodayHistoryApi> {
  /// «Сегодня», the owner's server settings, «Сделано», «Недели» and the review
  /// status (`design/today-history-contract.md`).
  TodayHistoryApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todayHistoryApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todayHistoryApiHash();

  @$internal
  @override
  $ProviderElement<TodayHistoryApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TodayHistoryApi create(Ref ref) {
    return todayHistoryApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TodayHistoryApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TodayHistoryApi>(value),
    );
  }
}

String _$todayHistoryApiHash() => r'0c726cbae55863fc5db968cd9cf6b59521f47c79';

/// The clock the day block reads. A provider so tests stand on a fixed day.

@ProviderFor(appClock)
final appClockProvider = AppClockProvider._();

/// The clock the day block reads. A provider so tests stand on a fixed day.

final class AppClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The clock the day block reads. A provider so tests stand on a fixed day.
  AppClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return appClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$appClockHash() => r'3a160822e94c7452db9eb102245e788a74843edf';

/// The owner's today, `YYYY-MM-DD`, local.
///
/// Not a timer: the shell calls [TodayKey.check] when the app comes back to
/// the foreground, and the Work screen when it is built -- a phone left on
/// the Work screen over midnight shows yesterday until it is touched, which
/// is what it would also do for the set. A pending timer in every widget test
/// would cost more than that.

@ProviderFor(TodayKey)
final todayKeyProvider = TodayKeyProvider._();

/// The owner's today, `YYYY-MM-DD`, local.
///
/// Not a timer: the shell calls [TodayKey.check] when the app comes back to
/// the foreground, and the Work screen when it is built -- a phone left on
/// the Work screen over midnight shows yesterday until it is touched, which
/// is what it would also do for the set. A pending timer in every widget test
/// would cost more than that.
final class TodayKeyProvider extends $NotifierProvider<TodayKey, String> {
  /// The owner's today, `YYYY-MM-DD`, local.
  ///
  /// Not a timer: the shell calls [TodayKey.check] when the app comes back to
  /// the foreground, and the Work screen when it is built -- a phone left on
  /// the Work screen over midnight shows yesterday until it is touched, which
  /// is what it would also do for the set. A pending timer in every widget test
  /// would cost more than that.
  TodayKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todayKeyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todayKeyHash();

  @$internal
  @override
  TodayKey create() => TodayKey();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$todayKeyHash() => r'ecffd6686227f00dd31040de7aa22ae3e5efd0dd';

/// The owner's today, `YYYY-MM-DD`, local.
///
/// Not a timer: the shell calls [TodayKey.check] when the app comes back to
/// the foreground, and the Work screen when it is built -- a phone left on
/// the Work screen over midnight shows yesterday until it is touched, which
/// is what it would also do for the set. A pending timer in every widget test
/// would cost more than that.

abstract class _$TodayKey extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// `GET /settings`, through the read cache: the horizon is needed offline to
/// fold «Позже», and the last known value is the honest one.

@ProviderFor(OwnerSettingsState)
final ownerSettingsStateProvider = OwnerSettingsStateProvider._();

/// `GET /settings`, through the read cache: the horizon is needed offline to
/// fold «Позже», and the last known value is the honest one.
final class OwnerSettingsStateProvider
    extends $AsyncNotifierProvider<OwnerSettingsState, OwnerSettings> {
  /// `GET /settings`, through the read cache: the horizon is needed offline to
  /// fold «Позже», and the last known value is the honest one.
  OwnerSettingsStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'ownerSettingsStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerSettingsStateHash();

  @$internal
  @override
  OwnerSettingsState create() => OwnerSettingsState();
}

String _$ownerSettingsStateHash() =>
    r'001b202111dc59b710d7b54a289b7d9e6664bee5';

/// `GET /settings`, through the read cache: the horizon is needed offline to
/// fold «Позже», and the last known value is the honest one.

abstract class _$OwnerSettingsState extends $AsyncNotifier<OwnerSettings> {
  FutureOr<OwnerSettings> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OwnerSettings>, OwnerSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OwnerSettings>, OwnerSettings>,
              AsyncValue<OwnerSettings>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The «Позже» horizon in days: the server's, the default until it is known.

@ProviderFor(laterHorizonDays)
final laterHorizonDaysProvider = LaterHorizonDaysProvider._();

/// The «Позже» horizon in days: the server's, the default until it is known.

final class LaterHorizonDaysProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// The «Позже» horizon in days: the server's, the default until it is known.
  LaterHorizonDaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'laterHorizonDaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$laterHorizonDaysHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return laterHorizonDays(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$laterHorizonDaysHash() => r'499e56bfb11e294d74b14ac064209ef5b25e8a79';

/// Rows changed by a day action that the board has not caught up with yet:
/// the one round trip between «Сегодня» pressed and the server's list, so the
/// row moves at the press. Cleared by the action when its write ends.

@ProviderFor(DayOverrides)
final dayOverridesProvider = DayOverridesProvider._();

/// Rows changed by a day action that the board has not caught up with yet:
/// the one round trip between «Сегодня» pressed and the server's list, so the
/// row moves at the press. Cleared by the action when its write ends.
final class DayOverridesProvider
    extends $NotifierProvider<DayOverrides, Map<String, Task>> {
  /// Rows changed by a day action that the board has not caught up with yet:
  /// the one round trip between «Сегодня» pressed and the server's list, so the
  /// row moves at the press. Cleared by the action when its write ends.
  DayOverridesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dayOverridesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dayOverridesHash();

  @$internal
  @override
  DayOverrides create() => DayOverrides();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, Task> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, Task>>(value),
    );
  }
}

String _$dayOverridesHash() => r'9c755e7a6283af6681fedc142dcf8bc995f3d545';

/// Rows changed by a day action that the board has not caught up with yet:
/// the one round trip between «Сегодня» pressed and the server's list, so the
/// row moves at the press. Cleared by the action when its write ends.

abstract class _$DayOverrides extends $Notifier<Map<String, Task>> {
  Map<String, Task> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Map<String, Task>, Map<String, Task>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, Task>, Map<String, Task>>,
              Map<String, Task>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The board as the day block reads it: the outbox's waiting edits and the
/// day actions in flight applied. Null while the board is not there at all.

@ProviderFor(placedBoardTasks)
final placedBoardTasksProvider = PlacedBoardTasksProvider._();

/// The board as the day block reads it: the outbox's waiting edits and the
/// day actions in flight applied. Null while the board is not there at all.

final class PlacedBoardTasksProvider
    extends $FunctionalProvider<List<DayTask>?, List<DayTask>?, List<DayTask>?>
    with $Provider<List<DayTask>?> {
  /// The board as the day block reads it: the outbox's waiting edits and the
  /// day actions in flight applied. Null while the board is not there at all.
  PlacedBoardTasksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'placedBoardTasksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$placedBoardTasksHash();

  @$internal
  @override
  $ProviderElement<List<DayTask>?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<DayTask>? create(Ref ref) {
    return placedBoardTasks(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<DayTask>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<DayTask>?>(value),
    );
  }
}

String _$placedBoardTasksHash() => r'24d88b266009814719baf35d63cd1485946190e5';

/// «Сегодня», what was closed today and «С прошлых дней», computed on the
/// client from the board (contract: offline «Сегодня» from the cache, the
/// server's `/today` is for MCP and checking). Null before any board.

@ProviderFor(dayView)
final dayViewProvider = DayViewProvider._();

/// «Сегодня», what was closed today and «С прошлых дней», computed on the
/// client from the board (contract: offline «Сегодня» from the cache, the
/// server's `/today` is for MCP and checking). Null before any board.

final class DayViewProvider
    extends $FunctionalProvider<DayView?, DayView?, DayView?>
    with $Provider<DayView?> {
  /// «Сегодня», what was closed today and «С прошлых дней», computed on the
  /// client from the board (contract: offline «Сегодня» from the cache, the
  /// server's `/today` is for MCP and checking). Null before any board.
  DayViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dayViewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dayViewHash();

  @$internal
  @override
  $ProviderElement<DayView?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DayView? create(Ref ref) {
    return dayView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DayView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DayView?>(value),
    );
  }
}

String _$dayViewHash() => r'b43be57066e49078184aaa93e4fd9842866c992b';

/// Whether the app is drawing from local copies because the server did not
/// answer: the last board refresh failed on the network. Used for the
/// «без сети» notes and the online-only buttons («Вернуть», the review).

@ProviderFor(appOffline)
final appOfflineProvider = AppOfflineProvider._();

/// Whether the app is drawing from local copies because the server did not
/// answer: the last board refresh failed on the network. Used for the
/// «без сети» notes and the online-only buttons («Вернуть», the review).

final class AppOfflineProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the app is drawing from local copies because the server did not
  /// answer: the last board refresh failed on the network. Used for the
  /// «без сети» notes and the online-only buttons («Вернуть», the review).
  AppOfflineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appOfflineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appOfflineHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return appOffline(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$appOfflineHash() => r'345ab36b6fe5fcf67ac736841d154c261f617d84';

@ProviderFor(DoneFeedState)
final doneFeedStateProvider = DoneFeedStateProvider._();

final class DoneFeedStateProvider
    extends $AsyncNotifierProvider<DoneFeedState, DoneFeed> {
  DoneFeedStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'doneFeedStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$doneFeedStateHash();

  @$internal
  @override
  DoneFeedState create() => DoneFeedState();
}

String _$doneFeedStateHash() => r'a79d51823ee8f904dcda9734844e5eedb4e8eec5';

abstract class _$DoneFeedState extends $AsyncNotifier<DoneFeed> {
  FutureOr<DoneFeed> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<DoneFeed>, DoneFeed>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<DoneFeed>, DoneFeed>,
              AsyncValue<DoneFeed>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(historyWeeks)
final historyWeeksProvider = HistoryWeeksProvider._();

final class HistoryWeeksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<HistoryWeek>>,
          List<HistoryWeek>,
          FutureOr<List<HistoryWeek>>
        >
    with
        $FutureModifier<List<HistoryWeek>>,
        $FutureProvider<List<HistoryWeek>> {
  HistoryWeeksProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'historyWeeksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyWeeksHash();

  @$internal
  @override
  $FutureProviderElement<List<HistoryWeek>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<HistoryWeek>> create(Ref ref) {
    return historyWeeks(ref);
  }
}

String _$historyWeeksHash() => r'3d11e077cd30bd6607487154ae7b7cf60e833e35';

/// `GET /reviews/status`, through the read cache: the History tab's dot and
/// the card. The local push is scheduled from it.

@ProviderFor(ReviewStatusState)
final reviewStatusStateProvider = ReviewStatusStateProvider._();

/// `GET /reviews/status`, through the read cache: the History tab's dot and
/// the card. The local push is scheduled from it.
final class ReviewStatusStateProvider
    extends $AsyncNotifierProvider<ReviewStatusState, ReviewStatus> {
  /// `GET /reviews/status`, through the read cache: the History tab's dot and
  /// the card. The local push is scheduled from it.
  ReviewStatusStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'reviewStatusStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reviewStatusStateHash();

  @$internal
  @override
  ReviewStatusState create() => ReviewStatusState();
}

String _$reviewStatusStateHash() => r'f087c23cf7405b68965c60f332fa21fa02ea5f8b';

/// `GET /reviews/status`, through the read cache: the History tab's dot and
/// the card. The local push is scheduled from it.

abstract class _$ReviewStatusState extends $AsyncNotifier<ReviewStatus> {
  FutureOr<ReviewStatus> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ReviewStatus>, ReviewStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReviewStatus>, ReviewStatus>,
              AsyncValue<ReviewStatus>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// True while the review is due: the dot on «История», the card.

@ProviderFor(reviewDue)
final reviewDueProvider = ReviewDueProvider._();

/// True while the review is due: the dot on «История», the card.

final class ReviewDueProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// True while the review is due: the dot on «История», the card.
  ReviewDueProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reviewDueProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reviewDueHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return reviewDue(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$reviewDueHash() => r'd1fbf580699e9bcae6e4bfc03173fa29df5faffd';

/// One of the device's interface notes (see `SettingsStore.readUiNote`).
/// Written optimistically: a note that fails to save costs the next run a
/// hint shown twice, not this one an error.

@ProviderFor(UiNote)
final uiNoteProvider = UiNoteFamily._();

/// One of the device's interface notes (see `SettingsStore.readUiNote`).
/// Written optimistically: a note that fails to save costs the next run a
/// hint shown twice, not this one an error.
final class UiNoteProvider extends $AsyncNotifierProvider<UiNote, String?> {
  /// One of the device's interface notes (see `SettingsStore.readUiNote`).
  /// Written optimistically: a note that fails to save costs the next run a
  /// hint shown twice, not this one an error.
  UiNoteProvider._({
    required UiNoteFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'uiNoteProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$uiNoteHash();

  @override
  String toString() {
    return r'uiNoteProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  UiNote create() => UiNote();

  @override
  bool operator ==(Object other) {
    return other is UiNoteProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$uiNoteHash() => r'4bc3f251dcaf206d68dc6934bd70a9ddf25e434b';

/// One of the device's interface notes (see `SettingsStore.readUiNote`).
/// Written optimistically: a note that fails to save costs the next run a
/// hint shown twice, not this one an error.

final class UiNoteFamily extends $Family
    with
        $ClassFamilyOverride<
          UiNote,
          AsyncValue<String?>,
          String?,
          FutureOr<String?>,
          String
        > {
  UiNoteFamily._()
    : super(
        retry: null,
        name: r'uiNoteProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// One of the device's interface notes (see `SettingsStore.readUiNote`).
  /// Written optimistically: a note that fails to save costs the next run a
  /// hint shown twice, not this one an error.

  UiNoteProvider call(String key) =>
      UiNoteProvider._(argument: key, from: this);

  @override
  String toString() => r'uiNoteProvider';
}

/// One of the device's interface notes (see `SettingsStore.readUiNote`).
/// Written optimistically: a note that fails to save costs the next run a
/// hint shown twice, not this one an error.

abstract class _$UiNote extends $AsyncNotifier<String?> {
  late final _$args = ref.$arg as String;
  String get key => _$args;

  FutureOr<String?> build(String key);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<String?>, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<String?>, String?>,
              AsyncValue<String?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
