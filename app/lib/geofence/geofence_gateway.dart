import 'package:flutter/foundation.dart';
import 'package:native_geofence/native_geofence.dart';

import '../domain/geofence_plan.dart';
import 'geofence_callback.dart';

/// The app's narrow view of the geofencing plugin -- the same idea as
/// `NotificationGateway`: tests talk to a fake that records real objects, and
/// the platform question ("can this device do zones at all?") has one answer.
abstract interface class GeofenceGateway {
  /// Android only. Windows and the browser show and edit places, but register
  /// nothing (the editor says «только на телефоне»).
  bool get supported;

  Future<void> initialize();

  /// What the plugin believes is registered.
  Future<List<String>> registeredIds();

  /// Registers (or replaces, same id) one zone, enter-only.
  Future<void> register(PlannedGeofence zone);

  Future<void> remove(String id);

  Future<void> removeAll();

  /// Re-adds every zone the plugin has persisted. The plugin's own boot
  /// receiver does this after a reboot; some OEM ROMs never deliver
  /// `BOOT_COMPLETED` to an app that was not opened, so the app repeats it once
  /// per process as a backstop.
  Future<void> reCreateAll();
}

/// [GeofenceGateway] over `native_geofence` (Android `GeofencingClient`).
class NativeGeofenceGateway implements GeofenceGateway {
  NativeGeofenceGateway({TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;

  final TargetPlatform _platform;
  bool _initialized = false;

  @override
  bool get supported => !kIsWeb && _platform == TargetPlatform.android;

  NativeGeofenceManager get _manager => NativeGeofenceManager.instance;

  @override
  Future<void> initialize() async {
    if (_initialized || !supported) return;
    await _manager.initialize();
    _initialized = true;
  }

  @override
  Future<List<String>> registeredIds() async {
    if (!supported) return const <String>[];
    await initialize();
    return _manager.getRegisteredGeofenceIds();
  }

  @override
  Future<void> register(PlannedGeofence zone) async {
    if (!supported) return;
    await initialize();
    await _manager.createGeofence(
      Geofence(
        id: zone.id,
        location: Location(latitude: zone.lat, longitude: zone.lng),
        radiusMeters: zone.radius.toDouble(),
        // Enter only: «хотел тут кое-что купить, это рядом — зайдёшь?» is a
        // question for arriving, not for leaving.
        triggers: const <GeofenceEvent>{GeofenceEvent.enter},
        iosSettings: const IosGeofenceSettings(),
        androidSettings: const AndroidGeofenceSettings(
          // No initial trigger: every sync re-registers changed zones, and
          // standing inside one while editing the task must not ping.
          initialTriggers: <GeofenceEvent>{},
          // A couple of minutes of latency is invisible for "you are near the
          // shop" and lets the OS batch location work.
          notificationResponsiveness: Duration(minutes: 2),
        ),
      ),
      onGeofenceEvent,
    );
  }

  @override
  Future<void> remove(String id) async {
    if (!supported) return;
    await initialize();
    try {
      await _manager.removeGeofenceById(id);
    } on NativeGeofenceException catch (error) {
      // Already gone is the outcome we wanted.
      if (error.code != NativeGeofenceErrorCode.geofenceNotFound) rethrow;
    }
  }

  @override
  Future<void> removeAll() async {
    if (!supported) return;
    await initialize();
    await _manager.removeAllGeofences();
  }

  @override
  Future<void> reCreateAll() async {
    if (!supported) return;
    await initialize();
    await _manager.reCreateAfterReboot();
  }
}
