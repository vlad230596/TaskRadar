// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'board_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The board: one fetch, one cache, and the rule for which of the two is on
/// screen.
///
/// ## The shape, and why it is three providers instead of one
///
/// The plan's requirement is "the screen draws from the snapshot instantly
/// while a request for fresh data goes out in parallel". The obvious way to
/// write that -- one notifier that returns the cache from `build` and then
/// overwrites its own state when the request lands -- has a race that is
/// invisible until it bites: a transport that answers immediately (which is
/// exactly what the fake backend in the tests does) can complete *before* the
/// cached first value has been published, and the notifier then overwrites the
/// fresh board with the stale one.
///
/// So the two sources stay separate and honest:
///
/// - [board] is only ever the network. Loading means "the wire has not
///   answered", an error means "the wire failed", and it knows nothing about
///   files.
/// - [boardSnapshot] is only ever the disk, read once.
/// - [boardView] combines them into the single value the screen renders, and it
///   is a plain synchronous provider, so there is no state to race over.
///
/// The parallelism falls out of it: [boardView] watches both in one synchronous
/// build, so the HTTP request and the disk read start in the same microtask.
/// The last good board from disk, or null if there is nothing usable there.
///
/// Read exactly once per app run: after the first successful refresh the
/// snapshot is strictly worse than what [board] holds, and re-reading it could
/// only ever show the user older data than they already have.

@ProviderFor(boardSnapshot)
final boardSnapshotProvider = BoardSnapshotProvider._();

/// The board: one fetch, one cache, and the rule for which of the two is on
/// screen.
///
/// ## The shape, and why it is three providers instead of one
///
/// The plan's requirement is "the screen draws from the snapshot instantly
/// while a request for fresh data goes out in parallel". The obvious way to
/// write that -- one notifier that returns the cache from `build` and then
/// overwrites its own state when the request lands -- has a race that is
/// invisible until it bites: a transport that answers immediately (which is
/// exactly what the fake backend in the tests does) can complete *before* the
/// cached first value has been published, and the notifier then overwrites the
/// fresh board with the stale one.
///
/// So the two sources stay separate and honest:
///
/// - [board] is only ever the network. Loading means "the wire has not
///   answered", an error means "the wire failed", and it knows nothing about
///   files.
/// - [boardSnapshot] is only ever the disk, read once.
/// - [boardView] combines them into the single value the screen renders, and it
///   is a plain synchronous provider, so there is no state to race over.
///
/// The parallelism falls out of it: [boardView] watches both in one synchronous
/// build, so the HTTP request and the disk read start in the same microtask.
/// The last good board from disk, or null if there is nothing usable there.
///
/// Read exactly once per app run: after the first successful refresh the
/// snapshot is strictly worse than what [board] holds, and re-reading it could
/// only ever show the user older data than they already have.

final class BoardSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<BoardSnapshot?>,
          BoardSnapshot?,
          FutureOr<BoardSnapshot?>
        >
    with $FutureModifier<BoardSnapshot?>, $FutureProvider<BoardSnapshot?> {
  /// The board: one fetch, one cache, and the rule for which of the two is on
  /// screen.
  ///
  /// ## The shape, and why it is three providers instead of one
  ///
  /// The plan's requirement is "the screen draws from the snapshot instantly
  /// while a request for fresh data goes out in parallel". The obvious way to
  /// write that -- one notifier that returns the cache from `build` and then
  /// overwrites its own state when the request lands -- has a race that is
  /// invisible until it bites: a transport that answers immediately (which is
  /// exactly what the fake backend in the tests does) can complete *before* the
  /// cached first value has been published, and the notifier then overwrites the
  /// fresh board with the stale one.
  ///
  /// So the two sources stay separate and honest:
  ///
  /// - [board] is only ever the network. Loading means "the wire has not
  ///   answered", an error means "the wire failed", and it knows nothing about
  ///   files.
  /// - [boardSnapshot] is only ever the disk, read once.
  /// - [boardView] combines them into the single value the screen renders, and it
  ///   is a plain synchronous provider, so there is no state to race over.
  ///
  /// The parallelism falls out of it: [boardView] watches both in one synchronous
  /// build, so the HTTP request and the disk read start in the same microtask.
  /// The last good board from disk, or null if there is nothing usable there.
  ///
  /// Read exactly once per app run: after the first successful refresh the
  /// snapshot is strictly worse than what [board] holds, and re-reading it could
  /// only ever show the user older data than they already have.
  BoardSnapshotProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardSnapshotProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardSnapshotHash();

  @$internal
  @override
  $FutureProviderElement<BoardSnapshot?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BoardSnapshot?> create(Ref ref) {
    return boardSnapshot(ref);
  }
}

String _$boardSnapshotHash() => r'd5859f6705b6db7d0ec6017f7d04c21634e72b2d';

/// `GET /board?archived=false`, plus the snapshot write that follows it.

@ProviderFor(Board)
final boardProvider = BoardProvider._();

/// `GET /board?archived=false`, plus the snapshot write that follows it.
final class BoardProvider extends $AsyncNotifierProvider<Board, FreshBoard> {
  /// `GET /board?archived=false`, plus the snapshot write that follows it.
  BoardProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'boardProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardHash();

  @$internal
  @override
  Board create() => Board();
}

String _$boardHash() => r'9012e9c82da11d11bd6b1329b65719c34da7e51b';

/// `GET /board?archived=false`, plus the snapshot write that follows it.

abstract class _$Board extends $AsyncNotifier<FreshBoard> {
  FutureOr<FreshBoard> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<FreshBoard>, FreshBoard>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<FreshBoard>, FreshBoard>,
              AsyncValue<FreshBoard>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Folds the network provider and the snapshot into one value.

@ProviderFor(boardView)
final boardViewProvider = BoardViewProvider._();

/// Folds the network provider and the snapshot into one value.

final class BoardViewProvider
    extends $FunctionalProvider<BoardView, BoardView, BoardView>
    with $Provider<BoardView> {
  /// Folds the network provider and the snapshot into one value.
  BoardViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardViewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardViewHash();

  @$internal
  @override
  $ProviderElement<BoardView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BoardView create(Ref ref) {
    return boardView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BoardView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BoardView>(value),
    );
  }
}

String _$boardViewHash() => r'0e645314fd354af0c35497b7549a66a8943d3e9b';

/// The wire from "the board changed" to "the OS alarm queue changed".
///
/// ## What this preserves
///
/// F1 built the reminder graph so that **changing the target set *is* the
/// reschedule**: `reminderSync` watches `reminderTargets`, so nobody calls
/// "reschedule" and there is no second place that has to remember to. This
/// provider keeps that property while adding the real data source -- it writes
/// the targets and nothing else. No scheduler call appears anywhere in the
/// board code.
///
/// ## Why it is a provider with two `listen`s
///
/// - The board is *listened to*, not watched, because writing another
///   notifier's state is a side effect and belongs outside a build.
/// - `reminderSync` is listened to with an empty callback purely to keep it
///   alive. A `keepAlive` provider that nobody subscribes to is never created
///   at all, so without this the targets would change and nothing downstream
///   would exist to notice. An empty `listen` rather than a `watch` because a
///   `watch` would rebuild this provider on every sync report and re-register
///   both subscriptions.
///
/// The board screen watches this once; that is the only thing that has to
/// remember anything.

@ProviderFor(boardReminderBridge)
final boardReminderBridgeProvider = BoardReminderBridgeProvider._();

/// The wire from "the board changed" to "the OS alarm queue changed".
///
/// ## What this preserves
///
/// F1 built the reminder graph so that **changing the target set *is* the
/// reschedule**: `reminderSync` watches `reminderTargets`, so nobody calls
/// "reschedule" and there is no second place that has to remember to. This
/// provider keeps that property while adding the real data source -- it writes
/// the targets and nothing else. No scheduler call appears anywhere in the
/// board code.
///
/// ## Why it is a provider with two `listen`s
///
/// - The board is *listened to*, not watched, because writing another
///   notifier's state is a side effect and belongs outside a build.
/// - `reminderSync` is listened to with an empty callback purely to keep it
///   alive. A `keepAlive` provider that nobody subscribes to is never created
///   at all, so without this the targets would change and nothing downstream
///   would exist to notice. An empty `listen` rather than a `watch` because a
///   `watch` would rebuild this provider on every sync report and re-register
///   both subscriptions.
///
/// The board screen watches this once; that is the only thing that has to
/// remember anything.

final class BoardReminderBridgeProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// The wire from "the board changed" to "the OS alarm queue changed".
  ///
  /// ## What this preserves
  ///
  /// F1 built the reminder graph so that **changing the target set *is* the
  /// reschedule**: `reminderSync` watches `reminderTargets`, so nobody calls
  /// "reschedule" and there is no second place that has to remember to. This
  /// provider keeps that property while adding the real data source -- it writes
  /// the targets and nothing else. No scheduler call appears anywhere in the
  /// board code.
  ///
  /// ## Why it is a provider with two `listen`s
  ///
  /// - The board is *listened to*, not watched, because writing another
  ///   notifier's state is a side effect and belongs outside a build.
  /// - `reminderSync` is listened to with an empty callback purely to keep it
  ///   alive. A `keepAlive` provider that nobody subscribes to is never created
  ///   at all, so without this the targets would change and nothing downstream
  ///   would exist to notice. An empty `listen` rather than a `watch` because a
  ///   `watch` would rebuild this provider on every sync report and re-register
  ///   both subscriptions.
  ///
  /// The board screen watches this once; that is the only thing that has to
  /// remember anything.
  BoardReminderBridgeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardReminderBridgeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardReminderBridgeHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return boardReminderBridge(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$boardReminderBridgeHash() =>
    r'9acddb8a586422d4d24a7683df33f6760eb61469';
