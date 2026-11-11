import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/geofence_plan.dart';

/// What the background isolate needs to know when a zone fires, kept on disk.
///
/// ## Why a file and not the board snapshot or `shared_preferences`
///
/// The geofence callback runs in a fresh background engine with no UI, no
/// Riverpod graph and no network: everything it says («Рядом: купить батарейки»)
/// has to be readable from local storage in a few milliseconds. The board
/// snapshot would do, but it is a cache the app may throw away and it is the
/// whole board; this is the exact list of zones the OS holds, written by the
/// same sync that registered them, so the two cannot disagree.
///
/// `shared_preferences` caches values per isolate: the main isolate would keep
/// reading a cooldown map the background isolate has since rewritten. Plain
/// files, read fresh every time, have no such second copy.
///
/// Two files, two writers: the main isolate writes [writeZones], the background
/// isolate writes [writeCooldowns]. Neither ever writes the other's file, so no
/// lock is needed.
abstract interface class GeofenceStore {
  /// The zones as last registered, by zone id. Empty when unreadable.
  Future<Map<String, PlannedGeofence>> readZones();

  Future<void> writeZones(Map<String, PlannedGeofence> zones);

  /// When each task last produced a place notification. Empty when unreadable.
  Future<Map<String, DateTime>> readCooldowns();

  Future<void> writeCooldowns(Map<String, DateTime> marks);
}

/// [GeofenceStore] as two JSON files in the app-support directory.
class FileGeofenceStore implements GeofenceStore {
  FileGeofenceStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const String zonesFile = 'geofence_zones.json';
  static const String cooldownsFile = 'geofence_cooldowns.json';

  final Future<Directory> Function() _directory;

  Future<File> _file(String name) async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$name');

  Future<Object?> _read(String name) async {
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (error) {
      // A missing plugin (tests), a truncated file, a schema from the future:
      // all of them mean "nothing recorded", which the sync repairs.
      debugPrint('Could not read $name: $error');
      return null;
    }
  }

  Future<void> _write(String name, Object json) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    // Write-then-rename: the background isolate may read while this writes.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<Map<String, PlannedGeofence>> readZones() async {
    final json = await _read(zonesFile);
    if (json is! List) return <String, PlannedGeofence>{};
    final zones = <String, PlannedGeofence>{};
    for (final entry in json) {
      try {
        final zone = PlannedGeofence.fromJson(
          (entry as Map).cast<String, dynamic>(),
        );
        zones[zone.id] = zone;
      } catch (error) {
        debugPrint('Skipping an unreadable zone: $error');
      }
    }
    return zones;
  }

  @override
  Future<void> writeZones(Map<String, PlannedGeofence> zones) => _write(
    zonesFile,
    <Object>[for (final zone in zones.values) zone.toJson()],
  );

  @override
  Future<Map<String, DateTime>> readCooldowns() async {
    final json = await _read(cooldownsFile);
    if (json is! Map) return <String, DateTime>{};
    final marks = <String, DateTime>{};
    for (final MapEntry(:key, :value) in json.entries) {
      final at = value is String ? DateTime.tryParse(value) : null;
      if (key is String && at != null) marks[key] = at;
    }
    return marks;
  }

  @override
  Future<void> writeCooldowns(Map<String, DateTime> marks) =>
      _write(cooldownsFile, <String, String>{
        for (final entry in marks.entries)
          entry.key: entry.value.toUtc().toIso8601String(),
      });
}
