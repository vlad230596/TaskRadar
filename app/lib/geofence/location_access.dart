import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/geofence_plan.dart';

/// How much location access the app has, in the terms the place-reminder flow
/// actually decides on.
enum LocationAccessLevel {
  /// Nothing granted yet; asking will show the system dialog.
  denied,

  /// Refused with "не спрашивать" (or twice): only the app's system settings
  /// page can change it now.
  deniedForever,

  /// «Только во время использования»: enough for «Моё место», not for zones --
  /// Android 10+ will not deliver a geofence to an app without background
  /// access.
  whileInUse,

  /// «Разрешать всегда». Zones work.
  always,

  /// The platform has no such concept or the plugin is missing (tests, web).
  unsupported;

  bool get canLocate => this == whileInUse || this == always;
}

/// The location plugin behind an interface, for the settings flow, the map's
/// «Моё место» and tests.
abstract interface class LocationAccess {
  Future<LocationAccessLevel> check();

  /// Shows the system prompt for whatever is missing next: foreground access
  /// first; once that is granted, background access (on Android 11+ that is a
  /// trip to the system page with «Разрешать всегда»). Call from a user
  /// gesture only.
  Future<LocationAccessLevel> request();

  /// Opens the app's page in system settings. False when it could not.
  Future<bool> openAppSettings();

  /// A fresh fix, or null (no access, location off, timeout).
  Future<GeoPoint?> currentPosition();

  /// The OS's cached fix, without waking the GPS. Null when there is none.
  Future<GeoPoint?> lastKnownPosition();
}

/// [LocationAccess] over `geolocator`.
class GeolocatorLocationAccess implements LocationAccess {
  const GeolocatorLocationAccess();

  static LocationAccessLevel _map(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.denied => LocationAccessLevel.denied,
        LocationPermission.deniedForever => LocationAccessLevel.deniedForever,
        LocationPermission.whileInUse => LocationAccessLevel.whileInUse,
        LocationPermission.always => LocationAccessLevel.always,
        LocationPermission.unableToDetermine => LocationAccessLevel.unsupported,
      };

  @override
  Future<LocationAccessLevel> check() async {
    try {
      return _map(await Geolocator.checkPermission());
    } catch (error) {
      debugPrint('Location permission check failed: $error');
      return LocationAccessLevel.unsupported;
    }
  }

  @override
  Future<LocationAccessLevel> request() async {
    try {
      return _map(await Geolocator.requestPermission());
    } catch (error) {
      debugPrint('Location permission request failed: $error');
      return check();
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (error) {
      debugPrint('Could not open app settings: $error');
      return false;
    }
  }

  @override
  Future<GeoPoint?> currentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (lat: position.latitude, lng: position.longitude);
    } catch (error) {
      debugPrint('Could not get the current position: $error');
      return lastKnownPosition();
    }
  }

  @override
  Future<GeoPoint?> lastKnownPosition() async {
    if (kIsWeb) return null; // not implemented in browsers
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return (lat: position.latitude, lng: position.longitude);
    } catch (error) {
      debugPrint('Could not get the last known position: $error');
      return null;
    }
  }
}
