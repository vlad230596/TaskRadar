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
import 'package:taskradar/screens/task_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
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
  /// Only the notes list has one now: F12 removed the task composer, because a
  /// one-line field was complaint number one. Adding a task opens
  /// `TaskScreen.draft` instead. The finder stays scoped to a list rather than
  /// using `find.byType(TextField).first`, because on the desktop both panes
  /// are on screen at once.
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
          theme: buildAppTheme(),
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

  /// Swaps the body to the notes.
  ///
  /// A header button rather than a tab since F12: the tabs cost a 48 px strip
  /// on every project screen to answer a question the icon answers, on a screen
  /// whose job is fitting as many 56 px task rows as it can.
  Future<void> openNotesTab(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Заметки проекта'));
    await settle(tester);
  }

  Future<void> openTasksTab(WidgetTester tester) async {
    await tester.tap(find.byTooltip('К задачам'));
    await settle(tester);
  }

  /// Opens one task on its own screen -- which is where every edit lives now.
  Future<void> openTask(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await settle(tester);
  }

  /// Opens the blank task screen from the end of the list.
  Future<void> openDraft(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Задача'));
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

    testWidgets('an empty project says so and still offers a way in', (
      tester,
    ) async {
      await pumpProject(tester);

      expect(find.text('Задач пока нет'), findsOneWidget);
      // No composer any more -- that one-line field was complaint number one.
      // What is here instead is the button that opens a 252 px one, and the
      // microphone, which skips the screen entirely.
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Задача'), findsOneWidget);
      expect(find.byTooltip('Задача голосом'), findsOneWidget);
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

    testWidgets('the header counts done against total', (tester) async {
      await pumpProject(tester);

      // Same rule as the planning row, and the same counter drawn the same way:
      // arriving here continues the row that was tapped rather than describing
      // the project a second way. Blocked is not done.
      expect(find.text('1 / 3'), findsOneWidget);
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

      // The one row in the whole app that asks for action *today*, so it says
      // so before it says the date.
      final today = DateTime.now();
      final date =
          '${today.day.toString().padLeft(2, '0')}.'
          '${today.month.toString().padLeft(2, '0')}';
      expect(find.textContaining('пора · $date'), findsOneWidget);
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
      // In steps, and past the whole of the next row: `ReorderableListView`
      // decides on the drop by where the pointer is relative to the item it is
      // over, and one jump can land between two frames of the animation.
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 18));
        await tester.pump(const Duration(milliseconds: 20));
      }
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
    testWidgets('the blank task screen creates the task', (tester) async {
      await pumpProject(tester);

      await openDraft(tester);
      // The field this screen exists for: 252 px of it, at 20 px type.
      expect(find.byType(TaskScreen), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.fontSize, 20);
      expect(field.maxLines, isNull);

      await tester.enterText(find.byType(TextField), 'Позвонить прорабу');
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      expect(server.titlesInOrder(projectId), <String>['Позвонить прорабу']);
      // ...and it is back on the list, which is where the next one is added
      // from.
      expect(find.byType(TaskScreen), findsNothing);
      expect(find.text('Позвонить прорабу'), findsOneWidget);
    });

    testWidgets('a create with no network rolls back and says why', (
      tester,
    ) async {
      await pumpProject(tester);
      await openDraft(tester);
      backend.alwaysFailToConnect();

      await tester.enterText(find.byType(TextField), 'Не доедет');
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      // Nothing was created...
      expect(server.tasks, isEmpty);
      // ...the reason is on screen, not swallowed -- a silent revert reads as a
      // UI bug and gets retried forever...
      expect(
        find.textContaining('Не удалось добавить задачу.'),
        findsOneWidget,
      );
      expect(find.textContaining('Нет связи с сервером.'), findsOneWidget);
      // ...and the words are still in the field. The old composer cleared
      // before the await and relied on a snackbar to say the sentence was
      // gone; a screen that is still open can simply keep it.
      expect(find.byType(TaskScreen), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Не доедет',
      );
    });

    testWidgets('one tap on the circle marks the task done', (tester) async {
      // The change that happens dozens of times a day costs one tap; the
      // three-way choice, which happens once in a while, is behind a long
      // press. The old row had it the other way round.
      server.addTask(projectId: projectId, title: 'Позвонить прорабу');
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Отметить сделанной'));
      await settle(tester);

      expect(server.tasks.single['status'], 'done');
      // And only the status went over the wire.
      expect(server.patches.last.body, <String, dynamic>{'status': 'done'});
    });

    testWidgets('a long press offers the three-way choice', (tester) async {
      server.addTask(projectId: projectId, title: 'Позвонить прорабу');
      await pumpProject(tester);

      await tester.longPress(find.byTooltip('Отметить сделанной'));
      await settle(tester);

      expect(find.text('В очереди'), findsOneWidget);
      expect(find.text('Блокер'), findsOneWidget);
      expect(find.text('Сделано'), findsOneWidget);
    });

    testWidgets('renaming sends only the title', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Старое',
        description: 'важное описание',
      );
      await pumpProject(tester);

      await openTask(tester, 'Старое');
      await tester.enterText(find.byType(TextField).first, 'Новое');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
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
      await openTask(tester, 'Лишняя');

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
      // ...and the screen the task was on is gone with it, rather than sitting
      // there addressing a row that no longer exists.
      expect(find.byType(TaskScreen), findsNothing);
      expect(find.text('Лишняя'), findsNothing);
    });

    testWidgets('the note can be set and then cleared', (tester) async {
      // Folded away when empty, because the screen that matters is a 252 px
      // field and three status buttons -- but reachable, because eleven
      // existing tasks already carry a description and a screen that edited
      // only the title would quietly make that text unreachable.
      server.addTask(projectId: projectId, title: 'Вентилятор в туалете');
      await pumpProject(tester);
      await openTask(tester, 'Вентилятор в туалете');

      await tester.tap(find.text('Заметка к задаче'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'у Петра до вторника',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await settle(tester);

      expect(server.tasks.single['description'], 'у Петра до вторника');

      // Emptying the field means "erase", which has to reach the server as an
      // explicit null rather than as an omission.
      await openTask(tester, 'Вентилятор в туалете');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'у Петра до вторника',
      );
      await tester.enterText(find.byType(TextField).last, '');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
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
      await openTasksTab(tester);
      expect(find.text('Задач пока нет'), findsOneWidget);
    });
  });

  group('scopes (F7)', () {
    testWidgets('with one scope there is nothing to move the project to', (
      tester,
    ) async {
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Действия с проектом'));
      await tester.pumpAndSettle();

      // A picker with one option, already selected, is not a choice.
      expect(find.text('Переместить в скоуп'), findsNothing);
      expect(find.text('Переименовать'), findsOneWidget);
    });

    testWidgets('moving the project to another scope sends only the scope', (
      tester,
    ) async {
      // Named unlike the project itself ('Дача'), so that tapping the scope in
      // the picker cannot accidentally hit the project's own title.
      final personal = server.addScope(name: 'Личное');
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Действия с проектом'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переместить в скоуп'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Личное'));
      await settle(tester);

      expect(server.projects[projectId]!['scopeId'], personal);
      // A move is not a rename: the name must not travel with it, or every move
      // would rewrite a string nobody touched.
      expect(server.patches.last.body, <String, dynamic>{'scopeId': personal});
    });

    testWidgets('and says where it went, because it leaves the board', (
      tester,
    ) async {
      server.addScope(name: 'Личное');
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Действия с проектом'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Переместить в скоуп'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Личное'));
      await settle(tester);

      // The one write in this app whose success is worth a snackbar: it makes
      // the project disappear from the board it was opened from.
      expect(find.textContaining('теперь в скоупе «Личное»'), findsOneWidget);
    });
  });

  group('desktop layout (F6)', () {
    /// A window wide enough for the two-pane layout. Must be called *before*
    /// `pumpProject`: the layout is a function of the window width.
    void useDesktopWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('tasks and notes are both on screen, with no tab strip', (
      tester,
    ) async {
      server.addTask(projectId: projectId, title: 'Позвонить прорабу');
      server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: 'Кабель заказан 3 сентября.',
      );
      useDesktopWindow(tester);

      await pumpProject(tester);

      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TaskListView), findsOneWidget);
      expect(find.byType(NoteListView), findsOneWidget);

      // The counters the tabs used to carry are still facts about the project,
      // so they survive the layout change.
      expect(find.text('Задачи · 0/1'), findsOneWidget);
      expect(find.text('Заметки · 1'), findsOneWidget);

      // ...and the content of both is readable at the same time, which is the
      // entire point: the note is the context, the task is what to do about it.
      expect(find.text('Позвонить прорабу'), findsOneWidget);
      expect(find.text('Кабель заказан 3 сентября.'), findsOneWidget);
    });

    testWidgets('both panes stay live: a note can be written without a tab switch', (
      tester,
    ) async {
      useDesktopWindow(tester);
      await pumpProject(tester);

      await tester.enterText(composerIn(NoteListView), 'Что выяснил');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(server.notes.single['title'], 'Что выяснил');
      expect(find.text('Заметки · 1'), findsOneWidget);
    });

    testWidgets('the project menu is reachable, as on the phone', (
      tester,
    ) async {
      useDesktopWindow(tester);
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Действия с проектом'));
      await tester.pumpAndSettle();

      expect(find.text('Переименовать'), findsOneWidget);
      expect(find.text('В архив'), findsOneWidget);
    });

    testWidgets('long titles and descriptions do not overflow a pane', (
      tester,
    ) async {
      useDesktopWindow(tester);

      server.addTask(
        projectId: projectId,
        title:
            'Очень длинный заголовок задачи, который не влезает в одну строку '
            'и должен переноситься, а не ломать вёрстку',
        description:
            'И описание такой же длины, потому что описания пишут абзацами, '
            'а не словами, и строка тут тоже не одна.',
        status: 'blocked',
        remindAt: _remindAt(0),
      );
      server.addNote(
        projectId: projectId,
        title: 'Очень длинное название заметки, которое тоже не влезает',
        content: 'Тело заметки.',
      );

      await pumpProject(tester);

      expect(find.text('Задачи · 0/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
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

      expect(find.text('0 / 1'), findsOneWidget);
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
