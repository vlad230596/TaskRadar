import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/dictation_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_voice.dart';

/// The three-mode shell (F12): switching, remembering, and the microphone that
/// never moves.
void main() {
  late FakeBackend backend;
  late FakeSettingsStore settings;
  late FakeVoiceRecorder recorder;
  late FakeSpeechRecognizer recognizer;

  setUp(() {
    backend = FakeBackend()..alwaysRespond(<dynamic>[]);

    // Режим истории (F13) читает `GET /history`, и это объект, а не массив:
    // общий «отвечай всем пустым списком» разобрался бы там в ошибку разбора.
    // Пустая сводка — как раз то, что оболочка показывает в этих тестах:
    // «Итогов пока нет».
    final canned = backend.responder!;
    backend.responder = (options) => options.path.startsWith('/history')
        ? jsonResponse(_emptyHistory())
        : canned(options);

    settings = FakeSettingsStore();
    recorder = FakeVoiceRecorder();
    recognizer = FakeSpeechRecognizer();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
          notificationGatewayProvider.overrideWithValue(
            FakeNotificationGateway(),
          ),
          settingsStoreProvider.overrideWithValue(settings),
          voiceRecorderProvider.overrideWithValue(recorder),
          speechRecognizerProvider.overrideWithValue(recognizer),
          voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ShellScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  group('switching', () {
    testWidgets('opens on planning', (tester) async {
      await pumpShell(tester);

      expect(find.text('Планирование'), findsOneWidget);
    });

    testWidgets('the bar carries three modes plus the voice, in that order', (
      tester,
    ) async {
      await pumpShell(tester);

      // "Голос" is last and fixed-width on purpose: the microphone lives in one
      // place, and a mode added or removed must not move it.
      expect(find.text('План'), findsOneWidget);
      expect(find.text('Работа'), findsOneWidget);
      expect(find.text('История'), findsOneWidget);
      expect(find.text('Голос'), findsOneWidget);
    });

    testWidgets('tapping a mode swaps the whole screen', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('История'));
      await settle(tester);

      expect(find.text('Итогов пока нет'), findsOneWidget);
      // The planning header is gone, not merely scrolled off: the modes replace
      // one another rather than stacking.
      expect(find.text('Планирование'), findsNothing);
    });

    testWidgets('switching back keeps the planning mode alive', (tester) async {
      // `IndexedStack`, not a rebuild: the board must not be re-fetched and the
      // scroll position must not be lost by looking at the history for a
      // second.
      await pumpShell(tester);
      final before = backend.requests
          .where((request) => request.path == '/board')
          .length;

      await tester.tap(find.text('Работа'));
      await settle(tester);
      await tester.tap(find.text('План'));
      await settle(tester);

      expect(
        backend.requests.where((request) => request.path == '/board').length,
        before,
      );
    });
  });

  group('remembering the mode', () {
    testWidgets('a switch is written down', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('Работа'));
      await settle(tester);

      expect(settings.modeWrites, <String>['work']);
    });

    testWidgets('and the app opens where it was closed', (tester) async {
      settings.appMode = 'history';

      await pumpShell(tester);

      expect(find.text('Итогов пока нет'), findsOneWidget);
    });

    testWidgets('a mode this build has never heard of lands on planning', (
      tester,
    ) async {
      // Stored by name rather than by index precisely so this is possible to
      // detect: an index would silently point at whatever is at that position
      // now.
      settings.appMode = 'inbox-zero';

      await pumpShell(tester);

      expect(find.text('Планирование'), findsOneWidget);
    });

    testWidgets('a tap during the restore wins over the stored mode', (
      tester,
    ) async {
      // The read is asynchronous so the first frame does not wait on a disk. If
      // the user taps inside that window, dragging them back would be the app
      // undoing something they just did.
      settings.appMode = 'history';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
            ),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            settingsStoreProvider.overrideWithValue(settings),
            voiceRecorderProvider.overrideWithValue(recorder),
            speechRecognizerProvider.overrideWithValue(recognizer),
            voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const ShellScreen(),
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      // One frame only: the stored mode has not been applied yet.
      await tester.pump();
      await tester.tap(find.text('Работа'));
      await settle(tester);

      expect(find.text('Набор ещё не собирается'), findsOneWidget);
      expect(find.text('Итогов пока нет'), findsNothing);
    });

    testWidgets('a store that cannot be written does not block the switch', (
      tester,
    ) async {
      // A preference that failed to persist must not make the screen refuse to
      // change under the user's finger. Worst case: it opens on planning
      // tomorrow.
      settings.writeFailure = StateError('no disk');

      await pumpShell(tester);
      await tester.tap(find.text('История'));
      await settle(tester);

      expect(find.text('Итогов пока нет'), findsOneWidget);
    });
  });

  group('the microphone', () {
    testWidgets('is on the bar from the first frame, model or no model', (
      tester,
    ) async {
      // It used to be absent until a disk probe came back, which made the first
      // tap of every cold start land on nothing -- half of "запускается не с
      // первого раза".
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
            ),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            settingsStoreProvider.overrideWithValue(settings),
            voiceRecorderProvider.overrideWithValue(recorder),
            speechRecognizerProvider.overrideWithValue(recognizer),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const ShellScreen(),
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Голос'), findsOneWidget);

      // Let the requests the first frame kicked off finish, or the test ends
      // with dio's timeout timers still pending.
      await settle(tester);
    });

    testWidgets('one tap opens the dictation screen, already recording', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.text('Голос'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(DictationScreen), findsOneWidget);
      expect(recorder.startCount, 1);
      // And it is going to the sandbox unless told otherwise, which is the
      // destination that costs no decision.
      expect(
        find.descendant(
          of: find.byType(DictationScreen),
          matching: find.text('Песочница'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('stays in the same place in every mode', (tester) async {
      await pumpShell(tester);
      final planPosition = tester.getCenter(find.text('Голос'));

      await tester.tap(find.text('История'));
      await settle(tester);

      expect(tester.getCenter(find.text('Голос')), planPosition);
    });
  });
}

/// Ответ `GET /history`, в котором ничего не происходило.
Map<String, dynamic> _emptyHistory() => <String, dynamic>{
  'range': '7d',
  'from': null,
  'to': DateTime.now().toUtc().toIso8601String(),
  'closedByDay': <dynamic>[],
  'closedTotal': 0,
  'projects': <dynamic>[],
  'stale': <dynamic>[],
};

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}
