// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Task writes made with no network, and the last week of what became of
/// them (the "Офлайн" view of the history mode).
///
/// ## What goes in, and when
///
/// Only what failed for want of a network: `ProjectTasks` tries the request
/// first, as it always has, and hands the write here when the answer is a
/// [NetworkException]. Unlike the capture queue (which takes every line, see
/// `CaptureQueue`), a task write online has a reconcile to do -- `isCurrent`,
/// positions -- and routing every edit through a file would make the common
/// case slower to buy nothing.
///
/// ## What "gentle" means here
///
/// An edit carries the values it was made against. If the server's task has
/// moved on since (edited on the laptop meanwhile), the server refuses it with
/// a 409, nothing is overwritten, and the entry waits in the history as
/// "пропущено" with both values -- the user can apply theirs on purpose, copy
/// it, or leave the server's. A create is idempotent by its key, so a replay
/// after a lost answer cannot make a twin.

@ProviderFor(Outbox)
final outboxProvider = OutboxProvider._();

/// Task writes made with no network, and the last week of what became of
/// them (the "Офлайн" view of the history mode).
///
/// ## What goes in, and when
///
/// Only what failed for want of a network: `ProjectTasks` tries the request
/// first, as it always has, and hands the write here when the answer is a
/// [NetworkException]. Unlike the capture queue (which takes every line, see
/// `CaptureQueue`), a task write online has a reconcile to do -- `isCurrent`,
/// positions -- and routing every edit through a file would make the common
/// case slower to buy nothing.
///
/// ## What "gentle" means here
///
/// An edit carries the values it was made against. If the server's task has
/// moved on since (edited on the laptop meanwhile), the server refuses it with
/// a 409, nothing is overwritten, and the entry waits in the history as
/// "пропущено" with both values -- the user can apply theirs on purpose, copy
/// it, or leave the server's. A create is idempotent by its key, so a replay
/// after a lost answer cannot make a twin.
final class OutboxProvider
    extends $AsyncNotifierProvider<Outbox, List<OutboxEntry>> {
  /// Task writes made with no network, and the last week of what became of
  /// them (the "Офлайн" view of the history mode).
  ///
  /// ## What goes in, and when
  ///
  /// Only what failed for want of a network: `ProjectTasks` tries the request
  /// first, as it always has, and hands the write here when the answer is a
  /// [NetworkException]. Unlike the capture queue (which takes every line, see
  /// `CaptureQueue`), a task write online has a reconcile to do -- `isCurrent`,
  /// positions -- and routing every edit through a file would make the common
  /// case slower to buy nothing.
  ///
  /// ## What "gentle" means here
  ///
  /// An edit carries the values it was made against. If the server's task has
  /// moved on since (edited on the laptop meanwhile), the server refuses it with
  /// a 409, nothing is overwritten, and the entry waits in the history as
  /// "пропущено" with both values -- the user can apply theirs on purpose, copy
  /// it, or leave the server's. A create is idempotent by its key, so a replay
  /// after a lost answer cannot make a twin.
  OutboxProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'outboxProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxHash();

  @$internal
  @override
  Outbox create() => Outbox();
}

String _$outboxHash() => r'9cb555fe56bde198fcd3a199331a65de08f1e2cb';

/// Task writes made with no network, and the last week of what became of
/// them (the "Офлайн" view of the history mode).
///
/// ## What goes in, and when
///
/// Only what failed for want of a network: `ProjectTasks` tries the request
/// first, as it always has, and hands the write here when the answer is a
/// [NetworkException]. Unlike the capture queue (which takes every line, see
/// `CaptureQueue`), a task write online has a reconcile to do -- `isCurrent`,
/// positions -- and routing every edit through a file would make the common
/// case slower to buy nothing.
///
/// ## What "gentle" means here
///
/// An edit carries the values it was made against. If the server's task has
/// moved on since (edited on the laptop meanwhile), the server refuses it with
/// a 409, nothing is overwritten, and the entry waits in the history as
/// "пропущено" with both values -- the user can apply theirs on purpose, copy
/// it, or leave the server's. A create is idempotent by its key, so a replay
/// after a lost answer cannot make a twin.

abstract class _$Outbox extends $AsyncNotifier<List<OutboxEntry>> {
  FutureOr<List<OutboxEntry>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<OutboxEntry>>, List<OutboxEntry>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<OutboxEntry>>, List<OutboxEntry>>,
              AsyncValue<List<OutboxEntry>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Everything in the outbox, or nothing while the file loads.

@ProviderFor(outboxEntries)
final outboxEntriesProvider = OutboxEntriesProvider._();

/// Everything in the outbox, or nothing while the file loads.

final class OutboxEntriesProvider
    extends
        $FunctionalProvider<
          List<OutboxEntry>,
          List<OutboxEntry>,
          List<OutboxEntry>
        >
    with $Provider<List<OutboxEntry>> {
  /// Everything in the outbox, or nothing while the file loads.
  OutboxEntriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboxEntriesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxEntriesHash();

  @$internal
  @override
  $ProviderElement<List<OutboxEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<OutboxEntry> create(Ref ref) {
    return outboxEntries(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<OutboxEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<OutboxEntry>>(value),
    );
  }
}

String _$outboxEntriesHash() => r'3c7ed908415f7645e5f5b0d213484bdf5015b684';

/// How many entries the history mode's badge counts: waiting, and waiting
/// for a decision.

@ProviderFor(outboxCounts)
final outboxCountsProvider = OutboxCountsProvider._();

/// How many entries the history mode's badge counts: waiting, and waiting
/// for a decision.

final class OutboxCountsProvider
    extends
        $FunctionalProvider<
          ({int decisions, int waiting}),
          ({int decisions, int waiting}),
          ({int decisions, int waiting})
        >
    with $Provider<({int decisions, int waiting})> {
  /// How many entries the history mode's badge counts: waiting, and waiting
  /// for a decision.
  OutboxCountsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboxCountsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxCountsHash();

  @$internal
  @override
  $ProviderElement<({int decisions, int waiting})> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ({int decisions, int waiting}) create(Ref ref) {
    return outboxCounts(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({int decisions, int waiting}) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<({int decisions, int waiting})>(
        value,
      ),
    );
  }
}

String _$outboxCountsHash() => r'ba8af6422aab9838db635f1c089a944e7e283921';

/// The marks of one project's rows, by task id (an unsent create's by its
/// `localTaskId`).

@ProviderFor(outboxMarks)
final outboxMarksProvider = OutboxMarksFamily._();

/// The marks of one project's rows, by task id (an unsent create's by its
/// `localTaskId`).

final class OutboxMarksProvider
    extends
        $FunctionalProvider<
          Map<String, OutboxMark>,
          Map<String, OutboxMark>,
          Map<String, OutboxMark>
        >
    with $Provider<Map<String, OutboxMark>> {
  /// The marks of one project's rows, by task id (an unsent create's by its
  /// `localTaskId`).
  OutboxMarksProvider._({
    required OutboxMarksFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outboxMarksProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outboxMarksHash();

  @override
  String toString() {
    return r'outboxMarksProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Map<String, OutboxMark>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, OutboxMark> create(Ref ref) {
    final argument = this.argument as String;
    return outboxMarks(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, OutboxMark> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, OutboxMark>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutboxMarksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outboxMarksHash() => r'4208dd9f9e62bcc40acc2414ff1ff9888af80d11';

/// The marks of one project's rows, by task id (an unsent create's by its
/// `localTaskId`).

final class OutboxMarksFamily extends $Family
    with $FunctionalFamilyOverride<Map<String, OutboxMark>, String> {
  OutboxMarksFamily._()
    : super(
        retry: null,
        name: r'outboxMarksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The marks of one project's rows, by task id (an unsent create's by its
  /// `localTaskId`).

  OutboxMarksProvider call(String projectId) =>
      OutboxMarksProvider._(argument: projectId, from: this);

  @override
  String toString() => r'outboxMarksProvider';
}

/// Whether the history mode shows its «Офлайн» view (the outbox) instead of
/// its charts. Kept above the screen so the header's switch and the body read
/// one answer.

@ProviderFor(HistoryShowsOutbox)
final historyShowsOutboxProvider = HistoryShowsOutboxProvider._();

/// Whether the history mode shows its «Офлайн» view (the outbox) instead of
/// its charts. Kept above the screen so the header's switch and the body read
/// one answer.
final class HistoryShowsOutboxProvider
    extends $NotifierProvider<HistoryShowsOutbox, bool> {
  /// Whether the history mode shows its «Офлайн» view (the outbox) instead of
  /// its charts. Kept above the screen so the header's switch and the body read
  /// one answer.
  HistoryShowsOutboxProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyShowsOutboxProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyShowsOutboxHash();

  @$internal
  @override
  HistoryShowsOutbox create() => HistoryShowsOutbox();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$historyShowsOutboxHash() =>
    r'7fb560a1e3108010e7f0d3f1605584022db4732b';

/// Whether the history mode shows its «Офлайн» view (the outbox) instead of
/// its charts. Kept above the screen so the header's switch and the body read
/// one answer.

abstract class _$HistoryShowsOutbox extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
