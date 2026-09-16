import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/note.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/providers/board_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/project_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fixtures.dart';

/// The F3 write path: optimistic frame, rollback, reconcile, and the effect a
/// write inside a project has on the board and on the alarm queue.
///
/// Run against the stateful [FakeProjectBackend] rather than canned bodies,
/// because every claim here is about a *sequence* -- "write, then re-read, then
/// splice" -- and a canned response cannot tell a correct sequence from an
/// incorrect one.
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

    // `flutter_timezone` is a platform channel; pinning it keeps "09:00 local"
    // identical on every machine.
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
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// `remindAt` in the shape the server stores it, [offsetDays] from today.
  String remindAt(int offsetDays) {
    final day = DateTime.now().add(Duration(days: offsetDays));
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}'
        'T00:00:00.000Z';
  }

  /// Subscribes the way the screen does and waits for the first load.
  Future<List<Task>> loadTasks(
    ProviderContainer container,
    String projectId,
  ) async {
    container.listen(projectTasksProvider(projectId), (_, _) {});
    return container.read(projectTasksProvider(projectId).future);
  }

  Future<List<Note>> loadNotes(
    ProviderContainer container,
    String projectId,
  ) async {
    container.listen(projectNotesProvider(projectId), (_, _) {});
    return container.read(projectNotesProvider(projectId).future);
  }

  List<Task> tasksNow(ProviderContainer container, String projectId) =>
      container.read(projectTasksProvider(projectId)).requireValue;

  List<String> titles(List<Task> tasks) =>
      tasks.map((task) => task.title).toList();

  group('loading', () {
    test('tasks come from GET /projects/:id/tasks, in server order', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Первая', status: 'done');
      server.addTask(projectId: projectId, title: 'Вторая');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);

      expect(titles(tasks), <String>['Первая', 'Вторая']);
      expect(tasks.last.isCurrent, isTrue);
    });

    test('a 404 becomes ProjectMissing, not an error page', () async {
      final container = makeContainer();
      container.listen(projectViewProvider('nope'), (_, _) {});

      await expectLater(
        container.read(projectTasksProvider('nope').future),
        throwsA(isA<ApiException>()),
      );
      await pumpEventQueue();

      expect(
        container.read(projectViewProvider('nope')),
        isA<ProjectMissing>(),
      );
    });

    test('with no network and a cached board, the snapshot is shown', () async {
      // The F4 case: a notification deep link on a phone with no signal. The
      // board snapshot holds tasks precisely so this screen can still open.
      const projectId = 'prj_cached';
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(<dynamic>[
          boardProjectJson(
            id: projectId,
            name: 'Дача',
            tasks: <Map<String, dynamic>>[
              taskJson(
                id: 'tsk_cached',
                projectId: projectId,
                title: 'Из кэша',
                isCurrent: true,
              ),
            ],
          ),
        ]),
        savedAt: DateTime.now(),
      );
      backend.alwaysFailToConnect();

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      container.listen(projectViewProvider(projectId), (_, _) {});
      await pumpEventQueue();

      final view = container.read(projectViewProvider(projectId));
      expect(view, isA<ProjectReady>());
      final ready = view as ProjectReady;
      expect(ready.project.name, 'Дача');
      expect(titles(ready.tasks), <String>['Из кэша']);
      expect(ready.origin, TaskOrigin.cache);
      expect(ready.isStale, isTrue);
      // And it says so: a write against this is going to fail.
      expect(ready.refreshError, isA<NetworkException>());
    });

    test('the project header costs no request when the board has it', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Задача');

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await container.read(boardProvider.future);

      final before = backend.requests.length;
      container.listen(projectHeaderProvider(projectId), (_, _) {});
      final project = await container.read(
        projectHeaderProvider(projectId).future,
      );

      expect(project.name, 'Дача');
      expect(
        backend.requests.length,
        before,
        reason: 'the board row IS GET /projects/:id plus tasks',
      );
    });
  });

  group('creating a task', () {
    test('the row appears before the server answers, then settles', () async {
      final projectId = server.addProject(name: 'Дача');
      final container = makeContainer();
      await loadTasks(container, projectId);

      final gate = Completer<void>();
      backend.delay = (options) =>
          options.method == 'POST' ? gate.future : Future<void>.value();

      final writing = container
          .read(projectTasksProvider(projectId).notifier)
          .create('Позвонить прорабу');
      await pumpEventQueue(times: 3);

      // The optimistic frame: on screen, with an id the server has never seen.
      final optimistic = tasksNow(container, projectId);
      expect(titles(optimistic), <String>['Позвонить прорабу']);
      expect(isOptimisticId(optimistic.single.id), isTrue);
      // It does not claim to be the current task -- that is the server's call,
      // even though it will in fact turn out to be true.
      expect(optimistic.single.isCurrent, isFalse);

      gate.complete();
      await writing;

      final settled = tasksNow(container, projectId);
      expect(isOptimisticId(settled.single.id), isFalse);
      expect(settled.single.id, server.tasks.single['id']);
      // ...and now the highlight is there, because the re-read said so.
      expect(settled.single.isCurrent, isTrue);
    });

    test('a failed create rolls the row back and reports', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Была');

      final container = makeContainer();
      await loadTasks(container, projectId);
      backend.alwaysFailToConnect();

      await expectLater(
        container
            .read(projectTasksProvider(projectId).notifier)
            .create('Не доедет'),
        throwsA(isA<NetworkException>()),
      );

      // Rolled back to exactly what was there. No queue, no "will sync later".
      expect(titles(tasksNow(container, projectId)), <String>['Была']);
    });

    test('a burst of creates is serialised, and all of them land', () async {
      // The primary gesture on this screen: type, Enter, type, Enter. Without
      // the mutation queue the second create would capture the first's
      // *prediction* as its rollback target.
      final projectId = server.addProject(name: 'Дача');
      final container = makeContainer();
      await loadTasks(container, projectId);

      final notifier = container.read(projectTasksProvider(projectId).notifier);
      await Future.wait<void>(<Future<void>>[
        notifier.create('Раз'),
        notifier.create('Два'),
        notifier.create('Три'),
      ]);

      expect(titles(tasksNow(container, projectId)), <String>[
        'Раз',
        'Два',
        'Три',
      ]);
      expect(server.titlesInOrder(projectId), <String>['Раз', 'Два', 'Три']);
    });

    test('an empty title is not a request', () async {
      final projectId = server.addProject(name: 'Дача');
      final container = makeContainer();
      await loadTasks(container, projectId);

      final before = backend.requests.length;
      await container
          .read(projectTasksProvider(projectId).notifier)
          .create('   ');

      expect(backend.requests, hasLength(before));
    });
  });

  group('changing a status', () {
    test('the current task moves on, as the server computes it', () async {
      final projectId = server.addProject(name: 'Дача');
      final first = server.addTask(projectId: projectId, title: 'Первая');
      final second = server.addTask(projectId: projectId, title: 'Вторая');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);
      expect(tasks.first.isCurrent, isTrue);

      await container
          .read(projectTasksProvider(projectId).notifier)
          .setStatus(tasks.first, TaskStatus.done);

      final after = tasksNow(container, projectId);
      expect(after.firstWhere((task) => task.id == first).isCurrent, isFalse);
      // The client never derived this; it re-read the list and the server said
      // so. Which is the point -- the rule lives in one place.
      expect(after.firstWhere((task) => task.id == second).isCurrent, isTrue);
      expect(server.currentTaskId(projectId), second);
    });

    test(
      'leaving blocked clears the reminder date; entering it does not',
      () async {
        final projectId = server.addProject(name: 'Дача');
        server.addTask(
          projectId: projectId,
          title: 'Жду кабель',
          status: 'pending',
          remindAt: remindAt(0),
        );

        final container = makeContainer();
        final tasks = await loadTasks(container, projectId);
        final notifier = container.read(
          projectTasksProvider(projectId).notifier,
        );

        // Entering `blocked` keeps whatever date is there -- F4 owns setting it,
        // and F3 must not wipe it on the way in.
        await notifier.setStatus(tasks.single, TaskStatus.blocked);
        expect(server.patches.last.body.containsKey('remindAt'), isFalse);
        expect(tasksNow(container, projectId).single.remindAt, isNotNull);

        // Leaving it drops the date, with an explicit null.
        await notifier.setStatus(
          tasksNow(container, projectId).single,
          TaskStatus.pending,
        );
        expect(server.patches.last.body['remindAt'], isNull);
        expect(server.patches.last.body.containsKey('remindAt'), isTrue);
        expect(tasksNow(container, projectId).single.remindAt, isNull);
      },
    );

    test('a failed status change rolls back', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Задача');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);
      backend.alwaysFailToConnect();

      await expectLater(
        container
            .read(projectTasksProvider(projectId).notifier)
            .setStatus(tasks.single, TaskStatus.done),
        throwsA(isA<NetworkException>()),
      );

      final after = tasksNow(container, projectId).single;
      expect(after.status, TaskStatus.pending);
      expect(after.isCurrent, isTrue, reason: 'the highlight came back too');
    });
  });

  group('editing text', () {
    test('a rename costs one request and keeps the highlight', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Старое');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);
      final before = backend.requests.length;

      await container
          .read(projectTasksProvider(projectId).notifier)
          .editTitle(tasks.single, 'Новое');

      // One PATCH and no re-read: a title cannot change the order or which task
      // is current, so there is nothing to ask about.
      expect(backend.requests.length - before, 1);

      final after = tasksNow(container, projectId).single;
      expect(after.title, 'Новое');
      // The mutation response carried no `isCurrent`; merging it naively is
      // exactly how the React client loses the highlight on rename.
      expect(after.isCurrent, isTrue);
    });

    test('an unchanged title is not a request', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Задача');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);
      final before = backend.requests.length;

      await container
          .read(projectTasksProvider(projectId).notifier)
          .editTitle(tasks.single, '  Задача  ');

      expect(backend.requests, hasLength(before));
    });

    test('an emptied description is cleared, not left alone', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(
        projectId: projectId,
        title: 'Задача',
        description: 'старое описание',
      );

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);

      await container
          .read(projectTasksProvider(projectId).notifier)
          .editDescription(tasks.single, '');

      expect(server.patches.last.body.containsKey('description'), isTrue);
      expect(server.patches.last.body['description'], isNull);
      expect(tasksNow(container, projectId).single.description, isNull);
    });

    test('a failed description edit rolls back', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(
        projectId: projectId,
        title: 'Задача',
        description: 'важное описание',
      );

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);
      backend.alwaysFailToConnect();

      await expectLater(
        container
            .read(projectTasksProvider(projectId).notifier)
            .editDescription(tasks.single, 'другое'),
        throwsA(isA<NetworkException>()),
      );

      expect(
        tasksNow(container, projectId).single.description,
        'важное описание',
      );
    });
  });

  group('deleting', () {
    test('the row goes, and the current task is re-read', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Первая');
      final second = server.addTask(projectId: projectId, title: 'Вторая');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);

      await container
          .read(projectTasksProvider(projectId).notifier)
          .remove(tasks.first);

      final after = tasksNow(container, projectId);
      expect(titles(after), <String>['Вторая']);
      expect(after.single.id, second);
      expect(after.single.isCurrent, isTrue);
    });

    test('a failed delete puts the row back', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Задача');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);
      backend.alwaysFailToConnect();

      await expectLater(
        container
            .read(projectTasksProvider(projectId).notifier)
            .remove(tasks.single),
        throwsA(isA<NetworkException>()),
      );

      expect(titles(tasksNow(container, projectId)), <String>['Задача']);
    });
  });

  group('reordering', () {
    test('the new order is shown at once and persisted', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'a');
      server.addTask(projectId: projectId, title: 'b');
      server.addTask(projectId: projectId, title: 'c');

      final container = makeContainer();
      await loadTasks(container, projectId);

      // Drag the first row to the bottom: ReorderableListView reports (0, 3).
      await container.read(projectTasksProvider(projectId).notifier).move(0, 3);

      expect(titles(tasksNow(container, projectId)), <String>['b', 'c', 'a']);
      expect(server.titlesInOrder(projectId), <String>['b', 'c', 'a']);
    });

    test('a no-op drag sends nothing', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'a');
      server.addTask(projectId: projectId, title: 'b');

      final container = makeContainer();
      await loadTasks(container, projectId);
      final before = backend.requests.length;

      await container.read(projectTasksProvider(projectId).notifier).move(1, 2);

      expect(backend.requests, hasLength(before));
    });

    test('a failed move rolls the order back', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'a');
      server.addTask(projectId: projectId, title: 'b');

      final container = makeContainer();
      await loadTasks(container, projectId);
      backend.alwaysFailToConnect();

      await expectLater(
        container.read(projectTasksProvider(projectId).notifier).move(0, 2),
        throwsA(isA<NetworkException>()),
      );

      expect(titles(tasksNow(container, projectId)), <String>['a', 'b']);
    });

    test(
      'after a server-side rebalance the client holds no stale positions',
      () async {
        // The case that only appears after a hundred reorders: the float gap
        // between two neighbours runs out, the server renumbers *every* row in one
        // transaction, and the reply still mentions only the moved one.
        final projectId = server.addProject(name: 'Дача');
        server.addTask(projectId: projectId, title: 'a');
        final b = server.addTask(projectId: projectId, title: 'b');
        final c = server.addTask(projectId: projectId, title: 'c');
        server.squeezePositions(b, c);

        final container = makeContainer();
        await loadTasks(container, projectId);

        // Move `a` between the two squeezed rows.
        await container
            .read(projectTasksProvider(projectId).notifier)
            .move(0, 2);

        final after = tasksNow(container, projectId);
        expect(titles(after), <String>['b', 'a', 'c']);
        // Every position matches the server's, including `c`'s -- which the move
        // response never mentioned. That equality is what the unconditional
        // re-read buys.
        expect(
          after.map((task) => task.position),
          server.positionsInOrder(projectId),
        );
      },
    );
  });

  group('the board follows a write inside a project', () {
    test('counters and the current task update with no GET /board', () async {
      final projectId = server.addProject(name: 'Дача');
      final first = server.addTask(projectId: projectId, title: 'Первая');
      server.addTask(projectId: projectId, title: 'Вторая');

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await container.read(boardProvider.future);

      final boardRequests = backend.requests
          .where((request) => request.path == '/board')
          .length;

      final tasks = await loadTasks(container, projectId);
      await container
          .read(projectTasksProvider(projectId).notifier)
          .setStatus(
            tasks.firstWhere((task) => task.id == first),
            TaskStatus.done,
          );

      final board = container.read(boardViewProvider) as BoardReady;
      final row = board.projects.single;
      expect(
        row.tasks.where((task) => task.status == TaskStatus.done),
        hasLength(1),
      );
      expect(row.currentTask?.title, 'Вторая');

      // The point: the board was updated from the project's own re-read, not by
      // refetching the whole board.
      expect(
        backend.requests.where((request) => request.path == '/board').length,
        boardRequests,
      );
    });

    test(
      'the read cache is rewritten so a restart shows the new state',
      () async {
        final projectId = server.addProject(name: 'Дача');
        server.addTask(projectId: projectId, title: 'Первая');

        final container = makeContainer();
        container.listen(boardViewProvider, (_, _) {});
        await container.read(boardProvider.future);

        final tasks = await loadTasks(container, projectId);
        await container
            .read(projectTasksProvider(projectId).notifier)
            .editTitle(tasks.single, 'Переименована');
        await pumpEventQueue();

        expect(
          snapshots.snapshot!.projects.single.tasks.single.title,
          'Переименована',
        );
      },
    );

    test('a write with no board loaded marks the board for a refetch', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Первая');

      final container = makeContainer();
      final tasks = await loadTasks(container, projectId);

      // Nothing ever watched the board, so there is no in-memory row to splice
      // into. It must not keep rows this write just invalidated.
      await container
          .read(projectTasksProvider(projectId).notifier)
          .editTitle(tasks.single, 'Переименована');

      container.listen(boardViewProvider, (_, _) {});
      final board = await container.read(boardProvider.future);
      expect(board.projects.single.tasks.single.title, 'Переименована');
    });
  });

  group('reminders follow a write, through the board and nothing else', () {
    /// Brings up the bridge the board screen brings up.
    void watchBridge(ProviderContainer container) {
      container.listen(boardReminderBridgeProvider, (_, _) {});
    }

    test('blocking a task dated today arms its reminder', () async {
      final projectId = server.addProject(name: 'Дача');
      // A pending task that already carries a date: the state you are in after
      // setting a reminder from the desktop and then unblocking the task.
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'pending',
        remindAt: remindAt(0),
      );

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      watchBridge(container);
      await container.read(boardProvider.future);
      await pumpEventQueue();

      // Nothing armed: a `pending` task with a leftover date is not a reminder.
      expect(container.read(reminderTargetsProvider), isEmpty);

      final tasks = await loadTasks(container, projectId);
      await container
          .read(projectTasksProvider(projectId).notifier)
          .setStatus(tasks.single, TaskStatus.blocked);
      await pumpEventQueue();

      final targets = container.read(reminderTargetsProvider);
      expect(targets, hasLength(1));
      expect(targets.single.taskTitle, 'Жду кабель');
      expect(targets.single.projectName, 'Дача');
      expect(targets.single.remindAt, remindAt(0));

      // Whether *today's* target becomes an armed alarm is the scheduler's own
      // decision and depends on the wall clock (today after 09:00 is
      // `SkipReason.inThePast`), which is why this test stops at the target set
      // -- the next one takes it all the way to the OS queue on a date that
      // cannot be ambiguous.
    });

    test(
      'a future date reaches the OS queue with nothing calling the scheduler',
      () async {
        final projectId = server.addProject(name: 'Дача');
        server.addTask(
          projectId: projectId,
          title: 'Жду кабель',
          status: 'pending',
          remindAt: remindAt(2),
        );

        final container = makeContainer();
        container.listen(boardViewProvider, (_, _) {});
        watchBridge(container);
        await container.read(boardProvider.future);
        await pumpEventQueue();
        expect(gateway.queue, isEmpty);

        final tasks = await loadTasks(container, projectId);
        await container
            .read(projectTasksProvider(projectId).notifier)
            .setStatus(tasks.single, TaskStatus.blocked);
        await pumpEventQueue();

        // Nothing in the F3 write path mentions the scheduler: replacing the
        // target set *is* the reschedule (F1's design), and this is the whole
        // chain -- PATCH, re-read, board splice, bridge, alarm -- running on its
        // own.
        await container.read(reminderSyncProvider.future);
        expect(gateway.queue, hasLength(1));
        expect(gateway.queue.values.single.payload, contains(tasks.single.id));
      },
    );

    test('a date in the past is armed too -- being overdue is the point', () async {
      final projectId = server.addProject(name: 'Ремонт');
      server.addTask(
        projectId: projectId,
        title: 'Спросить про плитку',
        status: 'pending',
        remindAt: remindAt(-3),
      );

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      watchBridge(container);
      await container.read(boardProvider.future);
      await pumpEventQueue();

      final tasks = await loadTasks(container, projectId);
      await container
          .read(projectTasksProvider(projectId).notifier)
          .setStatus(tasks.single, TaskStatus.blocked);
      await pumpEventQueue();

      expect(container.read(reminderTargetsProvider), hasLength(1));

      // The scheduler is the one that decides an overdue date fires at the next
      // morning rather than in the past; the target set only has to contain it.
      await container.read(reminderSyncProvider.future);
    });

    test(
      'unblocking disarms it, because the date went with the status',
      () async {
        final projectId = server.addProject(name: 'Дача');
        server.addTask(
          projectId: projectId,
          title: 'Жду кабель',
          status: 'blocked',
          remindAt: remindAt(0),
        );

        final container = makeContainer();
        container.listen(boardViewProvider, (_, _) {});
        watchBridge(container);
        await container.read(boardProvider.future);
        await pumpEventQueue();
        expect(container.read(reminderTargetsProvider), hasLength(1));

        final tasks = await loadTasks(container, projectId);
        await container
            .read(projectTasksProvider(projectId).notifier)
            .setStatus(tasks.single, TaskStatus.pending);
        await pumpEventQueue();

        expect(container.read(reminderTargetsProvider), isEmpty);
      },
    );

    test('deleting a blocked task disarms it', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: remindAt(1),
      );

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      watchBridge(container);
      await container.read(boardProvider.future);
      await pumpEventQueue();
      expect(container.read(reminderTargetsProvider), hasLength(1));

      final tasks = await loadTasks(container, projectId);
      await container
          .read(projectTasksProvider(projectId).notifier)
          .remove(tasks.single);
      await pumpEventQueue();

      expect(container.read(reminderTargetsProvider), isEmpty);
    });

    test('a rolled-back write leaves the alarm set alone', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: remindAt(0),
      );

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      watchBridge(container);
      await container.read(boardProvider.future);
      final tasks = await loadTasks(container, projectId);
      await pumpEventQueue();

      backend.alwaysFailToConnect();
      await expectLater(
        container
            .read(projectTasksProvider(projectId).notifier)
            .setStatus(tasks.single, TaskStatus.done),
        throwsA(isA<NetworkException>()),
      );
      await pumpEventQueue();

      // The write did not happen, so neither did the disarm. An optimistic
      // update that armed alarms before the server agreed would leave the phone
      // ringing about something that was never saved.
      expect(container.read(reminderTargetsProvider), hasLength(1));
    });
  });

  group('notes', () {
    test(
      'create shows the row, then replaces it with the server row',
      () async {
        final projectId = server.addProject(name: 'Дача');
        final container = makeContainer();
        await loadNotes(container, projectId);

        final gate = Completer<void>();
        backend.delay = (options) =>
            options.method == 'POST' ? gate.future : Future<void>.value();

        final writing = container
            .read(projectNotesProvider(projectId).notifier)
            .create('Контекст');
        await pumpEventQueue(times: 3);

        final optimistic = container
            .read(projectNotesProvider(projectId))
            .requireValue;
        expect(optimistic.single.title, 'Контекст');
        expect(isOptimisticId(optimistic.single.id), isTrue);

        gate.complete();
        await writing;

        final settled = container
            .read(projectNotesProvider(projectId))
            .requireValue;
        expect(isOptimisticId(settled.single.id), isFalse);
        expect(settled.single.content, '');
      },
    );

    test('editing content saves it and keeps the title', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: 'старое',
      );

      final container = makeContainer();
      final notes = await loadNotes(container, projectId);

      await container
          .read(projectNotesProvider(projectId).notifier)
          .edit(notes.single, content: '# Новое\n\n- раз');

      expect(server.patches.last.body, <String, dynamic>{
        'content': '# Новое\n\n- раз',
      });

      final after = container
          .read(projectNotesProvider(projectId))
          .requireValue
          .single;
      expect(after.content, '# Новое\n\n- раз');
      expect(after.title, 'Контекст');
    });

    test('a failed edit rolls the content back', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: 'важный текст',
      );

      final container = makeContainer();
      final notes = await loadNotes(container, projectId);
      backend.alwaysFailToConnect();

      await expectLater(
        container
            .read(projectNotesProvider(projectId).notifier)
            .edit(notes.single, content: 'потеряется'),
        throwsA(isA<NetworkException>()),
      );

      expect(
        container
            .read(projectNotesProvider(projectId))
            .requireValue
            .single
            .content,
        'важный текст',
      );
    });

    test('delete removes it, and a failure puts it back', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addNote(projectId: projectId, title: 'Первая');
      server.addNote(projectId: projectId, title: 'Вторая');

      final container = makeContainer();
      final notes = await loadNotes(container, projectId);
      final notifier = container.read(projectNotesProvider(projectId).notifier);

      await notifier.remove(notes.first);
      expect(
        container
            .read(projectNotesProvider(projectId))
            .requireValue
            .map((note) => note.title),
        <String>['Вторая'],
      );

      backend.alwaysFailToConnect();
      await expectLater(
        notifier.remove(
          container.read(projectNotesProvider(projectId)).requireValue.single,
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(
        container.read(projectNotesProvider(projectId)).requireValue,
        hasLength(1),
      );
    });

    test('a note write never touches the board', () async {
      final projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Задача');

      final container = makeContainer();
      container.listen(boardViewProvider, (_, _) {});
      await container.read(boardProvider.future);
      await loadNotes(container, projectId);

      final before = container.read(boardViewProvider) as BoardReady;
      await container
          .read(projectNotesProvider(projectId).notifier)
          .create('Контекст');

      // Notes are not on the board, so nothing about it may change -- including
      // the list identity, which would re-arm every alarm for nothing.
      final after = container.read(boardViewProvider) as BoardReady;
      expect(identical(before.projects, after.projects), isTrue);
    });
  });
}
