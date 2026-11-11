import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Something the user did on the home-screen widget that the app has to
/// finish: open a task, or refresh the set.
///
/// Collapse and expand are **not** here: those are handled natively in the
/// widget and never wake the app.
@immutable
sealed class HomeWidgetAction {
  const HomeWidgetAction();

  /// Parses what `MainActivity.takeAction` answers. Anything unrecognised is
  /// null -- a newer widget talking to an older Dart side must not crash it.
  static HomeWidgetAction? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    switch (map['action']) {
      case 'openTask':
        final taskId = map['taskId'];
        if (taskId is! String || taskId.isEmpty) return null;
        final projectId = map['projectId'];
        return HomeWidgetOpenTask(
          taskId: taskId,
          projectId: projectId is String && projectId.isNotEmpty
              ? projectId
              : null,
        );
      case 'refresh':
        return const HomeWidgetRefresh();
      default:
        return null;
    }
  }
}

/// A task row was tapped.
class HomeWidgetOpenTask extends HomeWidgetAction {
  const HomeWidgetOpenTask({required this.taskId, this.projectId});

  final String taskId;
  final String? projectId;

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetOpenTask &&
      other.taskId == taskId &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(taskId, projectId);
}

/// The refresh arrow in the widget's header was tapped.
class HomeWidgetRefresh extends HomeWidgetAction {
  const HomeWidgetRefresh();

  @override
  bool operator ==(Object other) => other is HomeWidgetRefresh;

  @override
  int get hashCode => (HomeWidgetRefresh).hashCode;
}

/// The app's view of the Android home-screen widget.
///
/// An interface for the same two reasons `NotificationGateway` is one: tests
/// get a fake that records real objects instead of method-name strings, and
/// the platforms that have no widget (Windows, web) get an implementation that
/// does nothing rather than a `MissingPluginException` at every set change.
abstract interface class HomeWidgetGateway {
  /// Whether there is a widget on this platform at all.
  bool get supported;

  /// Hands the widget a new snapshot (JSON, see `HomeWidgetSnapshot`) and
  /// redraws every placed instance. Never throws.
  Future<void> publish(String snapshotJson);

  /// The pending widget action, consumed: a second call answers null.
  ///
  /// Consuming for the reason `NotificationGateway.takeLaunchPayload` is: the
  /// launch intent outlives the tap, and re-reading it would open the task
  /// twice.
  Future<HomeWidgetAction?> takeAction();

  /// Called (with no argument) whenever a new action is waiting -- a tap that
  /// arrived while the app was alive. The listener then calls [takeAction].
  /// Null unregisters.
  void setActionListener(VoidCallback? listener);
}

/// Windows, web, and anything else without a home-screen widget.
class UnsupportedHomeWidgetGateway implements HomeWidgetGateway {
  const UnsupportedHomeWidgetGateway();

  @override
  bool get supported => false;

  @override
  Future<void> publish(String snapshotJson) async {}

  @override
  Future<HomeWidgetAction?> takeAction() async => null;

  @override
  void setActionListener(VoidCallback? listener) {}
}

/// Android: `MainActivity` answers on `taskradar/home_widget`.
///
/// Every call swallows its own failure. The widget is a convenience on top of
/// the app; a missing channel (a test VM, an engine without the activity) must
/// never turn into an error on the screen the user is actually looking at.
class MethodChannelHomeWidgetGateway implements HomeWidgetGateway {
  MethodChannelHomeWidgetGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'taskradar/home_widget';

  final MethodChannel _channel;

  @override
  bool get supported => true;

  @override
  Future<void> publish(String snapshotJson) async {
    try {
      await _channel.invokeMethod<void>('publish', snapshotJson);
    } catch (error) {
      debugPrint('Home widget publish failed: $error');
    }
  }

  @override
  Future<HomeWidgetAction?> takeAction() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'takeAction',
      );
      return HomeWidgetAction.fromMap(map);
    } catch (error) {
      debugPrint('Home widget takeAction failed: $error');
      return null;
    }
  }

  @override
  void setActionListener(VoidCallback? listener) {
    if (listener == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'actionAvailable') listener();
      return null;
    });
  }
}
