import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../domain/notification_actions.dart';

/// The isolate plumbing of `notification_actions_runner.dart`, kept apart so
/// the browser build -- which has no `dart:isolate` -- never compiles it (see
/// `notification_action_port.dart`).

/// Prepares a background isolate started by the notification plugin.
void ensureBackgroundIsolateReady() {
  WidgetsFlutterBinding.ensureInitialized();
  // Plugins implemented in Dart (path_provider's Android side among them)
  // register through this, and a background isolate does not do it on its
  // own.
  DartPluginRegistrant.ensureInitialized();
}

/// The name the app's port is registered under.
const String notificationActionPortName = 'taskradar.notification_actions';

/// How long the background isolate waits for the app to take a press.
const Duration forwardTimeout = Duration(seconds: 3);

/// Hands [request] to the running app, if there is one. True when the app
/// acknowledged it.
Future<bool> forwardNotificationAction(
  NotificationActionRequest request, {
  Duration timeout = forwardTimeout,
}) async {
  final port = IsolateNameServer.lookupPortByName(notificationActionPortName);
  if (port == null) return false;

  final reply = ReceivePort();
  try {
    port.send(<Object>[request.action.id, request.taskId, reply.sendPort]);
    await reply.first.timeout(timeout);
    return true;
  } on TimeoutException {
    debugPrint('The app did not take $request; handling it here.');
    return false;
  } finally {
    reply.close();
  }
}

/// The app's end of [forwardNotificationAction]: registers a port under
/// [notificationActionPortName] and calls [onRequest] for each press, after
/// acknowledging it. Returns the function that unregisters it.
///
/// Registered only while the app can act on a press (signed in): a press
/// that arrives while signed out is better done by the background isolate,
/// which has the stored token, than by an app with no session.
VoidCallback listenForNotificationActions(
  void Function(NotificationActionRequest request) onRequest,
) {
  final port = ReceivePort();
  // Replaces a mapping left behind by a previous run of this process.
  IsolateNameServer.removePortNameMapping(notificationActionPortName);
  IsolateNameServer.registerPortWithName(
    port.sendPort,
    notificationActionPortName,
  );
  port.listen((Object? message) {
    if (message is! List || message.length != 3) return;
    final reply = message[2];
    final action = ReminderAction.byId(message[0] as String?);
    final taskId = message[1];
    if (reply is SendPort) reply.send(true);
    if (action == null || taskId is! String) return;
    onRequest(NotificationActionRequest(action, taskId));
  });
  return () {
    IsolateNameServer.removePortNameMapping(notificationActionPortName);
    port.close();
  };
}
