import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/board_project.dart';
import '../models/task_location.dart';
import '../models/task_status.dart';
import 'reminder_schedule.dart';

/// Place reminders as data (`design/task-editor-spec.md` §7) -- the geofence
/// twin of `board_reminders.dart` + `reminder_schedule.dart`.
///
/// Everything in this file is pure Dart over the board: which tasks get a zone,
/// how the OS registration should change, whether a zone that just fired may
/// notify, and what the notification says. The plugin, the files and the
/// background isolate live in `lib/geofence/` and only *execute* what this file
/// decides, so every decision is testable without a phone.

/// Android allows 100 geofences per app. Ten are left free on purpose: the
/// plugin, a future feature or a half-finished re-registration must never be
/// the thing that hits the hard limit and gets a `GEOFENCE_TOO_MANY_GEOFENCES`.
const int geofenceLimit = 90;

/// A zone that fired is quiet for this long for the same task. Walking the
/// length of a shopping street in and out of a 200 m circle must not produce
/// five notifications.
const Duration geofenceCooldown = Duration(hours: 6);

/// The prefix of every zone id this app registers. The sync only ever removes
/// zones carrying it, for the same reason the reminder sweep only touches
/// payloads it recognises.
const String geofenceIdPrefix = 'task:';

/// The zone id for a task. Stable, so re-registering replaces rather than
/// duplicates (the plugin overwrites a zone with the same id).
String geofenceIdForTask(String taskId) => '$geofenceIdPrefix$taskId';

/// The task id back out of a zone id, or null if the zone is not ours.
String? taskIdFromGeofenceId(String id) {
  if (!id.startsWith(geofenceIdPrefix)) return null;
  final taskId = id.substring(geofenceIdPrefix.length);
  return taskId.isEmpty ? null : taskId;
}

/// The notification id a place reminder is posted under.
///
/// Deliberately *not* [notificationIdForTask]: the same task can have a date
/// reminder sitting in the shade, and a place notification must not silently
/// replace it. Hashing a different string keeps the id in the same safe range
/// (above the bench's reserved ids) without a second hash function.
int geofenceNotificationId(String taskId) =>
    notificationIdForTask('place:$taskId');

/// What the label falls back to on the wire (WP1: an empty label is stored as
/// «Место»), and what the picker pre-fills.
const String defaultPlaceLabel = 'Место';

/// One zone that should be registered with the OS, plus the text the
/// background callback needs to show without asking the server or the UI.
@immutable
class PlannedGeofence {
  const PlannedGeofence({
    required this.taskId,
    required this.taskTitle,
    required this.lat,
    required this.lng,
    required this.radius,
    this.label,
    this.projectName,
  });

  factory PlannedGeofence.fromJson(Map<String, dynamic> json) =>
      PlannedGeofence(
        taskId: json['taskId'] as String,
        taskTitle: json['taskTitle'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        radius: (json['radius'] as num).toInt(),
        label: json['label'] as String?,
        projectName: json['projectName'] as String?,
      );

  final String taskId;
  final String taskTitle;
  final double lat;
  final double lng;

  /// Metres, clamped to [TaskLocation.minRadius]..[TaskLocation.maxRadius] by
  /// [geofencesFromBoard].
  final int radius;
  final String? label;
  final String? projectName;

  String get id => geofenceIdForTask(taskId);

  /// Whether the OS registration of [other] is the same circle. A changed
  /// title is not a reason to re-register a zone; a moved pin is.
  bool sameGeometry(PlannedGeofence other) =>
      other.lat == lat && other.lng == lng && other.radius == radius;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'taskId': taskId,
    'taskTitle': taskTitle,
    'lat': lat,
    'lng': lng,
    'radius': radius,
    if (label != null) 'label': label,
    if (projectName != null) 'projectName': projectName,
  };

  @override
  bool operator ==(Object other) =>
      other is PlannedGeofence &&
      other.taskId == taskId &&
      other.taskTitle == taskTitle &&
      other.lat == lat &&
      other.lng == lng &&
      other.radius == radius &&
      other.label == label &&
      other.projectName == projectName;

  @override
  int get hashCode =>
      Object.hash(taskId, taskTitle, lat, lng, radius, label, projectName);

  @override
  String toString() => 'PlannedGeofence($id, $lat, $lng, ${radius}m)';
}

/// The result of planning: the zones to register, and the tasks that have a
/// place but did not make the cut (the editor shows «не отслеживается (лимит)»).
@immutable
class GeofencePlan {
  const GeofencePlan({required this.zones, this.overLimit = const <String>{}});

  static const GeofencePlan empty = GeofencePlan(zones: <PlannedGeofence>[]);

  final List<PlannedGeofence> zones;

  /// Task ids with a valid place that were left out by [geofenceLimit].
  final Set<String> overLimit;

  bool tracks(String taskId) => zones.any((zone) => zone.taskId == taskId);
}

/// A point, for "nearest first". Kept here rather than importing `latlong2`
/// so the domain stays free of map packages.
typedef GeoPoint = ({double lat, double lng});

/// The zones the board asks for.
///
/// - A zone exists for every task that is **not done** and has a location --
///   the same rule `remindersFromBoard` applies to dates.
/// - Invalid coordinates are dropped (a hand-edited row must not crash the
///   plugin); the radius is clamped to the picker's range.
/// - Over [limit]: when [near] is known (the last position the app saw) the
///   nearest zones win -- a reminder for a shop in another city is the one to
///   drop. Without a position the most recently changed tasks win, which is
///   the spec's rule ("90 самых недавно изменённых").
GeofencePlan geofencesFromBoard(
  Iterable<BoardProject> board, {
  int limit = geofenceLimit,
  GeoPoint? near,
}) {
  final candidates = <(PlannedGeofence, String)>[];
  final seen = <String>{};

  for (final row in board) {
    for (final task in row.tasks) {
      final location = task.location;
      if (task.status == TaskStatus.done || location == null) continue;
      if (!isValidLocation(location)) continue;
      if (!seen.add(task.id)) continue;

      candidates.add((
        PlannedGeofence(
          taskId: task.id,
          taskTitle: task.title,
          lat: location.lat,
          lng: location.lng,
          radius: location.radius.clamp(
            TaskLocation.minRadius,
            TaskLocation.maxRadius,
          ),
          label: _cleanLabel(location.label),
          projectName: row.project.name,
        ),
        task.updatedAt,
      ));
    }
  }

  if (near != null) {
    candidates.sort((a, b) {
      final byDistance = distanceMeters(
        near,
        (lat: a.$1.lat, lng: a.$1.lng),
      ).compareTo(distanceMeters(near, (lat: b.$1.lat, lng: b.$1.lng)));
      return byDistance != 0 ? byDistance : b.$2.compareTo(a.$2);
    });
  } else {
    // ISO-8601 strings from the server sort chronologically as text.
    candidates.sort((a, b) {
      final byTime = b.$2.compareTo(a.$2);
      return byTime != 0 ? byTime : a.$1.taskId.compareTo(b.$1.taskId);
    });
  }

  final kept = candidates.take(limit).map((c) => c.$1).toList();
  final dropped = candidates.skip(limit).map((c) => c.$1.taskId).toSet();

  return GeofencePlan(
    zones: List<PlannedGeofence>.unmodifiable(kept),
    overLimit: Set<String>.unmodifiable(dropped),
  );
}

bool isValidLocation(TaskLocation location) =>
    location.lat.isFinite &&
    location.lng.isFinite &&
    location.lat >= -90 &&
    location.lat <= 90 &&
    location.lng >= -180 &&
    location.lng <= 180;

String? _cleanLabel(String? label) {
  final trimmed = label?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Great-circle distance, haversine. Good to a few metres at city scale, which
/// is all "nearest first" needs.
double distanceMeters(GeoPoint a, GeoPoint b) {
  const earthRadius = 6371000.0;
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

/// How the OS registration has to change to match a plan.
@immutable
class GeofenceDiff {
  const GeofenceDiff({required this.register, required this.remove});

  /// New zones, and zones whose circle moved. Registering an existing id
  /// replaces it.
  final List<PlannedGeofence> register;

  /// Zone ids that are ours and no longer wanted.
  final List<String> remove;

  bool get isEmpty => register.isEmpty && remove.isEmpty;
}

/// Compares what is wanted with what is registered.
///
/// [registeredIds] is the plugin's own list (what the OS is believed to hold);
/// [recorded] is what this app last wrote down about each zone. A zone the
/// plugin has but the record lacks -- or records with a different circle -- is
/// re-registered: the record is the only place the old geometry is known, and
/// trusting a missing record would leave a stale circle in the OS forever.
///
/// Ids that are not ours ([taskIdFromGeofenceId] is null) are never removed.
GeofenceDiff diffGeofences({
  required List<PlannedGeofence> wanted,
  required Iterable<String> registeredIds,
  required Map<String, PlannedGeofence> recorded,
}) {
  final registered = registeredIds.toSet();
  final wantedIds = <String>{};
  final register = <PlannedGeofence>[];

  for (final zone in wanted) {
    wantedIds.add(zone.id);
    final known = recorded[zone.id];
    if (!registered.contains(zone.id) ||
        known == null ||
        !known.sameGeometry(zone)) {
      register.add(zone);
    }
  }

  final remove = <String>[
    for (final id in registered)
      if (!wantedIds.contains(id) && taskIdFromGeofenceId(id) != null) id,
  ]..sort();

  return GeofenceDiff(
    register: List<PlannedGeofence>.unmodifiable(register),
    remove: List<String>.unmodifiable(remove),
  );
}

/// Whether a zone that fired at [now] may notify, given when it last did.
///
/// A [lastNotified] in the future (the clock was moved back) counts as "long
/// ago": a phone whose clock jumped must not go silent for days.
bool cooldownAllows({
  required DateTime? lastNotified,
  required DateTime now,
  Duration cooldown = geofenceCooldown,
}) {
  if (lastNotified == null) return true;
  if (lastNotified.isAfter(now)) return true;
  return now.difference(lastNotified) >= cooldown;
}

/// Drops cooldown marks that no longer suppress anything, so the file the
/// background isolate rewrites stays a handful of entries.
Map<String, DateTime> pruneCooldowns(
  Map<String, DateTime> marks, {
  required DateTime now,
  Duration cooldown = geofenceCooldown,
}) => <String, DateTime>{
  for (final entry in marks.entries)
    if (!cooldownAllows(
      lastNotified: entry.value,
      now: now,
      cooldown: cooldown,
    ))
      entry.key: entry.value,
};

/// The notification for a zone: «Рядом: <задача>», with the place and the
/// project underneath.
({String title, String body}) geofenceNotificationText(PlannedGeofence zone) {
  final title = zone.taskTitle.trim().isEmpty
      ? 'Рядом: задача'
      : 'Рядом: ${zone.taskTitle.trim()}';
  final parts = <String>[
    zone.label ?? defaultPlaceLabel,
    if (zone.projectName != null && zone.projectName!.trim().isNotEmpty)
      zone.projectName!.trim(),
  ];
  return (title: title, body: '${parts.join(' · ')} — зайдёте?');
}
