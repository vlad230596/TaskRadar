import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/task_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';
import 'support/fake_project_backend.dart';

/// The Back rule for typed text (`widgets/unsaved_changes_guard.dart`), on the
/// screen where losing it hurt most. The emulator suite (`tests/android/`)
/// runs the same rule against the real keyboard on every field; this file is
/// the fast check that runs on every `flutter test`.
///
/// `handlePopRoute` is what the Android Back button reaches the app as, once
/// the keyboard (if any) has taken the first press for itself.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late String projectId;
  late String taskId;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    FakeHistoryBackend(backend);
    projectId = server.addProject(name: 'Дом', id: 'prj_dom');
    taskId = server.addTask(projectId: projectId, title: 'Купить кабель');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// A home route with the task screen pushed over it, so Back has somewhere
  /// to go.
  Future<void> pumpOver(WidgetTester tester, {String? task}) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(FakeBoardSnapshotStore()),
          deviceTimeZoneNameProvider.overrideWith((ref) async => 'Europe/Moscow'),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          navigatorKey: appNavigatorKey,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    appNavigatorKey.currentState!.pushNamed<void>(
      AppRoutes.task,
      arguments: TaskRouteArgs(projectId: projectId, taskId: task),
    );
    await settle(tester);
    expect(find.byType(TaskScreen), findsOneWidget);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
    // The page transition outlives [settle]; a route on its way out is still
    // in the tree until it ends.
    await tester.pump(const Duration(milliseconds: 600));
  }

  Finder titleField() => find.byType(TextField).first;

  testWidgets('nothing typed: Back leaves at once, no dialog', (tester) async {
    await pumpOver(tester, task: taskId);

    await back(tester);

    expect(find.text('Выйти без сохранения?'), findsNothing);
    expect(find.byType(TaskScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('an edit: Back asks; «Остаться» keeps the text', (tester) async {
    await pumpOver(tester, task: taskId);
    await tester.enterText(titleField(), 'Купить кабель HDMI');
    await settle(tester);

    await back(tester);
    expect(find.text('Выйти без сохранения?'), findsOneWidget);

    await tester.tap(find.text('Остаться'));
    await settle(tester);
    expect(find.byType(TaskScreen), findsOneWidget);
    expect(find.text('Купить кабель HDMI'), findsOneWidget);
  });

  testWidgets('an edit: «Выйти» leaves and saves nothing', (tester) async {
    await pumpOver(tester, task: taskId);
    await tester.enterText(titleField(), 'Купить кабель HDMI');
    await settle(tester);

    await back(tester);
    await tester.tap(find.text('Выйти'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('home'), findsOneWidget);
    expect(server.tasks.single['title'], 'Купить кабель');
    expect(server.patches, isEmpty);
  });

  testWidgets('an edit: «Сохранить» writes it, then leaves', (tester) async {
    await pumpOver(tester, task: taskId);
    await tester.enterText(titleField(), 'Купить кабель HDMI');
    await settle(tester);

    await back(tester);
    await tester.tap(find.text('Сохранить').last);
    await settle(tester);

    expect(server.tasks.single['title'], 'Купить кабель HDMI');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a draft: Back asks, and «Выйти» creates nothing', (tester) async {
    await pumpOver(tester);
    await tester.enterText(titleField(), 'Позвонить электрику');
    await settle(tester);

    await back(tester);
    expect(find.text('Новая задача не будет создана.'), findsOneWidget);

    await tester.tap(find.text('Выйти'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('home'), findsOneWidget);
    expect(server.tasks, hasLength(1));
  });

  testWidgets('a draft with the network down stays open with its text', (
    tester,
  ) async {
    await pumpOver(tester);
    backend.alwaysFailToConnect();
    await tester.enterText(titleField(), 'Позвонить электрику');
    await settle(tester);

    await tester.tap(find.text('Добавить'));
    await settle(tester);

    // Before the offline QA pass the screen closed here and the text was gone.
    expect(find.byType(TaskScreen), findsOneWidget);
    expect(find.text('Позвонить электрику'), findsOneWidget);
    expect(find.textContaining('Не удалось добавить задачу.'), findsOneWidget);
  });

  testWidgets('the close button follows the same rule as Back', (tester) async {
    await pumpOver(tester, task: taskId);
    await tester.enterText(titleField(), 'Купить кабель HDMI');
    await settle(tester);

    await tester.tap(find.byTooltip('Закрыть'));
    await settle(tester);

    expect(find.text('Выйти без сохранения?'), findsOneWidget);
  });
}
