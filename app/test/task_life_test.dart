import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/history_task_event.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/task_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/theme/tokens.dart';
import 'package:taskradar/widgets/history_charts.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';
import 'support/fake_project_backend.dart';

/// Блок «жизнь задачи» на экране задачи, на настоящем журнале (F13).
///
/// Остальной экран задачи принят в F12 и здесь не проверяется — на него есть
/// `project_screen_test.dart`. Проверяется ровно то, что изменилось: откуда
/// берётся разбивка и что происходит с блоком, когда журнала нет.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeHistoryBackend history;
  late String projectId;
  late String taskId;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    // После проектного фейка: `/tasks/:id/events` не пересекается с его
    // маршрутами, но порядок регистрации — часть контракта `FakeBackend`.
    history = FakeHistoryBackend(backend);

    projectId = server.addProject(name: 'Дом', id: 'prj_dom');
    taskId = server.addTask(
      projectId: projectId,
      id: 'tsk_vent',
      title: 'Посмотреть, почему не работает вентилятор',
      status: 'blocked',
    );
    history.events[taskId] = history.sampleJournal(taskId);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpTask(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TaskScreen(projectId: projectId, taskId: taskId),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('разбивка по фазам берётся из журнала', (tester) async {
    await pumpTask(tester);

    expect(find.text('ЖИЗНЬ ЗАДАЧИ'), findsOneWidget);
    // Восемь дней жизни: четыре в очереди, один в работе, три в блокере.
    expect(find.text('8 дней'), findsOneWidget);
    expect(find.text('лежала в очереди'), findsOneWidget);
    expect(find.text('была в работе'), findsOneWidget);
    expect(find.text('4 д'), findsOneWidget);
    expect(find.text('1 д'), findsOneWidget);
    expect(find.text('3 д'), findsOneWidget);
  });

  testWidgets('текущая фаза подписана датой, с которой идёт', (tester) async {
    await pumpTask(tester);

    final since = DateTime.now().subtract(const Duration(days: 3));
    final stamp =
        '${since.day.toString().padLeft(2, '0')}.'
        '${since.month.toString().padLeft(2, '0')}';

    expect(find.text('ждёт с $stamp'), findsOneWidget);
    // Прошедшие фазы — прошедшим временем, без даты.
    expect(find.text('ждала'), findsNothing);
  });

  testWidgets('полоска состоит из тех же трёх цветов', (tester) async {
    await pumpTask(tester);

    final bar = find.descendant(
      of: find.byType(SpanBar),
      matching: find.byType(ColoredBox),
    );
    final colours = tester
        .widgetList<ColoredBox>(bar)
        .map((box) => box.color)
        .toList();

    expect(colours, contains(AppColors.lineStrong));
    expect(colours, contains(AppColors.indigoLink));
    expect(colours, contains(AppColors.waitingDot));
    expect(colours, isNot(contains(AppColors.done)));
  });

  testWidgets('задача без событий всё равно получает свою жизнь целиком', (
    tester,
  ) async {
    history.events[taskId] = const <dynamic>[];
    await pumpTask(tester);

    // Журнал пуст — вся жизнь принадлежит нынешнему статусу, и блок это
    // показывает, а не прячется.
    expect(find.text('ЖИЗНЬ ЗАДАЧИ'), findsOneWidget);
    expect(find.textContaining('ждёт с '), findsOneWidget);
    expect(find.text('лежала в очереди'), findsNothing);
  });

  testWidgets('пока журнал едет — блок говорит, что считает', (tester) async {
    final inFlight = Completer<ResponseBody>();
    // Свой фейк, а не подмена маршрута в общем: маршруты `FakeBackend`
    // пробуются в порядке регистрации, так что перекрыть уже зарегистрированный
    // нельзя — его можно только не регистрировать.
    final rerouted = FakeBackend();
    FakeProjectBackend(rerouted)
      ..addProject(name: 'Дом', id: projectId)
      ..addTask(projectId: projectId, id: taskId, title: 'x', status: 'blocked');
    rerouted.on('GET', '/tasks/:id/events', (_) => inFlight.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(rerouted.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TaskScreen(projectId: projectId, taskId: taskId),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);

    expect(find.text('ЖИЗНЬ ЗАДАЧИ'), findsOneWidget);
    expect(find.textContaining('Считаем по журналу'), findsOneWidget);

    inFlight.complete(jsonResponse(const <dynamic>[]));
    await settle(tester);
  });

  testWidgets('журнал не прочитался — сказано об этом, экран рабочий', (
    tester,
  ) async {
    backend.failingPaths.add('/events');
    await pumpTask(tester);

    expect(find.text('ЖИЗНЬ ЗАДАЧИ'), findsOneWidget);
    expect(find.textContaining('не прочитался'), findsOneWidget);
    // Остальное на месте: поле, статусы, «Сохранить».
    expect(find.widgetWithText(FilledButton, 'Сохранить'), findsOneWidget);
    expect(find.text('Блокер'), findsOneWidget);
  });

  test('фазы и подписи разведены по времени', () {
    expect(phaseLabel(TaskLifePhase.queued), 'лежала в очереди');
    expect(phaseLabel(TaskLifePhase.working), 'была в работе');
    expect(phaseColour(TaskLifePhase.done), AppColors.done);
    expect(TaskStatus.values, contains(TaskStatus.blocked));
  });
}
