import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/capture_queue_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/dictation_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/voice/voice_model.dart';
import 'package:taskradar/widgets/dictation.dart';

import 'support/fake_backend.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_voice.dart';

/// The dictation screen (F12): dark, full of screen, and already recording.
///
/// ## What these tests are guarding
///
/// The gesture. Complaint number two was "диктовка запускается не с первого
/// раза, и непонятно, тап это или удержание", and the answer was to delete the
/// distinction: one tap opens a screen on which recording has already started,
/// and there is no press-and-hold anywhere in the app. The first group asserts
/// exactly that -- nothing is pressed, and the microphone is open.
///
/// Note the near-absence of `pumpAndSettle`. The screen pulses a dot while
/// recording and runs an indeterminate spinner while recognising, so there is
/// always another frame scheduled and "settle" never arrives; the tests pump
/// explicit durations instead, which is also the only way to move a clock the
/// user is meant to read.
void main() {
  late FakeVoiceRecorder recorder;
  late FakeSpeechRecognizer recognizer;

  late FakeBackend backend;
  late FakeCaptureQueueStore store;
  late FakeProjectBackend server;

  setUp(() {
    recorder = FakeVoiceRecorder();
    recognizer = FakeSpeechRecognizer();
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    store = FakeCaptureQueueStore();
  });

  /// Puts the screen up the way the microphone button does, and collects
  /// whatever it pops with.
  ///
  /// A [FieldDestination], so the screen hands the text back instead of writing
  /// it to a server -- which keeps this file about the gesture rather than
  /// about the sandbox.
  Future<List<String?>> open(
    WidgetTester tester, {
    bool modelReady = true,
  }) async {
    final popped = <String?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceRecorderProvider.overrideWithValue(recorder),
          speechRecognizerProvider.overrideWithValue(recognizer),
          if (modelReady)
            voiceModelInstallationProvider.overrideWith(_ReadyModel.new)
          else
            voiceModelInstallationProvider.overrideWith(_MissingModel.new),
          // Where a dictation goes when its screen was closed mid-recognition.
          apiClientProvider.overrideWithValue(backend.client),
          captureQueueStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.of(context)
                        .push<FieldDictation>(
                          MaterialPageRoute<FieldDictation>(
                            builder: (_) => const DictationScreen(
                              destination: FieldDestination('в задачу'),
                            ),
                          ),
                        );
                    // A field of one text is always handed words.
                    popped.add(switch (result) {
                      FieldWords(:final text) => text,
                      FieldTaskText() => fail('a note field got a task'),
                      null => null,
                    });
                  },
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    // Two pumps plus a frame: the route animates in, and `start` is called from
    // a post-frame callback.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    return popped;
  }

  group('the screen records by itself', () {
    testWidgets('opening it opens the microphone, with nothing pressed', (
      tester,
    ) async {
      await open(tester);

      expect(recorder.startCount, 1);
      expect(recorder.recording, isTrue);
      expect(find.text('Слушаю'), findsOneWidget);
      // The whole point: there is no second control to find, and nothing to
      // hold.
      expect(find.text('Готово'), findsOneWidget);
    });

    testWidgets('the clock counts the seconds up', (tester) async {
      await open(tester);

      expect(find.text('0:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('0:07'), findsOneWidget);
    });

    testWidgets('the level meter survives being fed by the microphone', (
      tester,
    ) async {
      // It did not. `List.filled` is fixed-length by default, and the meter's
      // first act on every sample is `removeAt(0)` -- so with a real recorder
      // it threw about 120 ms into every dictation. No test had ever handed it
      // a level, which is exactly how a bug lives through two iterations.
      recorder.levelSamples = const <double>[0.1, 0.6, 0.95, 0.3];
      await open(tester);

      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.byType(VoiceLevelMeter), findsOneWidget);
    });

    testWidgets('"Готово" stops the recording and shows what was heard', (
      tester,
    ) async {
      final popped = await open(tester);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();

      expect(recorder.stopCount, 1);
      expect(recognizer.transcribeCount, 1);
      // Still on screen: the first "Готово" ends the phrase, it does not commit
      // it. The words are correctable before they go anywhere.
      expect(popped, isEmpty);
      expect(find.text('Купить кабель'), findsOneWidget);
    });

    testWidgets('the recognised text is 20 px, which is the point', (
      tester,
    ) async {
      // Complaint number one, on the screen where it hurt most: a dictated
      // sentence you cannot read is a sentence you cannot correct.
      await open(tester);
      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.fontSize, 20);
    });

    testWidgets('the second "Готово" hands the text back and leaves', (
      tester,
    ) async {
      final popped = await open(tester);

      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(popped, <String?>['Купить кабель']);
    });

    testWidgets('a tap on the text area ends the recording too', (
      tester,
    ) async {
      // The spec's second way to finish: the natural way to say "хватит, дальше
      // я руками" is to reach for the words.
      await open(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump();

      expect(recorder.stopCount, 1);
      expect(find.text('Слушаю'), findsNothing);
      expect(find.text('Купить кабель'), findsOneWidget);
    });

    testWidgets('a forgotten microphone stops itself at the ceiling', (
      tester,
    ) async {
      // The one failure mode a held button could not have, and the reason the
      // ceiling survived the removal of the hold. What was recorded up to the
      // limit is still recognised.
      await open(tester);

      await tester.pump(VoiceDictation.ceiling);
      await tester.pump();
      await tester.pump();

      expect(recorder.stopCount, 1);
      expect(find.text('Купить кабель'), findsOneWidget);
    });

    testWidgets('"Отменить" throws the recording away and leaves', (
      tester,
    ) async {
      final popped = await open(tester);
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(recorder.cancelCount, 1);
      expect(recognizer.transcribeCount, 0);
      expect(popped, <String?>[null]);
    });
  });

  group('while things are not ready', () {
    testWidgets('the screen is up and talking before the microphone is', (
      tester,
    ) async {
      // The visible half of the first-press race: the old code did this inside
      // a press gesture and threw the answer away when the gesture ended.
      final gate = _gate();
      recorder.permissionGate = gate;

      await open(tester);

      expect(find.text('Включаю микрофон'), findsOneWidget);
      expect(recorder.startCount, 0);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Слушаю'), findsOneWidget);
    });

    testWidgets('a model still loading is said, and does not stop the audio', (
      tester,
    ) async {
      final gate = _gate();
      recognizer.loadGate = gate;

      await open(tester);

      expect(recorder.recording, isTrue);
      expect(find.textContaining('модель ещё грузится'), findsOneWidget);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('модель ещё грузится'), findsNothing);
    });

    testWidgets('no model at all: the screen says so instead of vanishing', (
      tester,
    ) async {
      // The button is a navigation item now and is always there. Pressing it
      // with nothing installed has to produce an explanation, not a dead tap.
      await open(tester, modelReady: false);

      expect(recorder.startCount, 0);
      expect(find.text('Не получилось'), findsOneWidget);
      expect(find.textContaining('настройках'), findsOneWidget);
    });

    testWidgets('silence offers another go without leaving the screen', (
      tester,
    ) async {
      recognizer.text = '';
      await open(tester);

      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('расслышали'), findsOneWidget);

      recognizer.text = 'Купить кабель';
      await tester.tap(find.text('Ещё раз'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Слушаю'), findsOneWidget);
    });
  });

  group('a long recording', () {
    testWidgets('recognition shows how far it has got and what it heard', (
      tester,
    ) async {
      recognizer.chunks = const <String>['Первое.', 'Второе.', 'Третье.'];
      final gates = <Completer<void>>[_gate(), _gate(), _gate()];
      recognizer.beforeChunk = (i) => gates[i].future;
      await open(tester);
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Распознаю · 0 из 3'), findsOneWidget);
      // The length the user watched counting up stays on screen.
      expect(find.text('0:03'), findsOneWidget);

      gates[0].complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Распознаю · 1 из 3'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(1 / 3, 1e-9));
      expect(find.textContaining('Первое.'), findsOneWidget);
      expect(find.textContaining('Второе.'), findsNothing);

      gates[1].complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Распознаю · 2 из 3'), findsOneWidget);
      expect(find.textContaining('Второе.'), findsOneWidget);

      gates[2].complete();
      await tester.pump();
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Первое. Второе. Третье.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"почти готово" only on the last piece, and the way out', (
      tester,
    ) async {
      recognizer.chunks = const <String>['Раз.', 'Два.', 'Три.', 'Четыре.'];
      final gates = <Completer<void>>[_gate(), _gate(), _gate(), _gate()];
      recognizer.beforeChunk = (i) => gates[i].future;
      await open(tester);
      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();

      // Under the bar from the start: the answer to "may I put it away?".
      expect(
        find.text('можно закрыть экран — текст попадёт в песочницу'),
        findsOneWidget,
      );
      // No piece done, no estimate: nothing is guessed from nothing.
      expect(find.textContaining('осталось около'), findsNothing);
      expect(find.text('почти готово'), findsNothing);

      gates[0].complete();
      await tester.pump();
      await tester.pump();
      gates[1].complete();
      await tester.pump();
      await tester.pump();
      // "2 из 4" is not almost done, however quick the first two were.
      expect(find.text('Распознаю · 2 из 4'), findsOneWidget);
      expect(find.text('почти готово'), findsNothing);
      expect(find.textContaining('осталось около'), findsOneWidget);

      gates[2].complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Распознаю · 3 из 4'), findsOneWidget);
      expect(find.text('почти готово'), findsOneWidget);

      gates[3].complete();
      await tester.pump();
      await tester.pump();
    });

    testWidgets('closing the screen mid-recognition files the text in the '
        'sandbox, and says so', (tester) async {
      recognizer.chunks = const <String>['Первое.', 'Второе.'];
      final gate = _gate();
      recognizer.beforeChunk = (i) => i == 1 ? gate.future : _done();
      final popped = await open(tester);
      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Распознаю · 1 из 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Закрыть без записи'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(DictationScreen), findsNothing);
      expect(popped, <String?>[null]);
      // Not deleted while it is the only copy of what was said.
      expect(recorder.discarded, isEmpty);

      gate.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Диктовка распознана — в песочнице'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('открыть')),
      );
      // In the sandbox: still queued on the device, or already on the server.
      final queued = container.read(pendingCapturesProvider);
      expect(
        <String>[
          ...queued.map((e) => e.text),
          ...server.inbox.map((item) => item['text'] as String),
        ],
        <String>['Первое. Второе.'],
      );
      expect(recorder.discarded, <String>['dictation.wav']);
    });

    testWidgets('half a minute before the ceiling, the screen counts down', (
      tester,
    ) async {
      await open(tester);

      await tester.pump(VoiceDictation.ceiling - const Duration(seconds: 31));
      expect(find.textContaining('осталось'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('осталось 0:30'), findsOneWidget);
      expect(find.textContaining('остановится сама'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('осталось 0:20'), findsOneWidget);
      expect(recorder.recording, isTrue);

      // And at the ceiling: stopped, recognised, the words on screen. Not an
      // abort -- nothing said in those ten minutes is thrown away.
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      await tester.pump();

      expect(recorder.stopCount, 1);
      expect(recorder.cancelCount, 0);
      expect(find.textContaining('осталось'), findsNothing);
      expect(find.text('Купить кабель'), findsOneWidget);
    });
  });

  group('inserting', () {
    test('a second phrase is added, not swapped in', () {
      // Dictating twice in a row is normal: two thoughts on the way to the same
      // place. The caret ends up after the text, ready for a correction.
      final controller = TextEditingController(text: 'Позвонить в сервис');

      appendDictated(controller, text: 'насчёт гарантии');

      expect(controller.text, 'Позвонить в сервис насчёт гарантии');
      expect(controller.selection.baseOffset, controller.text.length);
    });

    test('an empty field does not start with a separator', () {
      final controller = TextEditingController();

      appendDictated(controller, text: 'Купить кабель', separator: '\n');

      expect(controller.text, 'Купить кабель');
    });
  });

  group('the clock', () {
    test('reads as minutes and seconds, never as 87', () {
      expect(formatDictationClock(Duration.zero), '0:00');
      expect(formatDictationClock(const Duration(seconds: 7)), '0:07');
      expect(formatDictationClock(const Duration(seconds: 87)), '1:27');
    });
  });

  group('the guess under the recognition bar', () {
    DictationRecognising at(int done, int total, {int? seconds}) =>
        DictationRecognising(
          length: const Duration(minutes: 4),
          done: done,
          total: total,
          remaining: seconds == null ? null : Duration(seconds: seconds),
        );

    test('"почти готово" only while the last piece is being recognised', () {
      // At "2 из 8" with two quick pieces behind it, the old rule said "почти
      // готово" -- a promise six more pieces then broke.
      expect(recognitionEstimate(at(2, 8, seconds: 1)), isNot('почти готово'));
      expect(recognitionEstimate(at(7, 8, seconds: 1)), 'почти готово');
      expect(recognitionEstimate(at(7, 8)), 'почти готово');
    });

    test('"осталось около" only when there is an estimate', () {
      expect(recognitionEstimate(at(0, 8)), isNull);
      expect(recognitionEstimate(at(2, 8)), isNull);
      expect(recognitionEstimate(at(2, 8, seconds: 22)), 'осталось около 20 с');
      expect(recognitionEstimate(at(2, 8, seconds: 1)), 'осталось около 5 с');
      expect(
        recognitionEstimate(at(1, 8, seconds: 130)),
        'осталось около 2 мин',
      );
    });

    test('nothing once every piece is done', () {
      expect(recognitionEstimate(at(8, 8, seconds: 0)), isNull);
    });
  });
}

/// A completer typed for the fakes' gates, so the tests read as English.
Completer<void> _gate() => Completer<void>();

Future<void> _done() => Future<void>.value();

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

class _MissingModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => const VoiceModelMissing();
}
