import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/dictation_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/voice/voice_model.dart';
import 'package:taskradar/widgets/dictation.dart';

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

  setUp(() {
    recorder = FakeVoiceRecorder();
    recognizer = FakeSpeechRecognizer();
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
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<String>(
                      MaterialPageRoute<String>(
                        builder: (_) => const DictationScreen(
                          destination: FieldDestination('в задачу'),
                        ),
                      ),
                    );
                    popped.add(result);
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

    testWidgets('the recognised text is 25 px, which is the point', (
      tester,
    ) async {
      // Complaint number one, on the screen where it hurt most: a dictated
      // sentence you cannot read is a sentence you cannot correct.
      await open(tester);
      await tester.tap(find.text('Готово'));
      await tester.pump();
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.fontSize, 25);
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
}

/// A completer typed for the fakes' gates, so the tests read as English.
Completer<void> _gate() => Completer<void>();

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

class _MissingModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => const VoiceModelMissing();
}
