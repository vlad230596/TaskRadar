import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/pick_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// Сбор набора (F13): что предлагается брать, что происходит по тапу и где
/// живёт правило пяти.
///
/// Главное утверждение файла — последнее: шестая задача не берётся, **и при
/// этом на сервер не уходит ничего**. Предел экранный (сервер его не знает и
/// знать не обязан, см. `backend/src/routes/focus.ts`), и единственный способ
/// это проверить — посчитать запросы.
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpPick(WidgetTester tester) async {
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
          home: const PickScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  int focusWrites(String method) => backend.requests
      .where(
        (request) =>
            request.method.toUpperCase() == method &&
            request.path.endsWith('/focus'),
      )
      .length;

  Map<String, dynamic> taskRow(String id) =>
      server.tasks.firstWhere((task) => task['id'] == id);

  testWidgets('предлагаются открытые задачи, сгруппированные по проектам', (
    tester,
  ) async {
    server.addTask(projectId: dom, title: 'Купить лампочки', id: 't1');
    server.addTask(
      projectId: dom,
      title: 'Закрытая задача',
      id: 't2',
      status: 'done',
    );
    server.addTask(
      projectId: dom,
      title: 'Ждёт ответа УК',
      id: 't3',
      status: 'blocked',
    );
    server.addTask(projectId: tr, title: 'Потестить диктовку', id: 't4');

    await pumpPick(tester);

    expect(find.text('ДОМ'), findsOneWidget);
    expect(find.text('TASKRADAR'), findsOneWidget);
    expect(find.text('Купить лампочки'), findsOneWidget);
    expect(find.text('Потестить диктовку'), findsOneWidget);

    // Закрытая — уже не работа, блокер — работа, которой сейчас нельзя
    // заняться: ни ту, ни другую брать не предлагаем.
    expect(find.text('Закрытая задача'), findsNothing);
    expect(find.text('Ждёт ответа УК'), findsNothing);
  });

  testWidgets('тап берёт задачу в работу, повторный — убирает', (tester) async {
    server.addTask(projectId: dom, title: 'Купить лампочки', id: 't1');

    await pumpPick(tester);

    await tester.tap(find.text('Купить лампочки'));
    await settle(tester);

    expect(taskRow('t1')['focusedAt'], isNotNull);
    expect(focusWrites('POST'), 1);
    expect(find.text('Работать над одной'), findsOneWidget);

    await tester.tap(find.text('Купить лампочки'));
    await settle(tester);

    expect(taskRow('t1')['focusedAt'], isNull);
    expect(focusWrites('DELETE'), 1);
    expect(find.text('Пока ничего не выбрано'), findsOneWidget);
  });

  testWidgets('уже взятая задача показана отмеченной', (tester) async {
    server.addTask(
      projectId: dom,
      title: 'Вызвать курьера',
      id: 't1',
      focused: true,
    );

    await pumpPick(tester);

    expect(find.text('Работать над одной'), findsOneWidget);
    // Ничего не писали — набор пришёл с сервера таким.
    expect(focusWrites('POST'), 0);
  });

  testWidgets('шестая задача не берётся, и на сервер ничего не уходит', (
    tester,
  ) async {
    for (var i = 1; i <= 5; i++) {
      server.addTask(
        projectId: dom,
        title: 'Взятая $i',
        id: 't$i',
        focused: true,
      );
    }
    server.addTask(projectId: dom, title: 'Шестая', id: 't6');

    await pumpPick(tester);
    expect(find.text('Работать над пятью'), findsOneWidget);

    await tester.tap(find.text('Шестая'));
    await settle(tester);

    expect(taskRow('t6')['focusedAt'], isNull);
    expect(focusWrites('POST'), 0);
    expect(find.text('Работать над пятью'), findsOneWidget);

    // Сказано как есть: правило экранное, сервер тут ни при чём.
    expect(
      find.textContaining('больше на экран работы не помещается'),
      findsOneWidget,
    );
  });

  testWidgets('брать нечего — экран говорит об этом, а не показывает пустоту', (
    tester,
  ) async {
    server.addTask(
      projectId: dom,
      title: 'Закрытая задача',
      id: 't1',
      status: 'done',
    );

    await pumpPick(tester);

    expect(find.text('Брать нечего'), findsOneWidget);
  });
}
