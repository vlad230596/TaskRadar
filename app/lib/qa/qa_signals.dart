import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/board_providers.dart';

/// `--dart-define=TASKRADAR_QA=true`: the emulator QA package
/// (`tests/android/`). Gradle reads the same define to give that build its own
/// application id, so this is never true in an APK that a person uses.
const bool qaBuild = bool.fromEnvironment('TASKRADAR_QA');

/// Tells Android when the first frame with real board rows is on screen.
///
/// `MainActivity` turns the call into `reportFullyDrawn()`, and the bench
/// reads the resulting "Fully drawn" launch time from logcat: process start to
/// a board the user can read, which is the number the offline promise is
/// about. Not the splash, not the first frame, not an automation round trip.
///
/// Fires once per process and only for [BoardReady] -- a spinner or an error
/// page is not "useful", and timing them would pass a broken cache.
class QaBoardDrawnSignal extends ConsumerStatefulWidget {
  const QaBoardDrawnSignal({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<QaBoardDrawnSignal> createState() => _QaBoardDrawnSignalState();
}

class _QaBoardDrawnSignalState extends ConsumerState<QaBoardDrawnSignal> {
  static bool _sent = false;

  void _maybeSend(BoardView view) {
    if (_sent || view is! BoardReady || view.projects.isEmpty) return;
    _sent = true;
    // After the frame that draws the rows has been handed to the engine, and
    // one more frame, so it has been rasterized rather than merely built.
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
      try {
        await const MethodChannel(
          'taskradar/qa',
        ).invokeMethod<void>('cachedBoardRasterized');
      } on PlatformException catch (error) {
        debugPrint('QA signal failed: $error');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(boardViewProvider, (_, next) => _maybeSend(next));
    _maybeSend(ref.read(boardViewProvider));
    return widget.child;
  }
}
