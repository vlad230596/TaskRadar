import 'package:taskradar/domain/geofence_plan.dart';
import 'package:taskradar/geofence/geofence_callback.dart';
import 'package:taskradar/geofence/geofence_gateway.dart';
import 'package:taskradar/geofence/geofence_store.dart';
import 'package:taskradar/geofence/location_access.dart';

/// In-memory [GeofenceGateway]: a map of zone id to zone, plus a log of calls.
class FakeGeofenceGateway implements GeofenceGateway {
  FakeGeofenceGateway({this.supported = true});

  @override
  bool supported;

  final Map<String, PlannedGeofence> zones = <String, PlannedGeofence>{};
  final List<String> calls = <String>[];

  /// When set, [register] throws it.
  Object? registerFailure;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<String>> registeredIds() async => zones.keys.toList();

  @override
  Future<void> register(PlannedGeofence zone) async {
    final failure = registerFailure;
    if (failure != null) throw failure;
    calls.add('register ${zone.id}');
    zones[zone.id] = zone;
  }

  @override
  Future<void> remove(String id) async {
    calls.add('remove $id');
    zones.remove(id);
  }

  @override
  Future<void> removeAll() async {
    calls.add('removeAll');
    zones.clear();
  }

  @override
  Future<void> reCreateAll() async => calls.add('reCreateAll');
}

/// Scripted [LocationAccess]: [level] is what [check] answers, and each
/// [request] takes the next answer from [requestAnswers] (or keeps [level]).
class FakeLocationAccess implements LocationAccess {
  FakeLocationAccess({
    this.level = LocationAccessLevel.always,
    List<LocationAccessLevel>? requestAnswers,
    this.position,
  }) : requestAnswers = requestAnswers ?? <LocationAccessLevel>[];

  LocationAccessLevel level;
  final List<LocationAccessLevel> requestAnswers;
  GeoPoint? position;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<LocationAccessLevel> check() async => level;

  @override
  Future<LocationAccessLevel> request() async {
    requests++;
    if (requestAnswers.isNotEmpty) level = requestAnswers.removeAt(0);
    return level;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<GeoPoint?> currentPosition() async => level.canLocate ? position : null;

  @override
  Future<GeoPoint?> lastKnownPosition() async =>
      level.canLocate ? position : null;
}

class MemoryGeofenceStore implements GeofenceStore {
  Map<String, PlannedGeofence> zones = <String, PlannedGeofence>{};
  Map<String, DateTime> cooldowns = <String, DateTime>{};
  int zoneWrites = 0;

  @override
  Future<Map<String, PlannedGeofence>> readZones() async =>
      Map<String, PlannedGeofence>.of(zones);

  @override
  Future<void> writeZones(Map<String, PlannedGeofence> value) async {
    zoneWrites++;
    zones = Map<String, PlannedGeofence>.of(value);
  }

  @override
  Future<Map<String, DateTime>> readCooldowns() async =>
      Map<String, DateTime>.of(cooldowns);

  @override
  Future<void> writeCooldowns(Map<String, DateTime> value) async =>
      cooldowns = Map<String, DateTime>.of(value);
}

class FakePlaceNotifier implements PlaceNotifier {
  final List<({int id, String title, String body, String payload})> shown =
      <({int id, String title, String body, String payload})>[];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async => shown.add((id: id, title: title, body: body, payload: payload));
}
