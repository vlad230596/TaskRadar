import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home_widget/home_widget_gateway.dart';
import '../home_widget/home_widget_snapshot.dart';
import '../models/focus_task.dart';
import '../providers/focus_providers.dart';
import '../providers/home_widget_providers.dart';
import '../providers/notification_link_providers.dart';
import '../providers/read_cache_providers.dart';
import '../storage/read_cache_store.dart';

/// Keeps the Android home-screen widget («В работе») in step with the app, and
/// turns taps on it into what the app does with them.
///
/// ## What goes out
///
/// A [HomeWidgetSnapshot] of `focusSetProvider` -- the work mode's own set --
/// every time that set changes: the first load (cache or network), a take,
/// drop or «сделано», a refresh, and the quiet re-read on resume. The widget
/// draws the last snapshot it got, so offline it keeps showing the set with
/// the time it was true.
///
/// A set that failed to load with no copy publishes **nothing**: the widget's
/// previous snapshot is a better answer than an empty list.
///
/// ## What comes in
///
/// - a task tap: handed to `NotificationLink.open`, the same path a reminder
///   tap takes -- the board lookup, the archive fallback, the «нет связи»
///   dialog, and the navigation in `NotificationLinkScope`;
/// - the refresh arrow: a quiet re-read of the set ([FocusSet.syncQuietly]).
///
/// Collapse and expand never reach Dart -- the widget does them itself.
///
/// ## Where it sits
///
/// Inside the signed-in half of the app, under `NotificationLinkScope`: both
/// directions need a session (reading the set, resolving a task), and a tap that
/// arrives while signed out waits in `MainActivity` until this mounts. Leaving
/// the signed-in half (sign-out, a 401) tells the widget so, rather than
/// leaving the last user's tasks on the home screen.
class HomeWidgetScope extends ConsumerStatefulWidget {
  const HomeWidgetScope({required this.child, super.key});

  final Widget child;

  /// A resume re-reads the set only when the last fresh answer is older than
  /// this. Coming back to the app every few seconds should not cost a request
  /// each time.
  static const Duration resumeSyncAfter = Duration(minutes: 2);

  @override
  ConsumerState<HomeWidgetScope> createState() => _HomeWidgetScopeState();
}

class _HomeWidgetScopeState extends ConsumerState<HomeWidgetScope> {
  late final HomeWidgetGateway _gateway;
  AppLifecycleListener? _lifecycle;
  DateTime? _lastFresh;
  String? _lastPublished;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(homeWidgetGatewayProvider);
    if (!_gateway.supported) return;

    _gateway.setActionListener(_drainActions);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _drainActions();
        _syncIfStale();
      },
    );

    // After the first frame, like the other scopes: the shell paints first,
    // and `NotificationLinkScope` above is mounted by then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishFrom(ref.read(focusSetProvider));
      _drainActions();
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    if (_gateway.supported) {
      _gateway.setActionListener(null);
      unawaited(
        _gateway.publish(
          HomeWidgetSnapshot.signedOut(at: DateTime.now()).encode(),
        ),
      );
    }
    super.dispose();
  }

  void _publishFrom(AsyncValue<List<FocusTask>> set) {
    final rows = set.value;
    if (rows == null) return;

    final cachedAt = ref.read(cachedReadsProvider)[ReadCacheKeys.focus];
    if (cachedAt == null) _lastFresh = DateTime.now();

    final json = buildHomeWidgetSnapshot(
      rows,
      updatedAt: cachedAt ?? DateTime.now(),
      fromCache: cachedAt != null,
    ).encode();
    if (json == _lastPublished) return;
    _lastPublished = json;
    unawaited(_gateway.publish(json));
  }

  void _syncIfStale() {
    final last = _lastFresh;
    if (last != null &&
        DateTime.now().difference(last) < HomeWidgetScope.resumeSyncAfter) {
      return;
    }
    unawaited(ref.read(focusSetProvider.notifier).syncQuietly());
  }

  /// Takes every waiting action. A loop, because a tap can land while the
  /// previous one is being taken.
  Future<void> _drainActions() async {
    while (mounted) {
      final action = await _gateway.takeAction();
      if (action == null || !mounted) return;
      switch (action) {
        case HomeWidgetOpenTask(:final taskId):
          unawaited(ref.read(notificationLinkProvider.notifier).open(taskId));
        case HomeWidgetRefresh():
          _lastFresh = null;
          await ref.read(focusSetProvider.notifier).syncQuietly();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_gateway.supported) {
      ref.listen<AsyncValue<List<FocusTask>>>(
        focusSetProvider,
        (_, next) => _publishFrom(next),
      );
      // The set can stay the same object while its provenance changes (a
      // cached copy confirmed by the network): the stamp on the widget must
      // follow.
      ref.listen<DateTime?>(
        cachedReadsProvider.select((reads) => reads[ReadCacheKeys.focus]),
        (_, _) => _publishFrom(ref.read(focusSetProvider)),
      );
    }
    return widget.child;
  }
}
