import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/screens/board_screen.dart';
import 'package:taskradar/screens/notification_bench_screen.dart';
import 'package:taskradar/screens/settings_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';
import 'package:taskradar/widgets/project_card.dart';
import 'package:taskradar/widgets/project_column.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fixtures.dart';

/// Widget tests for the board screen: every state it can be in, and the three
/// numbers on a card that a person actually acts on.
///
/// These assert on rendered text rather than on widget types wherever the text
/// is the point -- a counter that says "1 / 3" when it should say "2 / 3" is a
/// product bug with no type error anywhere near it.
void main() {
  late FakeBackend backend;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;

  setUp(() {
    backend = FakeBackend();
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();
  });

  /// `pumpAndSettle` cannot be used on this screen: both the loading spinner
  /// and the "refreshing" hairline animate forever, so it would time out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpBoard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(snapshots),
          // The board screen brings the reminder bridge up, which initialises
          // the notification plugin. The real one degrades gracefully in the
          // test VM, but only the fake keeps these tests from depending on
          // that.
          notificationGatewayProvider.overrideWithValue(gateway),
          // The reminder hour is persisted from F4 on; the real store is a
          // `shared_preferences` platform channel the test VM does not have.
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        // `onGenerateRoute` as well as `home`, matching `app.dart`: from F3 a
        // board card pushes a named route, and without the generator a tap
        // would throw instead of navigating.
        child: MaterialApp(
          home: const BoardScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  /// `remindAt` in the shape the backend stores, [offsetDays] from today.
  String remindAt(int offsetDays) {
    final day = DateTime.now().add(Duration(days: offsetDays));
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}'
        'T00:00:00.000Z';
  }

  /// A three-project board covering the interesting shapes at once:
  /// a moving project, one stuck on a reminder that has come due, and one
  /// stuck on a reminder that has not.
  List<dynamic> sampleBoard() => <dynamic>[
    boardProjectJson(
      id: 'prj_a',
      name: 'Стройка',
      tasks: <Map<String, dynamic>>[
        taskJson(id: 'a1', status: 'done', position: 1000),
        taskJson(id: 'a2', status: 'done', position: 2000),
        taskJson(
          id: 'a3',
          title: 'Позвонить прорабу',
          position: 3000,
          isCurrent: true,
        ),
      ],
    ),
    boardProjectJson(
      id: 'prj_b',
      name: 'Дача',
      tasks: <Map<String, dynamic>>[
        taskJson(
          id: 'b1',
          title: 'Жду кабель',
          status: 'blocked',
          position: 1000,
          remindAt: remindAt(0),
        ),
        taskJson(id: 'b2', title: 'Покрасить забор', position: 2000, isCurrent: true),
      ],
    ),
    boardProjectJson(
      id: 'prj_c',
      name: 'Ремонт',
      tasks: <Map<String, dynamic>>[
        taskJson(
          id: 'c1',
          title: 'Ждём доставку плитки',
          status: 'blocked',
          position: 1000,
          remindAt: remindAt(4),
        ),
      ],
    ),
  ];

  group('loading', () {
    testWidgets('with no snapshot, the screen says it is loading', (tester) async {
      final inFlight = Completer<ResponseBody>();
      backend.responder = (_) => inFlight.future;

      await pumpBoard(tester);

      expect(find.text('Загружаем доску…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Nothing that could be mistaken for a fact about the data.
      expect(find.text('Проектов пока нет'), findsNothing);

      inFlight.complete(jsonResponse(sampleBoard()));
      await settle(tester);
      expect(find.text('Стройка'), findsOneWidget);
    });
  });

  group('a board from the wire', () {
    setUp(() => backend.alwaysRespond(sampleBoard()));

    testWidgets('renders one card per project, in server order', (tester) async {
      await pumpBoard(tester);

      expect(find.text('Стройка'), findsOneWidget);
      expect(find.text('Дача'), findsOneWidget);
      expect(find.text('Ремонт'), findsOneWidget);

      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((data) => <String>['Стройка', 'Дача', 'Ремонт'].contains(data))
          .toList();
      expect(names, <String>['Стройка', 'Дача', 'Ремонт']);
    });

    testWidgets('the counter counts done against total', (tester) async {
      await pumpBoard(tester);

      expect(find.text('2 / 3'), findsOneWidget, reason: 'Стройка');
      expect(find.text('0 / 2'), findsOneWidget, reason: 'Дача: blocked is not done');
      expect(find.text('0 / 1'), findsOneWidget, reason: 'Ремонт');
    });

    testWidgets('the current task is the one the server flagged', (tester) async {
      await pumpBoard(tester);

      expect(find.text('Позвонить прорабу'), findsOneWidget);
      expect(find.text('Покрасить забор'), findsOneWidget);

      // Ремонт has nothing but a blocked task, and that reads differently from
      // a finished project.
      expect(find.text('Нет текущей задачи — всё в блокерах'), findsOneWidget);
      expect(find.text('Все задачи сделаны'), findsNothing);
    });

    testWidgets('a due reminder is badged separately from a plain blocker', (
      tester,
    ) async {
      await pumpBoard(tester);

      final today = DateTime.now();
      final dueLabel =
          'Напоминание · ${today.day.toString().padLeft(2, '0')}.'
          '${today.month.toString().padLeft(2, '0')}';

      // Дача: the day has arrived -- the one thing on this screen that asks for
      // action today.
      expect(find.text(dueLabel), findsOneWidget);

      // ...and it still shows as a blocker, without repeating the date.
      expect(find.text('Блокер'), findsOneWidget);

      // Ремонт: blocked, but the date is four days out, so it carries its date
      // on the quiet badge and gets no red one.
      final soon = DateTime.now().add(const Duration(days: 4));
      expect(
        find.text(
          'Блокер · ${soon.day.toString().padLeft(2, '0')}.'
          '${soon.month.toString().padLeft(2, '0')}',
        ),
        findsOneWidget,
      );

      // Стройка has no blocker at all and must not be badged.
      expect(find.textContaining('Блокер'), findsNWidgets(2));
    });

    testWidgets('no stale banner when the data is live', (tester) async {
      await pumpBoard(tester);

      expect(find.text('Данные из кэша'), findsNothing);
      expect(find.text('Не удалось обновить'), findsNothing);
    });

    testWidgets('tapping a project opens the project screen, by id', (
      tester,
    ) async {
      await pumpBoard(tester);

      await tester.tap(find.text('Дача'));
      await settle(tester);

      // The screen is on stage and it was addressed by id, not handed the
      // loaded row -- which is what lets F4 open it from a notification with no
      // board in memory. See `navigation/app_routes.dart`.
      final screen = tester.widget<ProjectScreen>(find.byType(ProjectScreen));
      expect(screen.projectId, 'prj_b');
      expect(screen.highlightTaskId, isNull);

      // ...and it asked the server for that project's own data rather than
      // reusing the board array. (The fake answers every path with the board,
      // so what is on screen after this is not the point; the requests are.)
      expect(
        backend.requests.map((request) => request.path),
        contains('/projects/prj_b/tasks'),
      );
    });

    testWidgets('pull-to-refresh fetches again', (tester) async {
      await pumpBoard(tester);
      expect(backend.requests, hasLength(1));

      await tester.fling(find.text('Стройка'), const Offset(0, 320), 1200);
      await settle(tester);
      await settle(tester);

      expect(backend.requests, hasLength(2));
    });

    testWidgets('the overflow menu reaches the archive and the settings', (
      tester,
    ) async {
      await pumpBoard(tester);

      // F4 moved the bench out of the app bar and into settings, and put the
      // archive and the settings behind one menu -- see the note on
      // `_BoardMenuAction`.
      await tester.tap(find.byTooltip('Ещё'));
      await tester.pumpAndSettle();

      expect(find.text('Архив'), findsOneWidget);
      expect(find.text('Настройки'), findsOneWidget);
      expect(find.text('Выйти'), findsOneWidget);

      await tester.tap(find.text('Настройки'));
      await settle(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text(NotificationBenchScreen.title), findsOneWidget);
    });
  });

  group('an empty board', () {
    testWidgets('says so in words, rather than showing a blank screen', (
      tester,
    ) async {
      backend.alwaysRespond(<dynamic>[]);

      await pumpBoard(tester);

      expect(find.text('Проектов пока нет'), findsOneWidget);
      expect(find.textContaining('Кнопка «Проект»'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('the refresh failed', () {
    testWidgets('with a snapshot: the cached board stays, clearly labelled', (
      tester,
    ) async {
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(sampleBoard()),
        savedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      backend.alwaysFailToConnect();

      await pumpBoard(tester);

      // The rows are there...
      expect(find.text('Стройка'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);

      // ...and so is the fact that they are yesterday's.
      expect(find.text('Не удалось обновить'), findsOneWidget);
      expect(find.textContaining('Нет связи с сервером.'), findsOneWidget);
      expect(find.textContaining('Показан локальный снимок от вчера в'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
    });

    testWidgets('the retry button fetches again', (tester) async {
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(sampleBoard()),
        savedAt: DateTime.now(),
      );
      backend.alwaysFailToConnect();

      await pumpBoard(tester);
      expect(backend.requests, hasLength(1));

      backend.alwaysRespond(sampleBoard());
      await tester.tap(find.text('Повторить'));
      await settle(tester);

      expect(backend.requests, hasLength(2));
      expect(find.text('Не удалось обновить'), findsNothing);
      expect(find.text('Данные из кэша'), findsNothing);
    });

    testWidgets('without a snapshot: an error page, and it says there is no cache', (
      tester,
    ) async {
      backend.alwaysFailToConnect();

      await pumpBoard(tester);

      expect(find.text('Не удалось загрузить доску'), findsOneWidget);
      expect(find.textContaining('Локального снимка тоже нет'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);

      // Not "you have no projects".
      expect(find.text('Проектов пока нет'), findsNothing);
    });

    testWidgets('a server error is worded differently from no connection', (
      tester,
    ) async {
      backend.alwaysRespond(<String, dynamic>{
        'error': 'Internal Server Error',
        'message': 'boom',
      }, statusCode: 500);

      await pumpBoard(tester);

      expect(find.textContaining('Сервер ответил ошибкой 500: boom'), findsOneWidget);
      expect(find.textContaining('Нет связи с сервером'), findsNothing);
    });
  });

  group('desktop layout (F6)', () {
    /// A window wide enough for the column layout.
    ///
    /// Must be called *before* `pumpBoard`: the layout is a function of the
    /// window width, read during build.
    void useDesktopWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('a wide window draws columns instead of cards', (tester) async {
      backend.alwaysRespond(sampleBoard());
      useDesktopWindow(tester);

      await pumpBoard(tester);

      expect(find.byType(ProjectColumn), findsNWidgets(3));
      expect(find.byType(ProjectCard), findsNothing);
    });

    testWidgets('and the default (phone-sized) window still draws cards', (
      tester,
    ) async {
      backend.alwaysRespond(sampleBoard());

      await pumpBoard(tester);

      expect(find.byType(ProjectCard), findsNWidgets(3));
      expect(find.byType(ProjectColumn), findsNothing);
    });

    testWidgets('the line prints the titles worth reading and dots for the rest', (
      tester,
    ) async {
      backend.alwaysRespond(<dynamic>[
        boardProjectJson(
          id: 'prj_line',
          name: 'Дача',
          tasks: <Map<String, dynamic>>[
            taskJson(id: 't1', title: 'Сделано давно', status: 'done'),
            taskJson(id: 't2', title: 'Сейчас', position: 2000, isCurrent: true),
            taskJson(id: 't3', title: 'Потом', position: 3000),
            taskJson(
              id: 't4',
              title: 'Жду кабель',
              status: 'blocked',
              position: 4000,
              remindAt: remindAt(0),
            ),
            taskJson(
              id: 't5',
              title: 'Жду плитку',
              status: 'blocked',
              position: 5000,
              remindAt: remindAt(3),
            ),
            taskJson(
              id: 't6',
              title: 'Жду ответ',
              status: 'blocked',
              position: 6000,
            ),
          ],
        ),
      ]);
      useDesktopWindow(tester);

      await pumpBoard(tester);

      // The current task, and every blocker: the rows that say what is
      // happening here and what it is stuck on.
      expect(find.text('Сейчас'), findsOneWidget);
      expect(find.text('Жду кабель'), findsOneWidget);
      expect(find.text('Жду плитку'), findsOneWidget);
      expect(find.text('Жду ответ'), findsOneWidget);

      // Done and pending-but-not-current are dots, not text -- the rule that
      // keeps a 15-project board glanceable, so it is pinned here.
      expect(find.text('Сделано давно'), findsNothing);
      expect(find.text('Потом'), findsNothing);

      // ...but their titles are still reachable, because this layout only ever
      // renders where there is a mouse.
      expect(find.byTooltip('Сделано давно'), findsOneWidget);
      expect(find.byTooltip('Потом'), findsOneWidget);

      String ddmm(DateTime day) =>
          '${day.day.toString().padLeft(2, '0')}.'
          '${day.month.toString().padLeft(2, '0')}';

      // The day has arrived -- the one thing on this screen that asks for
      // action today -- and it is worded differently from one that has not.
      expect(find.text('проверить · ${ddmm(DateTime.now())}'), findsOneWidget);
      expect(
        find.text(
          'напомнить ${ddmm(DateTime.now().add(const Duration(days: 3)))}',
        ),
        findsOneWidget,
      );

      // A blocker with no date is stuck and will never say so again; the column
      // says that out loud rather than leaving the row merely quiet.
      expect(find.text('без даты'), findsOneWidget);
    });

    testWidgets('a project with no tasks says so rather than drawing an empty column', (
      tester,
    ) async {
      backend.alwaysRespond(<dynamic>[
        boardProjectJson(id: 'prj_empty', name: 'Пустой'),
      ]);
      useDesktopWindow(tester);

      await pumpBoard(tester);

      expect(find.text('Пустой'), findsOneWidget);
      expect(find.text('Задач пока нет'), findsOneWidget);
      // Not the board-level empty state: there *is* a project here.
      expect(find.text('Проектов пока нет'), findsNothing);
    });

    testWidgets('clicking a column opens that project, by id', (tester) async {
      backend.alwaysRespond(sampleBoard());
      useDesktopWindow(tester);

      await pumpBoard(tester);

      await tester.tap(find.text('Дача'));
      await settle(tester);

      final screen = tester.widget<ProjectScreen>(find.byType(ProjectScreen));
      expect(screen.projectId, 'prj_b');
    });

    testWidgets('the desktop board has a refresh button and it refetches', (
      tester,
    ) async {
      backend.alwaysRespond(sampleBoard());
      useDesktopWindow(tester);

      await pumpBoard(tester);
      expect(backend.requests, hasLength(1));

      // A mouse cannot pull to refresh; without this button the desktop board
      // could only be refreshed by restarting the app.
      await tester.tap(find.byTooltip('Обновить'));
      await settle(tester);

      expect(backend.requests, hasLength(2));
    });

    testWidgets('no refresh button at phone width', (tester) async {
      backend.alwaysRespond(sampleBoard());

      await pumpBoard(tester);

      expect(find.byTooltip('Обновить'), findsNothing);
    });

    testWidgets('long names and titles do not overflow a column', (
      tester,
    ) async {
      // The desktop counterpart of the phone guard below. The columns are sized
      // to fill the window, so the narrowest one this layout can produce is
      // ~260px -- narrower than a phone card, with the same text in it.
      useDesktopWindow(tester);

      backend.alwaysRespond(<dynamic>[
        for (var i = 0; i < 5; i++)
          boardProjectJson(
            id: 'prj_$i',
            name:
                'Очень длинное название проекта, которое точно не влезает в '
                'одну строку в колонке',
            tasks: <Map<String, dynamic>>[
              taskJson(id: 'w${i}0', status: 'done'),
              taskJson(
                id: 'w${i}1',
                title:
                    'Очень длинный заголовок текущей задачи, который тоже не '
                    'влезает и должен быть обрезан, а не сломать вёрстку',
                position: 2000,
                isCurrent: true,
              ),
              taskJson(
                id: 'w${i}2',
                title:
                    'Очень длинный заголовок заблокированной задачи, который '
                    'тоже должен быть обрезан',
                status: 'blocked',
                position: 3000,
                remindAt: remindAt(0),
              ),
            ],
          ),
      ]);

      await pumpBoard(tester);

      expect(find.byType(ProjectColumn), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });
  });

  group('phone-sized layout', () {
    // The closest thing to the visual check a person has to do by hand: at
    // 375x812 with text that is far too long, nothing may overflow. A
    // RenderFlex overflow fails this test through the framework's error
    // reporter, which is the only overflow detector available without a device.
    testWidgets('long names and titles do not overflow a 375x812 screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      backend.alwaysRespond(<dynamic>[
        boardProjectJson(
          id: 'prj_long',
          name: 'Очень длинное название проекта, которое точно не влезает в '
              'одну строку на телефоне',
          tasks: <Map<String, dynamic>>[
            taskJson(id: 'l0', status: 'done'),
            taskJson(
              id: 'l1',
              title: 'Очень длинный заголовок текущей задачи, который тоже не '
                  'влезает и должен быть обрезан, а не сломать вёрстку',
              isCurrent: true,
            ),
            taskJson(
              id: 'l2',
              title: 'Блокер',
              status: 'blocked',
              remindAt: remindAt(0),
            ),
            taskJson(
              id: 'l3',
              title: 'Второй блокер',
              status: 'blocked',
              remindAt: remindAt(3),
            ),
          ],
        ),
      ]);

      await pumpBoard(tester);

      expect(find.text('1 / 4'), findsOneWidget);
      expect(find.text('Блокеров: 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('showing the snapshot while the refresh is still running', () {
    testWidgets('cached rows appear first, then the fresh ones replace them', (
      tester,
    ) async {
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(<dynamic>[
          boardProjectJson(
            id: 'prj_old',
            name: 'Вчерашний проект',
            tasks: <Map<String, dynamic>>[
              taskJson(id: 'o1', title: 'Вчерашняя задача', isCurrent: true),
            ],
          ),
        ]),
        savedAt: DateTime.now(),
      );

      final inFlight = Completer<ResponseBody>();
      backend.responder = (_) => inFlight.future;

      await pumpBoard(tester);

      expect(find.text('Вчерашний проект'), findsOneWidget);
      expect(find.text('Вчерашняя задача'), findsOneWidget);
      expect(find.text('Данные из кэша'), findsOneWidget);
      expect(
        find.byType(LinearProgressIndicator),
        findsWidgets,
        reason: 'the app bar hairline says a refresh is running',
      );

      inFlight.complete(jsonResponse(sampleBoard()));
      await settle(tester);

      expect(find.text('Вчерашний проект'), findsNothing);
      expect(find.text('Стройка'), findsOneWidget);
      expect(find.text('Данные из кэша'), findsNothing);
    });
  });
}
