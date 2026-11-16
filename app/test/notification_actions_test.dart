import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/geofence_plan.dart';
import 'package:taskradar/domain/notification_actions.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/geofence/geofence_callback.dart';
import 'package:taskradar/geofence/geofence_store.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/notifications/notification_action_log.dart';
import 'package:taskradar/notifications/notification_actions_runner.dart';
import 'package:taskradar/notifications/reminder_scheduler.dart';
import 'package:taskradar/providers/board_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/geofence_providers.dart';
import 'package:taskradar/providers/notification_action_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';
import 'package:taskradar/storage/outbox_store.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_geofence.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_outbox_store.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_token_storage.dart';
import 'support/fixtures.dart';

/// «Выполнено» and «Завтра» on a reminder notification («Улучшить
/// уведомления»): which buttons a notification carries, how a press is read
/// back, and what it does -- with the app running (through the same writes as
/// a tap on the row) and without it (straight to the server, or to the
/// outbox file).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);

  group('reading a press back', () {
    test('Android: the action id, and the task from the payload', () {
      expect(
        NotificationActionRequest.parse(actionId: 'done', payload: 'task:t1'),
        const NotificationActionRequest(ReminderAction.done, 't1'),
      );
      expect(
        NotificationActionRequest.parse(
          actionId: 'tomorrow',
          payload: reminderPayload('t2'),
        ),
        const NotificationActionRequest(ReminderAction.tomorrow, 't2'),
      );
      expect(
        NotificationActionRequest.parse(
          actionId: 'place_tomorrow',
          payload: 'task:t3',
        ),
        const NotificationActionRequest(ReminderAction.placeTomorrow, 't3'),
      );
    });

    test('Windows: one self-contained argument, in either field', () {
      final argument = actionArgument(ReminderAction.done, 'task:t1');
      expect(argument, 'action:done|task:t1');
      const expected = NotificationActionRequest(ReminderAction.done, 't1');
      expect(
        NotificationActionRequest.parse(actionId: argument, payload: argument),
        expected,
      );
      expect(NotificationActionRequest.parse(payload: argument), expected);
    });

    test('anything that is not one of ours is ignored', () {
      // A body tap: no action.
      expect(NotificationActionRequest.parse(payload: 'task:t1'), isNull);
      // The bench's notification has the buttons but no task.
      expect(
        NotificationActionRequest.parse(actionId: 'done', payload: 'bench:now'),
        isNull,
      );
      // A button from some other build, an empty task, nothing at all.
      expect(
        NotificationActionRequest.parse(actionId: 'snooze', payload: 'task:t'),
        isNull,
      );
      expect(
        NotificationActionRequest.parse(actionId: 'done', payload: 'task:'),
        isNull,
      );
      expect(NotificationActionRequest.parse(), isNull);
      // Malformed Windows arguments.
      expect(NotificationActionRequest.parse(payload: 'action:done'), isNull);
      expect(
        NotificationActionRequest.parse(payload: 'action:nope|task:t1'),
        isNull,
      );
      expect(
        NotificationActionRequest.parse(payload: 'action:done|bench:now'),
        isNull,
      );
    });
  });

  group('«Завтра» in dates', () {
    test('the same time tomorrow', () {
      final target = postponeToTomorrow(
        remindTime: '18:30',
        now: DateTime(2026, 11, 17, 18, 31),
      );
      expect(target.date, '2026-11-18');
      expect(target.time, '18:30');
    });

    test('a day-only reminder stays day-only', () {
      final target = postponeToTomorrow(
        remindTime: null,
        now: DateTime(2026, 11, 17, 9),
      );
      expect(target.date, '2026-11-18');
      expect(target.time, isNull);
    });

    test('rolls over the month and the year', () {
      expect(
        postponeToTomorrow(remindTime: null, now: DateTime(2026, 11, 30)).date,
        '2026-12-01',
      );
      expect(
        postponeToTomorrow(
          remindTime: '23:59',
          now: DateTime(2026, 12, 31, 23, 59),
        ).date,
        '2027-01-01',
      );
      expect(
        postponeToTomorrow(remindTime: null, now: DateTime(2028, 2, 28)).date,
        '2028-02-29',
      );
    });

    test('tomorrow from now, not from the reminder it was about', () {
      // A notification left in the shade overnight.
      expect(
        postponeToTomorrow(
          remindTime: '09:00',
          now: DateTime(2026, 11, 19, 7),
        ).date,
        '2026-11-20',
      );
    });

    test('an unreadable time is dropped, not sent back', () {
      expect(
        postponeToTomorrow(remindTime: '9am', now: DateTime(2026, 11, 17)).time,
        isNull,
      );
    });

    test('a place is quiet until the next midnight', () {
      expect(
        placeSnoozeUntil(DateTime(2026, 11, 17, 14, 5)),
        DateTime(2026, 11, 18),
      );
      expect(placeSnoozeUntil(DateTime(2026, 12, 31, 23)), DateTime(2027));
    });
  });

  group('the buttons on a notification', () {
    test('every scheduled reminder carries «Выполнено» and «Завтра»', () async {
      final moscow = tz.getLocation('Europe/Moscow');
      final gateway = FakeNotificationGateway();
      final scheduler = ReminderScheduler(
        gateway: gateway,
        location: moscow,
        now: () => tz.TZDateTime(moscow, 2026, 9, 18, 8),
      );

      await scheduler.sync(
        reminders: const <TaskReminder>[
          TaskReminder(
            taskId: 'a',
            taskTitle: 'Позвонить',
            remindAt: '2026-09-18T00:00:00.000Z',
            remindTime: '18:30',
          ),
          TaskReminder(
            taskId: 'b',
            taskTitle: 'Жду кабель',
            remindAt: '2026-09-20T00:00:00.000Z',
          ),
        ],
      );

      expect(gateway.queue, hasLength(2));
      for (final scheduled in gateway.queue.values) {
        expect(scheduled.actions, <ReminderAction>[
          ReminderAction.done,
          ReminderAction.tomorrow,
        ]);
        expect(scheduled.actions.map((a) => a.label), <String>[
          'Выполнено',
          'Завтра',
        ]);
      }
    });

    test('at most two, and a place has its own «Завтра»', () {
      expect(dateReminderActions, hasLength(2));
      expect(placeReminderActions, <ReminderAction>[
        ReminderAction.done,
        ReminderAction.placeTomorrow,
      ]);
    });
  });

  group('a snoozed place', () {
    final now = DateTime(2026, 11, 17, 14);
    const zone = PlannedGeofence(
      taskId: 'tsk_shop',
      taskTitle: 'Купить батарейки',
      lat: 55.75,
      lng: 37.61,
      radius: 200,
    );

    test('does not ring until the snooze is over', () async {
      final store = MemoryGeofenceStore()
        ..zones = <String, PlannedGeofence>{zone.id: zone};
      final notifier = FakePlaceNotifier();

      await snoozePlace(
        store,
        zone.taskId,
        until: placeSnoozeUntil(now),
        now: now,
      );

      final quiet = await handleGeofenceEnter(
        zoneIds: <String>[zone.id],
        store: store,
        notifier: notifier,
        now: now.add(const Duration(hours: 9)),
      );
      expect(quiet, isEmpty);
      expect(notifier.shown, isEmpty);

      final next = await handleGeofenceEnter(
        zoneIds: <String>[zone.id],
        store: store,
        notifier: notifier,
        now: DateTime(2026, 11, 18, 0, 1),
      );
      expect(next, <String>['tsk_shop']);
    });

    test('survives the callback rewriting the cooldown file', () {
      final marks = <String, DateTime>{
        placeSnoozeKey('a'): DateTime(2026, 11, 18),
        placeSnoozeKey('b'): DateTime(2026, 11, 17, 13),
        'c': now.subtract(const Duration(hours: 1)),
      };
      final pruned = pruneCooldowns(marks, now: now);
      expect(pruned.keys, containsAll(<String>[placeSnoozeKey('a'), 'c']));
      expect(pruned.containsKey(placeSnoozeKey('b')), isFalse);
      expect(placeSnoozed(pruned, 'a', now: now), isTrue);
      expect(placeSnoozed(pruned, 'b', now: now), isFalse);
    });
  });

  group('with the app running', () {
    late FakeBackend backend;
    late FakeProjectBackend server;
    late FakeOutboxStore outbox;
    late FakeNotificationGateway gateway;
    late MemoryGeofenceStore geofences;
    late MemoryNotificationActionLog log;

    setUp(() {
      backend = FakeBackend();
      server = FakeProjectBackend(backend);
      outbox = FakeOutboxStore();
      gateway = FakeNotificationGateway();
      geofences = MemoryGeofenceStore();
      log = MemoryNotificationActionLog();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'),
            (MethodCall call) async =>
                call.method == 'getLocalTimezone' ? 'Europe/Moscow' : null,
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'),
            null,
          );
    });

    Future<ProviderContainer> start() async {
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
          notificationGatewayProvider.overrideWithValue(gateway),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          outboxStoreProvider.overrideWithValue(outbox),
          geofenceStoreProvider.overrideWithValue(geofences),
          notificationActionLogProvider.overrideWithValue(log),
        ],
      );
      addTearDown(container.dispose);
      container.listen(boardViewProvider, (_, _) {});
      container.listen(boardReminderBridgeProvider, (_, _) {});
      await container.read(boardProvider.future);
      await pumpEventQueue();
      return container;
    }

    Map<String, dynamic> serverTask(String id) =>
        server.tasks.singleWhere((row) => row['id'] == id);

    test('«Выполнено» closes the task, and the board shows it', () async {
      final projectId = server.addProject(name: 'Дача');
      final taskId = server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: '2026-10-01T00:00:00.000Z',
      );
      final container = await start();

      final outcome = await container
          .read(notificationActionsProvider.notifier)
          .handle(const NotificationActionRequest(ReminderAction.done, 'x'));
      expect(outcome.kind, NotificationActionOutcomeKind.ignored);

      final done = await container
          .read(notificationActionsProvider.notifier)
          .handle(NotificationActionRequest(ReminderAction.done, taskId));

      expect(done.kind, NotificationActionOutcomeKind.sent);
      expect(serverTask(taskId)['status'], 'done');
      expect(serverTask(taskId)['remindAt'], isNull);
      final board = container.read(boardProvider).requireValue.projects;
      expect(
        board.single.tasks.singleWhere((t) => t.id == taskId).status.name,
        'done',
      );
      expect(log.records.first.where, 'приложение');
      expect(log.records.first.outcome, 'отправлено');
    });

    test(
      'a press that reaches the app through the gateway is carried out',
      () async {
        final projectId = server.addProject(name: 'Дача');
        final taskId = server.addTask(projectId: projectId, title: 'Полить');
        // Pressed before anything was listening: buffered, not lost.
        gateway.press(NotificationActionRequest(ReminderAction.done, taskId));

        final container = await start();
        container.listen(notificationActionBridgeProvider, (_, _) {});
        await pumpEventQueue();

        expect(serverTask(taskId)['status'], 'done');
      },
    );

    test('«Выполнено» with no network goes to the outbox', () async {
      final projectId = server.addProject(name: 'Дача');
      final taskId = server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: '2026-10-01T00:00:00.000Z',
      );
      final container = await start();
      backend.failingPaths.add('/');

      final outcome = await container
          .read(notificationActionsProvider.notifier)
          .handle(NotificationActionRequest(ReminderAction.done, taskId));

      expect(outcome.kind, NotificationActionOutcomeKind.queued);
      expect(serverTask(taskId)['status'], 'blocked');
      final entry = outbox.entries.single;
      expect(entry.kind, OutboxKind.editTask);
      expect(entry.taskId, taskId);
      expect(entry.body, <String, Object?>{'status': 'done', 'remindAt': null});
      expect(entry.expected, <String, Object?>{'status': 'blocked'});
      // The place stays quiet until the app can drop the zone.
      expect(
        placeSnoozed(geofences.cooldowns, taskId, now: DateTime.now()),
        isTrue,
      );
    });

    test('«Завтра» moves the date and keeps the time', () async {
      final projectId = server.addProject(name: 'Дача');
      final taskId = server.addTask(
        projectId: projectId,
        title: 'Позвонить',
        remindAt: '2026-11-17T00:00:00.000Z',
        remindTime: '18:30',
      );
      final container = await start();

      final outcome = await container
          .read(notificationActionsProvider.notifier)
          .handle(
            NotificationActionRequest(ReminderAction.tomorrow, taskId),
            now: DateTime(2026, 11, 17, 18, 31),
          );

      expect(outcome.kind, NotificationActionOutcomeKind.sent);
      expect(serverTask(taskId)['remindAt'], startsWith('2026-11-18'));
      expect(serverTask(taskId)['remindTime'], '18:30');
    });

    test('«Завтра» on a day-only reminder, across a month', () async {
      final projectId = server.addProject(name: 'Дача');
      final taskId = server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: '2026-11-30T00:00:00.000Z',
      );
      final container = await start();

      await container
          .read(notificationActionsProvider.notifier)
          .handle(
            NotificationActionRequest(ReminderAction.tomorrow, taskId),
            now: DateTime(2026, 11, 30, 9),
          );

      expect(serverTask(taskId)['remindAt'], startsWith('2026-12-01'));
      expect(serverTask(taskId)['remindTime'], isNull);
    });

    test(
      '«Завтра» with no network: queued, and the alarm moves anyway',
      () async {
        final projectId = server.addProject(name: 'Дача');
        final taskId = server.addTask(
          projectId: projectId,
          title: 'Позвонить',
          remindAt: '2026-10-01T00:00:00.000Z',
          remindTime: '18:30',
        );
        final container = await start();
        // Nothing armed: the date is in the past.
        expect(
          gateway.queue.containsKey(notificationIdForTask(taskId)),
          isFalse,
        );
        backend.failingPaths.add('/');

        final now = DateTime.now();
        final outcome = await container
            .read(notificationActionsProvider.notifier)
            .handle(
              NotificationActionRequest(ReminderAction.tomorrow, taskId),
              now: now,
            );
        await pumpEventQueue();

        expect(outcome.kind, NotificationActionOutcomeKind.queued);
        final tomorrow = DateTime(now.year, now.month, now.day + 1);
        expect(outbox.entries.single.body, <String, Object?>{
          'remindAt': postponeToTomorrow(remindTime: null, now: now).date,
          'remindTime': '18:30',
        });

        final armed = gateway.queue[notificationIdForTask(taskId)];
        expect(armed, isNotNull, reason: 'the outbox edit re-arms the alarm');
        expect(
          <int>[armed!.fireAt.year, armed.fireAt.month, armed.fireAt.day],
          <int>[tomorrow.year, tomorrow.month, tomorrow.day],
        );
        expect(<int>[armed.fireAt.hour, armed.fireAt.minute], <int>[18, 30]);
        expect(armed.actions, dateReminderActions);
      },
    );

    test('«Завтра» on a place only quiets the place', () async {
      final container = await start();
      final requests = backend.requests.length;
      final now = DateTime(2026, 11, 17, 14);

      await container
          .read(notificationActionsProvider.notifier)
          .handle(
            const NotificationActionRequest(
              ReminderAction.placeTomorrow,
              'tsk_shop',
            ),
            now: now,
          );

      expect(backend.requests.length, requests);
      expect(
        geofences.cooldowns[placeSnoozeKey('tsk_shop')],
        DateTime(2026, 11, 18),
      );
    });
  });

  group('with no app running', () {
    late FakeBackend backend;
    late FakeProjectBackend server;
    late FakeOutboxStore outbox;
    late FakeNotificationGateway gateway;
    late MemoryGeofenceStore geofences;
    late FakeBoardSnapshotStore snapshots;
    late MemoryNotificationActionLog log;
    late FakeTokenStorage tokens;
    late final tz.Location moscow = tz.getLocation('Europe/Moscow');

    setUp(() {
      backend = FakeBackend();
      server = FakeProjectBackend(backend);
      outbox = FakeOutboxStore();
      gateway = FakeNotificationGateway();
      geofences = MemoryGeofenceStore();
      snapshots = FakeBoardSnapshotStore();
      log = MemoryNotificationActionLog();
      tokens = FakeTokenStorage('jwt.token');
    });

    HeadlessReminderActions headless() => HeadlessReminderActions(
      tokens: tokens,
      client: backend.client,
      snapshots: snapshots,
      outbox: outbox,
      gateway: gateway,
      geofences: geofences,
      settings: FakeSettingsStore(time: const ReminderTime(8, 15)),
      location: () async => moscow,
      log: log,
    );

    /// A task on the server, and the same task in the board snapshot.
    String seed({
      String status = 'blocked',
      String? remindAt = '2026-11-17T00:00:00.000Z',
      String? remindTime,
    }) {
      final projectId = server.addProject(name: 'Дача');
      final taskId = server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: status,
        remindAt: remindAt,
        remindTime: remindTime,
      );
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(<dynamic>[
          boardProjectJson(
            id: projectId,
            name: 'Дача',
            tasks: <Map<String, dynamic>>[
              <String, dynamic>{
                ...taskJson(
                  id: taskId,
                  projectId: projectId,
                  title: 'Жду кабель',
                  status: status,
                  remindAt: remindAt,
                ),
                'remindTime': remindTime,
              },
            ],
          ),
        ]),
        savedAt: DateTime(2026, 11, 17, 8),
      );
      return taskId;
    }

    Map<String, dynamic> serverTask(String id) =>
        server.tasks.singleWhere((row) => row['id'] == id);

    test(
      '«Выполнено» goes straight to the server with the stored token',
      () async {
        final taskId = seed();
        final now = DateTime(2026, 11, 17, 9);

        final outcome = await headless().run(
          NotificationActionRequest(ReminderAction.done, taskId),
          now: now,
        );

        expect(outcome.kind, NotificationActionOutcomeKind.sent);
        expect(serverTask(taskId)['status'], 'done');
        expect(serverTask(taskId)['remindAt'], isNull);
        expect(
          backend.lastRequest.headers['Authorization'],
          'Bearer jwt.token',
        );
        expect(outbox.entries, isEmpty);
        expect(
          gateway.cancelledIds,
          containsAll(<int>[
            notificationIdForTask(taskId),
            geofenceNotificationId(taskId),
          ]),
        );
        expect(placeSnoozed(geofences.cooldowns, taskId, now: now), isTrue);
        expect(log.records.single.where, 'фон');
      },
    );

    test(
      '«Выполнено» with no network is the outbox entry the app would make',
      () async {
        final taskId = seed();
        backend.failingPaths.add('/');

        final outcome = await headless().run(
          NotificationActionRequest(ReminderAction.done, taskId),
          now: DateTime(2026, 11, 17, 9),
        );

        expect(outcome.kind, NotificationActionOutcomeKind.queued);
        expect(serverTask(taskId)['status'], 'blocked');
        final entry = outbox.entries.single;
        expect(entry.kind, OutboxKind.editTask);
        expect(entry.isWaiting, isTrue);
        expect(entry.taskId, taskId);
        expect(entry.title, 'Жду кабель');
        expect(entry.body, <String, Object?>{
          'status': 'done',
          'remindAt': null,
        });
        expect(entry.expected, <String, Object?>{'status': 'blocked'});
      },
    );

    test('an entry it queued is sent by the app later', () async {
      final taskId = seed();
      backend.failingPaths.add('/');
      await headless().run(
        NotificationActionRequest(ReminderAction.done, taskId),
        now: DateTime(2026, 11, 17, 9),
      );
      backend.failingPaths.clear();

      // The app's own replay of the entry, as `Outbox.flush` does it.
      final entry = outbox.entries.single;
      await backend.client.patch<Map<String, dynamic>>(
        '/tasks/${entry.taskId}',
        body: <String, dynamic>{...entry.body, 'expected': entry.expected},
      );
      expect(serverTask(taskId)['status'], 'done');
    });

    test('«Завтра» moves the date and arms tomorrow\'s alarm', () async {
      final taskId = seed(remindTime: '18:30');
      final now = DateTime(2026, 11, 17, 18, 31);

      final outcome = await headless().run(
        NotificationActionRequest(ReminderAction.tomorrow, taskId),
        now: now,
      );

      expect(outcome.kind, NotificationActionOutcomeKind.sent);
      expect(serverTask(taskId)['remindAt'], startsWith('2026-11-18'));
      expect(serverTask(taskId)['remindTime'], '18:30');

      final armed = gateway.queue[notificationIdForTask(taskId)]!;
      expect(armed.fireAt, tz.TZDateTime(moscow, 2026, 11, 18, 18, 30));
      expect(armed.payload, reminderPayload(taskId));
      expect(armed.title, 'Дача');
      expect(armed.body, 'Жду кабель');
      expect(armed.actions, dateReminderActions);
    });

    test('«Завтра» on a day-only reminder fires at the settings hour, across a '
        'year', () async {
      final taskId = seed(remindAt: '2026-12-31T00:00:00.000Z');
      backend.failingPaths.add('/');

      final outcome = await headless().run(
        NotificationActionRequest(ReminderAction.tomorrow, taskId),
        now: DateTime(2026, 12, 31, 9),
      );

      expect(outcome.kind, NotificationActionOutcomeKind.queued);
      expect(outbox.entries.single.body, <String, Object?>{
        'remindAt': '2027-01-01',
      });
      expect(outbox.entries.single.expected, <String, Object?>{
        'remindAt': '2026-12-31',
      });
      expect(
        gateway.queue[notificationIdForTask(taskId)]!.fireAt,
        tz.TZDateTime(moscow, 2027, 1, 1, 8, 15),
      );
    });

    test('«Завтра» on a task already done changes nothing', () async {
      final taskId = seed(status: 'done', remindAt: null);
      final requests = backend.requests.length;

      final outcome = await headless().run(
        NotificationActionRequest(ReminderAction.tomorrow, taskId),
        now: DateTime(2026, 11, 17, 9),
      );

      expect(outcome.kind, NotificationActionOutcomeKind.ignored);
      expect(backend.requests.length, requests);
      expect(gateway.queue, isEmpty);
    });

    test('signed out: nothing is sent', () async {
      final taskId = seed();
      tokens.token = null;

      final outcome = await headless().run(
        NotificationActionRequest(ReminderAction.done, taskId),
        now: DateTime(2026, 11, 17, 9),
      );

      expect(outcome.kind, NotificationActionOutcomeKind.ignored);
      expect(backend.requests, isEmpty);
      expect(outbox.entries, isEmpty);
    });

    test('a task the server no longer has is reported, not queued', () async {
      seed();
      final outcome = await headless().run(
        const NotificationActionRequest(ReminderAction.done, 'tsk_gone'),
        now: DateTime(2026, 11, 17, 9),
      );

      expect(outcome.kind, NotificationActionOutcomeKind.failed);
      expect(outbox.entries, isEmpty);
    });

    test(
      '«Завтра» on a place needs neither the network nor a session',
      () async {
        tokens.token = null;
        final now = DateTime(2026, 11, 17, 14);

        await headless().run(
          const NotificationActionRequest(
            ReminderAction.placeTomorrow,
            'tsk_shop',
          ),
          now: now,
        );

        expect(backend.requests, isEmpty);
        expect(placeSnoozed(geofences.cooldowns, 'tsk_shop', now: now), isTrue);
        expect(
          placeSnoozed(
            geofences.cooldowns,
            'tsk_shop',
            now: DateTime(2026, 11, 18, 0, 1),
          ),
          isFalse,
        );
      },
    );
  });
}
