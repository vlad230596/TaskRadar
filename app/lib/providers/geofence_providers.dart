import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/geofence_plan.dart';
import '../geofence/geofence_gateway.dart';
import '../geofence/geofence_store.dart';
import '../geofence/geofence_syncer.dart';
import '../geofence/location_access.dart';
import '../models/board_project.dart';
import 'board_providers.dart';
import 'dependencies.dart';

/// Riverpod wiring for place reminders (`design/task-editor-spec.md` §7), the
/// same shape as `reminder_providers.dart`:
///
/// board → [boardGeofenceBridgeProvider] → [geofenceTargetsProvider] →
/// [geofencePlanProvider] → [geofenceSyncProvider] → the OS.
///
/// Nothing calls "register zones": changing the board, the setting or the
/// anchor position **is** the resync, because [geofenceSyncProvider] watches
/// all three. Every provider here lives as long as the container (manual
/// providers are never auto-disposed), like the reminder ones: they own
/// platform resources and must not depend on a screen staying mounted.

/// The plugin. Overridden with a fake in tests.
final geofenceGatewayProvider = Provider<GeofenceGateway>(
  (ref) => NativeGeofenceGateway(),
);

/// The location plugin, for the settings flow and the map's «Моё место».
final locationAccessProvider = Provider<LocationAccess>(
  (ref) => const GeolocatorLocationAccess(),
);

/// Where the zones and the cooldown marks are written for the background
/// isolate.
final geofenceStoreProvider = Provider<GeofenceStore>(
  (ref) => FileGeofenceStore(),
);

final geofenceSyncerProvider = Provider<GeofenceSyncer>(
  (ref) => GeofenceSyncer(
    gateway: ref.watch(geofenceGatewayProvider),
    store: ref.watch(geofenceStoreProvider),
    access: ref.watch(locationAccessProvider),
  ),
);

/// «Напоминания по месту» -- off by default, persisted, always off where
/// zones are not supported.
class PlaceRemindersSetting extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    if (!ref.watch(geofenceGatewayProvider).supported) return false;
    return await ref.watch(settingsStoreProvider).readPlaceReminders() ??
        false;
  }

  /// Applies and persists the switch. Turning it off also removes every zone
  /// right away (the sync would too, but only if it had a record to go by).
  ///
  /// As with the reminder hour, the state is set before the write and is not
  /// rolled back if the write throws; the caller reports the failure.
  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    if (!enabled) {
      try {
        await ref.read(geofenceSyncerProvider).clear();
      } catch (error) {
        debugPrint('Could not remove the zones: $error');
      }
    }
    await ref.read(settingsStoreProvider).writePlaceReminders(enabled);
  }
}

final placeRemindersSettingProvider =
    AsyncNotifierProvider<PlaceRemindersSetting, bool>(
      PlaceRemindersSetting.new,
    );

/// The board rows zones are planned from. Written by the bridge only.
class GeofenceTargets extends Notifier<List<BoardProject>> {
  @override
  List<BoardProject> build() => const <BoardProject>[];

  void replaceWith(List<BoardProject> board) => state = board;
}

final geofenceTargetsProvider =
    NotifierProvider<GeofenceTargets, List<BoardProject>>(GeofenceTargets.new);

/// Where the phone last was, read from the OS cache without prompting or
/// waking the GPS. Used only to prefer the nearest zones over the limit.
final geofenceAnchorProvider = FutureProvider<GeoPoint?>((ref) async {
  if (!ref.watch(geofenceGatewayProvider).supported) return null;
  final access = ref.watch(locationAccessProvider);
  if (!(await access.check()).canLocate) return null;
  return access.lastKnownPosition();
});

/// The zones that should exist.
final geofencePlanProvider = Provider<GeofencePlan>((ref) {
  final board = ref.watch(geofenceTargetsProvider);
  final near = ref.watch(geofenceAnchorProvider).value;
  return geofencesFromBoard(board, near: near);
});

/// Runs a sync whenever the plan or the setting changes, and holds the report.
class GeofenceSync extends AsyncNotifier<GeofenceSyncReport> {
  @override
  Future<GeofenceSyncReport> build() async {
    final syncer = ref.watch(geofenceSyncerProvider);
    final plan = ref.watch(geofencePlanProvider);
    final enabled = await ref.watch(placeRemindersSettingProvider.future);
    return syncer.sync(enabled: enabled, plan: plan);
  }

  /// Re-checks the access and the anchor, and re-runs the sync against the
  /// same board -- on resume, and after the settings flow.
  Future<void> resync() async {
    ref.invalidate(geofenceAnchorProvider);
    ref.invalidateSelf();
    await future;
  }
}

final geofenceSyncProvider =
    AsyncNotifierProvider<GeofenceSync, GeofenceSyncReport>(GeofenceSync.new);

/// The wire from the board to [geofenceTargetsProvider] -- see
/// `boardReminderBridge` for why it listens rather than watches, why it keeps
/// the sync alive with an empty listener, and why the catch-up is a microtask.
/// `ReminderBridgeScope` holds it for the signed-in half of the app.
final boardGeofenceBridgeProvider = Provider<void>((ref) {
  List<BoardProject>? published;

  void publish(BoardView view) {
    if (view is! BoardReady) return;
    if (identical(view.projects, published)) return;
    published = view.projects;
    ref.read(geofenceTargetsProvider.notifier).replaceWith(view.projects);
  }

  ref.listen(geofenceSyncProvider, (_, _) {});
  ref.listen(boardViewProvider, (_, next) => publish(next));

  Future.microtask(() {
    if (!ref.mounted) return;
    publish(ref.read(boardViewProvider));
  });
});

/// What the editor's place section says about one task's zone.
enum PlaceReminderStatus {
  /// Windows / web: places are kept, zones are not («только на телефоне»).
  phoneOnly,

  /// The setting is off.
  off,

  /// On, but without «Разрешать всегда»: the zone will not fire.
  noBackgroundAccess,

  /// On, but this task was left out by the 90-zone limit.
  overLimit,

  /// The last sync failed.
  failed,

  /// Tracked, or will be on the next sync (a task not saved yet).
  active,

  /// Still loading.
  unknown,
}

/// The status of [taskId]'s zone (null: a task not saved yet).
final placeReminderStatusProvider =
    Provider.family<PlaceReminderStatus, String?>((ref, taskId) {
      if (!ref.watch(geofenceGatewayProvider).supported) {
        return PlaceReminderStatus.phoneOnly;
      }
      final enabled = ref.watch(placeRemindersSettingProvider).value;
      if (enabled == null) return PlaceReminderStatus.unknown;
      if (!enabled) return PlaceReminderStatus.off;

      final report = ref.watch(geofenceSyncProvider).value;
      switch (report?.status) {
        case GeofenceSyncStatus.noBackgroundAccess:
          return PlaceReminderStatus.noBackgroundAccess;
        case GeofenceSyncStatus.failed:
          return PlaceReminderStatus.failed;
        case null:
          return PlaceReminderStatus.unknown;
        case _:
          break;
      }
      if (taskId != null &&
          ref.watch(geofencePlanProvider).overLimit.contains(taskId)) {
        return PlaceReminderStatus.overLimit;
      }
      return PlaceReminderStatus.active;
    });

/// A resync that never throws, for lifecycle callbacks.
Future<void> resyncGeofences(ProviderContainer container) async {
  try {
    await container.read(geofenceSyncProvider.notifier).resync();
  } catch (error) {
    debugPrint('Geofence resync failed: $error');
  }
}
