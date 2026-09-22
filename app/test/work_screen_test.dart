import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/pick_screen.dart';
import 'package:taskradar/screens/work_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// Режим работы (F13): набор, который пришёл с сервера, и три действия над ним.
///
/// Проверяется поведение, а не вёрстка: какая задача оказалась крупной, что
/// «Сделано» действительно закрывает задачу *и* выводит её из набора одним
/// запросом, и что «Убрать» статуса не трогает. Размеры и цвета сверяются
/// снимками (`zz_capture_work_test.dart`) против `design/reference/Focus.html`
/// — здесь их проверять нечем.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late String dom;
  late String tr;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    dom = server.addProject(name: 'Дом', id: 'prj_dom');
    tr = server.addProject(name: 'TaskRadar', id: 'prj_tr');
  });

  /// `pumpAndSettle` здесь не годится по той же причине, что и на доске:
  /// спиннер загрузки крутится вечно.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpWork(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(FakeBoardSnapshotStore()),
          notificationGatewayProvider.overrideWithValue(
            FakeNotificationGateway(),
          ),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: WorkScreen()),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  int requestsTo(String method, String path) => backend.requests
      .where(
        (request) =>
            request.method.toUpperCase() == method && request.path == path,
      )
      .length;

  Map<String, dynamic> taskRow(String id) =>
      server.tasks.firstWhere((task) => task['id'] == id);

  testWidgets('набор рисуется в серверном порядке: первая крупно, остальные следом', (
    tester,
  ) async {
    server.addTask(
      projectId: dom,
      title: 'Вызвать курьера из Яндекс Маркета.',
      id: 't1',
      focused: true,
    );
    server.addTask(
      projectId: tr,
      title: 'Потестить диктовку на телефоне',
      id: 't2',
      focused: true,
    );

    await pumpWork(tester);

    expect(find.text('Вызвать курьера из Яндекс Маркета.'), findsOneWidget);
    // Чип проекта у крупной задачи и подпись у той, что следом.
    expect(find.text('Дом'), findsOneWidget);
    expect(find.text('Потестить диктовку на телефоне'), findsOneWidget);
    expect(find.text('TaskRadar'), findsOneWidget);
    // Кнопка «Сделано» ровно одна: крупная задача одна.
    expect(find.text('Сделано'), findsOneWidget);
    expect(find.text('ДАЛЬШЕ'), findsOneWidget);
  });

  testWidgets('крупно — первая задача, которой можно заняться, а не блокер', (
    tester,
  ) async {
    server.addTask(
      projectId: dom,
      title: 'Ждёт ответа УК',
      id: 't1',
      status: 'blocked',
      focused: true,
    );
    server.addTask(
      projectId: dom,
      title: 'Вызвать курьера',
      id: 't2',
      focused: true,
    );

    await pumpWork(tester);

    // Блокер остался в наборе (сервер его оттуда не выводит), но крупный слот
    // занят тем, что сейчас можно сделать.
    expect(find.text('Ждёт ответа УК'), findsOneWidget);
    expect(find.text('Вызвать курьера'), findsOneWidget);

    final head = tester.getTopLeft(find.text('Вызвать курьера'));
    final next = tester.getTopLeft(find.text('Ждёт ответа УК'));
    expect(head.dy, lessThan(next.dy));
  });

  testWidgets('«Сделано» закрывает задачу и выводит её из набора одним запросом', (
    tester,
  ) async {
    server.addTask(
      projectId: dom,
      title: 'Вызвать курьера',
      id: 't1',
      focused: true,
    );
    server.addTask(
      projectId: tr,
      title: 'Потестить диктовку',
      id: 't2',
      focused: true,
    );

    await pumpWork(tester);
    await tester.tap(find.text('Сделано'));
    await settle(tester);

    expect(taskRow('t1')['status'], 'done');
    // Вышла из набора сама, вторым запросом её никто не убирал.
    expect(taskRow('t1')['focusedAt'], isNull);
    expect(requestsTo('DELETE', '/tasks/t1/focus'), 0);

    // На экране осталась следующая, и уже крупно.
    expect(find.text('Вызвать курьера'), findsNothing);
    expect(find.text('Потестить диктовку'), findsOneWidget);
    expect(find.text('ДАЛЬШЕ'), findsNothing);
  });

  testWidgets('«Убрать» выводит задачу из набора, не трогая её статус', (
    tester,
  ) async {
    server.addTask(
      projectId: dom,
      title: 'Вызвать курьера',
      id: 't1',
      focused: true,
    );

    await pumpWork(tester);
    await tester.tap(find.text('Убрать'));
    await settle(tester);

    expect(requestsTo('DELETE', '/tasks/t1/focus'), 1);
    expect(taskRow('t1')['focusedAt'], isNull);
    expect(taskRow('t1')['status'], 'pending');

    // Набор опустел — и говорит об этом.
    expect(find.text('Набор пуст'), findsOneWidget);
  });

  testWidgets('пустой набор предлагает его собрать', (tester) async {
    await pumpWork(tester);

    expect(find.text('Набор пуст'), findsOneWidget);

    await tester.tap(find.text('Собрать набор'));
    await settle(tester);

    expect(find.byType(PickScreen), findsOneWidget);
  });

  testWidgets('набор не загрузился — экран говорит об этом и даёт повторить', (
    tester,
  ) async {
    backend.failingPaths.add('/focus');

    await pumpWork(tester);

    expect(find.text('Не удалось загрузить набор'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });
}
