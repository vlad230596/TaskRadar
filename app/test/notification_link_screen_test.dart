import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/board_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/widgets/notification_link_scope.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// What the user sees after tapping a reminder (F4).
///
/// `notification_link_test.dart` proves the resolution; this proves the half
/// that resolution is for -- the project screen actually opens with the task
/// highlighted, and the two ways it can fail produce a sentence rather than a
/// blank screen.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (MethodCall call) async =>
              call.method == 'getLocalTimezone' ? 'Europe/Moscow' : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// The signed-in half of `app.dart`, with the same navigator key the
  /// background opener pushes onto.
  Future<void> pumpSignedIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(snapshots),
          notificationGatewayProvider.overrideWithValue(gateway),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: const NotificationLinkScope(child: BoardScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  ({String projectId, String taskId}) seedBlockedTask() {
    final projectId = server.addProject(name: 'Дача');
    server.addTask(projectId: projectId, title: 'Покрасить забор');
    final taskId = server.addTask(
      projectId: projectId,
      title: 'Жду кабель',
      status: 'blocked',
      remindAt: '2026-10-01T00:00:00.000Z',
    );
    return (projectId: projectId, taskId: taskId);
  }

  testWidgets('a cold start from a reminder opens the task, highlighted', (
    tester,
  ) async {
    final seeded = seedBlockedTask();
    // The app was not running: the tap is only readable through the launch
    // details, never through the response callback.
    gateway.launchPayload = 'task:${seeded.taskId}';

    await pumpSignedIn(tester);

    final screen = tester.widget<ProjectScreen>(find.byType(ProjectScreen));
    expect(screen.projectId, seeded.projectId);
    expect(
      screen.highlightTaskId,
      seeded.taskId,
      reason: 'the reminder was about one task, so that task is pointed at',
    );
    expect(find.text('Жду кабель'), findsWidgets);
  });

  testWidgets('a tap while the app is running opens it the same way', (
    tester,
  ) async {
    final seeded = seedBlockedTask();
    await pumpSignedIn(tester);
    expect(find.byType(ProjectScreen), findsNothing);

    gateway.tap('task:${seeded.taskId}');
    await settle(tester);

    expect(
      tester.widget<ProjectScreen>(find.byType(ProjectScreen)).projectId,
      seeded.projectId,
    );
  });

  testWidgets('a deleted task gets a sentence, not a blank screen', (
    tester,
  ) async {
    seedBlockedTask();
    gateway.launchPayload = 'task:tsk_deleted_last_week';

    await pumpSignedIn(tester);

    expect(find.text('Задача не найдена'), findsOneWidget);
    expect(find.textContaining('её удалили'), findsOneWidget);
    // No project screen was pushed: there was nothing to push.
    expect(find.byType(ProjectScreen), findsNothing);

    await tester.tap(find.text('Понятно'));
    await settle(tester);
    expect(find.byType(BoardScreen), findsOneWidget);
  });

  testWidgets('no network is "нет связи", with a retry that works', (
    tester,
  ) async {
    final seeded = seedBlockedTask();
    backend.alwaysFailToConnect();
    gateway.launchPayload = 'task:${seeded.taskId}';

    await pumpSignedIn(tester);

    expect(find.text('Не удалось открыть задачу'), findsOneWidget);
    // Scoped to the dialog: the board behind it is also saying "нет связи" in
    // its own banner, which is correct and not what this asserts.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Нет связи с сервером.'),
      ),
      findsOneWidget,
    );
    // Not "задача удалена": the app could not confirm anything, and saying it
    // was deleted would be the worst available answer.
    expect(find.text('Задача не найдена'), findsNothing);

    // The network comes back and the retry resolves the very same task.
    backend.responder = null;
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Повторить'),
      ),
    );
    await settle(tester);

    expect(
      tester.widget<ProjectScreen>(find.byType(ProjectScreen)).projectId,
      seeded.projectId,
    );
  });

  testWidgets('a dismissed failure does not come back on the next rebuild', (
    tester,
  ) async {
    seedBlockedTask();
    gateway.launchPayload = 'task:tsk_gone';

    await pumpSignedIn(tester);
    await tester.tap(find.text('Понятно'));
    await settle(tester);
    expect(find.text('Задача не найдена'), findsNothing);

    // A board refresh rebuilds the scope. An unacked request would be handled
    // again here and the dialog would reappear for ever.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await settle(tester);

    expect(find.text('Задача не найдена'), findsNothing);
  });

  testWidgets('a bench notification navigates nowhere', (tester) async {
    seedBlockedTask();
    await pumpSignedIn(tester);

    gateway.tap('bench:now');
    await settle(tester);

    expect(find.byType(ProjectScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
