import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/dictation_screen.dart';
import 'package:taskradar/screens/inbox_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_voice.dart';

/// The sandbox screen, as F12 redrew it: the line you are working on is open
/// and editable, and the projects are buttons under it.
///
/// ## What changed, and why these tests changed with it
///
/// F8 put a one-line composer at the top and a `ListTile` per line under it,
/// each with a four-item overflow menu. That screen carried two of the three
/// complaints this redesign answers: the field showed two or three words of a
/// dictated sentence, and filing a line cost a menu, a dialog and a scroll
/// through every project.
///
/// So the composer is gone -- capture is the microphone, which opens the
/// dictation screen -- and the menu is gone: one tap on a project's name files
/// the line. What has **not** changed is the queue (F8.1), and the assertions
/// about it are word for word the ones F8.1 wrote: a line captured with no
/// signal appears immediately, marked as unsent, and a sandbox that could not be
/// loaded still shows what this device has written down.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeCaptureQueueStore queue;
  late FakeNotificationGateway gateway;
  late FakeVoiceRecorder microphone;
  late FakeSpeechRecognizer recogniser;
  late FakeVoiceModelStore voiceModels;

  setUp(() {
    microphone = FakeVoiceRecorder();
    recogniser = FakeSpeechRecognizer();
    voiceModels = FakeVoiceModelStore();
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

  Future<void> pump(
    WidgetTester tester, {
    Widget? home,
    bool withVoiceModel = false,
  }) async {
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
          voiceRecorderProvider.overrideWithValue(microphone),
          speechRecognizerProvider.overrideWithValue(recogniser),
          voiceModelStoreProvider.overrideWithValue(
            voiceModels..present = withVoiceModel,
          ),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: home ?? const InboxScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  /// Captures a line the only way the screen offers: the microphone, the
  /// dictation screen, and two presses of "Готово" -- one to stop the phrase,
  /// one to commit it.
  Future<void> dictate(WidgetTester tester, String heard) async {
    recogniser.text = heard;
    await tester.tap(find.byTooltip('Записать ещё'));
    await settle(tester);

    await tester.tap(find.text('Готово'));
    await settle(tester);
    await tester.tap(find.text('Готово'));
    await settle(tester);
  }

  /// The field of whichever sandbox line is open for editing.
  String openLineText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  group('the pile', () {
    testWidgets('an empty sandbox says what it is for', (tester) async {
      await pump(tester);

      expect(find.text('Песочница пуста'), findsOneWidget);
      expect(find.textContaining('записано на ходу'), findsOneWidget);
      // ...and the microphone is there anyway, because that is the point of
      // opening this screen.
      expect(find.byTooltip('Записать ещё'), findsOneWidget);
    });

    testWidgets('the oldest line is open and editable, the rest are rows', (
      tester,
    ) async {
      // The pile is worked oldest first: the line at risk of rotting is the one
      // that has waited longest.
      server.addInboxItem(text: 'Спросить про кабель');
      server.addInboxItem(text: 'Посмотреть налоги');
      await pump(tester);

      expect(openLineText(tester), 'Спросить про кабель');
      expect(find.text('Посмотреть налоги'), findsOneWidget);
      // Exactly one line is open, so there is exactly one field.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('tapping another line opens that one instead', (tester) async {
      server.addInboxItem(text: 'Спросить про кабель');
      server.addInboxItem(text: 'Посмотреть налоги');
      await pump(tester);

      await tester.tap(find.text('Посмотреть налоги'));
      await settle(tester);

      expect(openLineText(tester), 'Посмотреть налоги');
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the open line is a text area, not a one-line field', (
      tester,
    ) async {
      // Complaint number one: a dictated sentence has to be readable in the
      // place it is corrected.
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, isNull);
      expect(field.style?.fontSize, 19);
    });
  });

  group('sorting', () {
    testWidgets('one tap on a project turns the line into a task', (
      tester,
    ) async {
      // The whole screen, in one gesture. F8 spent a menu, a dialog and a
      // scroll on this.
      final projectId = server.addProject(name: 'Дача');
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      await tester.tap(find.widgetWithText(InkWell, 'Дача').first);
      await settle(tester);

      expect(server.titlesInOrder(projectId), contains('Спросить про кабель'));
      expect(server.inbox, isEmpty);
      expect(find.text('Песочница пуста'), findsOneWidget);
      // It disappeared from here, so it says where it went.
      expect(find.textContaining('Задача добавлена в «Дача»'), findsOneWidget);
    });

    testWidgets('every project is offered, whatever scope it is in', (
      tester,
    ) async {
      // A line captured without deciding which part of life it belongs to must
      // not be filed through a switcher that has already decided.
      final dacha = server.addScope(name: 'Дача');
      server.addProject(name: 'Крыша', scopeId: dacha);
      server.addProject(name: 'Бэкенд');
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      expect(find.text('Крыша'), findsOneWidget);
      expect(find.text('Бэкенд'), findsOneWidget);
    });

    testWidgets('an edit made before filing is what gets filed', (
      tester,
    ) async {
      // The moment the line becomes a task is the only moment its text has to
      // be right, and a correction that was typed and then filed must not be
      // filed in its old wording.
      final projectId = server.addProject(name: 'Дача');
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      await tester.enterText(
        find.byType(TextField),
        'Спросить про кабель у Пети',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, 'Дача').first);
      await settle(tester);

      expect(
        server.titlesInOrder(projectId),
        contains('Спросить про кабель у Пети'),
      );
    });

    testWidgets('a line can become a project of its own', (tester) async {
      server.addInboxItem(text: 'Ремонт балкона');
      await pump(tester);

      await tester.tap(find.byTooltip('В новый проект'));
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
      expect(
        server.titlesInOrder(created['id'] as String),
        <String>['Ремонт балкона'],
      );
      expect(server.inbox, isEmpty);
    });

    testWidgets('throwing a line away asks first', (tester) async {
      server.addInboxItem(text: 'Спросить про кабель');
      await pump(tester);

      await tester.tap(find.byTooltip('Выбросить строку'));
      await tester.pumpAndSettle();

      expect(find.text('Выбросить строчку?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Выбросить'));
      await settle(tester);

      expect(server.inbox, isEmpty);
      expect(find.text('Песочница пуста'), findsOneWidget);
    });
  });

  group('capture, with and without a signal', () {
    testWidgets('the microphone writes a line straight into the pile', (
      tester,
    ) async {
      await pump(tester, withVoiceModel: true);

      await dictate(tester, 'Спросить про кабель');

      expect(server.inbox.single['text'], 'Спросить про кабель');
      // Through the queue and out the other side: with a network it drains
      // immediately, so what is left is a server row and an empty queue.
      expect(queue.queue, isEmpty);
      expect(find.text('Песочница'), findsOneWidget);
    });

    testWidgets('a line captured with no network appears, marked as unsent', (
      tester,
    ) async {
      await pump(tester, withVoiceModel: true);
      backend.failingPaths.add('/inbox');

      await dictate(tester, 'Спросить про кабель');

      // The promise of the sandbox is "it is written down now", and with the
      // queue that promise is true offline: the line is on this device's disk
      // before it is on the screen.
      expect(find.text('Спросить про кабель'), findsOneWidget);
      expect(find.textContaining('Не отправлено'), findsOneWidget);
      expect(queue.queue.single.text, 'Спросить про кабель');
      expect(server.inbox, isEmpty);
    });

    testWidgets('a line that could not reach the disk is reported', (
      tester,
    ) async {
      // The one failure that still has to be said out loud: if the queue file
      // could not be written, the line exists nowhere at all -- so the screen
      // holding it must not close.
      await pump(tester, withVoiceModel: true);
      queue.writeFailure = const FileSystemException('disk full');

      await dictate(tester, 'Спросить про кабель');

      expect(
        find.textContaining('Не удалось записать строчку на устройство.'),
        findsOneWidget,
      );
      // Still on the dictation screen, with the words still in it.
      expect(find.byType(DictationScreen), findsOneWidget);
    });

    testWidgets('an unsent line can be thrown away', (tester) async {
      await pump(tester, withVoiceModel: true);
      backend.failingPaths.add('/inbox');
      await dictate(tester, 'Спросить про кабель');

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
      await pump(tester, withVoiceModel: true);

      await dictate(tester, 'Спросить про кабель');

      expect(find.text('Спросить про кабель'), findsOneWidget);
      expect(find.text('Не удалось загрузить песочницу'), findsNothing);
      expect(
        find.textContaining('записано на этом устройстве'),
        findsOneWidget,
        reason: 'the failure is a banner over the lines, not instead of them',
      );
    });
  });

  group('from planning', () {
    testWidgets('the sandbox row opens the sandbox', (tester) async {
      await pump(tester, home: const ShellScreen());

      await tester.tap(find.text('Песочница'));
      await settle(tester);

      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('the count is on the row, because a pile nobody sees rots', (
      tester,
    ) async {
      server.addInboxItem(text: 'Спросить про кабель');
      server.addInboxItem(text: 'Посмотреть налоги');
      await pump(tester, home: const ShellScreen());

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('an empty sandbox shows no number at all', (tester) async {
      // Not "0": a count that says zero and then changes to three is a small
      // lie told on every cold start.
      await pump(tester, home: const ShellScreen());

      expect(find.text('Песочница'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });

  group('dictation', () {
    testWidgets('the microphone is on the screen whatever the model says', (
      tester,
    ) async {
      // It used to disappear without one. It is structural now -- the same
      // indigo square in the same corner on every sub-screen -- and the screen
      // it opens is what explains a missing model.
      await pump(tester);

      expect(find.byTooltip('Записать ещё'), findsOneWidget);
    });

    testWidgets('the open line can be dictated into, appending', (
      tester,
    ) async {
      // A phrase said in two goes is one thought continued, not two.
      server.addInboxItem(text: 'Купить');
      await pump(tester, withVoiceModel: true);
      recogniser.text = 'кабель для монитора';

      await tester.tap(find.byTooltip('Договорить голосом'));
      await settle(tester);
      await tester.tap(find.text('Готово'));
      await settle(tester);
      await tester.tap(find.text('Готово'));
      await settle(tester);

      expect(openLineText(tester), 'Купить кабель для монитора');
      // Nothing was filed: the words went into the line, to be checked.
      expect(server.inbox.single['text'], 'Купить');
    });
  });
}
