import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/archive_screen.dart';
import 'package:taskradar/screens/board_screen.dart';
import 'package:taskradar/screens/project_screen.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// The archive, the delete that is only reachable through it, and the two ways
/// a project gets into and out of it (F4).
///
/// The assertion worth naming: **the delete confirmation cannot be given by
/// reflex.** The rest of this app confirms destructive things with a yes/no,
/// which is right for a task; deleting a project takes its tasks and its notes
/// with it, and a yes/no in front of that is a speed bump, not a confirmation.
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
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(1000, 1200);
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
          home: home ?? const ArchiveScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  group('the archive list', () {
    testWidgets('an empty archive says where projects come from', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Архив пуст'), findsOneWidget);
      expect(find.textContaining('«В архив»'), findsOneWidget);
    });

    testWidgets('shows archived projects with how far they got', (
      tester,
    ) async {
      final projectId = server.addProject(
        name: 'Старый проект',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      server.addTask(projectId: projectId, title: 'Раз', status: 'done');
      server.addTask(projectId: projectId, title: 'Два');
      // Active projects belong on the board, not here.
      server.addProject(name: 'Дача');

      await pump(tester);

      expect(find.text('Старый проект'), findsOneWidget);
      expect(find.text('Дача'), findsNothing);
      expect(find.text('Задач: 1 из 2 сделано'), findsOneWidget);
    });

    testWidgets('a failed load says so instead of showing an empty archive', (
      tester,
    ) async {
      backend.alwaysFailToConnect();
      await pump(tester);

      expect(find.text('Не удалось загрузить архив'), findsOneWidget);
      expect(find.textContaining('Нет связи с сервером.'), findsOneWidget);
      expect(find.text('Архив пуст'), findsNothing);
    });
  });

  group('unarchiving', () {
    testWidgets('one tap, and the project leaves the archive', (tester) async {
      server.addProject(
        name: 'Старый проект',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      await pump(tester);

      await tester.tap(find.text('Вернуть'));
      await settle(tester);

      expect(find.text('Архив пуст'), findsOneWidget);
      expect(server.projects.values.single['archivedAt'], isNull);
    });

    testWidgets('a failure is said out loud and the row stays', (tester) async {
      server.addProject(
        name: 'Старый проект',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      await pump(tester);

      backend.alwaysFailToConnect();
      await tester.tap(find.text('Вернуть'));
      await settle(tester);

      expect(find.textContaining('Не удалось вернуть проект'), findsOneWidget);
      expect(find.text('Старый проект'), findsOneWidget);
    });
  });

  group('deleting', () {
    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Удалить навсегда'));
      await tester.pumpAndSettle();
    }

    testWidgets('spells out exactly what goes', (tester) async {
      final projectId = server.addProject(
        name: 'Старый проект',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      server.addTask(projectId: projectId, title: 'Раз');
      server.addTask(projectId: projectId, title: 'Два');
      await pump(tester);

      await openDeleteDialog(tester);

      expect(find.text('Удалить проект навсегда?'), findsOneWidget);
      expect(find.textContaining('все его задачи'), findsOneWidget);
      expect(find.textContaining('(2)'), findsOneWidget);
      expect(find.textContaining('Отменить это нельзя'), findsOneWidget);
    });

    testWidgets('cannot be confirmed without typing the name', (tester) async {
      server.addProject(
        name: 'Старый проект',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      await pump(tester);
      await openDeleteDialog(tester);

      // The point of the whole dialog: the confirm button asks "which project",
      // which is a question about a fact, not "are you sure", which is a
      // question about a mood and can be answered by a mis-tap.
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Удалить навсегда'),
      );
      expect(confirm.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Не тот проект');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Удалить навсегда'),
            )
            .onPressed,
        isNull,
      );

      expect(server.projects, hasLength(1));
    });

    testWidgets('the typed name is trimmed and case-insensitive', (
      tester,
    ) async {
      server.addProject(
        name: 'Старый проект',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      await pump(tester);
      await openDeleteDialog(tester);

      // Proving you know which project this is, not that you can reproduce
      // capitalisation.
      await tester.enterText(find.byType(TextField), '  старый ПРОЕКТ  ');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Удалить навсегда'));
      await settle(tester);

      expect(server.projects, isEmpty);
      expect(find.text('Архив пуст'), findsOneWidget);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      server.addProject(
        name: 'Старый проект',
        archivedAt: '2026-09-01T00:00:00.000Z',
      );
      await pump(tester);
      await openDeleteDialog(tester);

      await tester.enterText(find.byType(TextField), 'Старый проект');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await settle(tester);

      expect(server.projects, hasLength(1));
      expect(find.text('Старый проект'), findsOneWidget);
    });
  });

  group('archiving from the project screen', () {
    testWidgets('asks, then archives, then goes back to the board', (
      tester,
    ) async {
      final projectId = server.addProject(name: 'Дача', id: 'prj_1');
      server.addTask(projectId: projectId, title: 'Покрасить забор');

      await pump(tester, home: const BoardScreen());
      await tester.tap(find.text('Дача'));
      await settle(tester);
      expect(find.byType(ProjectScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Действия с проектом'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В архив'));
      await tester.pumpAndSettle();

      expect(find.text('Убрать проект с доски?'), findsOneWidget);
      expect(find.textContaining('напоминания его задач'), findsOneWidget);
      expect(
        find.textContaining('Вернуть можно в любой момент'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'В архив'));
      await settle(tester);

      // Back on the board, and the card is gone from it.
      expect(find.byType(ProjectScreen), findsNothing);
      expect(find.byType(BoardScreen), findsOneWidget);
      expect(find.text('Дача'), findsNothing);
      expect(
        server.projects.values.single['archivedAt'],
        FakeProjectBackend.archivedAtStamp,
      );
    });

    testWidgets('there is no rename -- the backend has no endpoint for it', (
      tester,
    ) async {
      // Documented as a test rather than only as a comment: if
      // `PATCH /projects/:id` ever appears, this is the line that should start
      // looking wrong.
      server.addProject(name: 'Дача', id: 'prj_1');

      await pump(tester, home: const BoardScreen());
      await tester.tap(find.text('Дача'));
      await settle(tester);

      await tester.tap(find.byTooltip('Действия с проектом'));
      await tester.pumpAndSettle();

      expect(find.text('В архив'), findsOneWidget);
      expect(find.textContaining('переимен'), findsNothing);
    });
  });

  group('creating a project from the board', () {
    testWidgets('names it, creates it and opens it', (tester) async {
      await pump(tester, home: const BoardScreen());
      expect(find.text('Проектов пока нет'), findsOneWidget);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Проект'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  Ремонт кухни  ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
      await settle(tester);

      expect(server.projects.values.single['name'], 'Ремонт кухни');
      // Straight into it: a new project is empty and the next thing anyone does
      // is type its first task.
      expect(find.byType(ProjectScreen), findsOneWidget);
      expect(find.text('Задач пока нет'), findsOneWidget);
    });

    testWidgets('an empty name cannot be submitted', (tester) async {
      await pump(tester, home: const BoardScreen());

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Проект'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Создать'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Отмена'));
      await settle(tester);
      expect(server.projects, isEmpty);
    });

    testWidgets('a failed create says why and stays on the board', (
      tester,
    ) async {
      await pump(tester, home: const BoardScreen());
      backend.alwaysFailToConnect();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Проект'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ремонт кухни');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
      await settle(tester);

      expect(find.textContaining('Не удалось создать проект.'), findsOneWidget);
      expect(find.byType(ProjectScreen), findsNothing);
    });
  });
}
