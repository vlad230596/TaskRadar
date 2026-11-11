import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/attachments/clipboard_image.dart';
import 'package:taskradar/attachments/compress.dart';
import 'package:taskradar/attachments/pick.dart';
import 'package:taskradar/attachments/share_intake.dart';
import 'package:taskradar/domain/outbox_overlay.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/project.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_attachment.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/providers/attachment_providers.dart';
import 'package:taskradar/providers/board_providers.dart';
import 'package:taskradar/providers/project_providers.dart';
import 'package:taskradar/storage/outbox_store.dart';
import 'package:taskradar/widgets/attachment_badge.dart';
import 'package:taskradar/widgets/editor/attachment_strip.dart';
import 'package:taskradar/widgets/editor/sections.dart';

/// WP6's widgets: the strip in each picture state, undoable delete, the
/// viewer, Ctrl+V of a picture, the share-into-app flow, the editor slot
/// and the row badge (`design/task-editor-spec.md` §6).
void main() {
  // A real 1x1 PNG, so `Image.memory` decodes.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );
  XFile picture(String name) => XFile.fromData(png, path: name);

  late _FakeQueue queue;
  late _FakeSource source;
  late _FakeClipboard clipboard;

  setUp(() {
    queue = _FakeQueue();
    source = _FakeSource();
    clipboard = _FakeClipboard();
  });

  List<Override> overrides({List<Override> extra = const <Override>[]}) =>
      <Override>[
        attachmentQueueProvider.overrideWithValue(queue),
        pictureSourceProvider.overrideWithValue(source),
        imageEncoderProvider.overrideWithValue(null),
        clipboardImageReaderProvider.overrideWithValue(clipboard),
        clipboardImageWriterProvider.overrideWithValue(clipboard),
        attachmentBytesProvider.overrideWith((ref, args) async => png),
        ...extra,
      ];

  Future<void> pumpApp(
    WidgetTester tester,
    Widget child, {
    List<Override> extra = const <Override>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(extra: extra),
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  TaskAttachment server(String id) => TaskAttachment(
    id: id,
    mime: 'image/png',
    width: 1,
    height: 1,
    sizeBytes: png.length,
    createdAt: '2026-11-11T10:00:00.000Z',
  );

  PendingAttachment pending(
    String key, {
    PendingAttachmentState state = PendingAttachmentState.waiting,
    double? progress,
  }) => PendingAttachment(
    entry: OutboxEntry(
      key: key,
      kind: OutboxKind.uploadAttachment,
      projectId: 'p1',
      taskId: 't1',
      title: 'Шкаф',
      body: <String, Object?>{
        'uploadKey': key,
        'mime': 'image/png',
        'localPath': 'memory:$key.png',
      },
      createdAt: DateTime.utc(2026, 11, 11),
      state: state == PendingAttachmentState.refused
          ? OutboxState.refused
          : OutboxState.waiting,
      message: state == PendingAttachmentState.refused
          ? 'Слишком большой'
          : null,
    ),
    state: state,
    progress: progress,
  );

  group('the strip', () {
    testWidgets('draws every state, and «+» adds compressed picks', (
      tester,
    ) async {
      final added = <List<XFile>>[];
      source.files = <XFile>[picture('a.png'), picture('b.png')];
      await pumpApp(
        tester,
        AttachmentStrip(
          taskIdOrLocal: 't1',
          attachments: <TaskAttachment>[server('s1')],
          pending: <PendingAttachment>[
            pending('w1'),
            pending('u1', progress: 0.4),
            pending('r1', state: PendingAttachmentState.refused),
          ],
          drafts: <XFile>[picture('d.png')],
          onAdd: (files) async => added.add(files),
          onDelete: (_) {},
        ),
      );

      expect(find.text('КАРТИНКИ · 5'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('strip-waiting')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('strip-progress')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('strip-refused')),
        findsOneWidget,
      );
      expect(find.byType(AttachmentTile), findsNWidgets(5));

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('strip-add')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('strip-add')));
      await tester.pumpAndSettle();
      expect(source.limits, <int?>[25]);
      expect(added.single.map((f) => f.name), <String>['a.png', 'b.png']);
    });

    testWidgets('a refused picture offers «Повторить» and «Убрать»', (
      tester,
    ) async {
      final refused = pending('r1', state: PendingAttachmentState.refused);
      await pumpApp(
        tester,
        AttachmentStrip(
          taskIdOrLocal: 't1',
          attachments: const <TaskAttachment>[],
          pending: <PendingAttachment>[refused],
          onAdd: (_) async {},
          onDelete: (_) {},
        ),
      );

      await tester.tap(find.byType(AttachmentTile));
      await tester.pumpAndSettle();
      expect(find.textContaining('Слишком большой'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('strip-retry')));
      await tester.pumpAndSettle();
      expect(queue.retried, <String>['local:upload:r1']);

      await tester.tap(find.byType(AttachmentTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('strip-discard')));
      await tester.pumpAndSettle();
      expect(queue.discarded, <String>['local:upload:r1']);
    });

    testWidgets('delete hides at once, «Вернуть» undoes, otherwise it goes', (
      tester,
    ) async {
      final deleted = <String>[];
      await pumpApp(
        tester,
        AttachmentStrip(
          taskIdOrLocal: 't1',
          attachments: <TaskAttachment>[server('s1'), server('s2')],
          pending: const <PendingAttachment>[],
          onAdd: (_) async {},
          onDelete: deleted.add,
        ),
      );

      Future<void> deleteFirst() async {
        await tester.longPress(find.byType(AttachmentTile).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('strip-delete')));
        await tester.pumpAndSettle();
      }

      await deleteFirst();
      expect(find.byType(AttachmentTile), findsOneWidget);
      expect(find.text('Картинка удалена'), findsOneWidget);
      await tester.tap(find.text('Вернуть'));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentTile), findsNWidgets(2));
      expect(deleted, isEmpty);

      await deleteFirst();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(deleted, <String>['s1']);
    });

    testWidgets('a removed draft is handed back after the undo window', (
      tester,
    ) async {
      final draft = picture('d.png');
      final removed = <XFile>[];
      await pumpApp(
        tester,
        AttachmentStrip(
          taskIdOrLocal: 'new',
          attachments: const <TaskAttachment>[],
          pending: const <PendingAttachment>[],
          drafts: <XFile>[draft],
          onAdd: (_) async {},
          onDelete: (_) => fail('not a server picture'),
          onRemoveDraft: removed.add,
        ),
      );
      await tester.longPress(find.byType(AttachmentTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('strip-delete')));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentTile), findsNothing);
      expect(removed, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(removed, <XFile>[draft]);
    });
  });

  group('the viewer', () {
    testWidgets('swipes, copies, and deletes with a confirmation', (
      tester,
    ) async {
      final deleted = <String>[];
      await pumpApp(
        tester,
        AttachmentStrip(
          taskIdOrLocal: 't1',
          attachments: <TaskAttachment>[server('s1'), server('s2')],
          pending: const <PendingAttachment>[],
          onAdd: (_) async {},
          onDelete: deleted.add,
        ),
      );

      await tester.tap(find.byType(AttachmentTile).first);
      await tester.pumpAndSettle();
      expect(find.text('1 из 2'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('2 из 2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('viewer-copy')));
      await tester.pumpAndSettle();
      expect(clipboard.written, hasLength(1));
      expect(find.text('Картинка скопирована'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('viewer-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Удалить картинку?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-delete-confirm')),
      );
      await tester.pumpAndSettle();
      // One left, the viewer stays on it.
      expect(find.text('Картинка'), findsOneWidget);

      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentTile), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(deleted, <String>['s2']);
    });
  });

  group('Ctrl+V', () {
    Future<TextEditingController> pumpField(
      WidgetTester tester,
      List<List<XFile>> added,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        PictureClipboardPaste(
          enabled: true,
          onAdd: (files) async => added.add(files),
          child: TextField(controller: controller, autofocus: true),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    Future<void> pressCtrlV(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('a picture on the clipboard becomes an attachment', (
      tester,
    ) async {
      final added = <List<XFile>>[];
      clipboard.image = png;
      final controller = await pumpField(tester, added);
      await pressCtrlV(tester);
      expect(added.single.single.mimeType, 'image/png');
      expect(controller.text, isEmpty);
    });

    testWidgets('text on the clipboard is pasted as text', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => switch (call.method) {
          'Clipboard.getData' => <String, Object?>{'text': 'молоко'},
          'Clipboard.hasStrings' => <String, Object?>{'value': true},
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final added = <List<XFile>>[];
      final controller = await pumpField(tester, added);
      await pressCtrlV(tester);
      expect(added, isEmpty);
      expect(controller.text, 'молоко');
    });
  });

  group('sharing into the app', () {
    final project = Project(
      id: 'p1',
      name: 'Дом',
      scopeId: 's',
      archivedAt: null,
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
    );
    Task task(
      String id,
      String title, {
      TaskStatus status = TaskStatus.pending,
    }) => Task(
      id: id,
      projectId: 'p1',
      title: title,
      description: null,
      status: status,
      position: 1,
      remindAt: null,
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-0${id.length}T00:00:00.000Z',
      isCurrent: false,
    );
    final board = BoardReady(
      projects: <BoardProject>[
        BoardProject(
          project: project,
          tasks: <Task>[
            task('t1', 'Собрать шкаф'),
            task('t22', 'Готово давно', status: TaskStatus.done),
          ],
        ),
      ],
      origin: BoardOrigin.network,
      updatedAt: DateTime.utc(2026, 11, 11),
    );

    Future<List<String>> pumpScope(
      WidgetTester tester,
      _FakeInbox inbox,
    ) async {
      final opened = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(
            extra: <Override>[
              shareInboxProvider.overrideWithValue(inbox),
              boardViewProvider.overrideWithValue(board),
              projectTasksProvider.overrideWith2((_) => _FakeProjectTasks()),
              pendingAttachmentCountsProvider.overrideWithValue(
                const <String, int>{},
              ),
            ],
          ),
          child: MaterialApp(
            home: ShareIntakeScope(
              openTask:
                  (context, {required projectId, required taskId}) async =>
                      opened.add('$projectId/$taskId'),
              child: const Scaffold(body: Text('доска')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('to an existing task: queued there, the task opens', (
      tester,
    ) async {
      final inbox = _FakeInbox(<XFile>[picture('/shared/shot.png')]);
      final opened = await pumpScope(tester, inbox);

      expect(find.text('В какую задачу?'), findsOneWidget);
      expect(find.text('Готово давно'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Собрать шкаф'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Собрать шкаф'));
      await tester.pumpAndSettle();

      expect(inbox.resets, 1);
      expect(queue.added, <String>['t1']);
      expect(opened, <String>['p1/t1']);
    });

    testWidgets('to a new task: created in the chosen project first', (
      tester,
    ) async {
      final inbox = _FakeInbox(<XFile>[picture('/shared/shot.png')]);
      final opened = await pumpScope(tester, inbox);

      await tester.enterText(
        find.byKey(const ValueKey<String>('share-title')),
        'Чек из магазина',
      );
      await tester.tap(find.byKey(const ValueKey<String>('share-create')));
      await tester.pumpAndSettle();

      expect(_FakeProjectTasks.created, <String>['p1:Чек из магазина']);
      expect(queue.added, <String>['new1']);
      expect(opened, <String>['p1/new1']);
    });

    testWidgets('shares arriving later are asked about too', (tester) async {
      final inbox = _FakeInbox(const <XFile>[]);
      await pumpScope(tester, inbox);
      expect(find.text('В какую задачу?'), findsNothing);
      inbox.controller.add(<XFile>[picture('/shared/later.png')]);
      await tester.pumpAndSettle();
      expect(find.text('В какую задачу?'), findsOneWidget);
    });
  });

  group('the editor slot', () {
    testWidgets('a new task: the chip picks drafts, «Добавить» queues them', (
      tester,
    ) async {
      final extras = EditorExtras();
      addTearDown(extras.dispose);
      source.files = <XFile>[picture('a.png')];
      const scope = 'p1';
      final sectionScope = EditorSectionScope(
        projectId: scope,
        task: null,
        extras: extras,
        expanded: true,
      );
      var opened = 0;
      await pumpApp(
        tester,
        Column(
          children: <Widget>[
            ...EditorSlots.chips(sectionScope, onOpen: () => opened++),
            EditorSlots.attachments(sectionScope),
          ],
        ),
      );
      expect(find.byType(AttachmentStrip), findsNothing);
      expect(find.text('+ Фото'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('chip-pictures')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(AttachmentTile), findsOneWidget);
      expect(find.text('Фото · 1'), findsOneWidget);
      expect(queue.added, isEmpty);

      await extras.afterCreate(
        projectId: 'p1',
        outcome: const WriteOutcome.queuedAs('local:outbox:k1', 'k1'),
      );
      await tester.pumpAndSettle();
      expect(queue.added, <String>['local:outbox:k1']);
      expect(find.byType(AttachmentStrip), findsNothing);
    });
  });

  testWidgets('the row badge counts sent and waiting pictures', (tester) async {
    final row = Task(
      id: 't1',
      projectId: 'p1',
      title: 'Шкаф',
      description: null,
      status: TaskStatus.pending,
      position: 1,
      remindAt: null,
      attachments: <TaskAttachment>[server('s1'), server('s2')],
      createdAt: '2026-11-01T00:00:00.000Z',
      updatedAt: '2026-11-01T00:00:00.000Z',
      isCurrent: false,
    );
    await pumpApp(
      tester,
      Column(
        children: <Widget>[
          AttachmentCountBadge(task: row),
          AttachmentCountBadge(
            task: row.copyWith(id: 't2', attachments: []),
          ),
        ],
      ),
      extra: <Override>[
        pendingAttachmentCountsProvider.overrideWithValue(const <String, int>{
          't1': 1,
        }),
      ],
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
  });
}

class _FakeQueue implements AttachmentQueue {
  final List<String> added = <String>[];
  final List<String> retried = <String>[];
  final List<String> discarded = <String>[];
  final List<String> removed = <String>[];

  @override
  Future<PendingAttachment> add(
    String taskIdOrLocal,
    XFile file, {
    String? projectId,
    String? title,
  }) async {
    added.add(taskIdOrLocal);
    return PendingAttachment(
      entry: OutboxEntry(
        key: 'k${added.length}',
        kind: OutboxKind.uploadAttachment,
        projectId: projectId ?? 'p',
        title: title ?? '',
        body: const <String, Object?>{},
        createdAt: DateTime.utc(2026),
      ),
      state: PendingAttachmentState.waiting,
    );
  }

  @override
  Future<List<PendingAttachment>> addAll(
    String taskIdOrLocal,
    List<XFile> files, {
    String? projectId,
    String? title,
  }) async => <PendingAttachment>[
    for (final f in files)
      await add(taskIdOrLocal, f, projectId: projectId, title: title),
  ];

  @override
  Future<void> discard(PendingAttachment pending) async =>
      discarded.add(pending.id);

  @override
  Future<void> remove(Task task, String attachmentId) async =>
      removed.add(attachmentId);

  @override
  Future<void> retry(PendingAttachment pending) async =>
      retried.add(pending.id);
}

class _FakeSource implements PictureSource {
  List<XFile> files = const <XFile>[];
  final List<int?> limits = <int?>[];

  @override
  Future<List<XFile>> pickImages({int? limit}) async {
    limits.add(limit);
    return files;
  }
}

class _FakeClipboard implements ClipboardImageReader, ClipboardImageWriter {
  Uint8List? image;
  final List<Uint8List> written = <Uint8List>[];

  @override
  Future<Uint8List?> readImage() async => image;

  @override
  Future<bool> writeImage(Uint8List bytes) async {
    written.add(bytes);
    return true;
  }
}

class _FakeInbox implements ShareInbox {
  _FakeInbox(this.start);

  final List<XFile> start;
  final StreamController<List<XFile>> controller =
      StreamController<List<XFile>>.broadcast();
  int resets = 0;

  @override
  Future<List<XFile>?> initial() async => start;

  @override
  Stream<List<XFile>> get incoming => controller.stream;

  @override
  Future<void> reset() async => resets++;
}

class _FakeProjectTasks extends ProjectTasks {
  static final List<String> created = <String>[];

  @override
  Future<List<Task>> build(String projectId) async => const <Task>[];

  @override
  Future<WriteOutcome> create(
    String title, {
    String? description,
    String? categoryId,
    TaskStatus? status,
    String? remindAt,
    String? remindTime,
    dynamic checklist,
    dynamic location,
    String? dictationParseId,
  }) async {
    created.add('$projectId:$title');
    return const WriteOutcome.sentAs('new1', 'k');
  }
}
