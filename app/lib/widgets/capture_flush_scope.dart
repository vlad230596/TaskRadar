import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/capture_queue_providers.dart';

/// Sends whatever the capture queue is holding, whenever there is a fresh
/// reason to believe the network is back (F8.1).
///
/// ## The two moments, and why they are enough
///
/// **Mount** -- which is the app starting, or a login. A line captured
/// yesterday in a lift should be on the server before the user has finished
/// looking at the board, without them going anywhere near the sandbox screen.
///
/// **Resume** -- the app coming back to the foreground, which is the single
/// best signal a phone offers that the world may have changed. The user walked
/// out of the metro, unlocked the phone, and the queue drains while they are
/// reading a notification.
///
/// There is deliberately **no timer and no connectivity listener**. A poll
/// would spend battery to beat the next resume by minutes, and a connectivity
/// package would add a dependency and a permission to learn something the next
/// request discovers for free -- "connected" on Android means an interface is
/// up, not that this server can be reached. The plan's third trigger, the
/// `workmanager` periodic task, is not wired up because that worker does not
/// exist in this app yet; when it does, it calls `flush()` and this comment
/// gets a line shorter.
///
/// Mounted **inside** the signed-in half of the app (see `app.dart`), unlike
/// `ReminderLifecycleScope`: flushing needs a session, and a queue flushed
/// under no session would just collect 401s. The lines are safe on disk in the
/// meantime -- that is the whole point of the file.
class CaptureFlushScope extends ConsumerStatefulWidget {
  const CaptureFlushScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CaptureFlushScope> createState() => _CaptureFlushScopeState();
}

class _CaptureFlushScopeState extends ConsumerState<CaptureFlushScope> {
  late final AppLifecycleListener _listener;

  /// While something is unsent and the app is in front, try again every
  /// [retryEvery]. Start and resume alone missed the most common case: the
  /// app stays open while the phone walks back into coverage, and the line
  /// sat "не отправлено" until the next restart. Foreground only and only
  /// with a non-empty queue, so an idle app makes no requests.
  static const Duration retryEvery = Duration(seconds: 30);
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () {
        _flush();
        _retry ??= Timer.periodic(retryEvery, (_) => _retryIfPending());
      },
      onPause: () {
        _retry?.cancel();
        _retry = null;
      },
    );
    _retry = Timer.periodic(retryEvery, (_) => _retryIfPending());

    // After the first frame rather than during `initState`: reading a provider
    // here would build the queue (a file read) inside a widget's construction,
    // and the board this sits above should paint first. The queue has waited
    // since the last session; it can wait one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _flush();
    });
  }

  void _retryIfPending() {
    if (ref.read(pendingCapturesProvider).isNotEmpty) _flush();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _listener.dispose();
    super.dispose();
  }

  void _flush() {
    // Fire and forget: a lifecycle callback must return immediately, and
    // `flush` already swallows its own failures -- an unsendable queue is a
    // normal state, not an error to report from here.
    unawaited(ref.read(captureQueueProvider.notifier).flush());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
