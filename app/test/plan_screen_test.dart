import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/notification_bench_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/screens/settings_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/glance.dart';
import 'package:taskradar/widgets/mode_navigation.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fixtures.dart';

/// The planning mode (F12), which is what the board screen became.
///
/// These assert on rendered text rather than on widget types wherever the text
/// is the point -- a counter that says "1 / 3" when it should say "2 / 3" is a
/// product bug with no type error anywhere near it.
///
/// The one structural assertion that is not about text is the age chip. The
/// spec pins it as "не переносится и не сжимается" *because it already broke on
/// a phone*, and the only way to state that is to measure it next to a name
/// long enough to squeeze it.
void main() {
  late FakeBackend backend;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;
  late FakeSettingsStore settings;

  setUp(() {
    backend = FakeBackend();
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();
    settings = FakeSettingsStore();
  });

  /// `pumpAndSettle` cannot be used on this screen: both the loading spinner
  /// and the "refreshing" hairline animate forever, so it would time out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// How many times the board itself was fetched.
  ///
  /// Counted by path rather than as "every request the screen made": the shell
  /// also reads `GET /scopes` and `GET /inbox`, and a test about refreshing the
  /// board should not have to know that.
  int boardReads() =>
      backend.requests.where((request) => request.path == '/board').length;

  /// Holds `GET /board` open, while the other two answer immediately.
  ///
  /// Hanging *every* request would leave them pending at teardown, and the test
  /// would fail on a stray dio timeout timer rather than on anything it is
  /// about.
  void holdBoardOpen(Completer<ResponseBody> inFlight) {
    backend.responder = (options) {
      if (options.path.startsWith('/scopes')) {
        return jsonResponse(defaultScopesJson());
      }
      if (options.path.startsWith('/inbox')) {
        return jsonResponse(const <dynamic>[]);
      }
      return inFlight.future;
    };
  }

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(snapshots),
          // The planning mode brings the reminder bridge up, which initialises
          // the notification plugin. The real one degrades gracefully in the
          // test VM, but only the fake keeps these tests from depending on
          // that.
          notificationGatewayProvider.overrideWithValue(gateway),
          // The mode, the layout and the reminder hour are all persisted; the
          // real store is a `shared_preferences` platform channel the test VM
          // does not have.
          settingsStoreProvider.overrideWithValue(settings),
        ],
        // `onGenerateRoute` as well as `home`, matching `app.dart`: a project
        // row pushes a named route, and without the generator a tap would throw
        // instead of navigating.
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ShellScreen(),
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

  /// An ISO instant [days] ago, for a project's `updatedAt` -- i.e. its age.
  String daysAgo(int days) =>
      DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

  /// A three-project board covering the interesting shapes at once: a moving
  /// project, one stuck on a reminder that has come due, and one stuck on a
  /// reminder that has not.
  List<dynamic> sampleBoard() => <dynamic>[
    boardProjectJson(
      id: 'prj_a',
      name: 'Стройка',
      updatedAt: daysAgo(1),
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
      updatedAt: daysAgo(5),
      tasks: <Map<String, dynamic>>[
        taskJson(
          id: 'b1',
          title: 'Жду кабель',
          status: 'blocked',
          position: 1000,
          remindAt: remindAt(0),
        ),
        taskJson(
          id: 'b2',
          title: 'Покрасить забор',
          position: 2000,
          isCurrent: true,
        ),
      ],
    ),
    boardProjectJson(
      id: 'prj_c',
      name: 'Ремонт',
      updatedAt: daysAgo(2),
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
    testWidgets('with no snapshot, the screen says it is loading', (
      tester,
    ) async {
      final inFlight = Completer<ResponseBody>();
      holdBoardOpen(inFlight);

      await pumpShell(tester);

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

    testWidgets('renders one row per project, in server order', (tester) async {
      await pumpShell(tester);

      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((data) => <String>['Стройка', 'Дача', 'Ремонт'].contains(data))
          .toList();
      expect(names, <String>['Стройка', 'Дача', 'Ремонт']);
    });

    testWidgets('the counter counts done against total', (tester) async {
      await pumpShell(tester);

      expect(find.text('2 / 3'), findsOneWidget, reason: 'Стройка');
      expect(
        find.text('0 / 2'),
        findsOneWidget,
        reason: 'Дача: blocked is not done',
      );
      expect(find.text('0 / 1'), findsOneWidget, reason: 'Ремонт');
    });

    testWidgets('the current task is the one the server flagged', (
      tester,
    ) async {
      await pumpShell(tester);

      expect(find.text('Позвонить прорабу'), findsOneWidget);
      expect(find.text('Покрасить забор'), findsOneWidget);

      // Ремонт has nothing but a blocked task, and that reads differently from
      // a finished project.
      expect(find.text('всё ждёт'), findsOneWidget);
      expect(find.text('всё сделано'), findsNothing);
    });

    testWidgets('the age is a number plus a colour, not a sentence', (
      tester,
    ) async {
      await pumpShell(tester);

      // "меньше текста, больше графики". One day and two days are ordinary;
      // five has gone past `kStaleAfterDays` and reads warm.
      expect(find.text('1 д'), findsOneWidget);
      expect(find.text('2 д'), findsOneWidget);
      expect(find.text('5 д'), findsOneWidget);
      expect(find.text('5 дней'), findsNothing);
    });

    testWidgets('the age chip neither wraps nor shrinks next to a long name', (
      tester,
    ) async {
      // The rule the spec states twice, because it already broke on a phone. A
      // `Row` will take space from an inflexible child to satisfy a flexible
      // one, which turns "12 д" into a two-line chip and the row into 40 px.
      backend.alwaysRespond(<dynamic>[
        boardProjectJson(
          id: 'prj_long',
          name: 'Ремонт ванной, кухни и коридора — длинное название проекта',
          updatedAt: daysAgo(12),
          tasks: <Map<String, dynamic>>[
            taskJson(id: 'x1', title: 'Задача', isCurrent: true),
          ],
        ),
      ]);

      await pumpShell(tester);

      final chip = find.byType(AgeChip);
      expect(chip, findsOneWidget);
      // The full number, on one line, at the height the chip is specified as.
      expect(find.text('12 д'), findsOneWidget);
      expect(tester.getSize(chip).height, 22);
      // And the layout survived it: an overflow would have been recorded here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('no stale banner when the data is live', (tester) async {
      await pumpShell(tester);

      expect(find.text('Данные из кэша'), findsNothing);
      expect(find.text('Не удалось обновить'), findsNothing);
    });

    testWidgets('tapping a project opens the project screen, by id', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.text('Дача'));
      await settle(tester);

      // The screen is on stage and it was addressed by id, not handed the
      // loaded row -- which is what lets F4 open it from a notification with no
      // board in memory. See `navigation/app_routes.dart`.
      final screen = tester.widget<ProjectScreen>(find.byType(ProjectScreen));
      expect(screen.projectId, 'prj_b');
      expect(screen.highlightTaskId, isNull);

      expect(
        backend.requests.map((request) => request.path),
        contains('/projects/prj_b/tasks'),
      );
    });

    testWidgets('pull-to-refresh fetches again', (tester) async {
      await pumpShell(tester);
      expect(boardReads(), 1);

      await tester.fling(find.text('Стройка'), const Offset(0, 320), 1200);
      await settle(tester);
      await settle(tester);

      expect(boardReads(), 2);
    });

    testWidgets('the overflow menu reaches the archive and the settings', (
      tester,
    ) async {
      // The reference has no settings entry on a phone at all. It still has to
      // be reachable -- see `ShellOverflowButton`.
      await pumpShell(tester);

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

  group('list or tiles', () {
    setUp(() => backend.alwaysRespond(sampleBoard()));

    testWidgets('the list is what a fresh install opens with', (tester) async {
      await pumpShell(tester);

      // The list prints each project's current task; the tile prints a badge
      // letter instead.
      expect(find.text('Позвонить прорабу'), findsOneWidget);
      expect(find.byType(ProjectBadge), findsNothing);
    });

    testWidgets('the toggle swaps to tiles, badge and all', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.byTooltip('Значками'));
      await settle(tester);

      // One badge per project. The sandbox tile has an icon rather than a
      // letter, so it is not counted here.
      expect(find.byType(ProjectBadge), findsNWidgets(3));
      // The letter is the project's first, upper-cased.
      expect(find.text('С'), findsOneWidget);
      expect(find.text('Д'), findsOneWidget);
      expect(find.text('Р'), findsOneWidget);
    });

    testWidgets('the same name always gets the same colour', (tester) async {
      // The whole value of the badge is that "Дача" is the same colour every
      // morning. `String.hashCode` is seeded randomly per run and would not be.
      await pumpShell(tester);
      await tester.tap(find.byTooltip('Значками'));
      await settle(tester);

      Color colourOf(String letter) {
        final badge = tester.widget<Container>(
          find.ancestor(
            of: find.text(letter),
            matching: find.byType(Container),
          ).first,
        );
        return (badge.decoration! as BoxDecoration).color!;
      }

      expect(colourOf('Д'), colourOf('Д'));
      expect(colourOf('С'), isNot(colourOf('Д')));
    });

    testWidgets('the choice is remembered', (tester) async {
      // Equal layouts, says the spec -- so a toggle that reset every launch
      // would be the app insisting the list is the real one.
      await pumpShell(tester);

      await tester.tap(find.byTooltip('Значками'));
      await settle(tester);

      expect(settings.layoutWrites, <String>['tiles']);
      expect(settings.planLayout, 'tiles');
    });

    testWidgets('and restored on the next launch', (tester) async {
      settings.planLayout = 'tiles';

      await pumpShell(tester);

      expect(find.byType(ProjectBadge), findsNWidgets(3));
    });

    testWidgets('an unknown stored layout falls back to the list', (
      tester,
    ) async {
      // A value written by a future build, or a hand-edited preferences file.
      settings.planLayout = 'carousel';

      await pumpShell(tester);

      expect(find.byType(ProjectBadge), findsNothing);
    });
  });

  group('an empty board', () {
    testWidgets('says so in words, rather than showing a blank screen', (
      tester,
    ) async {
      backend.alwaysRespond(<dynamic>[]);

      await pumpShell(tester);

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

      await pumpShell(tester);

      // The rows are there...
      expect(find.text('Стройка'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);

      // ...and so is the fact that they are yesterday's.
      expect(find.text('Не удалось обновить'), findsOneWidget);
      expect(find.textContaining('Нет связи с сервером.'), findsOneWidget);
      expect(
        find.textContaining('Показан локальный снимок от вчера в'),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsOneWidget);
    });

    testWidgets('the retry button fetches again', (tester) async {
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(sampleBoard()),
        savedAt: DateTime.now(),
      );
      backend.alwaysFailToConnect();

      await pumpShell(tester);
      expect(boardReads(), 1);

      backend.alwaysRespond(sampleBoard());
      await tester.tap(find.text('Повторить'));
      await settle(tester);

      expect(boardReads(), 2);
      expect(find.text('Не удалось обновить'), findsNothing);
      expect(find.text('Данные из кэша'), findsNothing);
    });

    testWidgets('without a snapshot: an error page saying there is no cache', (
      tester,
    ) async {
      backend.alwaysFailToConnect();

      await pumpShell(tester);

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

      await pumpShell(tester);

      expect(
        find.textContaining('Сервер ответил ошибкой 500: boom'),
        findsOneWidget,
      );
      expect(find.textContaining('Нет связи с сервером'), findsNothing);
    });
  });

  group('the desktop', () {
    /// A window wide enough for the rail.
    ///
    /// Must be called *before* `pumpShell`: the layout is a function of the
    /// window width, read during build.
    void useDesktopWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('a wide window draws the rail instead of the bar', (
      tester,
    ) async {
      backend.alwaysRespond(sampleBoard());
      useDesktopWindow(tester);

      await pumpShell(tester);

      expect(find.byType(ModeRail), findsOneWidget);
      expect(find.byType(ModeBar), findsNothing);
      // The rail's history item is the short label; the bar's is the long one.
      expect(find.text('Итоги'), findsOneWidget);
    });

    testWidgets('and a phone-sized window draws the bar', (tester) async {
      backend.alwaysRespond(sampleBoard());

      await pumpShell(tester);

      expect(find.byType(ModeBar), findsOneWidget);
      expect(find.byType(ModeRail), findsNothing);
      expect(find.text('История'), findsOneWidget);
    });
  });
}
