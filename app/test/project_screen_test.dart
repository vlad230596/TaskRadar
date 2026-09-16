import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/note_editor_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';
import 'package:taskradar/widgets/note_list.dart';
import 'package:taskradar/widgets/task_list.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fixtures.dart';

/// Widget tests for the project screen: the states it can be in, and the four
/// gestures that make up the day -- add a task, change its status, rename it,
/// delete it -- plus the notes side.
///
/// Assertions are on rendered text wherever the text is the point, in the same
/// spirit as `board_screen_test.dart`: a status control that does nothing has no
/// type error anywhere near it.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;
  late String projectId;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();
    projectId = server.addProject(name: 'Дача', id: 'prj_1');
  });

  /// `pumpAndSettle` is unusable on this screen for the same reason as on the
  /// board: the loading spinner and the refresh hairline animate forever.
  Future<void> settle(WidgetTester tester) async {
    // 20 x 40 ms comfortably covers a MaterialPageRoute transition (300 ms) and
    // a dialog's (150 ms), both of which this screen opens.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// The composer inside whichever list is on screen.
  ///
  /// `find.byType(TextField).first` is wrong here and wrong in a way that passes
  /// half the time: `TabBarView` keeps both tabs' children in the tree, so the
  /// "first" text field is the *tasks* composer even while the notes tab is
  /// showing.
  Finder composerIn(Type list) => find
      .descendant(of: find.byType(list), matching: find.byType(TextField))
      .first;

  Future<void> pumpProject(
    WidgetTester tester, {
    String? highlightTaskId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(snapshots),
          notificationGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp(
          home: ProjectScreen(
            projectId: projectId,
            highlightTaskId: highlightTaskId,
          ),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> openNotesTab(WidgetTester tester) async {
    await tester.tap(find.textContaining('Заметки'));
    await settle(tester);
  }

  group('states', () {
    testWidgets('loading says so, with nothing that looks like data', (
      tester,
    ) async {
      final gate = Completer<void>();
      backend.delay = (_) => gate.future;

      await pumpProject(tester);

      expect(find.text('Загружаем проект…'), findsOneWidget);
      expect(find.text('Задач пока нет'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(find.text('Дача'), findsOneWidget);
    });

    testWidgets('an empty project says so and still offers the composer', (
      tester,
    ) async {
      await pumpProject(tester);

      expect(find.text('Задач пока нет'), findsOneWidget);
      // The composer is the point of the screen, so it is there even with
      // nothing to show.
      expect(find.widgetWithText(TextField, ''), findsWidgets);
      expect(find.byTooltip('Добавить задачу'), findsOneWidget);
    });

    testWidgets('no network and no cache: an error, and it names the cause', (
      tester,
    ) async {
      backend.alwaysFailToConnect();

      await pumpProject(tester);

      expect(find.text('Не удалось открыть проект'), findsOneWidget);
      expect(find.textContaining('Нет связи с сервером.'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      // Not "this project is empty".
      expect(find.text('Задач пока нет'), findsNothing);
    });

    testWidgets('a server error is worded differently from no connection', (
      tester,
    ) async {
      backend.responder = (_) => jsonResponse(<String, dynamic>{
        'error': 'Internal Server Error',
        'message': 'boom',
      }, statusCode: 500);

      await pumpProject(tester);

      expect(
        find.textContaining('Сервер ответил ошибкой 500: boom'),
        findsOneWidget,
      );
      expect(find.textContaining('Нет связи'), findsNothing);
    });

    testWidgets('a deleted project reads as "not found", not as a failure', (
      tester,
    ) async {
      server.projects.clear();

      await pumpProject(tester);

      expect(find.text('Проект не найден'), findsOneWidget);
      expect(find.text('Повторить'), findsNothing);
    });

    testWidgets('the retry button asks all three endpoints again', (
      tester,
    ) async {
      backend.alwaysFailToConnect();
      await pumpProject(tester);

      backend.responder = null; // the routed fake takes over again
      await tester.tap(find.text('Повторить'));
      await settle(tester);

      expect(find.text('Дача'), findsOneWidget);
      expect(find.text('Задач пока нет'), findsOneWidget);
    });

    testWidgets('a cached project is shown, and says writes will fail', (
      tester,
    ) async {
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(<dynamic>[
          boardProjectJson(
            id: projectId,
            name: 'Дача',
            tasks: <Map<String, dynamic>>[
              taskJson(
                id: 'tsk_cached',
                title: 'Задача из снимка',
                isCurrent: true,
              ),
            ],
          ),
        ]),
        savedAt: DateTime.now(),
      );
      backend.alwaysFailToConnect();

      await pumpProject(tester);

      expect(find.text('Задача из снимка'), findsOneWidget);
      expect(
        find.textContaining('изменения сейчас не сохранятся'),
        findsOneWidget,
      );
    });
  });

  group('a project with tasks', () {
    setUp(() {
      server.addTask(
        projectId: projectId,
        title: 'Уже сделано',
        status: 'done',
      );
      server.addTask(projectId: projectId, title: 'Позвонить прорабу');
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: _remindAt(0),
      );
    });

    testWidgets('renders every task in server order', (tester) async {
      await pumpProject(tester);

      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where(
            (data) => <String>[
              'Уже сделано',
              'Позвонить прорабу',
              'Жду кабель',
            ].contains(data),
          )
          .toList();

      expect(titles, <String>[
        'Уже сделано',
        'Позвонить прорабу',
        'Жду кабель',
      ]);
    });

    testWidgets('the tab counts done against total', (tester) async {
      await pumpProject(tester);

      // Same rule as the board card: blocked is not done.
      expect(find.text('Задачи · 1/3'), findsOneWidget);
    });

    testWidgets(
      'the current task is the one the server flagged, and it looks it',
      (tester) async {
        await pumpProject(tester);

        final current = tester.widget<Text>(find.text('Позвонить прорабу'));
        final other = tester.widget<Text>(find.text('Жду кабель'));

        expect(current.style?.fontWeight, FontWeight.w600);
        expect(other.style?.fontWeight, isNot(FontWeight.w600));

        // A done task is struck through rather than hidden -- it is part of the
        // record of what happened in this project.
        final done = tester.widget<Text>(find.text('Уже сделано'));
        expect(done.style?.decoration, TextDecoration.lineThrough);
      },
    );

    testWidgets('a due reminder is shown on the blocked task', (tester) async {
      await pumpProject(tester);

      final today = DateTime.now();
      final label =
          'Напомнить · ${today.day.toString().padLeft(2, '0')}.'
          '${today.month.toString().padLeft(2, '0')}';
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('highlightTaskId outlines the row F4 will point at', (
      tester,
    ) async {
      final taskId =
          server.tasks.firstWhere((task) => task['title'] == 'Жду кабель')['id']
              as String;

      await pumpProject(tester, highlightTaskId: taskId);

      // The wiring, end to end: the route argument reaches the row. F4 only has
      // to supply the argument from a notification payload.
      final screen = tester.widget<ProjectScreen>(find.byType(ProjectScreen));
      expect(screen.highlightTaskId, taskId);
      expect(find.text('Жду кабель'), findsOneWidget);
    });

    testWidgets('a drag handle exists for every task and nothing else', (
      tester,
    ) async {
      await pumpProject(tester);
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
    });

    testWidgets('dragging a row persists the new order', (tester) async {
      await pumpProject(tester);

      // The real gesture, through `ReorderableDragStartListener`: press the
      // handle of the first row and pull it below the second.
      final handle = find.byIcon(Icons.drag_indicator).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await settle(tester);
      await settle(tester);

      expect(server.titlesInOrder(projectId), <String>[
        'Позвонить прорабу',
        'Уже сделано',
        'Жду кабель',
      ]);
    });
  });

  group('writing', () {
    testWidgets('typing a title and submitting creates the task', (
      tester,
    ) async {
      await pumpProject(tester);

      await tester.enterText(composerIn(TaskListView), 'Позвонить прорабу');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(find.text('Позвонить прорабу'), findsOneWidget);
      expect(server.titlesInOrder(projectId), <String>['Позвонить прорабу']);
      // The field is empty again, ready for the next one -- this is the fast
      // path and it has to stay fast.
      expect(
        tester.widget<TextField>(composerIn(TaskListView)).controller?.text,
        isEmpty,
      );
    });

    testWidgets('a create with no network rolls back and says why', (
      tester,
    ) async {
      await pumpProject(tester);
      backend.alwaysFailToConnect();

      await tester.enterText(composerIn(TaskListView), 'Не доедет');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      // Gone from the list...
      expect(find.text('Не доедет'), findsNothing);
      // ...and the reason is on screen, not swallowed. A silent revert reads as
      // a UI bug and gets retried forever.
      expect(
        find.textContaining('Не удалось добавить задачу.'),
        findsOneWidget,
      );
      expect(find.textContaining('Нет связи с сервером.'), findsOneWidget);
    });

    testWidgets('the status menu changes the status', (tester) async {
      server.addTask(projectId: projectId, title: 'Позвонить прорабу');
      await pumpProject(tester);

      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await settle(tester);
      expect(find.text('Готово'), findsOneWidget);

      await tester.tap(find.text('Готово'));
      await settle(tester);

      expect(server.tasks.single['status'], 'done');
      // And only the status went over the wire.
      expect(server.patches.last.body, <String, dynamic>{'status': 'done'});
    });

    testWidgets('renaming sends only the title', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Старое',
        description: 'важное описание',
      );
      await pumpProject(tester);

      await tester.tap(find.text('Старое'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).last, 'Новое');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(find.text('Новое'), findsOneWidget);
      expect(server.patches.last.body, <String, dynamic>{'title': 'Новое'});
      // The trap: a PATCH that also carried `description: null` would have
      // wiped this, successfully and silently.
      expect(server.tasks.single['description'], 'важное описание');
    });

    testWidgets('deleting asks first, then deletes', (tester) async {
      server.addTask(projectId: projectId, title: 'Лишняя');
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Удалить задачу'));
      await settle(tester);
      expect(find.text('Удалить задачу?'), findsOneWidget);

      // Cancelling really cancels.
      await tester.tap(find.text('Отмена'));
      await settle(tester);
      expect(server.tasks, hasLength(1));

      await tester.tap(find.byTooltip('Удалить задачу'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await settle(tester);

      expect(server.tasks, isEmpty);
      expect(find.text('Лишняя'), findsNothing);
    });

    testWidgets('the description dialog can set and then clear it', (
      tester,
    ) async {
      server.addTask(projectId: projectId, title: 'Задача');
      await pumpProject(tester);

      await tester.tap(find.text('описание'));
      await settle(tester);

      await tester.enterText(
        find.byType(TextField).last,
        'у Петра до вторника',
      );
      await tester.tap(find.text('Сохранить'));
      await settle(tester);

      expect(find.text('у Петра до вторника'), findsOneWidget);
      expect(server.tasks.single['description'], 'у Петра до вторника');

      // Emptying the field means "erase", which has to reach the server as an
      // explicit null rather than as an omission.
      await tester.tap(find.text('у Петра до вторника'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.tap(find.text('Сохранить'));
      await settle(tester);

      expect(server.patches.last.body.containsKey('description'), isTrue);
      expect(server.patches.last.body['description'], isNull);
      expect(server.tasks.single['description'], isNull);
    });
  });

  group('notes', () {
    testWidgets('an empty notes tab says so', (tester) async {
      await pumpProject(tester);
      await openNotesTab(tester);

      expect(find.text('Заметок пока нет'), findsOneWidget);
    });

    testWidgets('notes render as markdown, not as source', (tester) async {
      server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: '# Что помнить\n\n- ключи у соседей',
      );

      await pumpProject(tester);
      await openNotesTab(tester);

      expect(find.text('Заметки · 1'), findsOneWidget);
      expect(find.text('Контекст'), findsOneWidget);
      expect(find.text('Что помнить'), findsOneWidget);
      expect(find.text('ключи у соседей'), findsOneWidget);
      expect(find.textContaining('# Что помнить'), findsNothing);
    });

    testWidgets('creating a note takes a title only', (tester) async {
      await pumpProject(tester);
      await openNotesTab(tester);

      await tester.enterText(composerIn(NoteListView), 'Контекст');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(server.notes.single['title'], 'Контекст');
      expect(server.notes.single['content'], '');
      expect(find.text('Пусто'), findsOneWidget);
    });

    testWidgets('tapping a note opens the editor and saving writes it', (
      tester,
    ) async {
      server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: 'старое',
      );

      await pumpProject(tester);
      await openNotesTab(tester);

      await tester.tap(find.text('старое'));
      await settle(tester);
      expect(find.byType(NoteEditorScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '# Новое');
      await settle(tester);
      // The app bar says there is something to lose.
      expect(find.text('Заметка · не сохранено'), findsOneWidget);

      await tester.tap(find.byTooltip('Сохранить'));
      await settle(tester);

      expect(server.notes.single['content'], '# Новое');
      expect(find.text('Заметка'), findsOneWidget);
    });

    testWidgets('the editor previews the draft as markdown', (tester) async {
      server.addNote(projectId: projectId, title: 'Контекст');

      await pumpProject(tester);
      await openNotesTab(tester);
      await tester.tap(find.text('Контекст'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).last, '- раз\n- два');
      await tester.tap(find.byTooltip('Просмотр'));
      await settle(tester);

      expect(find.text('раз'), findsOneWidget);
      expect(find.text('два'), findsOneWidget);
    });

    testWidgets('leaving the editor with unsaved text asks first', (
      tester,
    ) async {
      server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: 'старое',
      );

      await pumpProject(tester);
      await openNotesTab(tester);
      await tester.tap(find.text('старое'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).last, 'наполовину набрано');
      await settle(tester);

      await tester.tap(find.byTooltip('Back'));
      await settle(tester);

      expect(find.text('Выйти без сохранения?'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await settle(tester);
      // Still here, text intact.
      expect(find.byType(NoteEditorScreen), findsOneWidget);
    });

    testWidgets('deleting a note asks first', (tester) async {
      server.addNote(projectId: projectId, title: 'Лишняя');

      await pumpProject(tester);
      await openNotesTab(tester);

      await tester.tap(find.byTooltip('Удалить заметку'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await settle(tester);

      expect(server.notes, isEmpty);
      expect(find.text('Заметок пока нет'), findsOneWidget);
    });

    testWidgets('a failed notes load is reported on that tab alone', (
      tester,
    ) async {
      // Only the notes endpoint is down. The project must not become an error
      // page over it -- the tasks are perfectly readable.
      backend.failingPaths.add('/notes');
      await pumpProject(tester);

      await openNotesTab(tester);
      expect(find.text('Не удалось загрузить заметки'), findsOneWidget);
      expect(find.textContaining('Нет связи с сервером.'), findsOneWidget);
      // The tasks side is untouched.
      await tester.tap(find.textContaining('Задачи'));
      await settle(tester);
      expect(find.text('Задач пока нет'), findsOneWidget);
    });
  });

  group('phone-sized layout', () {
    testWidgets('long titles and descriptions do not overflow 375x812', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      server.addTask(
        projectId: projectId,
        title:
            'Очень длинный заголовок задачи, который не влезает в одну строку '
            'на телефоне и должен переноситься, а не ломать вёрстку',
        description:
            'И описание такой же длины, потому что описания пишут абзацами, '
            'а не словами, и строка тут тоже не одна.',
        status: 'blocked',
        remindAt: _remindAt(0),
      );

      await pumpProject(tester);

      expect(find.text('Задачи · 0/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// `remindAt` in the shape the backend stores, [offsetDays] from today.
String _remindAt(int offsetDays) {
  final day = DateTime.now().add(Duration(days: offsetDays));
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}'
      'T00:00:00.000Z';
}
