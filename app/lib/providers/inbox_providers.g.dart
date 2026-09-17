// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The sandbox (F8): the pile, and the four things that can happen to a line in
/// it.
///
/// ## Why the writes here are not optimistic
///
/// Every other write in this app shows its result immediately and rolls back on
/// failure (`project_providers.dart` explains why). Capture is the exception,
/// and for a reason specific to what it is for: **a captured line that quietly
/// disappears is the failure this feature exists to prevent.** An optimistic
/// row is a promise the client cannot keep without a queue, and there is no
/// queue -- `../../../flutter-migration-plan.md` still defers offline editing.
/// So capture waits for the server and only then shows the line, and a failure
/// is a message with the text still in the field rather than a row that appears
/// and then evaporates.
///
/// That is also the honest limit of F8, worth knowing before relying on it:
/// **capture needs the network.** The scenario it is built for -- writing
/// something down while walking -- is exactly the one where the phone may have
/// no signal. If that turns out to matter in practice, an offline capture queue
/// is the natural first exception to the no-offline-writes rule, precisely
/// because an inbox item has no ordering and no conflicts: two devices can only
/// ever add lines.

@ProviderFor(Inbox)
final inboxProvider = InboxProvider._();

/// The sandbox (F8): the pile, and the four things that can happen to a line in
/// it.
///
/// ## Why the writes here are not optimistic
///
/// Every other write in this app shows its result immediately and rolls back on
/// failure (`project_providers.dart` explains why). Capture is the exception,
/// and for a reason specific to what it is for: **a captured line that quietly
/// disappears is the failure this feature exists to prevent.** An optimistic
/// row is a promise the client cannot keep without a queue, and there is no
/// queue -- `../../../flutter-migration-plan.md` still defers offline editing.
/// So capture waits for the server and only then shows the line, and a failure
/// is a message with the text still in the field rather than a row that appears
/// and then evaporates.
///
/// That is also the honest limit of F8, worth knowing before relying on it:
/// **capture needs the network.** The scenario it is built for -- writing
/// something down while walking -- is exactly the one where the phone may have
/// no signal. If that turns out to matter in practice, an offline capture queue
/// is the natural first exception to the no-offline-writes rule, precisely
/// because an inbox item has no ordering and no conflicts: two devices can only
/// ever add lines.
final class InboxProvider
    extends $AsyncNotifierProvider<Inbox, List<InboxItem>> {
  /// The sandbox (F8): the pile, and the four things that can happen to a line in
  /// it.
  ///
  /// ## Why the writes here are not optimistic
  ///
  /// Every other write in this app shows its result immediately and rolls back on
  /// failure (`project_providers.dart` explains why). Capture is the exception,
  /// and for a reason specific to what it is for: **a captured line that quietly
  /// disappears is the failure this feature exists to prevent.** An optimistic
  /// row is a promise the client cannot keep without a queue, and there is no
  /// queue -- `../../../flutter-migration-plan.md` still defers offline editing.
  /// So capture waits for the server and only then shows the line, and a failure
  /// is a message with the text still in the field rather than a row that appears
  /// and then evaporates.
  ///
  /// That is also the honest limit of F8, worth knowing before relying on it:
  /// **capture needs the network.** The scenario it is built for -- writing
  /// something down while walking -- is exactly the one where the phone may have
  /// no signal. If that turns out to matter in practice, an offline capture queue
  /// is the natural first exception to the no-offline-writes rule, precisely
  /// because an inbox item has no ordering and no conflicts: two devices can only
  /// ever add lines.
  InboxProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'inboxProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxHash();

  @$internal
  @override
  Inbox create() => Inbox();
}

String _$inboxHash() => r'c3855c4f4cdfde5b92b62787ed2fbaf159f9a364';

/// The sandbox (F8): the pile, and the four things that can happen to a line in
/// it.
///
/// ## Why the writes here are not optimistic
///
/// Every other write in this app shows its result immediately and rolls back on
/// failure (`project_providers.dart` explains why). Capture is the exception,
/// and for a reason specific to what it is for: **a captured line that quietly
/// disappears is the failure this feature exists to prevent.** An optimistic
/// row is a promise the client cannot keep without a queue, and there is no
/// queue -- `../../../flutter-migration-plan.md` still defers offline editing.
/// So capture waits for the server and only then shows the line, and a failure
/// is a message with the text still in the field rather than a row that appears
/// and then evaporates.
///
/// That is also the honest limit of F8, worth knowing before relying on it:
/// **capture needs the network.** The scenario it is built for -- writing
/// something down while walking -- is exactly the one where the phone may have
/// no signal. If that turns out to matter in practice, an offline capture queue
/// is the natural first exception to the no-offline-writes rule, precisely
/// because an inbox item has no ordering and no conflicts: two devices can only
/// ever add lines.

abstract class _$Inbox extends $AsyncNotifier<List<InboxItem>> {
  FutureOr<List<InboxItem>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<InboxItem>>, List<InboxItem>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<InboxItem>>, List<InboxItem>>,
              AsyncValue<List<InboxItem>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// How many lines are waiting, or null while the pile has not loaded.
///
/// Null rather than 0 on purpose: the board draws this as a badge, and a badge
/// that says nothing while the request is in flight is right, whereas one that
/// says "0" and then changes to "3" is a small lie told every cold start.

@ProviderFor(inboxCount)
final inboxCountProvider = InboxCountProvider._();

/// How many lines are waiting, or null while the pile has not loaded.
///
/// Null rather than 0 on purpose: the board draws this as a badge, and a badge
/// that says nothing while the request is in flight is right, whereas one that
/// says "0" and then changes to "3" is a small lie told every cold start.

final class InboxCountProvider extends $FunctionalProvider<int?, int?, int?>
    with $Provider<int?> {
  /// How many lines are waiting, or null while the pile has not loaded.
  ///
  /// Null rather than 0 on purpose: the board draws this as a badge, and a badge
  /// that says nothing while the request is in flight is right, whereas one that
  /// says "0" and then changes to "3" is a small lie told every cold start.
  InboxCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxCountProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxCountHash();

  @$internal
  @override
  $ProviderElement<int?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int? create(Ref ref) {
    return inboxCount(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$inboxCountHash() => r'a2501c7bc6b63712a190cb3c9e7f506f7e6eaedb';
