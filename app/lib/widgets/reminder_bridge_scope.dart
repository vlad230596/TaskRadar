import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/board_providers.dart';
import '../providers/geofence_providers.dart';

/// Keeps `boardReminderBridge` -- and through it `reminderSync` -- subscribed
/// for as long as the signed-in half of the app exists, whatever is on screen.
///
/// ## Why not a `ref.watch` in a screen
///
/// That is what the planning screen used to do, and it lost alarms. Riverpod
/// pauses a `Consumer`'s subscriptions while its `TickerMode` is off, and the
/// navigator turns it off for every route covered by an opaque one -- the
/// shell, and the planning screen in it, whenever a project, a task or the
/// dictation screen is open. Which is exactly where reminders are set. With its
/// only subscriber paused the bridge went inactive, its own `listen`s on the
/// board went with it, and the new reminder never reached the OS alarm queue.
/// (The shell's own `IndexedStack` is not the culprit: it keeps hidden modes
/// ticking. But a holder inside one mode would still be one route away from the
/// same bug.)
///
/// A subscription made on the container directly is not a widget's and is
/// never paused, so this holds one and closes it on dispose. It sits in the
/// shell rather than in `main` because the board behind the bridge needs a
/// session: alive while signed out it would fetch the board and get a 401.
class ReminderBridgeScope extends StatefulWidget {
  const ReminderBridgeScope({super.key, required this.child});

  final Widget child;

  @override
  State<ReminderBridgeScope> createState() => _ReminderBridgeScopeState();
}

class _ReminderBridgeScopeState extends State<ReminderBridgeScope> {
  ProviderSubscription<void>? _bridge;

  /// The same for place reminders (`boardGeofenceBridgeProvider`): the board
  /// that arms alarms also plans the geofences.
  ProviderSubscription<void>? _geofences;

  /// Zones survive in the OS on their own, but the *access* behind them does
  /// not: the user may have granted «Разрешать всегда» in system settings, or
  /// taken it away. A resume is when that becomes visible, so the zone sync
  /// re-checks then (a diff, so it costs nothing when nothing changed).
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    final container = ProviderScope.containerOf(context, listen: false);
    _bridge = container.listen<void>(boardReminderBridgeProvider, (_, _) {});
    if (container.read(geofenceGatewayProvider).supported) {
      _geofences = container.listen<void>(
        boardGeofenceBridgeProvider,
        (_, _) {},
      );
      _lifecycle = AppLifecycleListener(
        onResume: () => resyncGeofences(container),
      );
    }
  }

  @override
  void dispose() {
    _bridge?.close();
    _geofences?.close();
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
