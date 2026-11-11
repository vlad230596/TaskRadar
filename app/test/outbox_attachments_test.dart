
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/patch_field.dart';
import 'package:taskradar/domain/outbox_overlay.dart';
import 'package:taskradar/models/checklist_item.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_location.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/providers/attachment_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/outbox_providers.dart';
import 'package:taskradar/providers/project_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/storage/attachment_cache.dart';
import 'package:taskradar/storage/outbox_files.dart';
import 'package:taskradar/storage/outbox_store.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/outbox_history.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_outbox_store.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// The task editor's writes through `ProjectTasks` and the outbox (WP2):
/// checklist and place in creates and edits, and pictures going up and
/// down -- online, offline, and behind a create that has not gone yet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeOutboxStore store;
  late MemoryOutboxFileStore files;
  late MemoryAttachmentCache cache;

  final png = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9, 9, //
  ]);
  XFile picture() => XFile.fromData(png, name: 'shot.png');

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    store = FakeOutboxStore();
    files = MemoryOutboxFileStore();
    cache = MemoryAttachmentCache();
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

  List<Override> overrides() => [
    apiClientProvider.overrideWithValue(backend.client),
    boardSnapshotStoreProvider.overrideWithValue(FakeBoardSnapshotStore()),
    notificationGatewayProvider.overrideWithValue(FakeNotificationGateway()),
    settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
    outboxStoreProvider.overrideWithValue(store),
    outboxFileStoreProvider.overrideWithValue(files),
    attachmentCacheProvider.overrideWithValue(cache),
  ];

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    return container;
  }

  void offline() => backend.failingPaths.add('/');
  void online() => backend.failingPaths.clear();

  Future<void> loadTasks(ProviderContainer c, String projectId) async {
    c.listen(projectTasksProvider(projectId), (_, _) {});
    c.listen(projectViewProvider(projectId), (_, _) {});
    await c.read(outboxProvider.future);
    await c.read(projectTasksProvider(projectId).future);
    await c.read(projectHeaderProvider(projectId).future);
  }

  ProjectTasks tasksOf(ProviderContainer c, String projectId) =>
      c.read(projectTasksProvider(projectId).notifier);

  List<Task> drawn(ProviderContainer c, String projectId) =>
      (c.read(projectViewProvider(projectId)) as ProjectReady).tasks;

  Map<String, dynamic> serverTask(String id) =>
      server.tasks.singleWhere((row) => row['id'] == id);

  Future<void> flush(ProviderContainer c) =>
      c.read(outboxProvider.notifier).flush();

  const items = <ChecklistItem>[
    ChecklistItem(id: 'item0001', text: 'Шурупы'),
    ChecklistItem(id: 'item0002', text: 'Петли', done: true),
  ];
  const place = TaskLocation(lat: 55.75, lng: 37.62, radius: 300, label: 'Дом');

  group('a create from the editor', () {
    test(
      'online: carries checklist, place and status, and names the task',
      () async {
        final projectId = server.addProject(name: 'Дом');
        final container = makeContainer();
        await loadTasks(container, projectId);

        final outcome = await tasksOf(container, projectId).create(
          'Собрать шкаф',
          status: TaskStatus.blocked,
          checklist: items,
          location: place,
        );

        expect(outcome, WriteOutcome.sent);
        final saved = server.tasks.single;
        expect(outcome.taskId, saved['id']);
        expect(outcome.createKey, saved['createKey']);
        expect(saved['status'], 'blocked');
        expect((saved['checklist'] as List).length, 2);
        expect((saved['location'] as Map)['label'], 'Дом');
        final row = drawn(container, projectId).single;
        expect(row.checklist, items);
        expect(row.location, place);
      },
    );

    test(
      'offline: queued with them, drawn with them, sent with them',
      () async {
        final projectId = server.addProject(name: 'Дом');
        final container = makeContainer();
        await loadTasks(container, projectId);

        offline();
        final outcome = await tasksOf(container, projectId).create(
          'Собрать шкаф',
          status: TaskStatus.blocked,
          checklist: items,
          location: place,
        );

        expect(outcome, WriteOutcome.queued);
        final entry = store.entries.single;
        expect(outcome.taskId, entry.localTaskId);
        expect(outcome.createKey, entry.key);
        final row = drawn(container, projectId).single;
        expect(row.checklist, items);
        expect(row.location, place);
        expect(row.status, TaskStatus.blocked);

        online();
        await flush(container);
        final saved = server.tasks.single;
        expect(saved['status'], 'blocked');
        expect(saved['checklist'], hasLength(2));
        expect((saved['location'] as Map)['radius'], 300);
      },
    );
  });

  group('an edit from the editor', () {
    late String projectId;
    late String taskId;
    late ProviderContainer container;

    setUp(() async {
      projectId = server.addProject(name: 'Дом');
      taskId = server.addTask(
        projectId: projectId,
        title: 'Шкаф',
        checklist: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'item0001', 'text': 'Шурупы', 'done': false},
          <String, dynamic>{'id': 'item0002', 'text': 'Петли', 'done': true},
        ],
      );
      container = makeContainer();
      await loadTasks(container, projectId);
    });

    Task row() =>
        drawn(container, projectId).singleWhere((t) => t.id == taskId);

    test('online: one PATCH with only what changed', () async {
      final outcome = await tasksOf(container, projectId).edit(
        row(),
        title: 'Шкаф-купе',
        // Unchanged: not sent.
        checklist: PatchField<List<ChecklistItem>>.to(row().checklist!),
        location: const PatchField<TaskLocation>.to(place),
      );

      expect(outcome, WriteOutcome.sent);
      final body = server.patches.single.body;
      expect(body.keys.toSet(), <String>{'title', 'location'});
      expect(row().title, 'Шкаф-купе');
      expect(row().location, place);
      expect(serverTask(taskId)['location'], isNotNull);
    });

    test('nothing changed is no request', () async {
      final outcome = await tasksOf(
        container,
        projectId,
      ).edit(row(), title: 'Шкаф');
      expect(outcome, WriteOutcome.sent);
      expect(server.patches, isEmpty);
    });

    test('«Сделано» from the editor re-reads and drops the date', () async {
      await tasksOf(container, projectId).setRemindAt(row(), '2026-12-01');
      server.patches.clear();

      await tasksOf(container, projectId).edit(row(), status: TaskStatus.done);
      final body = server.patches.single.body;
      expect(body['status'], 'done');
      expect(body.containsKey('remindAt'), isTrue);
      expect(body['remindAt'], isNull);
      expect(row().status, TaskStatus.done);
    });

    test('offline: queued with the whole checklist in `expected`', () async {
      offline();
      final outcome = await tasksOf(container, projectId).edit(
        row(),
        checklist: const PatchField<List<ChecklistItem>>.to(<ChecklistItem>[
          ChecklistItem(id: 'item0001', text: 'Шурупы 4×30'),
        ]),
      );
      expect(outcome, WriteOutcome.queued);
      expect(row().checklist!.single.text, 'Шурупы 4×30');

      online();
      await flush(container);
      final patch = server.patches.last.body;
      expect((patch['expected'] as Map)['checklist'], hasLength(2));
      expect(serverTask(taskId)['checklist'], hasLength(1));
      expect(store.entries.single.state, OutboxState.sent);
    });

    test('a tick is saved at once', () async {
      await tasksOf(
        container,
        projectId,
      ).toggleChecklistItem(row(), 'item0001');
      expect(row().checklist!.first.done, isTrue);
      expect((serverTask(taskId)['checklist'] as List).first['done'], isTrue);
    });

    test(
      'an offline tick is skipped when the list changed elsewhere',
      () async {
        offline();
        await tasksOf(
          container,
          projectId,
        ).toggleChecklistItem(row(), 'item0001');
        expect(row().checklist!.first.done, isTrue);

        // Meanwhile, on the laptop.
        serverTask(taskId)['checklist'] = <Map<String, dynamic>>[
          <String, dynamic>{'id': 'item0003', 'text': 'Другое', 'done': false},
        ];

        online();
        await flush(container);
        final entry = store.entries.single;
        expect(entry.state, OutboxState.skipped);
        expect(entry.conflictFields, <String>['checklist']);
        expect(
          (serverTask(taskId)['checklist'] as List).single['id'],
          'item0003',
        );
      },
    );
  });

  group('a picture', () {
    late String projectId;
    late String taskId;
    late ProviderContainer container;

    setUp(() async {
      projectId = server.addProject(name: 'Дом');
      taskId = server.addTask(projectId: projectId, title: 'Шкаф');
      container = makeContainer();
      await loadTasks(container, projectId);
    });

    AttachmentQueue queue() => container.read(attachmentQueueProvider);

    test('online: goes up, lands in the row, and leaves no history', () async {
      await queue().add(taskId, picture());
      await flush(container);

      final uploaded = server.tasks.single['attachments'] as List;
      expect(uploaded, hasLength(1));
      expect(server.attachmentBytes.values.single, png);
      expect(server.uploads.single.taskId, taskId);
      // Sent on the first try: not offline history, and the copy is gone.
      expect(store.entries, isEmpty);
      expect(files.files, isEmpty);
      final row = drawn(container, projectId).single;
      expect(row.attachments.single.id, (uploaded.single as Map)['id']);
      expect(container.read(pendingAttachmentsProvider(taskId)), isEmpty);
    });

    test('offline: drawn from its copy, counted, and sent later', () async {
      offline();
      final pending = await queue().add(taskId, picture());
      await flush(container);

      expect(pending.id, startsWith('local:upload:'));
      final strip = container.read(pendingAttachmentsProvider(taskId));
      expect(strip.single.state, PendingAttachmentState.waiting);
      expect(strip.single.mime, 'image/png');
      expect(container.read(pendingAttachmentCountsProvider)[taskId], 1);
      expect(
        container.read(outboxMarksProvider(projectId))[taskId],
        OutboxMark.waiting,
      );
      expect(
        await container.read(
          attachmentBytesProvider((pending.id, false)).future,
        ),
        png,
      );
      expect(store.entries.single.waited, isTrue);

      online();
      await flush(container);
      expect(server.tasks.single['attachments'], hasLength(1));
      expect(store.entries.single.state, OutboxState.sent);
      expect(files.files, isEmpty);
      expect(container.read(pendingAttachmentsProvider(taskId)), isEmpty);
      expect(drawn(container, projectId).single.attachments, hasLength(1));
    });

    test('of a task created offline waits for the create, then goes to its '
        'id', () async {
      offline();
      final created = await tasksOf(container, projectId).create('Полка');
      final localId = created.taskId!;
      expect(localId, startsWith('local:outbox:'));
      await queue().add(localId, picture());
      await flush(container);

      expect(container.read(pendingAttachmentsProvider(localId)), hasLength(1));
      expect(container.read(pendingAttachmentCountsProvider)[localId], 1);
      final upload = store.entries.last;
      expect(upload.projectId, projectId);
      expect(upload.title, 'Полка');

      online();
      await flush(container);

      final polka = server.tasks.singleWhere((t) => t['title'] == 'Полка');
      expect(polka['attachments'], hasLength(1));
      expect(server.uploads.single.taskId, polka['id']);
      expect(store.entries.map((e) => e.state), everyElement(OutboxState.sent));
      expect(store.entries.last.taskId, polka['id']);
      expect(
        container.read(pendingAttachmentsProvider(polka['id'] as String)),
        isEmpty,
      );
    });

    test('of a create the server refused waits with it, holding up nothing '
        'else', () async {
      offline();
      final created = await tasksOf(container, projectId).create('Полка');
      await queue().add(created.taskId!, picture());
      await queue().add(taskId, picture());
      await flush(container);
      // The project goes away before the network comes back.
      server.projects.remove(projectId);

      online();
      await flush(container);

      final byKind = {for (final e in store.entries) e.key: e};
      final create = store.entries.first;
      expect(create.state, OutboxState.refused);
      expect(byKind.values.where((e) => e.isWaiting), hasLength(1));
      expect(
        store.entries.where((e) => e.state == OutboxState.sent),
        hasLength(1),
      );
      expect(server.uploads.single.taskId, taskId);
    });

    test('of a create that was thrown away is refused', () async {
      offline();
      final created = await tasksOf(container, projectId).create('Полка');
      await queue().add(created.taskId!, picture());
      await flush(container);
      await container
          .read(outboxProvider.notifier)
          .discard(store.entries.first);

      online();
      await flush(container);
      expect(store.entries.single.state, OutboxState.refused);
      expect(store.entries.single.message, 'Задача не была создана');
      expect(
        container
            .read(pendingAttachmentsProvider(created.taskId!))
            .single
            .state,
        PendingAttachmentState.refused,
      );
    });

    test('refused by the server waits for a decision; «Убрать» drops the '
        'copy', () async {
      for (var i = 0; i < FakeProjectBackend.maxAttachmentsPerTask; i++) {
        server.addAttachment(taskId: taskId);
      }
      await queue().add(taskId, picture());
      await flush(container);

      final pending = container.read(pendingAttachmentsProvider(taskId)).single;
      expect(pending.state, PendingAttachmentState.refused);
      expect(pending.message, isNotNull);
      expect(files.files, hasLength(1));

      await queue().discard(pending);
      expect(store.entries, isEmpty);
      expect(files.files, isEmpty);
    });

    test('that is not a picture is refused here', () async {
      await expectLater(
        queue().add(taskId, XFile.fromData(Uint8List.fromList(<int>[1, 2, 3]))),
        throwsA(isA<UnsupportedAttachment>()),
      );
      expect(store.entries, isEmpty);
      expect(files.files, isEmpty);
    });

    test('deleted offline is gone from the row at once, and on the server '
        'later', () async {
      final attachmentId = server.addAttachment(taskId: taskId);
      await tasksOf(container, projectId).refresh();
      final row = drawn(container, projectId).single;
      expect(row.attachments, hasLength(1));

      offline();
      await queue().remove(row, attachmentId);
      await flush(container);
      expect(drawn(container, projectId).single.attachments, isEmpty);
      expect(server.attachmentBytes, hasLength(1));

      online();
      await flush(container);
      expect(server.attachmentBytes, isEmpty);
      expect(store.entries.single.state, OutboxState.sent);
      expect(drawn(container, projectId).single.attachments, isEmpty);
    });

    test('deleted when it is already gone counts as sent', () async {
      final attachmentId = server.addAttachment(taskId: taskId);
      await tasksOf(container, projectId).refresh();
      final row = drawn(container, projectId).single;
      server.attachmentBytes.remove(attachmentId);

      await queue().remove(row, attachmentId);
      await flush(container);
      expect(store.entries, isEmpty); // sent on the first try
    });

    test('still waiting is just taken off the outbox', () async {
      offline();
      final pending = await queue().add(taskId, picture());
      await flush(container);
      await queue().remove(drawn(container, projectId).single, pending.id);
      expect(store.entries, isEmpty);
      expect(files.files, isEmpty);
    });
  });

  group('attachmentBytesProvider', () {
    test('fetches once, then reads the cache; the thumbnail apart', () async {
      final projectId = server.addProject(name: 'Дом');
      final taskId = server.addTask(projectId: projectId, title: 'Шкаф');
      final id = server.addAttachment(
        taskId: taskId,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final container = makeContainer();

      expect(
        await container.read(attachmentBytesProvider((id, false)).future),
        <int>[1, 2, 3],
      );
      expect(
        await container.read(attachmentBytesProvider((id, true)).future),
        <int>[3, 2, 1],
      );
      expect(cache.entries.keys, containsAll(<String>[id, '$id.thumb']));

      final requests = backend.requests.length;
      final fresh = ProviderContainer(overrides: overrides());
      addTearDown(fresh.dispose);
      expect(
        await fresh.read(attachmentBytesProvider((id, false)).future),
        <int>[1, 2, 3],
      );
      expect(backend.requests.length, requests);
    });
  });

  group('linkPreviewProvider', () {
    test(
      'a preview, and null rather than an error when there is none',
      () async {
        server.linkPreviews['https://a.test/'] = <String, dynamic>{
          'url': 'https://a.test/',
          'title': 'A',
          'siteName': null,
        };
        final container = makeContainer();
        expect(
          (await container.read(
            linkPreviewProvider('https://a.test/').future,
          ))!.title,
          'A',
        );
        offline();
        expect(
          await container.read(linkPreviewProvider('https://b.test/').future),
          isNull,
        );
      },
    );
  });

  group('the overlay', () {
    final task = Task(
      id: 't1',
      projectId: 'p',
      title: 'Шкаф',
      description: null,
      status: TaskStatus.pending,
      position: 1000,
      remindAt: null,
      createdAt: '2026-11-11T10:00:00.000Z',
      updatedAt: '2026-11-11T10:00:00.000Z',
      isCurrent: true,
    );

    test('applies a checklist and a place', () {
      final next = applyTaskPatch(task, <String, Object?>{
        'checklist': <Object?>[
          <String, Object?>{'id': 'item0001', 'text': 'a', 'done': true},
        ],
        'location': <String, Object?>{'lat': 1, 'lng': 2, 'radius': 100},
      });
      expect(next.checklist!.single.done, isTrue);
      expect(next.location!.radius, 100);
      final cleared = applyTaskPatch(next, <String, Object?>{
        'checklist': null,
        'location': null,
      });
      expect(cleared.checklist, isNull);
      expect(cleared.location, isNull);
    });

    test('a pending picture is found by either name of its task', () {
      final create = OutboxEntry(
        key: 'c1',
        kind: OutboxKind.createTask,
        projectId: 'p',
        title: 'Полка',
        body: const <String, Object?>{'title': 'Полка'},
        createdAt: DateTime.utc(2026, 11, 11),
        state: OutboxState.sent,
        taskId: 'real1',
      );
      final upload = OutboxEntry(
        key: 'u1',
        kind: OutboxKind.uploadAttachment,
        projectId: 'p',
        taskId: 'local:outbox:c1',
        title: 'Полка',
        body: const <String, Object?>{
          'uploadKey': 'u1',
          'mime': 'image/png',
          'localPath': 'memory:u1.png',
        },
        createdAt: DateTime.utc(2026, 11, 11),
      );
      final entries = <OutboxEntry>[create, upload];
      expect(pendingAttachments(entries, 'real1').single.id, 'local:upload:u1');
      expect(pendingAttachments(entries, 'local:outbox:c1'), hasLength(1));
      expect(pendingAttachmentCounts(entries), <String, int>{'real1': 1});
      expect(resolvedTaskId(upload, entries), 'real1');
    });
  });

  group('the «Офлайн» view', () {
    testWidgets('names the new fields and kinds', (tester) async {
      backend.alwaysFailToConnect();
      store.entries = <OutboxEntry>[
        OutboxEntry(
          key: 'e1',
          kind: OutboxKind.editTask,
          projectId: 'p',
          taskId: 't',
          title: 'Шкаф',
          body: const <String, Object?>{
            'checklist': <Object?>[
              <String, Object?>{'id': 'item0001', 'text': 'a', 'done': true},
              <String, Object?>{'id': 'item0002', 'text': 'b', 'done': false},
            ],
            'location': <String, Object?>{
              'lat': 1,
              'lng': 2,
              'radius': 100,
              'label': 'Дача',
            },
          },
          createdAt: DateTime.now(),
        ),
        OutboxEntry(
          key: 'u1',
          kind: OutboxKind.uploadAttachment,
          projectId: 'p',
          taskId: 't',
          title: 'Шкаф',
          body: const <String, Object?>{
            'uploadKey': 'u1',
            'mime': 'image/png',
            'localPath': 'memory:u1.png',
          },
          createdAt: DateTime.now(),
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: OutboxHistoryView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Список, Место'), findsOneWidget);
      expect(find.textContaining('список 1/2'), findsOneWidget);
      expect(find.textContaining('Дача'), findsOneWidget);
      expect(find.textContaining('Картинка'), findsOneWidget);
    });
  });
}
