import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/providers/board_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/notification_link_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';
import 'support/fixtures.dart';

/// "The user tapped a reminder; open that task" -- both paths, and every way it
/// can fail to resolve (F4).
///
/// The two paths are not two flavours of the same thing. A tap on a *running*
/// app arrives through the plugin's response callback; a tap that **starts** the
/// app does not reach that callback at all and is readable only through
/// `getNotificationAppLaunchDetails`. The second is the one that matters (09:00,
/// phone on the table, app swiped away overnight) and the one that is silently
/// missing if only the first is wired, so it is tested first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();

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

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        boardSnapshotStoreProvider.overrideWithValue(snapshots),
        notificationGatewayProvider.overrideWithValue(gateway),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A project with one blocked, dated task -- the shape a reminder comes from.
  ({String projectId, String taskId}) seedBlockedTask() {
    final projectId = server.addProject(name: 'Дача');
    final taskId = server.addTask(
      projectId: projectId,
      title: 'Жду кабель',
      status: 'blocked',
      remindAt: '2026-10-01T00:00:00.000Z',
    );
    return (projectId: projectId, taskId: taskId);
  }

  /// Brings the bridge up, the way the signed-in scope does, and lets it settle.
  Future<void> startBridge(ProviderContainer container) async {
    container.listen(notificationLinkProvider, (_, _) {});
    await container.read(notificationLinkBridgeProvider.future);
    await pumpEventQueue();
  }

  group('payload parsing', () {
    test('a reminder payload yields its task id', () {
      expect(taskIdFromPayload('task:tsk_1'), 'tsk_1');
      expect(taskIdFromPayload(reminderPayload('abc')), 'abc');
    });

    test('anything else yields nothing', () {
      // The bench posts `bench:` payloads for its diagnostics. Those must never
      // navigate anywhere.
      expect(taskIdFromPayload('bench:now'), isNull);
      expect(taskIdFromPayload('task:'), isNull);
      expect(taskIdFromPayload(null), isNull);
      expect(taskIdFromPayload(''), isNull);
    });

    test('a non-reminder payload does not start a request', () async {
      final container = makeContainer();
      await startBridge(container);

      container
          .read(notificationLinkProvider.notifier)
          .requestFromPayload('bench:now');
      await pumpEventQueue();

      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkIdle>(),
      );
    });
  });

  group('cold start -- the app was launched by the tap', () {
    test('the launch payload is read and resolved', () async {
      final seeded = seedBlockedTask();
      gateway.launchPayload = 'task:${seeded.taskId}';

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await startBridge(container);

      final state = container.read(notificationLinkProvider);
      expect(state, isA<NotificationLinkReady>());
      expect((state as NotificationLinkReady).projectId, seeded.projectId);
      expect(state.taskId, seeded.taskId);
    });

    test('it is read exactly once per run', () async {
      // On Android `onNewIntent` replaces the activity's launch intent, so a
      // second read would hand back a *background* tap that the callback has
      // already delivered -- and the app would navigate twice.
      final seeded = seedBlockedTask();
      gateway.launchPayload = 'task:${seeded.taskId}';

      final container = makeContainer();
      await startBridge(container);
      expect(gateway.launchPayloadReads, 1);

      container.read(notificationLinkProvider.notifier).ack();
      await container.read(notificationLinkBridgeProvider.future);
      await pumpEventQueue();

      expect(gateway.launchPayloadReads, 1);
      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkIdle>(),
      );
    });

    test('no launch payload means nothing pending', () async {
      seedBlockedTask();
      final container = makeContainer();
      await startBridge(container);

      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkIdle>(),
      );
    });
  });

  group('from the background -- the app was already running', () {
    test(
      'a tap delivered through the callback resolves the same way',
      () async {
        final seeded = seedBlockedTask();

        final container = makeContainer();
        container.listen(boardViewProvider, (_, _) {});
        await startBridge(container);
        expect(
          container.read(notificationLinkProvider),
          isA<NotificationLinkIdle>(),
        );

        gateway.tap('task:${seeded.taskId}');
        await pumpEventQueue();

        final state = container.read(notificationLinkProvider);
        expect(state, isA<NotificationLinkReady>());
        expect((state as NotificationLinkReady).projectId, seeded.projectId);
      },
    );

    test('a tap that arrives before anyone is listening is not lost', () async {
      // The race that only ever loses on a slow device: the plugin is up but
      // the navigation layer has not subscribed yet.
      final seeded = seedBlockedTask();
      gateway.tap('task:${seeded.taskId}');

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await startBridge(container);

      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkReady>(),
      );
    });
  });

  group('resolving without the network', () {
    test(
      'the board snapshot answers, so a reminder opens with no signal',
      () async {
        // The whole reason the snapshot holds tasks rather than project names.
        snapshots.snapshot = BoardSnapshot(
          projects: BoardProject.listFromJson(<dynamic>[
            boardProjectJson(
              id: 'prj_cached',
              name: 'Дача',
              tasks: <Map<String, dynamic>>[
                taskJson(
                  id: 'tsk_cached',
                  projectId: 'prj_cached',
                  title: 'Жду кабель',
                  status: 'blocked',
                  remindAt: '2026-10-01T00:00:00.000Z',
                ),
              ],
            ),
          ]),
          savedAt: DateTime.now().subtract(const Duration(hours: 6)),
        );
        backend.alwaysFailToConnect();

        final container = makeContainer();
        container.listen(boardViewProvider, (_, _) {});
        // Let the failed fetch and the snapshot read both settle first.
        await pumpEventQueue();

        gateway.launchPayload = 'task:tsk_cached';
        await startBridge(container);

        final state = container.read(notificationLinkProvider);
        expect(state, isA<NotificationLinkReady>());
        expect((state as NotificationLinkReady).projectId, 'prj_cached');
        expect(
          backend.requests.where((r) => r.path == '/board').length,
          1,
          reason: 'the cache answered; there was nothing to ask the server',
        );
      },
    );

    test(
      'no snapshot and no network is "не удалось", never "задача удалена"',
      () async {
        backend.alwaysFailToConnect();

        final container = makeContainer();
        container.listen(boardViewProvider, (_, _) {});
        gateway.launchPayload = 'task:tsk_unknown';
        await startBridge(container);

        final state = container.read(notificationLinkProvider);
        expect(
          state,
          isA<NotificationLinkUnreachable>(),
          reason:
              'telling someone their task is gone when the truth is that the '
              'train went into a tunnel is the worst available answer',
        );
        expect(
          (state as NotificationLinkUnreachable).error,
          isA<NetworkException>(),
        );
      },
    );

    test('a task missing from the cache is refetched before judging', () async {
      // The snapshot is older than the task: the reminder is real, the cache is
      // just behind. One refresh settles it.
      snapshots.snapshot = BoardSnapshot(
        projects: const <BoardProject>[],
        savedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final seeded = seedBlockedTask();

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await pumpEventQueue();

      gateway.launchPayload = 'task:${seeded.taskId}';
      await startBridge(container);

      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkReady>(),
      );
    });
  });

  group('the task is not there', () {
    test('a deleted task is reported as not found', () async {
      seedBlockedTask();

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      gateway.launchPayload = 'task:tsk_deleted_last_week';
      await startBridge(container);

      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkNotFound>(),
      );
    });

    test('a task in an archived project still opens', () async {
      // A project can be archived after its alarm was armed. The task still
      // exists and the screen still works, so saying "deleted" would be wrong.
      final projectId = server.addProject(
        name: 'Дача',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      final taskId = server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: '2026-10-01T00:00:00.000Z',
      );

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      gateway.launchPayload = 'task:$taskId';
      await startBridge(container);

      final state = container.read(notificationLinkProvider);
      expect(state, isA<NotificationLinkReady>());
      expect((state as NotificationLinkReady).projectId, projectId);
    });
  });

  group('the state machine', () {
    test('ack clears the request so it is not acted on twice', () async {
      final seeded = seedBlockedTask();
      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await startBridge(container);

      gateway.tap('task:${seeded.taskId}');
      await pumpEventQueue();
      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkReady>(),
      );

      container.read(notificationLinkProvider.notifier).ack();
      expect(
        container.read(notificationLinkProvider),
        isA<NotificationLinkIdle>(),
      );
    });

    test('a second tap wins over the first one landing late', () async {
      final first = seedBlockedTask();
      final secondProject = server.addProject(name: 'Ремонт');
      final secondTask = server.addTask(
        projectId: secondProject,
        title: 'Ждём плитку',
        status: 'blocked',
        remindAt: '2026-10-02T00:00:00.000Z',
      );

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await startBridge(container);

      final link = container.read(notificationLinkProvider.notifier);
      // Not awaited: both run, and the generation counter decides which answer
      // is allowed to publish.
      final firstRun = link.open(first.taskId);
      final secondRun = link.open(secondTask);
      await Future.wait(<Future<void>>[firstRun, secondRun]);
      await pumpEventQueue();

      final state = container.read(notificationLinkProvider);
      expect(state, isA<NotificationLinkReady>());
      expect((state as NotificationLinkReady).taskId, secondTask);
    });
  });
}
