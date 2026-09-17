import 'dart:io';

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
import 'support/fake_capture_queue_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// The sandbox screen (F8), as F8.1 left it: capture at the top, sorting
/// underneath, and both working with no network.
///
/// The assertions worth naming: **a line captured with no signal appears
/// immediately, marked as unsent**, and **a sandbox that could not be loaded
/// still shows what this device has written down**. F8's rule -- the text stays
/// in the field until the server has it -- was the right one when there was
/// nowhere else to put the line, and the queue replaced it: the field now
/// clears as soon as the line is on disk, and only a failed *disk* write keeps
/// it.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeCaptureQueueStore queue;
  late FakeNotificationGateway gateway;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    snapshots = FakeBoardSnapshotStore();
    queue = FakeCaptureQueueStore();
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
          captureQueueStoreProvider.overrideWithValue(queue),
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

    testWidgets('a line captured with no network appears, marked as unsent', (
      tester,
    ) async {
      await pump(tester);
      backend.failingPaths.add('/inbox');

      await capture(tester, 'Спросить про кабель');

      // The promise of the sandbox is "it is written down now", and with the
      // queue that promise is true offline: the line is on this device's disk
      // before it is on the screen.
      expect(find.text('Спросить про кабель'), findsOneWidget);
      expect(find.textContaining('Не отправлено'), findsOneWidget);
      expect(queue.queue.single.text, 'Спросить про кабель');
      // The field is empty and focused all the same -- the gesture is "empty my
      // head", and a signal is not part of it.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(server.inbox, isEmpty);
    });

    testWidgets('a line that could not reach the disk stays in the field', (
      tester,
    ) async {
      // The one failure that still has to be reported: if the queue file could
      // not be written, the line exists nowhere at all.
      await pump(tester);
      queue.writeFailure = const FileSystemException('disk full');

      await capture(tester, 'Спросить про кабель');

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Спросить про кабель',
      );
      expect(
        find.textContaining('Не удалось записать строчку на устройство.'),
        findsOneWidget,
      );
    });

    testWidgets('an unsent line can be thrown away', (tester) async {
      await pump(tester);
      backend.failingPaths.add('/inbox');
      await capture(tester, 'Спросить про кабель');

      await tester.tap(find.byTooltip('Выбросить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Выбросить'));
      await settle(tester);

      expect(find.text('Спросить про кабель'), findsNothing);
      expect(queue.queue, isEmpty);
    });

    testWidgets('a sandbox that cannot be loaded still shows the unsent lines', (
      tester,
    ) async {
      // The screen used to replace the whole list with an error here. It cannot
      // any more: the lines captured in the lift are exactly what the user came
      // to see, and hiding them behind "не удалось загрузить" would say the
      // thought was lost while it sits on this device's disk.
      backend.failingPaths.add('/inbox');
      await pump(tester);

      await capture(tester, 'Спросить про кабель');

      expect(find.text('Спросить про кабель'), findsOneWidget);
      expect(find.text('Не удалось загрузить песочницу'), findsNothing);
      expect(
        find.textContaining('записано на этом устройстве'),
        findsOneWidget,
        reason: 'the failure is a banner over the lines, not instead of them',
      );
    });

    testWidgets('an empty sandbox with nothing queued still says it is empty', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Песочница пуста'), findsOneWidget);
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
