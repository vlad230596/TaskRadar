import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/geofence_plan.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/geofence/geofence_callback.dart';
import 'package:taskradar/geofence/geofence_store.dart';
import 'package:taskradar/geofence/geofence_syncer.dart';
import 'package:taskradar/geofence/location_access.dart';
import 'package:taskradar/models/board_project.dart';

import 'support/fake_geofence.dart';
import 'support/fixtures.dart';

Map<String, dynamic> _placeTask(
  String id, {
  double lat = 55.75,
  double lng = 37.61,
  int radius = 200,
  String? label,
  String status = 'pending',
  String title = 'Купить батарейки',
  String updatedAt = '2026-08-01T09:00:00.000Z',
}) => <String, dynamic>{
  ...taskJson(id: id, status: status, title: title, updatedAt: updatedAt),
  'location': <String, dynamic>{
    'lat': lat,
    'lng': lng,
    'radius': radius,
    'label': ?label,
  },
};

List<BoardProject> _board(List<Map<String, dynamic>> tasks) => <BoardProject>[
  BoardProject.fromJson(
    boardProjectJson(id: 'prj_1', name: 'Дом', tasks: tasks),
  ),
];

PlannedGeofence _zone(
  String taskId, {
  double lat = 55.75,
  double lng = 37.61,
  int radius = 200,
  String title = 'Купить батарейки',
}) => PlannedGeofence(
  taskId: taskId,
  taskTitle: title,
  lat: lat,
  lng: lng,
  radius: radius,
  label: 'Магазин',
  projectName: 'Дом',
);

void main() {
  group('geofencesFromBoard', () {
    test('plans open tasks with a place, skips done and placeless ones', () {
      final plan = geofencesFromBoard(
        _board(<Map<String, dynamic>>[
          _placeTask('t1', label: 'Магазин'),
          _placeTask('t2', status: 'done'),
          taskJson(id: 't3'),
          _placeTask('t4', status: 'blocked'),
        ]),
      );

      expect(plan.zones.map((z) => z.taskId), containsAll(<String>['t1', 't4']));
      expect(plan.zones, hasLength(2));
      final first = plan.zones.firstWhere((z) => z.taskId == 't1');
      expect(first.id, 'task:t1');
      expect(first.label, 'Магазин');
      expect(first.projectName, 'Дом');
      expect(plan.overLimit, isEmpty);
    });

    test('drops invalid coordinates and clamps the radius', () {
      final plan = geofencesFromBoard(
        _board(<Map<String, dynamic>>[
          _placeTask('bad', lat: 123),
          _placeTask('small', radius: 20),
          _placeTask('big', radius: 5000),
        ]),
      );
      final byId = {for (final z in plan.zones) z.taskId: z};
      expect(byId.keys, unorderedEquals(<String>['small', 'big']));
      expect(byId['small']!.radius, 100);
      expect(byId['big']!.radius, 1000);
    });

    test('over the limit keeps the most recently changed tasks', () {
      final tasks = <Map<String, dynamic>>[
        for (var i = 0; i < 95; i++)
          _placeTask(
            't$i',
            updatedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i))
                .toIso8601String(),
          ),
      ];
      final plan = geofencesFromBoard(_board(tasks));
      expect(plan.zones, hasLength(geofenceLimit));
      expect(plan.overLimit, <String>{'t0', 't1', 't2', 't3', 't4'});
      expect(plan.tracks('t94'), isTrue);
      expect(plan.tracks('t0'), isFalse);
    });

    test('with a known position the nearest zones win', () {
      final plan = geofencesFromBoard(
        _board(<Map<String, dynamic>>[
          _placeTask('far', lat: 59.93, lng: 30.33, updatedAt: '2026-09-01'),
          _placeTask('near', lat: 55.751, lng: 37.611),
          _placeTask('mid', lat: 55.9, lng: 37.8),
        ]),
        limit: 2,
        near: (lat: 55.75, lng: 37.61),
      );
      expect(plan.zones.map((z) => z.taskId), <String>['near', 'mid']);
      expect(plan.overLimit, <String>{'far'});
    });
  });

  test('distanceMeters is about right', () {
    // Moscow - Saint Petersburg is ~634 km.
    final d = distanceMeters(
      (lat: 55.7558, lng: 37.6173),
      (lat: 59.9343, lng: 30.3351),
    );
    expect(d, closeTo(634000, 5000));
  });

  group('diffGeofences', () {
    test('registers new zones and removes stale ones that are ours', () {
      final diff = diffGeofences(
        wanted: <PlannedGeofence>[_zone('a'), _zone('b')],
        registeredIds: <String>['task:a', 'task:old', 'foreign'],
        recorded: <String, PlannedGeofence>{'task:a': _zone('a')},
      );
      expect(diff.register.map((z) => z.id), <String>['task:b']);
      expect(diff.remove, <String>['task:old']);
    });

    test('a moved circle is re-registered; a renamed task is not', () {
      final diff = diffGeofences(
        wanted: <PlannedGeofence>[
          _zone('moved', radius: 300),
          _zone('renamed', title: 'Новое имя'),
        ],
        registeredIds: <String>['task:moved', 'task:renamed'],
        recorded: <String, PlannedGeofence>{
          'task:moved': _zone('moved'),
          'task:renamed': _zone('renamed'),
        },
      );
      expect(diff.register.map((z) => z.taskId), <String>['moved']);
      expect(diff.remove, isEmpty);
    });

    test('a registered zone without a record is re-registered', () {
      final diff = diffGeofences(
        wanted: <PlannedGeofence>[_zone('a')],
        registeredIds: <String>['task:a'],
        recorded: const <String, PlannedGeofence>{},
      );
      expect(diff.register, hasLength(1));
    });
  });

  group('cooldown', () {
    final now = DateTime.utc(2026, 11, 11, 12);

    test('allows the first time and after six hours, not before', () {
      expect(cooldownAllows(lastNotified: null, now: now), isTrue);
      expect(
        cooldownAllows(
          lastNotified: now.subtract(const Duration(hours: 5, minutes: 59)),
          now: now,
        ),
        isFalse,
      );
      expect(
        cooldownAllows(
          lastNotified: now.subtract(const Duration(hours: 6)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a mark from the future does not silence the task', () {
      expect(
        cooldownAllows(
          lastNotified: now.add(const Duration(days: 2)),
          now: now,
        ),
        isTrue,
      );
    });

    test('prune keeps only marks that still suppress', () {
      final pruned = pruneCooldowns(<String, DateTime>{
        'fresh': now.subtract(const Duration(hours: 1)),
        'old': now.subtract(const Duration(hours: 7)),
      }, now: now);
      expect(pruned.keys, <String>['fresh']);
    });
  });

  test('notification text and ids', () {
    final text = geofenceNotificationText(_zone('a'));
    expect(text.title, 'Рядом: Купить батарейки');
    expect(text.body, 'Магазин · Дом — зайдёте?');
    expect(geofenceNotificationId('a'), isNot(notificationIdForTask('a')));
    expect(
      geofenceNotificationId('a'),
      greaterThanOrEqualTo(reservedNotificationIds),
    );
    expect(taskIdFromGeofenceId('task:abc'), 'abc');
    expect(taskIdFromGeofenceId('other'), isNull);
  });

  group('GeofenceSyncer', () {
    late FakeGeofenceGateway gateway;
    late MemoryGeofenceStore store;
    late FakeLocationAccess access;
    late GeofenceSyncer syncer;

    setUp(() {
      gateway = FakeGeofenceGateway();
      store = MemoryGeofenceStore();
      access = FakeLocationAccess();
      syncer = GeofenceSyncer(gateway: gateway, store: store, access: access);
    });

    GeofencePlan plan(List<PlannedGeofence> zones) =>
        GeofencePlan(zones: zones);

    test('unsupported platforms touch nothing', () async {
      gateway.supported = false;
      final report = await syncer.sync(
        enabled: true,
        plan: plan(<PlannedGeofence>[_zone('a')]),
      );
      expect(report.status, GeofenceSyncStatus.unsupported);
      expect(gateway.calls, isEmpty);
    });

    test('disabled with nothing recorded costs nothing', () async {
      final report = await syncer.sync(
        enabled: false,
        plan: plan(<PlannedGeofence>[_zone('a')]),
      );
      expect(report.status, GeofenceSyncStatus.disabled);
      expect(gateway.calls, isEmpty);
    });

    test('registers, records, then only diffs', () async {
      final first = await syncer.sync(
        enabled: true,
        plan: plan(<PlannedGeofence>[_zone('a'), _zone('b')]),
      );
      expect(first.status, GeofenceSyncStatus.active);
      expect(first.registered, 2);
      expect(gateway.zones.keys, unorderedEquals(<String>['task:a', 'task:b']));
      expect(store.zones.keys, unorderedEquals(<String>['task:a', 'task:b']));
      expect(gateway.calls.first, 'reCreateAll');

      gateway.calls.clear();
      final second = await syncer.sync(
        enabled: true,
        plan: plan(<PlannedGeofence>[
          _zone('a', title: 'Переименована'),
          _zone('c'),
        ]),
      );
      expect(second.registered, 1);
      expect(second.removed, 1);
      expect(
        gateway.calls,
        unorderedEquals(<String>['remove task:b', 'register task:c']),
      );
      // The new title is recorded for the background isolate.
      expect(store.zones['task:a']!.taskTitle, 'Переименована');
    });

    test('a zone the plugin lost is re-added', () async {
      await syncer.sync(enabled: true, plan: plan(<PlannedGeofence>[_zone('a')]));
      gateway.zones.clear();
      gateway.calls.clear();
      await syncer.sync(enabled: true, plan: plan(<PlannedGeofence>[_zone('a')]));
      expect(gateway.calls, <String>['register task:a']);
    });

    test('without background access nothing is registered', () async {
      access.level = LocationAccessLevel.whileInUse;
      final report = await syncer.sync(
        enabled: true,
        plan: plan(<PlannedGeofence>[_zone('a')]),
      );
      expect(report.status, GeofenceSyncStatus.noBackgroundAccess);
      expect(gateway.zones, isEmpty);
    });

    test('turning off removes every zone and the record', () async {
      await syncer.sync(enabled: true, plan: plan(<PlannedGeofence>[_zone('a')]));
      final report = await syncer.sync(
        enabled: false,
        plan: plan(<PlannedGeofence>[_zone('a')]),
      );
      expect(report.status, GeofenceSyncStatus.disabled);
      expect(gateway.zones, isEmpty);
      expect(store.zones, isEmpty);
    });

    test('a plugin failure is reported, not thrown', () async {
      gateway.registerFailure = StateError('play services');
      final report = await syncer.sync(
        enabled: true,
        plan: plan(<PlannedGeofence>[_zone('a')]),
      );
      expect(report.status, GeofenceSyncStatus.failed);
      expect(report.error, contains('play services'));
    });
  });

  group('handleGeofenceEnter (the background callback)', () {
    late MemoryGeofenceStore store;
    late FakePlaceNotifier notifier;
    final now = DateTime.utc(2026, 11, 11, 12);

    setUp(() {
      store = MemoryGeofenceStore()
        ..zones = <String, PlannedGeofence>{'task:a': _zone('a')};
      notifier = FakePlaceNotifier();
    });

    test('notifies with a deep link to the task and records the time', () async {
      final notified = await handleGeofenceEnter(
        zoneIds: <String>['task:a'],
        store: store,
        notifier: notifier,
        now: now,
      );
      expect(notified, <String>['a']);
      expect(notifier.shown.single.title, 'Рядом: Купить батарейки');
      expect(notifier.shown.single.payload, reminderPayload('a'));
      expect(taskIdFromPayload(notifier.shown.single.payload), 'a');
      expect(notifier.shown.single.id, geofenceNotificationId('a'));
      expect(store.cooldowns['a'], now);
    });

    test('stays quiet for six hours per task', () async {
      store.cooldowns = <String, DateTime>{
        'a': now.subtract(const Duration(hours: 2)),
      };
      await handleGeofenceEnter(
        zoneIds: <String>['task:a'],
        store: store,
        notifier: notifier,
        now: now,
      );
      expect(notifier.shown, isEmpty);

      await handleGeofenceEnter(
        zoneIds: <String>['task:a'],
        store: store,
        notifier: notifier,
        now: now.add(const Duration(hours: 4, minutes: 1)),
      );
      expect(notifier.shown, hasLength(1));
    });

    test('a zone with no record is skipped', () async {
      final notified = await handleGeofenceEnter(
        zoneIds: <String>['task:unknown'],
        store: store,
        notifier: notifier,
        now: now,
      );
      expect(notified, isEmpty);
      expect(notifier.shown, isEmpty);
    });
  });

  test('FileGeofenceStore round-trips zones and cooldowns', () async {
    final dir = await Directory.systemTemp.createTemp('geofence_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileGeofenceStore(directory: () async => dir);

    expect(await store.readZones(), isEmpty);
    await store.writeZones(<String, PlannedGeofence>{'task:a': _zone('a')});
    expect(await store.readZones(), <String, PlannedGeofence>{
      'task:a': _zone('a'),
    });

    final at = DateTime.utc(2026, 11, 11, 12);
    await store.writeCooldowns(<String, DateTime>{'a': at});
    expect(await store.readCooldowns(), <String, DateTime>{'a': at});

    await File('${dir.path}/${FileGeofenceStore.zonesFile}').writeAsString('{');
    expect(await store.readZones(), isEmpty);
  });
}
