// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The sandbox (F8): the pile of lines the server holds, and what can happen to
/// one.
///
/// ## Where capture went (F8.1)
///
/// It is not here any more. Writing a line down is `CaptureQueue.capture` in
/// `capture_queue_providers.dart`: it goes to a file on the device first and
/// reaches the server afterwards, because the sandbox has to work with no
/// network -- "надо не забыть" arrives in a lift. This provider holds the lines
/// the server has acknowledged; the screen shows both, and the queued ones
/// carry an "unsent" mark.
///
/// That also retired the long note F8 left here about capture being the app's
/// one non-optimistic write. The reasoning was right for the code as it stood
/// (a row that appears and evaporates breaks the sandbox's only promise) and
/// wrong the moment a queue existed: with one, the line is on disk before it is
/// on screen, so showing it immediately promises nothing that cannot be kept.
///
/// ## What still requires the network, and why that is not inconsistent
///
/// Editing, discarding and filing all go straight to the server here. The
/// exception F8.1 carved out is about the *shape of the data*, not about the
/// sandbox being special: a captured line has no order, no state another device
/// can change, and a lifetime of hours, so two devices merging is set union.
/// Filing lands a task at a position in a list somebody else may have reordered
/// since -- the conflict resolution this product still defers.

@ProviderFor(Inbox)
final inboxProvider = InboxProvider._();

/// The sandbox (F8): the pile of lines the server holds, and what can happen to
/// one.
///
/// ## Where capture went (F8.1)
///
/// It is not here any more. Writing a line down is `CaptureQueue.capture` in
/// `capture_queue_providers.dart`: it goes to a file on the device first and
/// reaches the server afterwards, because the sandbox has to work with no
/// network -- "надо не забыть" arrives in a lift. This provider holds the lines
/// the server has acknowledged; the screen shows both, and the queued ones
/// carry an "unsent" mark.
///
/// That also retired the long note F8 left here about capture being the app's
/// one non-optimistic write. The reasoning was right for the code as it stood
/// (a row that appears and evaporates breaks the sandbox's only promise) and
/// wrong the moment a queue existed: with one, the line is on disk before it is
/// on screen, so showing it immediately promises nothing that cannot be kept.
///
/// ## What still requires the network, and why that is not inconsistent
///
/// Editing, discarding and filing all go straight to the server here. The
/// exception F8.1 carved out is about the *shape of the data*, not about the
/// sandbox being special: a captured line has no order, no state another device
/// can change, and a lifetime of hours, so two devices merging is set union.
/// Filing lands a task at a position in a list somebody else may have reordered
/// since -- the conflict resolution this product still defers.
final class InboxProvider
    extends $AsyncNotifierProvider<Inbox, List<InboxItem>> {
  /// The sandbox (F8): the pile of lines the server holds, and what can happen to
  /// one.
  ///
  /// ## Where capture went (F8.1)
  ///
  /// It is not here any more. Writing a line down is `CaptureQueue.capture` in
  /// `capture_queue_providers.dart`: it goes to a file on the device first and
  /// reaches the server afterwards, because the sandbox has to work with no
  /// network -- "надо не забыть" arrives in a lift. This provider holds the lines
  /// the server has acknowledged; the screen shows both, and the queued ones
  /// carry an "unsent" mark.
  ///
  /// That also retired the long note F8 left here about capture being the app's
  /// one non-optimistic write. The reasoning was right for the code as it stood
  /// (a row that appears and evaporates breaks the sandbox's only promise) and
  /// wrong the moment a queue existed: with one, the line is on disk before it is
  /// on screen, so showing it immediately promises nothing that cannot be kept.
  ///
  /// ## What still requires the network, and why that is not inconsistent
  ///
  /// Editing, discarding and filing all go straight to the server here. The
  /// exception F8.1 carved out is about the *shape of the data*, not about the
  /// sandbox being special: a captured line has no order, no state another device
  /// can change, and a lifetime of hours, so two devices merging is set union.
  /// Filing lands a task at a position in a list somebody else may have reordered
  /// since -- the conflict resolution this product still defers.
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

String _$inboxHash() => r'f2398e7971ec22607a5c82c418e6860df0d4c6e3';

/// The sandbox (F8): the pile of lines the server holds, and what can happen to
/// one.
///
/// ## Where capture went (F8.1)
///
/// It is not here any more. Writing a line down is `CaptureQueue.capture` in
/// `capture_queue_providers.dart`: it goes to a file on the device first and
/// reaches the server afterwards, because the sandbox has to work with no
/// network -- "надо не забыть" arrives in a lift. This provider holds the lines
/// the server has acknowledged; the screen shows both, and the queued ones
/// carry an "unsent" mark.
///
/// That also retired the long note F8 left here about capture being the app's
/// one non-optimistic write. The reasoning was right for the code as it stood
/// (a row that appears and evaporates breaks the sandbox's only promise) and
/// wrong the moment a queue existed: with one, the line is on disk before it is
/// on screen, so showing it immediately promises nothing that cannot be kept.
///
/// ## What still requires the network, and why that is not inconsistent
///
/// Editing, discarding and filing all go straight to the server here. The
/// exception F8.1 carved out is about the *shape of the data*, not about the
/// sandbox being special: a captured line has no order, no state another device
/// can change, and a lifetime of hours, so two devices merging is set union.
/// Filing lands a task at a position in a list somebody else may have reordered
/// since -- the conflict resolution this product still defers.

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

/// How many lines are waiting, or null while there is nothing honest to say.
///
/// Counts both halves of the sandbox: what the server holds and what is still
/// queued on this device (F8.1). A line captured in the lift is in the pile
/// from the user's point of view the moment it is typed, and a badge that only
/// caught up once the phone found a signal would be telling them their sandbox
/// is emptier than it is.
///
/// Null rather than 0 while the server half is unknown *and* nothing is queued:
/// the board draws this as a badge, and one that says "0" and then changes to
/// "3" is a small lie told every cold start. With something queued there is a
/// real number to show, so it shows it.

@ProviderFor(inboxCount)
final inboxCountProvider = InboxCountProvider._();

/// How many lines are waiting, or null while there is nothing honest to say.
///
/// Counts both halves of the sandbox: what the server holds and what is still
/// queued on this device (F8.1). A line captured in the lift is in the pile
/// from the user's point of view the moment it is typed, and a badge that only
/// caught up once the phone found a signal would be telling them their sandbox
/// is emptier than it is.
///
/// Null rather than 0 while the server half is unknown *and* nothing is queued:
/// the board draws this as a badge, and one that says "0" and then changes to
/// "3" is a small lie told every cold start. With something queued there is a
/// real number to show, so it shows it.

final class InboxCountProvider extends $FunctionalProvider<int?, int?, int?>
    with $Provider<int?> {
  /// How many lines are waiting, or null while there is nothing honest to say.
  ///
  /// Counts both halves of the sandbox: what the server holds and what is still
  /// queued on this device (F8.1). A line captured in the lift is in the pile
  /// from the user's point of view the moment it is typed, and a badge that only
  /// caught up once the phone found a signal would be telling them their sandbox
  /// is emptier than it is.
  ///
  /// Null rather than 0 while the server half is unknown *and* nothing is queued:
  /// the board draws this as a badge, and one that says "0" and then changes to
  /// "3" is a small lie told every cold start. With something queued there is a
  /// real number to show, so it shows it.
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

String _$inboxCountHash() => r'a292277e4112f06ee6f4c144a641ff13eee8d6af';
