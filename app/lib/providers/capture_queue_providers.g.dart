// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capture_queue_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Offline capture (F8.1): the lines this device has written down and not sent
/// yet.
///
/// ## Why capture goes through here even when the network is fine
///
/// There is exactly one capture path, and it always ends up in the queue first.
/// The alternative -- send if online, queue if not -- means two code paths, two
/// sets of failure modes, and a decision ("am I online?") that no phone can
/// answer correctly in advance: the honest answer only arrives when a request
/// has already failed. So every captured line is written to disk, appears
/// immediately with an "unsent" mark, and the flush below turns it into a
/// server row moments later -- usually fast enough that the mark is never seen.
///
/// ## This reverses F8's "capture is not optimistic"
///
/// F8 made capture the one non-optimistic write in the app, and the reasoning
/// was sound *given no queue*: a line that appears and then evaporates breaks
/// the sandbox's only promise. With a queue the line does not evaporate -- it
/// is on disk before it is on screen -- so showing it immediately is no longer
/// a promise the client cannot keep.
///
/// The "unsent" mark is not decoration, it is the other half of that: without
/// it, "written down" and "written down in my pocket" would look identical, and
/// the difference matters to someone deciding whether it is safe to forget.

@ProviderFor(CaptureQueue)
final captureQueueProvider = CaptureQueueProvider._();

/// Offline capture (F8.1): the lines this device has written down and not sent
/// yet.
///
/// ## Why capture goes through here even when the network is fine
///
/// There is exactly one capture path, and it always ends up in the queue first.
/// The alternative -- send if online, queue if not -- means two code paths, two
/// sets of failure modes, and a decision ("am I online?") that no phone can
/// answer correctly in advance: the honest answer only arrives when a request
/// has already failed. So every captured line is written to disk, appears
/// immediately with an "unsent" mark, and the flush below turns it into a
/// server row moments later -- usually fast enough that the mark is never seen.
///
/// ## This reverses F8's "capture is not optimistic"
///
/// F8 made capture the one non-optimistic write in the app, and the reasoning
/// was sound *given no queue*: a line that appears and then evaporates breaks
/// the sandbox's only promise. With a queue the line does not evaporate -- it
/// is on disk before it is on screen -- so showing it immediately is no longer
/// a promise the client cannot keep.
///
/// The "unsent" mark is not decoration, it is the other half of that: without
/// it, "written down" and "written down in my pocket" would look identical, and
/// the difference matters to someone deciding whether it is safe to forget.
final class CaptureQueueProvider
    extends $AsyncNotifierProvider<CaptureQueue, List<PendingCapture>> {
  /// Offline capture (F8.1): the lines this device has written down and not sent
  /// yet.
  ///
  /// ## Why capture goes through here even when the network is fine
  ///
  /// There is exactly one capture path, and it always ends up in the queue first.
  /// The alternative -- send if online, queue if not -- means two code paths, two
  /// sets of failure modes, and a decision ("am I online?") that no phone can
  /// answer correctly in advance: the honest answer only arrives when a request
  /// has already failed. So every captured line is written to disk, appears
  /// immediately with an "unsent" mark, and the flush below turns it into a
  /// server row moments later -- usually fast enough that the mark is never seen.
  ///
  /// ## This reverses F8's "capture is not optimistic"
  ///
  /// F8 made capture the one non-optimistic write in the app, and the reasoning
  /// was sound *given no queue*: a line that appears and then evaporates breaks
  /// the sandbox's only promise. With a queue the line does not evaporate -- it
  /// is on disk before it is on screen -- so showing it immediately is no longer
  /// a promise the client cannot keep.
  ///
  /// The "unsent" mark is not decoration, it is the other half of that: without
  /// it, "written down" and "written down in my pocket" would look identical, and
  /// the difference matters to someone deciding whether it is safe to forget.
  CaptureQueueProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'captureQueueProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$captureQueueHash();

  @$internal
  @override
  CaptureQueue create() => CaptureQueue();
}

String _$captureQueueHash() => r'09d385978b5a166fa102beb7ac88889b6bec128d';

/// Offline capture (F8.1): the lines this device has written down and not sent
/// yet.
///
/// ## Why capture goes through here even when the network is fine
///
/// There is exactly one capture path, and it always ends up in the queue first.
/// The alternative -- send if online, queue if not -- means two code paths, two
/// sets of failure modes, and a decision ("am I online?") that no phone can
/// answer correctly in advance: the honest answer only arrives when a request
/// has already failed. So every captured line is written to disk, appears
/// immediately with an "unsent" mark, and the flush below turns it into a
/// server row moments later -- usually fast enough that the mark is never seen.
///
/// ## This reverses F8's "capture is not optimistic"
///
/// F8 made capture the one non-optimistic write in the app, and the reasoning
/// was sound *given no queue*: a line that appears and then evaporates breaks
/// the sandbox's only promise. With a queue the line does not evaporate -- it
/// is on disk before it is on screen -- so showing it immediately is no longer
/// a promise the client cannot keep.
///
/// The "unsent" mark is not decoration, it is the other half of that: without
/// it, "written down" and "written down in my pocket" would look identical, and
/// the difference matters to someone deciding whether it is safe to forget.

abstract class _$CaptureQueue extends $AsyncNotifier<List<PendingCapture>> {
  FutureOr<List<PendingCapture>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<PendingCapture>>, List<PendingCapture>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<PendingCapture>>,
                List<PendingCapture>
              >,
              AsyncValue<List<PendingCapture>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The lines waiting to be sent, or an empty list while the file is loading.
///
/// Empty rather than null on the way in: unlike the inbox count, "we do not
/// know yet" has no useful rendering here -- the queue is a local file that
/// loads in milliseconds, and the screen shows what it has.

@ProviderFor(pendingCaptures)
final pendingCapturesProvider = PendingCapturesProvider._();

/// The lines waiting to be sent, or an empty list while the file is loading.
///
/// Empty rather than null on the way in: unlike the inbox count, "we do not
/// know yet" has no useful rendering here -- the queue is a local file that
/// loads in milliseconds, and the screen shows what it has.

final class PendingCapturesProvider
    extends
        $FunctionalProvider<
          List<PendingCapture>,
          List<PendingCapture>,
          List<PendingCapture>
        >
    with $Provider<List<PendingCapture>> {
  /// The lines waiting to be sent, or an empty list while the file is loading.
  ///
  /// Empty rather than null on the way in: unlike the inbox count, "we do not
  /// know yet" has no useful rendering here -- the queue is a local file that
  /// loads in milliseconds, and the screen shows what it has.
  PendingCapturesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingCapturesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingCapturesHash();

  @$internal
  @override
  $ProviderElement<List<PendingCapture>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<PendingCapture> create(Ref ref) {
    return pendingCaptures(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PendingCapture> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PendingCapture>>(value),
    );
  }
}

String _$pendingCapturesHash() => r'a55ceb3132c14d61338bc329a7e74266fa541a08';
