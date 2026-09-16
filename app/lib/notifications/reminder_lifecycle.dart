import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/reminder_providers.dart';

/// Re-runs the reminder resync every time the app comes back to the foreground.
///
/// ## Why this is not optional
///
/// The OS queue is not durable in the way the code above it pretends. Android
/// drops every scheduled alarm on reboot (the boot receiver in the manifest is
/// what re-arms them), a force-stop from the app switcher drops them too and
/// there is no receiver for that, and OEM "battery optimisation" sweeps clear
/// them for reasons the app is never told about. A resync on foreground is the
/// cheap, always-available repair: whatever the queue looks like, thirty
/// milliseconds after the user opens the app it matches the target set again.
///
/// It is also the fallback for freshness. A reminder created on the desktop
/// reaches the phone on the next board refresh; opening the app is the most
/// common moment that happens.
///
/// Mounted above the whole app (see `app.dart`) rather than inside the
/// signed-in half, because the listener costs nothing until a resume actually
/// happens and it should not be torn down and rebuilt by a login.
class ReminderLifecycleScope extends ConsumerStatefulWidget {
  const ReminderLifecycleScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReminderLifecycleScope> createState() =>
      _ReminderLifecycleScopeState();
}

class _ReminderLifecycleScopeState
    extends ConsumerState<ReminderLifecycleScope> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    // Nothing is *read* here on purpose: touching the reminder providers in
    // `initState` would initialise the notification plugin on every cold start,
    // including in widget tests that care about nothing of the sort. The first
    // resume is early enough.
    _listener = AppLifecycleListener(onResume: _resync);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _resync() {
    // Fire and forget: a lifecycle callback must return immediately, and
    // `sync` already swallows its own failures into a report.
    unawaited(
      ref
          .read(reminderSyncProvider.notifier)
          .resync()
          .catchError(
            (Object error) =>
                debugPrint('Foreground reminder resync failed: $error'),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
