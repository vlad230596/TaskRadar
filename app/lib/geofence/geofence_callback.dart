import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';

import '../domain/geofence_plan.dart';
import '../domain/reminder_schedule.dart';
import 'geofence_store.dart';

/// The geofence callback: what runs when the phone walks into a zone.
///
/// ## Where this runs
///
/// In a **background isolate** that `native_geofence` starts in a WorkManager
/// job, usually with the app not running at all. There is no Riverpod graph, no
/// signed-in session, no board in memory and possibly no network. Everything
/// the notification says therefore comes from [GeofenceStore], which the main
/// isolate's sync wrote when it registered the zone.
///
/// ## What it must not do
///
/// Promote itself to a foreground service. `native_geofence` 1.4 declares its
/// service without a `foregroundServiceType`, and starting it on Android 14+
/// throws `MissingForegroundServiceTypeException` (see the WP1 note in
/// `design/task-editor-spec.md`). Reading two small files and posting one
/// notification is well inside the time a plain worker gets.
///
/// ## The tap
///
/// The payload is the ordinary reminder payload ([reminderPayload]), so a tap
/// goes down exactly the path a date reminder's does
/// (`providers/notification_link_providers.dart`): cold start via the launch
/// details, warm via the response callback, both resolving the task against
/// the board and opening it.
@pragma('vm:entry-point')
Future<void> onGeofenceEvent(GeofenceCallbackParams params) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (params.event != GeofenceEvent.enter) return;
  try {
    await handleGeofenceEnter(
      zoneIds: params.geofences.map((zone) => zone.id),
      store: FileGeofenceStore(),
      notifier: PluginPlaceNotifier(),
      now: DateTime.now(),
    );
  } catch (error, stackTrace) {
    // Nothing to report to: there is no UI. The log is what `adb logcat` shows.
    debugPrint('Place reminder failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

/// Posts one place notification. An interface so [handleGeofenceEnter] can be
/// tested without the plugin.
abstract interface class PlaceNotifier {
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });
}

/// The decision half of [onGeofenceEvent]: for each zone that fired, notify
/// unless the task was notified less than [geofenceCooldown] ago, and record
/// that it was.
///
/// Returns the task ids that were notified, in order.
///
/// A zone id with no record is skipped rather than announced as «Рядом:
/// задача»: it is a zone from before the record existed, or one the sync is
/// about to remove, and a notification that cannot say what it is about is
/// worse than none.
Future<List<String>> handleGeofenceEnter({
  required Iterable<String> zoneIds,
  required GeofenceStore store,
  required PlaceNotifier notifier,
  required DateTime now,
  Duration cooldown = geofenceCooldown,
}) async {
  final zones = await store.readZones();
  final marks = await store.readCooldowns();
  final notified = <String>[];

  for (final id in zoneIds.toSet()) {
    final zone = zones[id];
    if (zone == null) {
      debugPrint('Place reminder: no record for zone $id, skipping.');
      continue;
    }
    if (!cooldownAllows(
      lastNotified: marks[zone.taskId],
      now: now,
      cooldown: cooldown,
    )) {
      continue;
    }

    final text = geofenceNotificationText(zone);
    await notifier.show(
      id: geofenceNotificationId(zone.taskId),
      title: text.title,
      body: text.body,
      payload: reminderPayload(zone.taskId),
    );
    marks[zone.taskId] = now;
    notified.add(zone.taskId);
  }

  if (notified.isNotEmpty) {
    await store.writeCooldowns(
      pruneCooldowns(marks, now: now, cooldown: cooldown),
    );
  }
  return notified;
}

/// [PlaceNotifier] over `flutter_local_notifications`, initialised in whatever
/// isolate it is used in.
///
/// Not `LocalNotificationGateway`: that one reads the *launch* details during
/// initialisation and owns the tap handler, both of which belong to the UI
/// isolate. Here the only job is to post.
class PluginPlaceNotifier implements PlaceNotifier {
  PluginPlaceNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// A channel of its own so the user can silence "near a place" without
  /// silencing the morning reminders, or the other way round.
  static const AndroidNotificationChannel placesChannel =
      AndroidNotificationChannel(
        'taskradar.places',
        'Напоминания по месту',
        description: 'Когда вы рядом с местом, привязанным к задаче.',
        importance: Importance.high,
      );

  static const String _icon = '@drawable/ic_notification';

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(placesChannel);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          placesChannel.id,
          placesChannel.name,
          channelDescription: placesChannel.description,
          importance: placesChannel.importance,
          priority: Priority.high,
          icon: _icon,
          category: AndroidNotificationCategory.reminder,
          styleInformation: const BigTextStyleInformation(''),
        ),
      ),
    );
  }
}
