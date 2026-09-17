import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_exception.dart';
import '../models/inbox_item.dart';
import '../storage/capture_queue_store.dart';
import 'board_providers.dart' show noAutomaticRetry;
import 'dependencies.dart';
import 'inbox_providers.dart';

part 'capture_queue_providers.g.dart';

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
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class CaptureQueue extends _$CaptureQueue {
  /// The tail of the chain of flushes, so that they run one after another.
  ///
  /// Not "return early if one is already running", which is the obvious version
  /// and is wrong in a way that loses work: a pass sends the queue *as it stood
  /// when it started*, so a line captured a second later -- while the first
  /// request is still in flight -- would sit there until some later trigger
  /// happened to come along. Chaining means every caller's line is sent by the
  /// time that caller's future completes.
  ///
  /// Not "run them in parallel" either: two passes over the same queue would
  /// send the same line twice, which the server's idempotency key forgives and
  /// which is still pointless work on a phone's radio.
  Future<void>? _flushing;

  @override
  Future<List<PendingCapture>> build() {
    return ref.read(captureQueueStoreProvider).read();
  }

  /// Writes [text] down: to disk first, then to the screen, then (if there is a
  /// network) to the server.
  ///
  /// Returns once the line is **persisted**, which is the moment the promise
  /// "it is written down" becomes true. Sending happens after, without being
  /// awaited, so a capture on a train is as fast as one at a desk.
  ///
  /// Throws only if the disk write failed -- the one failure the user has to
  /// know about, because then the line exists nowhere.
  Future<PendingCapture> capture(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'an inbox item needs text');
    }

    final entry = PendingCapture(
      key: PendingCapture.newKey(),
      text: trimmed,
      capturedAt: DateTime.now(),
    );

    // Appended: the queue drains oldest first, in the order things were thought
    // of. `await future` rather than `state.value` because a capture can happen
    // before the file has finished loading (the composer autofocuses on a
    // screen that has just opened), and dropping the not-yet-loaded queue on
    // the floor would lose whatever was still waiting from last time.
    final queue = <PendingCapture>[...await future, entry];
    await ref.read(captureQueueStoreProvider).write(queue);
    _publish(queue);

    unawaited(flush());
    return entry;
  }

  /// Forgets a line that has not been sent yet.
  ///
  /// There is a race here, and it is the honest kind: if this lands while the
  /// line is in flight, the server keeps its copy and the line reappears on the
  /// next refresh as an ordinary item -- which can then be thrown away the
  /// ordinary way. The alternative (blocking the button while a request is in
  /// flight) would make the common case worse to protect against a window of a
  /// few hundred milliseconds, and the failure mode of this choice is "it is
  /// still there", never "it is gone twice over".
  Future<void> discard(PendingCapture entry) async {
    final queue = (await future)
        .where((row) => row.key != entry.key)
        .toList(growable: false);
    await ref.read(captureQueueStoreProvider).write(queue);
    _publish(queue);
  }

  /// Sends what is queued, oldest first. Never throws.
  ///
  /// Called on capture, on app start, on resume, and on pull-to-refresh -- i.e.
  /// at every moment when the network might have just come back. There is no
  /// timer and no retry schedule: this app has no background worker yet, and a
  /// poll that runs while the user is looking at something else would spend
  /// battery to be marginally earlier than the next resume.
  Future<void> flush() {
    final running = _flushing;
    final next = running == null ? _flush() : running.then((_) => _flush());
    _flushing = next;
    // Cleared only if nothing else has queued behind it in the meantime, so the
    // chain does not detach from its own tail.
    next.whenComplete(() {
      if (identical(_flushing, next)) _flushing = null;
    });
    return next;
  }

  Future<void> _flush() async {
    final queue = await future;
    if (queue.isEmpty) return;

    final api = ref.read(inboxApiProvider);
    final sent = <InboxItem>[];
    final sentKeys = <String>{};
    final refusedKeys = <String>{};

    for (final entry in queue) {
      try {
        final item = await api.capture(text: entry.text, captureKey: entry.key);
        sentKeys.add(entry.key);
        sent.add(item);
      } on NetworkException {
        // Still no network. Stop: every following line would fail the same way,
        // and the queue is meant to drain in order.
        break;
      } on UnauthorizedException {
        // The session is gone. The 401 interceptor is already taking the user
        // to the login screen; the queue survives on disk and is flushed again
        // when the signed-in half of the app is mounted anew.
        break;
      } on ApiException catch (error) {
        // The server answered, and said no. That is not a connectivity problem
        // and looping will not fix it, so the line is *kept* -- it is still the
        // only copy of a thought -- and marked, which is what puts a visible
        // "сервер не принял" on it and offers a way out. The next flush tries
        // again: a 500 deserves another attempt, and a 400 costs one request to
        // learn nothing new. The lines behind it are not held hostage.
        debugPrint('Capture ${entry.key} refused: $error');
        refusedKeys.add(entry.key);
        continue;
      }
    }

    if (sentKeys.isEmpty && refusedKeys.isEmpty) return;

    /*
     * Reconciled against the queue **as it stands now**, not against the
     * snapshot this pass started from.
     *
     * A capture can land while a request is in flight -- that is the normal
     * case, not a corner one: typing the next line takes less time than a
     * round trip. Writing back `snapshot minus sent` would quietly drop that
     * new line from both the screen and the file, which is the exact failure
     * this whole feature exists to prevent.
     */
    final live = await future;
    final remaining = <PendingCapture>[
      for (final row in live)
        if (!sentKeys.contains(row.key))
          refusedKeys.contains(row.key) ? row.copyWith(failed: true) : row,
    ];

    if (sentKeys.isNotEmpty) {
      try {
        await ref.read(captureQueueStoreProvider).write(remaining);
      } catch (error) {
        // The lines *are* on the server; the file still lists them. The next
        // launch will send them again, which is exactly the case the
        // idempotency key exists for, so no duplicate materialises -- a stale
        // file is a better failure than a queue the user cannot see drain.
        debugPrint('Could not shorten the capture queue on disk: $error');
      }

      // Into the pile, without a round trip: the rows just came from the
      // server, in the shape `GET /inbox` would have sent them.
      ref.read(inboxProvider.notifier).adoptAll(sent);
    }

    _publish(remaining);
  }

  void _publish(List<PendingCapture> queue) {
    // A flush outlives its trigger by design -- it is started unawaited from a
    // capture and from a lifecycle callback -- so it can still be in flight
    // when the provider is torn down (sign-out, a test's container being
    // disposed). Publishing into a disposed notifier throws; the lines are
    // already safe on disk, so there is nothing to salvage and nothing to
    // report.
    if (!ref.mounted) return;

    state = AsyncValue<List<PendingCapture>>.data(
      List<PendingCapture>.unmodifiable(queue),
    );
  }
}

/// The lines waiting to be sent, or an empty list while the file is loading.
///
/// Empty rather than null on the way in: unlike the inbox count, "we do not
/// know yet" has no useful rendering here -- the queue is a local file that
/// loads in milliseconds, and the screen shows what it has.
@Riverpod(keepAlive: true)
List<PendingCapture> pendingCaptures(Ref ref) =>
    ref.watch(captureQueueProvider).value ?? const <PendingCapture>[];
