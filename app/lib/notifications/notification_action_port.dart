/// Passing a notification button press from the plugin's background isolate
/// to the running app (`notification_actions_runner.dart`). Split by
/// conditional import: the browser build has no `dart:isolate`.
library;

export 'notification_action_port_stub.dart'
    if (dart.library.isolate) 'notification_action_port_io.dart';
