import 'package:flutter/foundation.dart';

import '../domain/notification_actions.dart';

/// The browser's `notification_action_port_io.dart`: there are no
/// notification buttons on the web build, and no isolates to pass them
/// between.

const String notificationActionPortName = 'taskradar.notification_actions';

void ensureBackgroundIsolateReady() {}

Future<bool> forwardNotificationAction(
  NotificationActionRequest request, {
  Duration timeout = Duration.zero,
}) async => false;

VoidCallback listenForNotificationActions(
  void Function(NotificationActionRequest request) onRequest,
) => () {};
