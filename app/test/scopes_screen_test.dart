import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/screens/scopes_screen.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// Managing scopes (F7): the screen where they are created, renamed, reordered
/// and deleted -- and the two refusals that make deleting one safe.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;
  late FakeSettingsStore settings;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();
    settings = FakeSettingsStore();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(snapshots),
          notificationGatewayProvider.overrideWithValue(gateway),
          settingsStoreProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          home: home ?? const ScopesScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  group('the list', () {
    testWidgets('shows every scope in order', (tester) async {
      server.addScope(name: 'Дача', id: 's-dacha');
      await pump(tester);

      expect(find.text('Основной'), findsOneWidget);
      expect(find.text('Дача'), findsOneWidget);
    });

    testWidgets('says how many projects each scope holds', (tester) async {
      server.addScope(name: 'Дача', id: 's-dacha');
      server.addProject(name: 'Забор', scopeId: 's-dacha');
      await pump(tester);

      // The count comes from the board the client already holds, not from a
      // count endpoint -- it is the number that makes "why can I not delete
      // this" answerable before the 409.
      expect(find.text('Проектов на доске: 1'), findsOneWidget);
      expect(find.text('Проектов нет'), findsOneWidget);
    });
  });

  group('writing', () {
    testWidgets('creating a scope adds it at the end', (tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Скоуп'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Дача');
      // The confirm button is disabled until the field is non-empty, and the
      // enable happens in a setState -- so the frame has to be pumped before
      // the tap, or the tap lands on a disabled button and nothing happens.
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
      await settle(tester);

      expect(find.text('Дача'), findsOneWidget);
      expect(server.scopes.map((s) => s['name']), contains('Дача'));
    });

    testWidgets('renaming one writes the new name', (tester) async {
      server.addScope(name: 'Дача', id: 's-dacha');
      await pump(tester);

      await tester.tap(find.byTooltip('Переименовать').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Загород');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Переименовать'));
      await settle(tester);

      expect(find.text('Загород'), findsOneWidget);
      expect(server.scopes.last['name'], 'Загород');
    });

    testWidgets('deleting an empty scope asks once, then removes it', (
      tester,
    ) async {
      server.addScope(name: 'Дача', id: 's-dacha');
      await pump(tester);

      await tester.tap(find.byTooltip('Удалить').last);
      await tester.pumpAndSettle();

      // A plain yes/no -- deliberately *not* the type-the-name confirmation
      // that guards deleting a project, because a deletable scope holds nothing.
      expect(find.text('Удалить скоуп?'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await settle(tester);

      expect(find.text('Дача'), findsNothing);
      expect(server.scopes, hasLength(1));
    });

    testWidgets('deleting a scope with projects fails with the server reason', (
      tester,
    ) async {
      server.addScope(name: 'Дача', id: 's-dacha');
      server.addProject(name: 'Забор', scopeId: 's-dacha');
      await pump(tester);

      await tester.tap(find.byTooltip('Удалить').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await settle(tester);

      // The 409 text, not a generic failure: "move its projects first" is an
      // instruction, "не удалось" is not.
      expect(find.textContaining('Не удалось удалить скоуп.'), findsOneWidget);
      expect(find.text('Дача'), findsOneWidget);
      expect(server.scopes, hasLength(2));
    });

    testWidgets('the last scope cannot be deleted', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await settle(tester);

      expect(find.text('Основной'), findsOneWidget);
      expect(server.scopes, hasLength(1));
    });
  });

  /// Opens the planning header's scope pill and picks [name].
  ///
  /// Two taps rather than one, which is what the pill costs against the old row
  /// of chips -- and what it buys is a header that does not scroll away and a
  /// switcher that costs no vertical space when there is one scope.
  Future<void> chooseScope(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Какой экран проектов'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await settle(tester);
  }

  group('the board follows the switcher', () {
    testWidgets('one scope draws no switcher at all', (tester) async {
      server.addProject(name: 'Дача');
      await pump(tester, home: const ShellScreen());

      // The feature is invisible until it means something: every installation
      // has exactly one scope the moment the migration runs.
      expect(find.byTooltip('Какой экран проектов'), findsNothing);
      expect(find.text('Дача'), findsOneWidget);
    });

    testWidgets('two scopes draw a chip each, and the board shows one of them', (
      tester,
    ) async {
      final dacha = server.addScope(name: 'Дача');
      server.addProject(name: 'Крыша', scopeId: dacha);
      server.addProject(name: 'Бэкенд');

      await pump(tester, home: const ShellScreen());

      // F12: one pill in the planning header rather than a row of chips over
      // the board -- see `PlanHeader`. It names the scope that is showing and
      // opens the rest.
      expect(find.byTooltip('Какой экран проектов'), findsOneWidget);
      // The first scope by position is the default, and the board shows only
      // its projects.
      expect(find.text('Бэкенд'), findsOneWidget);
      expect(find.text('Крыша'), findsNothing);
    });

    testWidgets('tapping a chip switches the board and remembers the choice', (
      tester,
    ) async {
      final dacha = server.addScope(name: 'Дача');
      server.addProject(name: 'Крыша', scopeId: dacha);
      server.addProject(name: 'Бэкенд');

      await pump(tester, home: const ShellScreen());
      await chooseScope(tester, 'Дача');

      expect(find.text('Крыша'), findsOneWidget);
      expect(find.text('Бэкенд'), findsNothing);

      // ...and tomorrow's launch opens on the same board.
      expect(settings.scopeWrites, <String>[dacha]);
    });

    testWidgets('a scope with no projects says so, and says where they are', (
      tester,
    ) async {
      final dacha = server.addScope(name: 'Дача');
      server.addProject(name: 'Бэкенд');

      await pump(tester, home: const ShellScreen());
      await chooseScope(tester, 'Дача');

      // Not "Проектов пока нет": the projects exist, they are one tap away.
      expect(find.text('Здесь пусто'), findsOneWidget);
      expect(find.text('Проектов пока нет'), findsNothing);
      expect(find.textContaining('в остальных их 1'), findsOneWidget);
      expect(settings.scopeWrites, <String>[dacha]);
    });

    testWidgets('a new project lands in the scope on screen', (tester) async {
      final dacha = server.addScope(name: 'Дача');
      await pump(tester, home: const ShellScreen());

      await chooseScope(tester, 'Дача');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Проект'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Забор');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
      await settle(tester);

      // Landing anywhere else would be the worst possible answer to "where did
      // it go" -- the board it was created from is showing one specific scope.
      final created = server.projects.values.firstWhere(
        (project) => project['name'] == 'Забор',
      );
      expect(created['scopeId'], dacha);
    });
  });

  group('reachability', () {
    testWidgets('the board menu opens this screen', (tester) async {
      await pump(tester, home: const ShellScreen());

      await tester.tap(find.byTooltip('Ещё'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ScopesScreen.title));
      await settle(tester);

      expect(find.byType(ScopesScreen), findsOneWidget);
    });
  });
}
