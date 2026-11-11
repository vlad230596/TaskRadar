import 'package:flutter/foundation.dart';

import '../domain/geofence_plan.dart';
import 'geofence_gateway.dart';
import 'geofence_store.dart';
import 'location_access.dart';

/// Brings the OS geofence registration in line with a [GeofencePlan] -- the
/// zone twin of `ReminderScheduler`.
///
/// ## Diff, not full re-arm
///
/// The reminder scheduler re-arms everything on every sync because re-arming an
/// alarm is free and harmless. Re-registering a geofence is neither: each one
/// is a Play-services call, and a zone that is re-added while the phone is
/// already inside it can re-trigger on some devices. So this computes a diff
/// ([diffGeofences]) against the plugin's own list *and* the app's record of
/// what each zone was, which keeps the self-healing property: a zone the
/// plugin lost is re-added, a zone whose circle moved is replaced, a zone
/// nobody wants is removed.
///
/// ## Never throws
///
/// Same contract as the reminder sync: a board refresh must not fail because a
/// geofence call did. Failures land in [GeofenceSyncReport.error].
class GeofenceSyncer {
  GeofenceSyncer({
    required GeofenceGateway gateway,
    required GeofenceStore store,
    required LocationAccess access,
  }) : _gateway = gateway,
       _store = store,
       _access = access;

  final GeofenceGateway _gateway;
  final GeofenceStore _store;
  final LocationAccess _access;

  bool _recreated = false;

  /// The sync in flight. Syncs run one after another: two interleaved ones
  /// (a board refresh landing during a resume) could otherwise write their
  /// records in the wrong order and leave the file describing the older plan.
  Future<void> _last = Future<void>.value();

  Future<GeofenceSyncReport> sync({
    required bool enabled,
    required GeofencePlan plan,
  }) {
    final run = _last.then((_) => _sync(enabled: enabled, plan: plan));
    _last = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<GeofenceSyncReport> _sync({
    required bool enabled,
    required GeofencePlan plan,
  }) async {
    if (!_gateway.supported) {
      return GeofenceSyncReport(status: GeofenceSyncStatus.unsupported);
    }

    try {
      if (!enabled) {
        // Only touch the plugin if something is recorded: a disabled feature
        // on a phone that never enabled it should cost nothing at all.
        final recorded = await _store.readZones();
        if (recorded.isEmpty) {
          return GeofenceSyncReport(status: GeofenceSyncStatus.disabled);
        }
        await _clear();
        return GeofenceSyncReport(
          status: GeofenceSyncStatus.disabled,
          removed: recorded.length,
        );
      }

      final access = await _access.check();
      if (access != LocationAccessLevel.always) {
        // Registering would throw `missingBackgroundLocationPermission`, and
        // zones already registered will not be delivered. Leave them: if the
        // access comes back (the user flips it in system settings), they work
        // again without a resync.
        return GeofenceSyncReport(
          status: GeofenceSyncStatus.noBackgroundAccess,
          planned: plan.zones.length,
          overLimit: plan.overLimit.length,
        );
      }

      if (!_recreated) {
        _recreated = true;
        await _guard(_gateway.reCreateAll, 'reCreateAfterReboot');
      }

      final recorded = await _store.readZones();
      final registered = await _gateway.registeredIds();
      final diff = diffGeofences(
        wanted: plan.zones,
        registeredIds: registered,
        recorded: recorded,
      );

      for (final id in diff.remove) {
        await _gateway.remove(id);
      }
      for (final zone in diff.register) {
        await _gateway.register(zone);
      }

      // The record is rewritten even when the diff is empty: a renamed task
      // changes what the notification says without moving the circle.
      final wanted = <String, PlannedGeofence>{
        for (final zone in plan.zones) zone.id: zone,
      };
      if (!mapEquals(wanted, recorded)) await _store.writeZones(wanted);

      return GeofenceSyncReport(
        status: GeofenceSyncStatus.active,
        planned: plan.zones.length,
        registered: diff.register.length,
        removed: diff.remove.length,
        overLimit: plan.overLimit.length,
      );
    } catch (error, stackTrace) {
      debugPrint('Geofence sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return GeofenceSyncReport(
        status: GeofenceSyncStatus.failed,
        planned: plan.zones.length,
        error: error.toString(),
      );
    }
  }

  /// Removes every zone and forgets them. What switching the feature off does.
  Future<void> clear() {
    final run = _last.then((_) => _clear());
    _last = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _clear() async {
    if (!_gateway.supported) return;
    await _gateway.removeAll();
    await _store.writeZones(const <String, PlannedGeofence>{});
  }

  Future<void> _guard(Future<void> Function() call, String what) async {
    try {
      await call();
    } catch (error) {
      debugPrint('Geofence $what failed: $error');
    }
  }
}

enum GeofenceSyncStatus {
  /// Not Android: nothing is registered, by design.
  unsupported,

  /// The setting is off.
  disabled,

  /// The setting is on, but background location access is missing.
  noBackgroundAccess,

  /// Zones match the plan.
  active,

  /// The plugin threw; see the error.
  failed,
}

@immutable
class GeofenceSyncReport {
  const GeofenceSyncReport({
    required this.status,
    this.planned = 0,
    this.registered = 0,
    this.removed = 0,
    this.overLimit = 0,
    this.error,
  });

  final GeofenceSyncStatus status;

  /// Zones in the plan.
  final int planned;

  /// Zones (re-)registered by this sync.
  final int registered;

  /// Zones removed by this sync.
  final int removed;

  /// Tasks with a place left out by the limit.
  final int overLimit;
  final String? error;

  @override
  String toString() =>
      'GeofenceSyncReport(${status.name}, planned $planned, '
      'registered $registered, removed $removed, over limit $overLimit'
      '${error == null ? '' : ', error $error'})';
}
