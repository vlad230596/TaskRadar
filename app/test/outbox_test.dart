import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/outbox_providers.dart';
import 'package:taskradar/providers/project_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/storage/outbox_store.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/outbox_history.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_outbox_store.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// The outbox of task writes: what a create or an edit made with no network
/// becomes, how it is drawn until it is sent, and what happens when the
/// server has moved on in the meantime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeOutboxStore store;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    store = FakeOutboxStore();
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
        boardSnapshotStoreProvider.overrideWithValue(FakeBoardSnapshotStore()),
        notificationGatewayProvider.overrideWithValue(
          FakeNotificationGateway(),
        ),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        outboxStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void offline() => backend.failingPaths.add('/');
  void online() => backend.failingPaths.clear();

  Future<List<Task>> loadTasks(ProviderContainer c, String projectId) async {
    c.listen(projectTasksProvider(projectId), (_, _) {});
    c.listen(projectViewProvider(projectId), (_, _) {});
    await c.read(outboxProvider.future);
    final rows = await c.read(projectTasksProvider(projectId).future);
    await c.read(projectHeaderProvider(projectId).future);
    return rows;
  }

  ProjectTasks tasksOf(ProviderContainer c, String projectId) =>
      c.read(projectTasksProvider(projectId).notifier);

  List<Task> drawn(ProviderContainer c, String projectId) =>
      (c.read(projectViewProvider(projectId)) as ProjectReady).tasks;

  Map<String, dynamic> serverTask(String id) =>
      server.tasks.singleWhere((row) => row['id'] == id);

  group('a task created with no network', () {
    test('is queued on disk, drawn as not sent, and sent when the network is '
        'back', () async {
      final projectId = server.addProject(name: 'Дом');
      final container = makeContainer();
      await loadTasks(container, projectId);

      offline();
      final outcome = await tasksOf(
        container,
        projectId,
      ).create('Купить фильтр для пылесоса');

      expect(outcome, WriteOutcome.queued);
      expect(server.tasks, isEmpty);
      expect(store.entries.single.kind, OutboxKind.createTask);
      expect(store.entries.single.isWaiting, isTrue);

      final row = drawn(container, projectId).single;
      expect(row.title, 'Купить фильтр для пылесоса');
      expect(isOptimisticId(row.id), isTrue);
      expect(
        container.read(outboxMarksProvider(projectId))[row.id],
        OutboxMark.waiting,
      );

      online();
      await container.read(outboxProvider.notifier).flush();

      final saved = server.tasks.single;
      expect(saved['title'], 'Купить фильтр для пылесоса');
      expect(saved['createKey'], store.entries.single.key);
      expect(store.entries.single.state, OutboxState.sent);
      expect(store.entries.single.taskId, saved['id']);

      // The server's row in place of the drawn one, carrying the green mark.
      final settled = drawn(container, projectId).single;
      expect(settled.id, saved['id']);
      expect(
        container.read(outboxMarksProvider(projectId))[settled.id],
        OutboxMark.sent,
      );
    });

    test('is not made twice when the first answer was lost', () async {
      final projectId = server.addProject(name: 'Дом');
      final container = makeContainer();
      await loadTasks(container, projectId);

      offline();
      await tasksOf(container, projectId).create('Купить лампочки');
      // The request reached the server; the answer did not reach the phone.
      server.addTask(projectId: projectId, title: 'Купить лампочки');
      server.tasks.single['createKey'] = store.entries.single.key;

      online();
      await container.read(outboxProvider.notifier).flush();

      expect(server.tasks, hasLength(1));
      expect(store.entries.single.state, OutboxState.sent);
    });

    test('is queued when the list itself could not be loaded', () async {
      final projectId = server.addProject(name: 'Дом');
      final container = makeContainer();
      offline();
      await expectLater(loadTasks(container, projectId), throwsA(anything));

      final outcome = await tasksOf(container, projectId).create('Записаться');

      expect(outcome, WriteOutcome.queued);
      expect(store.entries.single.body['title'], 'Записаться');
    });

    test('says so when even the phone could not keep it', () async {
      final projectId = server.addProject(name: 'Дом');
      final container = makeContainer();
      await loadTasks(container, projectId);
      store.writeFailure = const FileSystemException('disk full');

      offline();
      await expectLater(
        tasksOf(container, projectId).create('Купить лампочки'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('a list whose load failed with no network', () {
    test('is loaded again by the next write, without a refresh', () async {
      final projectId = server.addProject(name: 'Дом');
      final taskId = server.addTask(projectId: projectId, title: 'Полить');
      final container = makeContainer();
      offline();
      await expectLater(loadTasks(container, projectId), throwsA(anything));

      online();
      expect(
        container.read(projectTasksProvider(projectId)).hasError,
        isTrue,
        reason: 'the failed load is still the answer',
      );

      final task = Task.fromJson(<String, dynamic>{
        ...serverTask(taskId),
        'isCurrent': true,
      });
      final outcome = await tasksOf(
        container,
        projectId,
      ).setStatus(task, TaskStatus.done);

      expect(outcome, WriteOutcome.sent);
      expect(serverTask(taskId)['status'], 'done');
      expect(store.entries, isEmpty);
    });
  });

  group('an edit made with no network', () {
    late String projectId;
    late String taskId;
    late ProviderContainer container;

    setUp(() async {
      projectId = server.addProject(name: 'Дача');
      taskId = server.addTask(
        projectId: projectId,
        title: 'Починить кран',
        description: 'Кран капает',
      );
      container = makeContainer();
      await loadTasks(container, projectId);
    });

    Task row() =>
        drawn(container, projectId).singleWhere((t) => t.id == taskId);

    test('is drawn at once and sent with what it was made against', () async {
      offline();
      final outcome = await tasksOf(
        container,
        projectId,
      ).setStatus(row(), TaskStatus.done);

      expect(outcome, WriteOutcome.queued);
      expect(row().status, TaskStatus.done);
      expect(serverTask(taskId)['status'], 'pending');

      online();
      await container.read(outboxProvider.notifier).flush();

      expect(serverTask(taskId)['status'], 'done');
      final patch = server.patches.last.body;
      expect(patch['expected'], <String, dynamic>{'status': 'pending'});
      expect(store.entries.single.state, OutboxState.sent);
    });

    test('a second edit is made against the first', () async {
      offline();
      await tasksOf(container, projectId).editTitle(row(), 'Починить кран 1');
      await tasksOf(container, projectId).editTitle(row(), 'Починить кран 2');
      expect(row().title, 'Починить кран 2');

      online();
      await container.read(outboxProvider.notifier).flush();

      expect(serverTask(taskId)['title'], 'Починить кран 2');
      expect(store.entries.map((e) => e.state), everyElement(OutboxState.sent));
    });

    test('is skipped, not applied, when the field was changed elsewhere, '
        'and waits for a decision', () async {
      offline();
      await tasksOf(
        container,
        projectId,
      ).editDescription(row(), 'Купить прокладку');

      // Meanwhile, on the laptop.
      serverTask(taskId)['description'] = 'Вызвать сантехника';

      online();
      await container.read(outboxProvider.notifier).flush();

      expect(serverTask(taskId)['description'], 'Вызвать сантехника');
      final entry = store.entries.single;
      expect(entry.state, OutboxState.skipped);
      expect(entry.conflictFields, <String>['description']);
      expect(entry.serverTask?['description'], 'Вызвать сантехника');
      // The server's value is the one drawn: nothing pretends it applied.
      expect(row().description, 'Вызвать сантехника');
      expect(container.read(outboxCountsProvider).decisions, 1);

      await container.read(outboxProvider.notifier).applyMine(entry);
      await container.read(outboxProvider.notifier).flush();

      expect(serverTask(taskId)['description'], 'Купить прокладку');
      expect(store.entries.single.state, OutboxState.sent);
    });

    test('left as the server has it stops asking', () async {
      offline();
      await tasksOf(container, projectId).editTitle(row(), 'Моё');
      serverTask(taskId)['title'] = 'С ноутбука';
      online();
      await container.read(outboxProvider.notifier).flush();

      await container
          .read(outboxProvider.notifier)
          .keepServer(store.entries.single);

      expect(store.entries.single.state, OutboxState.resolved);
      expect(serverTask(taskId)['title'], 'С ноутбука');
      expect(container.read(outboxCountsProvider).decisions, 0);
    });

    test('that the server refuses is kept, and can be thrown away', () async {
      offline();
      await tasksOf(container, projectId).editTitle(row(), 'Новое');
      server.tasks.clear(); // deleted elsewhere

      online();
      await container.read(outboxProvider.notifier).flush();

      final entry = store.entries.single;
      expect(entry.state, OutboxState.refused);
      expect(entry.message, isNotEmpty);

      await container.read(outboxProvider.notifier).discard(entry);
      expect(store.entries, isEmpty);
    });

    test('a delete still needs the network', () async {
      offline();
      await expectLater(
        tasksOf(container, projectId).remove(row()),
        throwsA(anything),
      );
      expect(store.entries, isEmpty);
    });
  });

  group('a move to another project', () {
    late String home;
    late String dacha;
    late String taskId;
    late ProviderContainer container;

    setUp(() async {
      home = server.addProject(name: 'Дом');
      dacha = server.addProject(name: 'Дача');
      final categoryId = server.addCategory(projectId: home, name: 'Кухня');
      server.addTask(projectId: home, title: 'Купить хлеб');
      taskId = server.addTask(
        projectId: home,
        title: 'Покрасить забор',
        categoryId: categoryId,
      );
      server.addTask(projectId: dacha, title: 'Скосить траву');
      container = makeContainer();
      await loadTasks(container, home);
      await loadTasks(container, dacha);
    });

    List<String> titles(String projectId) =>
        drawn(container, projectId).map((t) => t.title).toList();

    Task rowIn(String projectId) =>
        drawn(container, projectId).singleWhere((t) => t.id == taskId);

    test('online: leaves one list and lands last in the other', () async {
      final outcome = await tasksOf(
        container,
        home,
      ).moveToProject(rowIn(home), dacha);

      expect(outcome, WriteOutcome.sent);
      expect(serverTask(taskId)['projectId'], dacha);
      expect(store.entries, isEmpty);
      expect(titles(home), <String>['Купить хлеб']);
      // The target's open list was re-read, not left to its next visit.
      expect(titles(dacha), <String>['Скосить траву', 'Покрасить забор']);
      expect(rowIn(dacha).categoryId, isNull);
    });

    test('offline: queued, drawn in the target, and sent later', () async {
      offline();
      final outcome = await tasksOf(
        container,
        home,
      ).moveToProject(rowIn(home), dacha);

      expect(outcome, WriteOutcome.queued);
      expect(serverTask(taskId)['projectId'], home);
      final entry = store.entries.single;
      expect(entry.kind, OutboxKind.moveTask);
      expect(entry.projectId, home);
      expect(entry.targetProjectId, dacha);

      expect(titles(home), <String>['Купить хлеб']);
      expect(titles(dacha), <String>['Скосить траву', 'Покрасить забор']);
      expect(rowIn(dacha).projectId, dacha);
      expect(rowIn(dacha).categoryId, isNull);
      expect(
        container.read(outboxMarksProvider(dacha))[taskId],
        OutboxMark.waiting,
      );
      expect(container.read(outboxMarksProvider(home)), isEmpty);

      online();
      await container.read(outboxProvider.notifier).flush();

      expect(serverTask(taskId)['projectId'], dacha);
      expect(serverTask(taskId)['categoryId'], isNull);
      expect(store.entries.single.state, OutboxState.sent);
      expect(titles(home), <String>['Купить хлеб']);
      expect(titles(dacha), <String>['Скосить траву', 'Покрасить забор']);
      expect(
        container.read(outboxMarksProvider(dacha))[taskId],
        OutboxMark.sent,
      );
    });

    test('an edit of the moved row, offline, follows the move', () async {
      offline();
      await tasksOf(container, home).moveToProject(rowIn(home), dacha);
      final outcome = await tasksOf(
        container,
        dacha,
      ).editTitle(rowIn(dacha), 'Покрасить забор в зелёный');

      // Not "sent": the row is not in the server's list here yet, and
      // dropping the edit silently was the alternative.
      expect(outcome, WriteOutcome.queued);
      expect(rowIn(dacha).title, 'Покрасить забор в зелёный');

      online();
      await container.read(outboxProvider.notifier).flush();

      expect(serverTask(taskId)['projectId'], dacha);
      expect(serverTask(taskId)['title'], 'Покрасить забор в зелёный');
      expect(store.entries.map((e) => e.state), everyElement(OutboxState.sent));
    });

    test('a second move, offline, goes on from where the first went', () async {
      final garage = server.addProject(name: 'Гараж');
      await loadTasks(container, garage);

      offline();
      await tasksOf(container, home).moveToProject(rowIn(home), dacha);
      final outcome = await tasksOf(
        container,
        dacha,
      ).moveToProject(rowIn(dacha), garage);

      expect(outcome, WriteOutcome.queued);
      expect(titles(home), <String>['Купить хлеб']);
      expect(titles(dacha), <String>['Скосить траву']);
      expect(titles(garage), <String>['Покрасить забор']);

      online();
      await container.read(outboxProvider.notifier).flush();
      expect(serverTask(taskId)['projectId'], garage);
      expect(titles(garage), <String>['Покрасить забор']);
    });

    test('refused when the target is gone, and the task stays put', () async {
      offline();
      await tasksOf(container, home).moveToProject(rowIn(home), dacha);
      server.projects.remove(dacha);

      online();
      await container.read(outboxProvider.notifier).flush();

      expect(store.entries.single.state, OutboxState.refused);
      expect(serverTask(taskId)['projectId'], home);
      // No longer drawn over: the server's list is the truth again.
      expect(titles(home), <String>['Купить хлеб', 'Покрасить забор']);
    });

    test('an unsent create cannot be moved', () async {
      offline();
      await tasksOf(container, home).create('Новая');
      final local = drawn(container, home).last;

      expect(
        () => tasksOf(container, home).moveToProject(local, dacha),
        throwsStateError,
      );
    });

    test('round-trips through the file with its copy of the row', () {
      final entry = OutboxEntry(
        key: 'k1',
        kind: OutboxKind.moveTask,
        projectId: home,
        taskId: taskId,
        title: 'Покрасить забор',
        body: <String, Object?>{'projectId': dacha},
        row: rowIn(home).toJson(),
        createdAt: DateTime.utc(2026, 11, 1, 10),
      );

      final back = OutboxStore.decode(OutboxStore.encode(<OutboxEntry>[entry]));

      expect(back.single.toJson(), entry.toJson());
      expect(back.single.landsInProjectId, dacha);
    });
  });

  group('the history', () {
    test(
      'forgets what settled more than a week ago, never what waits',
      () async {
        final old = DateTime.now().subtract(const Duration(days: 8));
        OutboxEntry entry(String key, OutboxState state) => OutboxEntry(
          key: key,
          kind: OutboxKind.createTask,
          projectId: 'p',
          title: key,
          body: <String, Object?>{'title': key},
          createdAt: old,
          state: state,
          settledAt: state == OutboxState.waiting ? null : old,
        );
        store.entries = <OutboxEntry>[
          entry('sent', OutboxState.sent),
          entry('waiting', OutboxState.waiting),
          entry('refused', OutboxState.refused),
        ];

        final container = makeContainer();
        final kept = await container.read(outboxProvider.future);

        expect(kept.map((e) => e.key), <String>['waiting', 'refused']);
      },
    );
  });

  group('the file', () {
    test('round-trips, and sets an unreadable one aside', () async {
      final directory = await Directory.systemTemp.createTemp('outbox');
      addTearDown(() => directory.delete(recursive: true));
      final fileStore = OutboxStore(directory: () async => directory);

      final entry = OutboxEntry(
        key: 'k1',
        kind: OutboxKind.editTask,
        projectId: 'p',
        taskId: 't',
        title: 'Задача',
        body: const <String, Object?>{'remindAt': null, 'status': 'done'},
        expected: const <String, Object?>{'status': 'pending'},
        createdAt: DateTime.utc(2026, 10, 25, 10),
        state: OutboxState.skipped,
        settledAt: DateTime.utc(2026, 10, 25, 11),
        conflictFields: const <String>['status'],
        serverTask: const <String, Object?>{'status': 'blocked'},
      );
      await fileStore.write(<OutboxEntry>[entry]);

      final back = (await fileStore.read()).single;
      expect(back.toJson(), entry.toJson());
      expect(back.body.containsKey('remindAt'), isTrue);

      File(
        '${directory.path}${Platform.pathSeparator}${OutboxStore.fileName}',
      ).writeAsStringSync('{not json');
      expect(await fileStore.read(), isEmpty);
      expect(
        File(
          '${directory.path}${Platform.pathSeparator}'
          '${OutboxStore.fileName}.corrupt',
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('the «Офлайн» view', () {
    OutboxEntry edit(String key, OutboxState state) => OutboxEntry(
      key: key,
      kind: OutboxKind.editTask,
      projectId: 'p',
      taskId: 't_$key',
      title: 'Починить кран',
      body: const <String, Object?>{'description': 'Купить прокладку'},
      expected: const <String, Object?>{'description': 'Кран капает'},
      createdAt: DateTime.now(),
      state: state,
      settledAt: state == OutboxState.waiting ? null : DateTime.now(),
      conflictFields: state == OutboxState.skipped
          ? const <String>['description']
          : const <String>[],
      serverTask: state == OutboxState.skipped
          ? const <String, Object?>{'description': 'Вызвать сантехника'}
          : null,
    );

    Future<void> pumpView(WidgetTester tester) async {
      backend.alwaysFailToConnect();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
            ),
            outboxStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: OutboxHistoryView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('groups what waits, what needs a decision and what went', (
      tester,
    ) async {
      store.entries = <OutboxEntry>[
        edit('a', OutboxState.sent),
        edit('b', OutboxState.waiting),
        edit('c', OutboxState.skipped),
      ];
      await pumpView(tester);

      expect(find.text('ЖДУТ СВЯЗИ · 1'), findsOneWidget);
      expect(find.text('ТРЕБУЕТ РЕШЕНИЯ · 1'), findsOneWidget);
      expect(find.text('ОТПРАВЛЕНО · 1'), findsOneWidget);
      expect(
        find.text('пропущено — изменено на другом устройстве'),
        findsOneWidget,
      );
    });

    testWidgets('a skipped edit opens to both values, and «Оставить» settles '
        'it', (tester) async {
      store.entries = <OutboxEntry>[edit('c', OutboxState.skipped)];
      await pumpView(tester);

      await tester.tap(find.text('пропущено — изменено на другом устройстве'));
      await tester.pumpAndSettle();
      expect(find.text('Вызвать сантехника'), findsOneWidget);
      expect(find.text('Применить моё'), findsOneWidget);

      await tester.tap(find.text('Оставить'));
      await tester.pumpAndSettle();

      expect(store.entries.single.state, OutboxState.resolved);
      expect(find.text('оставлено как на сервере'), findsOneWidget);
    });

    testWidgets('says so when there is nothing', (tester) async {
      await pumpView(tester);
      expect(find.text('Всё отправлено'), findsOneWidget);
    });
  });
}
