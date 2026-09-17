import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/board_screen.dart';
import 'package:taskradar/screens/inbox_screen.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// The sandbox screen (F8): capture at the top, sorting underneath.
///
/// The assertion worth naming: **a line that could not be captured stays in the
/// field.** Everything else in this app writes optimistically, and here that
/// would be the wrong trade -- the promise of the sandbox is "it is written
/// down now", and there is no offline queue behind it.
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
    tester.view.physicalSize = const Size(1000, 1400);
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
          home: home ?? const InboxScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
    await tester.tap(find.byTooltip('Записать'));
    await settle(tester);
  }

  group('capture', () {
    testWidgets('an empty sandbox says what it is for', (tester) async {
      await pump(tester);

      expect(find.text('Песочница пуста'), findsOneWidget);
      expect(find.textContaining('записано на ходу'), findsOneWidget);
      // ...and the field is there anyway, because that is the point of opening
      // this screen.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('one line, one Enter, and the field is ready for the next', (
      tester,
    ) async {
      await pump(tester);

      await capture(tester, 'Спросить про кабель');

      expect(find.text('Спросить про кабель'), findsOneWidget);
      expect(server.inbox.single['text'], 'Спросить про кабель');
      // Cleared and still focused: the gesture is "empty my head", not "add one
      // item".
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
      expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('a line that could not be sent stays in the field', (
      tester,
    ) async {
      await pump(tester);
      backend.failingPaths.add('/inbox');

      await capture(tester, 'Спросить про кабель');

      // Not lost, not shown as if it had been saved: still there, to be sent
      // again when there is signal.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Спросить про кабель',
      );
      expect(find.textContaining('Не удалось записать в песочницу.'), findsOneWidget);
      expect(server.inbox, isEmpty);
    });
  });

  group('sorting', () {
    testWidgets('filing a line into an existing project', (tester) async {
      final projectId = server.addProject(name: 'Дача');
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      await tester.tap(find.text('Спросить про кабель'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Дача'));
      await settle(tester);

      expect(server.titlesInOrder(projectId), contains('Спросить про кабель'));
      expect(server.inbox, isEmpty);
      expect(find.text('Песочница пуста'), findsOneWidget);
      // It disappeared from here, so it says where it went.
      expect(find.textContaining('Задача добавлена в «Дача»'), findsOneWidget);
    });

    testWidgets('the picker groups projects by scope when there is more than one', (
      tester,
    ) async {
      final dacha = server.addScope(name: 'Дача');
      server.addProject(name: 'Крыша', scopeId: dacha);
      server.addProject(name: 'Бэкенд');
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      await tester.tap(find.text('Спросить про кабель'));
      await tester.pumpAndSettle();

      // Every project of every scope: a line captured without deciding which
      // part of life it belongs to must not be filed through a switcher that
      // has already decided.
      expect(find.text('Крыша'), findsOneWidget);
      expect(find.text('Бэкенд'), findsOneWidget);
      expect(find.text('Основной'), findsOneWidget, reason: 'the scope heading');
    });

    testWidgets('a line can become a project of its own', (tester) async {
      server.addInboxItem(text: 'Ремонт балкона');
      await pump(tester);

      await tester.tap(find.text('Ремонт балкона'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый проект…'));
      await tester.pumpAndSettle();

      // The captured line is offered as the name -- usually it is the name, or
      // nearly.
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'Ремонт балкона',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Создать'));
      await settle(tester);

      final created = server.projects.values.firstWhere(
        (project) => project['name'] == 'Ремонт балкона',
      );
      expect(server.titlesInOrder(created['id'] as String), <String>['Ремонт балкона']);
      expect(server.inbox, isEmpty);
    });

    testWidgets('editing a line before filing it', (tester) async {
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      await tester.tap(find.byTooltip('Что сделать со строчкой'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Поправить текст'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Спросить про кабель у Пети');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await settle(tester);

      expect(find.text('Спросить про кабель у Пети'), findsOneWidget);
      expect(server.inbox.single['text'], 'Спросить про кабель у Пети');
    });

    testWidgets('throwing a line away asks first', (tester) async {
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      await tester.tap(find.byTooltip('Что сделать со строчкой'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выбросить'));
      await tester.pumpAndSettle();

      expect(find.text('Выбросить строчку?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Выбросить'));
      await settle(tester);

      expect(server.inbox, isEmpty);
      expect(find.text('Песочница пуста'), findsOneWidget);
    });
  });

  group('from the board', () {
    testWidgets('the button opens the sandbox', (tester) async {
      await pump(tester, home: const BoardScreen());

      await tester.tap(find.byTooltip(InboxScreen.title));
      await settle(tester);

      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('the badge counts what is waiting', (tester) async {
      server.addInboxItem(text: 'Спросить про кабель');
      server.addInboxItem(text: 'Посмотреть налоги');
      await pump(tester, home: const BoardScreen());

      // A pile nobody is reminded of is a pile that rots, and things were
      // written there *instead of* being remembered.
      expect(find.widgetWithText(Badge, '2'), findsOneWidget);
    });

    testWidgets('an empty sandbox draws no badge at all', (tester) async {
      await pump(tester, home: const BoardScreen());

      expect(find.byType(Badge), findsNothing);
      expect(find.byTooltip(InboxScreen.title), findsOneWidget);
    });
  });
}
