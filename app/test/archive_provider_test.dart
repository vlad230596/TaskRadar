import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/project.dart';
import 'package:taskradar/providers/archive_providers.dart';
import 'package:taskradar/providers/board_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// Creating a project, archiving it, bringing it back, and deleting it (F4).
///
/// Two claims here are worth more than the CRUD:
///
/// - **archiving stops the reminders**, with nothing in this file mentioning
///   the scheduler. That has to be true or an archived project keeps waking
///   someone up at 09:00 about work they explicitly put down;
/// - **deleting an active project is refused before it is asked**, which is the
///   client half of `canHardDeleteProject`.
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
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), null);
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

  /// Subscribes the way the board screen does, so an invalidation refetches.
  Future<void> watchBoard(ProviderContainer container) async {
    container.listen(boardViewProvider, (_, _) {});
    await container.read(boardProvider.future);
  }

  List<String> boardNames(ProviderContainer container) => <String>[
    for (final row in container.read(boardProvider).requireValue.projects)
      row.project.name,
  ];

  /// `remindAt` [offsetDays] from today, in the shape the server stores.
  String remindAt(int offsetDays) {
    final day = DateTime.now().add(Duration(days: offsetDays));
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}'
        'T00:00:00.000Z';
  }

  group('creating a project', () {
    test('POSTs the name and puts the project on the board', () async {
      final container = makeContainer();
      await watchBoard(container);
      expect(boardNames(container), isEmpty);

      final created = await container
          .read(projectLifecycleProvider.notifier)
          .create('  Ремонт квартиры  ');

      expect(created.name, 'Ремонт квартиры', reason: 'trimmed');
      expect(created.archivedAt, isNull);

      await container.read(boardProvider.future);
      expect(boardNames(container), <String>['Ремонт квартиры']);
    });

    test('an empty name is refused without a request', () async {
      final container = makeContainer();
      final before = backend.requests.length;

      expect(
        () => container.read(projectLifecycleProvider.notifier).create('   '),
        throwsArgumentError,
      );
      expect(backend.requests.length, before);
    });

    test('a failed create leaves the board alone and throws', () async {
      final container = makeContainer();
      await watchBoard(container);
      backend.alwaysFailToConnect();

      await expectLater(
        container.read(projectLifecycleProvider.notifier).create('Новый'),
        throwsA(isA<NetworkException>()),
      );
      // There is no optimistic row to roll back: a project is created by the
      // server or not at all.
      expect(boardNames(container), isEmpty);
    });
  });

  group('archiving', () {
    test('takes the project off the board and puts it in the archive', () async {
      final active = server.addProject(name: 'Дача');
      server.addProject(name: 'TaskRadar', createdAt: '2026-08-02T09:00:00.000Z');

      final container = makeContainer();
      await watchBoard(container);
      expect(boardNames(container), <String>['Дача', 'TaskRadar']);

      await container.read(projectLifecycleProvider.notifier).archive(active);
      await container.read(boardProvider.future);

      expect(boardNames(container), <String>['TaskRadar']);
      final archived = await container.read(archivedBoardProvider.future);
      expect(archived.map((row) => row.project.name), <String>['Дача']);
      expect(
        archived.single.project.archivedAt,
        FakeProjectBackend.archivedAtStamp,
      );
    });

    test('the archived project keeps its tasks', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Покрасить забор');
      server.addTask(projectId: projectId, title: 'Жду кабель', status: 'done');

      final container = makeContainer();
      await watchBoard(container);
      await container.read(projectLifecycleProvider.notifier).archive(projectId);

      final archived = await container.read(archivedBoardProvider.future);
      expect(archived.single.tasks, hasLength(2));
    });

    test(
      'the alarms of its blocked tasks are cancelled, with nothing here '
      'calling the scheduler',
      () async {
        final projectId = server.addProject(name: 'Дача');
        final taskId = server.addTask(
          projectId: projectId,
          title: 'Жду кабель',
          status: 'blocked',
          remindAt: remindAt(3),
        );

        final container = makeContainer();
        container.listen(boardReminderBridgeProvider, (_, _) {});
        await watchBoard(container);
        await pumpEventQueue();
        await container.read(reminderSyncProvider.future);

        expect(gateway.queue, hasLength(1));
        expect(gateway.queue.values.single.payload, 'task:$taskId');

        await container
            .read(projectLifecycleProvider.notifier)
            .archive(projectId);
        await container.read(boardProvider.future);
        await pumpEventQueue();
        await container.read(reminderSyncProvider.future);

        // This is the whole chain running on its own: the board no longer has
        // the row, so `remindersFromBoard` produces a smaller target set, so the
        // scheduler cancels. An archived project must stop nagging -- that is
        // what archiving it means.
        expect(container.read(reminderTargetsProvider), isEmpty);
        expect(gateway.queue, isEmpty);
      },
    );

    test('a failed archive leaves the board as it was', () async {
      final projectId = server.addProject(name: 'Дача');
      final container = makeContainer();
      await watchBoard(container);

      backend.alwaysFailToConnect();
      await expectLater(
        container.read(projectLifecycleProvider.notifier).archive(projectId),
        throwsA(isA<NetworkException>()),
      );

      expect(boardNames(container), <String>['Дача']);
    });
  });

  group('unarchiving', () {
    test('puts the project back on the board and out of the archive', () async {
      final projectId = server.addProject(
        name: 'Дача',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );

      final container = makeContainer();
      await watchBoard(container);
      expect(boardNames(container), isEmpty);
      expect(await container.read(archivedBoardProvider.future), hasLength(1));

      await container
          .read(projectLifecycleProvider.notifier)
          .unarchive(projectId);
      await container.read(boardProvider.future);

      expect(boardNames(container), <String>['Дача']);
      expect(await container.read(archivedBoardProvider.future), isEmpty);
    });

    test('its reminders come back with it', () async {
      final projectId = server.addProject(
        name: 'Дача',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      final taskId = server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: remindAt(3),
      );

      final container = makeContainer();
      container.listen(boardReminderBridgeProvider, (_, _) {});
      await watchBoard(container);
      await pumpEventQueue();
      await container.read(reminderSyncProvider.future);
      expect(gateway.queue, isEmpty);

      await container
          .read(projectLifecycleProvider.notifier)
          .unarchive(projectId);
      await container.read(boardProvider.future);
      await pumpEventQueue();
      await container.read(reminderSyncProvider.future);

      expect(gateway.queue, hasLength(1));
      expect(gateway.queue.values.single.payload, 'task:$taskId');
    });
  });

  group('deleting', () {
    test('an archived project goes, with its tasks and its notes', () async {
      final projectId = server.addProject(
        name: 'Дача',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      server.addTask(projectId: projectId, title: 'Покрасить забор');
      server.addNote(projectId: projectId, title: 'Контекст');

      final container = makeContainer();
      await watchBoard(container);

      final archived = await container.read(archivedBoardProvider.future);
      await container
          .read(projectLifecycleProvider.notifier)
          .delete(archived.single.project);

      expect(await container.read(archivedBoardProvider.future), isEmpty);
      expect(server.projects, isEmpty);
      expect(server.tasks, isEmpty);
      expect(server.notes, isEmpty);
    });

    test('an active project is refused by the client, without a request', () async {
      final projectId = server.addProject(name: 'Дача');
      final container = makeContainer();
      await watchBoard(container);
      final before = backend.requests.length;

      final active = container
          .read(boardProvider)
          .requireValue
          .projects
          .single
          .project;
      expect(active.id, projectId);
      expect(active.archivedAt, isNull);

      expect(
        () => container.read(projectLifecycleProvider.notifier).delete(active),
        throwsStateError,
      );
      expect(
        backend.requests.length,
        before,
        reason: 'the rule is stated before the round trip, not after a 409',
      );
      expect(server.projects, hasLength(1));
    });

    test('and the server refuses it too, if anyone ever asks anyway', () async {
      // The guard lives on the server (`canHardDeleteProject`); the client's
      // refusal above is a convenience, not the protection. If this ever stops
      // being a 409, the UI's ordering is the only thing left standing between
      // a mis-tap and a permanent delete.
      final projectId = server.addProject(name: 'Дача');
      final container = makeContainer();

      await expectLater(
        container.read(projectApiProvider).deleteProject(projectId),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
        ),
      );
      expect(server.projects, hasLength(1));
    });

    test('a failed delete leaves the project in the archive', () async {
      server.addProject(name: 'Дача', archivedAt: '2026-09-01T00:00:00.000Z');
      final container = makeContainer();
      final archived = await container.read(archivedBoardProvider.future);

      backend.alwaysFailToConnect();
      await expectLater(
        container
            .read(projectLifecycleProvider.notifier)
            .delete(archived.single.project),
        throwsA(isA<NetworkException>()),
      );
      expect(server.projects, hasLength(1));
    });
  });

  group('projectIdForTask', () {
    // The deep link's whole mapping from `task:<id>` to a project, because the
    // backend has no `GET /tasks/:id` to ask.
    List<BoardProject> rows() => <BoardProject>[
      BoardProject(
        project: const Project(
          id: 'prj_a',
          name: 'Дача',
          scopeId: 's-main',
          archivedAt: null,
          createdAt: '2026-08-01T09:00:00.000Z',
          updatedAt: '2026-08-01T09:00:00.000Z',
        ),
        tasks: const [],
      ),
      BoardProject.fromJson(<String, dynamic>{
        'id': 'prj_b',
        'name': 'Ремонт',
        'scopeId': 's-main',
        'archivedAt': null,
        'createdAt': '2026-08-02T09:00:00.000Z',
        'updatedAt': '2026-08-02T09:00:00.000Z',
        'tasks': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'tsk_1',
            'projectId': 'prj_b',
            'title': 'Жду кабель',
            'description': null,
            'status': 'blocked',
            'position': 1000,
            'remindAt': '2026-10-01T00:00:00.000Z',
            'createdAt': '2026-08-02T09:00:00.000Z',
            'updatedAt': '2026-08-02T09:00:00.000Z',
            'isCurrent': false,
          },
        ],
      }),
    ];

    test('finds the project a task belongs to', () {
      expect(projectIdForTask(rows(), 'tsk_1'), 'prj_b');
    });

    test('answers null for a task that is not there', () {
      expect(projectIdForTask(rows(), 'tsk_gone'), isNull);
      expect(projectIdForTask(const <BoardProject>[], 'tsk_1'), isNull);
    });
  });
}
