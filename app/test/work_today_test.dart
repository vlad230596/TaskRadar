import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminders.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/screens/work_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/today/next_sheet.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// «С прошлых дней», «Сегодня» and the date actions of rows
/// (`design/today-history-contract.md`, «Правила интерфейса»): what each
/// button sends, and what the screen shows after. The look is checked by
/// `zz_capture_today_test.dart`.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late String dom;
  late String stands;

  String day(int offset) =>
      calendarDateForApi(DateTime.now().add(Duration(days: offset)));
  String stored(int offset) => '${day(offset)}T00:00:00.000Z';

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    dom = server.addProject(name: 'Дом', id: 'prj_dom');
    stands = server.addProject(name: 'Стенды', id: 'prj_st');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpHome(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
          notificationGatewayProvider.overrideWithValue(
            FakeNotificationGateway(),
          ),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpWork(WidgetTester tester) =>
      pumpHome(tester, const Scaffold(body: WorkScreen()));

  Map<String, dynamic> row(String id) =>
      server.tasks.firstWhere((task) => task['id'] == id);

  group('«С прошлых дней»', () {
    testWidgets('lists open tasks dated before today, oldest first', (
      tester,
    ) async {
      server.addTask(
        projectId: dom,
        title: 'Позвонить в ЖЭК',
        id: 'old',
        remindAt: stored(-3),
      );
      server.addTask(
        projectId: stands,
        title: 'Скинуть Лене презентацию',
        id: 'yday',
        remindAt: stored(-1),
      );
      await pumpWork(tester);

      expect(find.text('С прошлых дней'), findsOneWidget);
      expect(find.textContaining('3 дн. назад'), findsOneWidget);
      expect(find.textContaining('вчера'), findsOneWidget);
      final first = tester.getTopLeft(find.text('Позвонить в ЖЭК')).dy;
      final second = tester
          .getTopLeft(find.text('Скинуть Лене презентацию'))
          .dy;
      expect(first, lessThan(second));
    });

    testWidgets('«Сегодня» moves one task to today and drops its time', (
      tester,
    ) async {
      server.addTask(
        projectId: dom,
        title: 'Позвонить в ЖЭК',
        id: 'old',
        remindAt: stored(-3),
        remindTime: '09:00',
      );
      await pumpWork(tester);

      await tester.tap(find.byKey(const ValueKey<String>('tail-today-old')));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{
        'remindAt': day(0),
        'remindTime': null,
      });
      expect(find.text('С прошлых дней'), findsNothing);
      expect(find.text('0 из 1'), findsOneWidget);
      expect(find.text('На сегодня'), findsOneWidget);

      // «Отменить» gives the date and the time back.
      await tester.tap(find.text('Отменить'));
      await settle(tester);
      expect(row('old')['remindAt'], stored(-3));
      expect(row('old')['remindTime'], '09:00');
    });

    testWidgets('«Все в сегодня» moves each one, and the undo each back', (
      tester,
    ) async {
      server.addTask(projectId: dom, title: 'А', id: 'a', remindAt: stored(-3));
      server.addTask(projectId: dom, title: 'Б', id: 'b', remindAt: stored(-1));
      await pumpWork(tester);

      await tester.tap(find.text('Все в сегодня'));
      await settle(tester);
      expect(row('a')['remindAt'], stored(0));
      expect(row('b')['remindAt'], stored(0));
      expect(find.text('2 задачи на сегодня'), findsOneWidget);

      await tester.tap(find.text('Отменить'));
      await settle(tester);
      expect(row('a')['remindAt'], stored(-3));
      expect(row('b')['remindAt'], stored(-1));
    });

    testWidgets('«⋯ → В стопку» takes the date off; the task stays', (
      tester,
    ) async {
      server.addTask(projectId: dom, title: 'А', id: 'a', remindAt: stored(-2));
      await pumpWork(tester);

      await tester.tap(find.byTooltip('Ещё'));
      await settle(tester);
      expect(find.text('снять дату, останется в проекте'), findsOneWidget);
      await tester.tap(find.text('В стопку'));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{'remindAt': null});
      expect(row('a')['status'], 'pending');
      expect(find.text('В стопке'), findsOneWidget);
    });

    testWidgets('more than four folds to three and «Ещё N»', (tester) async {
      for (var i = 0; i < 6; i++) {
        server.addTask(
          projectId: dom,
          title: 'Хвост $i',
          remindAt: stored(-10 + i),
        );
      }
      await pumpWork(tester);

      expect(find.text('Хвост 0'), findsOneWidget);
      expect(find.text('Хвост 3'), findsNothing);
      await tester.tap(find.text('Ещё 3'));
      await settle(tester);
      expect(find.text('Хвост 5'), findsOneWidget);
    });
  });

  group('«Сегодня»', () {
    testWidgets('«N из M», scopes not headed with one scope, empty state', (
      tester,
    ) async {
      await pumpWork(tester);
      expect(find.text('На сегодня ничего'), findsOneWidget);
    });

    testWidgets('counts today and closed today; timed first', (tester) async {
      server.addTask(projectId: dom, title: 'Без времени', remindAt: stored(0));
      server.addTask(
        projectId: dom,
        title: 'Встретить курьера',
        remindAt: stored(0),
        remindTime: '15:00',
      );
      server.addTask(
        projectId: dom,
        title: 'Отправить акт',
        id: 'done',
        status: 'done',
        remindAt: stored(0),
      );
      row('done')['doneAt'] = DateTime.now().toUtc().toIso8601String();
      // Closed today with no date: not part of «Сегодня» (answer 5).
      server.addTask(projectId: dom, title: 'Без даты', status: 'done');
      await pumpWork(tester);

      expect(find.text('1 из 3'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      final timed = tester.getTopLeft(find.text('Встретить курьера')).dy;
      final free = tester.getTopLeft(find.text('Без времени')).dy;
      expect(timed, lessThan(free));
      expect(find.text('Отправить акт'), findsOneWidget);
      expect(find.text('Без даты'), findsNothing);
    });

    testWidgets('the ring closes it; «Следом…» makes a follow-up', (
      tester,
    ) async {
      server.addTask(
        projectId: dom,
        title: 'Купить батарейки',
        id: 'b',
        remindAt: stored(0),
      );
      await pumpWork(tester);

      await tester.tap(find.byTooltip('Отметить сделанной'));
      await settle(tester);
      expect(row('b')['status'], 'done');
      // The date stays with the closing.
      expect(row('b')['remindAt'], stored(0));
      expect(find.text('1 из 1'), findsOneWidget);
      expect(find.textContaining('Сделано: Купить батарейки'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('snack-next')));
      await settle(tester);
      expect(find.byType(NextSheet), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Проверить пульт');
      await tester.pump();
      await tester.tap(find.text('Создать'));
      await settle(tester);

      final made = server.tasks.firstWhere(
        (task) => task['title'] == 'Проверить пульт',
      );
      expect(made['projectId'], dom);
      // «через неделю» by default.
      expect(made['remindAt'] as String, startsWith(day(7)));
    });

    testWidgets('a blocker: «Разблокировать» keeps the date', (tester) async {
      server.addTask(
        projectId: stands,
        title: 'Поговорить с Васей',
        id: 'v',
        status: 'blocked',
        remindAt: stored(0),
      );
      await pumpWork(tester);

      expect(find.text('проверить'), findsOneWidget);
      // A tap on the lock does not close a waiting task.
      await tester.tap(find.text('Разблокировать'));
      await settle(tester);
      expect(server.patches.last.body, <String, dynamic>{'status': 'pending'});
      expect(row('v')['remindAt'], stored(0));
      expect(find.text('Разблокирована'), findsOneWidget);
    });

    testWidgets('a blocker: «Ещё ждём…» picks when to check again', (
      tester,
    ) async {
      server.addTask(
        projectId: stands,
        title: 'Поговорить с Васей',
        id: 'v',
        status: 'blocked',
        remindAt: stored(0),
      );
      await pumpWork(tester);

      await tester.tap(find.text('Ещё ждём…'));
      await tester.pumpAndSettle();
      expect(find.text('Когда проверить снова'), findsOneWidget);
      await tester.tap(find.text('Завтра'));
      await settle(tester);

      expect(row('v')['remindAt'], stored(1));
      expect(row('v')['status'], 'blocked');
      expect(find.text('Поговорить с Васей'), findsNothing);
    });

    testWidgets('a task of the set dated today is only in «Сегодня»', (
      tester,
    ) async {
      server.addTask(
        projectId: stands,
        title: 'Собрать стенд',
        id: 'head',
        focused: true,
      );
      server.addTask(
        projectId: stands,
        title: 'Спроектировать экран',
        id: 'today',
        remindAt: stored(0),
        focused: true,
      );
      await pumpWork(tester);

      // Once, in «Сегодня», with the «в работе» dot; the big card is the
      // other one.
      expect(find.text('Спроектировать экран'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('today-in-work')),
        findsOneWidget,
      );
      expect(find.text('Собрать стенд'), findsOneWidget);
    });
  });

  group('a project', () {
    testWidgets('the date label and «Позже: N» folded at the bottom', (
      tester,
    ) async {
      server.addTask(projectId: dom, title: 'Сейчас', remindAt: stored(1));
      server.addTask(projectId: dom, title: 'Далеко', remindAt: stored(40));
      server.addTask(
        projectId: dom,
        title: 'Ждём далеко',
        status: 'blocked',
        remindAt: stored(30),
      );
      await pumpHome(tester, ProjectScreen(projectId: dom));

      expect(find.textContaining('завтра'), findsOneWidget);
      expect(find.text('Далеко'), findsNothing);
      expect(find.text('Ждём далеко'), findsNothing);
      expect(find.text('Позже · '), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      await tester.tap(find.text('Позже · '));
      await settle(tester);
      expect(find.text('ПОЗЖЕ · 2'), findsOneWidget);
      expect(find.text('Далеко'), findsOneWidget);
      expect(find.text('Ждём далеко'), findsOneWidget);
    });

    testWidgets('a swipe gives «Сегодня» and «Завтра»', (tester) async {
      server.addTask(projectId: dom, title: 'Купить лампочки', id: 'l');
      await pumpHome(tester, ProjectScreen(projectId: dom));

      await tester.drag(find.text('Купить лампочки'), const Offset(-140, 0));
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('swipe-tomorrow')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('swipe-tomorrow')));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{
        'remindAt': day(1),
        'remindTime': null,
      });
      expect(find.text('На завтра'), findsOneWidget);
    });

    testWidgets('a full swipe is «Сегодня» at once', (tester) async {
      server.addTask(projectId: dom, title: 'Купить лампочки', id: 'l');
      await pumpHome(tester, ProjectScreen(projectId: dom));

      await tester.drag(find.text('Купить лампочки'), const Offset(-330, 0));
      await settle(tester);
      expect(row('l')['remindAt'], stored(0));
    });

    testWidgets('the long press menu has the date block', (tester) async {
      server.addTask(
        projectId: dom,
        title: 'Купить лампочки',
        id: 'l',
        remindAt: stored(3),
      );
      await pumpHome(tester, ProjectScreen(projectId: dom));

      await tester.longPress(find.byTooltip('Отметить сделанной'));
      await settle(tester);
      expect(find.text('Сегодня'), findsOneWidget);
      expect(find.text('Завтра'), findsOneWidget);
      expect(find.text('Дата…'), findsOneWidget);
      await tester.tap(find.text('Снять дату'));
      await settle(tester);
      expect(server.patches.last.body, <String, dynamic>{'remindAt': null});
    });
  });
}
