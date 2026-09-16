import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_schedule.dart';
import 'notification_gateway.dart';

/// The real [NotificationGateway], on top of `flutter_local_notifications`.
///
/// Everything platform-specific in F1 is in this file. The rest of the app --
/// the scheduler, the providers, the bench screen -- talks to the interface and
/// contains no `if (Platform.isAndroid)`.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    TargetPlatform? platform,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _platform = platform ?? defaultTargetPlatform;

  /// The Android notification channel. Created eagerly at [initialize] rather
  /// than implicitly on the first notification, because a channel's importance
  /// is **immutable after creation**: if the first notification ever posted
  /// created the channel with the wrong importance, no later code could raise
  /// it, and the only fix on the user's phone would be reinstalling the app.
  ///
  /// [Importance.high] (not `max`) means heads-up + sound, without the
  /// full-screen-intent treatment reserved for alarms and calls. A reminder that
  /// merely slides down the status bar would be missed on a phone that spent the
  /// night face-down, which is the exact scenario this iteration tests.
  static const AndroidNotificationChannel remindersChannel =
      AndroidNotificationChannel(
        'taskradar.reminders',
        'Напоминания',
        description:
            'Напоминания о заблокированных задачах в назначенный день.',
        importance: Importance.high,
      );

  /// `@mipmap/ic_launcher` is against Android's guidance (a notification icon is
  /// supposed to be a white-on-transparent silhouette, and a full-colour
  /// launcher icon renders as a grey blob on some versions). It is used anyway
  /// for F1 because it is guaranteed to exist: a missing icon resource makes the
  /// notification fail *silently*, which would be indistinguishable from the
  /// power-management failure this iteration exists to measure. Swap it for a
  /// dedicated monochrome drawable when the app gets real branding.
  static const String _androidIcon = '@mipmap/ic_launcher';

  final FlutterLocalNotificationsPlugin _plugin;
  final TargetPlatform _platform;

  bool _initialized = false;

  /// Set when [initialize] could not reach the plugin at all.
  ///
  /// The case that matters is the `flutter test` VM, where every platform
  /// channel answers with `MissingPluginException` while `defaultTargetPlatform`
  /// still claims to be Android. Without this flag, mounting the app in a widget
  /// test would throw from a place that has nothing to do with the test. It also
  /// covers the real-world version of the same thing: a stripped OEM ROM where
  /// the plugin fails to register.
  bool _unavailable = false;

  @override
  NotificationSupport get support {
    if (_unavailable) return NotificationSupport.none;
    return switch (_platform) {
      TargetPlatform.android => NotificationSupport.android,
      TargetPlatform.windows => NotificationSupport.windows,
      _ => NotificationSupport.none,
    };
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _platform == TargetPlatform.android
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (!support.schedulesReminders) {
      _initialized = true;
      return;
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_androidIcon),
          windows: WindowsInitializationSettings(
            appName: 'TaskRadar',
            // Reverse-DNS, matching the Android applicationId so the two targets
            // are recognisably one app.
            appUserModelId: 'com.taskradar.app',
            // Fixed, arbitrary, and must never change: Windows uses it to route
            // a toast activation back to this app. Regenerating it would orphan
            // every toast already queued on the machine.
            guid: '0b2e0e4a-3a1a-4a2e-9a5a-5c2f1f9b7d10',
          ),
        ),
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Android 8+ requires the channel to exist before anything is posted to
      // it.
      await _android?.createNotificationChannel(remindersChannel);
    } catch (error) {
      // See [_unavailable]. Degrading to "this platform cannot do reminders" is
      // right even in production: the rest of the app keeps working and the
      // bench screen says out loud that the plugin is not there, which is far
      // more useful than a crash on the second frame.
      debugPrint('Notification plugin unavailable: $error');
      _unavailable = true;
    }

    _initialized = true;
  }

  /// Foreground tap handling.
  ///
  /// F1 only logs: there is nowhere meaningful to navigate yet. F4 turns the
  /// payload into a deep link to the task -- the payload format is already
  /// fixed (see [reminderPayload]) so that change is confined to this method.
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: payload=${response.payload}');
  }

  @override
  Future<NotificationPermissionState> permissions() async {
    final android = _android;
    if (android == null) return NotificationPermissionState.unknown;

    return NotificationPermissionState(
      notificationsEnabled: await _guard(android.areNotificationsEnabled),
      canScheduleExactAlarms: await _guard(
        android.canScheduleExactNotifications,
      ),
    );
  }

  @override
  Future<NotificationPermissionState> requestPermissions() async {
    final android = _android;
    if (android == null) return NotificationPermissionState.unknown;

    // POST_NOTIFICATIONS, Android 13+. On older versions the plugin answers
    // true without showing anything.
    await _guard(android.requestNotificationsPermission);

    // SCHEDULE_EXACT_ALARM, Android 12+. This one does not show a dialog: it
    // sends the user to a full-screen system settings page ("Alarms & reminders"
    // for this app), and control only comes back when they navigate back. Asking
    // for it only if it is actually missing keeps that out of the way of a user
    // who already granted it -- and, on a build where USE_EXACT_ALARM applies,
    // avoids bouncing them to a page that has nothing to toggle.
    if (await _guard(android.canScheduleExactNotifications) == false) {
      await _guard(android.requestExactAlarmsPermission);
    }

    return permissions();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime fireAt,
    required bool exact,
    String? payload,
  }) async {
    if (!support.schedulesReminders) return;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: fireAt,
      payload: payload,
      androidScheduleMode: exact
          // `exactAllowWhileIdle` rather than `exact`: plain `exact` is still
          // deferred by Doze, and Doze is precisely what a phone does all night
          // on the bedside table. `alarmClock` would be even stronger but shows
          // a persistent alarm icon in the status bar, which is wrong for a
          // to-do reminder.
          ? AndroidScheduleMode.exactAllowWhileIdle
          // The graceful degradation when the exact-alarm permission is absent:
          // still pierces Doze, but Android batches it and it can arrive hours
          // late. See [NotificationScheduleMode.inexact].
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: _details(),
    );
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!support.schedulesReminders) return;

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: _details(),
    );
  }

  @override
  Future<List<PendingNotification>> pending() async {
    if (!support.schedulesReminders) return const <PendingNotification>[];

    final requests = await _plugin.pendingNotificationRequests();
    return requests
        .map(
          (request) => PendingNotification(
            id: request.id,
            title: request.title,
            body: request.body,
            payload: request.payload,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> cancel(int id) async {
    if (!support.schedulesReminders) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    if (!support.schedulesReminders) return;
    await _plugin.cancelAll();
  }

  NotificationDetails _details() => NotificationDetails(
    android: AndroidNotificationDetails(
      remindersChannel.id,
      remindersChannel.name,
      channelDescription: remindersChannel.description,
      importance: remindersChannel.importance,
      priority: Priority.high,
      icon: _androidIcon,
      // The body is a task title and can be long; without this it is clipped to
      // one line on the lock screen, which is where it will most often be read.
      styleInformation: const BigTextStyleInformation(''),
    ),
    windows: const WindowsNotificationDetails(),
  );

  /// Runs a platform call that is allowed to fail.
  ///
  /// Permission queries go over a method channel and can throw on OEM ROMs that
  /// stubbed the API out. A thrown query must not take down a resync or blank
  /// the bench screen -- an unknown answer (`null`) is the honest result and the
  /// UI already renders it as "неизвестно".
  Future<bool?> _guard(Future<bool?> Function() call) async {
    try {
      return await call();
    } catch (error) {
      debugPrint('Notification permission call failed: $error');
      return null;
    }
  }
}
