import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/voice/voice_model.dart';
import 'package:taskradar/widgets/dictation.dart';

import 'support/fake_voice.dart';

/// Dictation on screen (F9), after the rework that came out of testing it on a
/// phone: hold *or* tap, a target a thumb can find, and a panel that says what
/// is happening.
///
/// Note the near-absence of `pumpAndSettle` below. The panel pulses a dot while
/// recording and runs an indeterminate bar while recognising, so there is
/// always another frame scheduled and "settle" never arrives; the tests pump
/// explicit durations instead, which is also the only way to move a clock the
/// user is meant to read.
void main() {
  late FakeVoiceRecorder recorder;
  late FakeSpeechRecognizer recognizer;
  late List<String> dictated;

  setUp(() {
    recorder = FakeVoiceRecorder();
    recognizer = FakeSpeechRecognizer();
    dictated = <String>[];
  });

  Future<void> pump(WidgetTester tester, {bool modelReady = true}) async {
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
          home: Scaffold(
            body: DictatedField(
              onText: dictated.add,
              field: const TextField(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final Finder mic = find.byType(DictateButton);

  /// Presses the button, holds it for [held], and releases.
  Future<void> hold(
    WidgetTester tester, {
    Duration held = const Duration(seconds: 2),
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(held);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('holding', () {
    testWidgets('press, speak, release: the text lands in the field', (
      tester,
    ) async {
      await pump(tester);

      await hold(tester);

      expect(dictated, <String>['Купить кабель']);
      expect(recorder.startCount, 1);
      expect(recorder.stopCount, 1);
    });

    testWidgets('the panel says it is listening while the button is down', (
      tester,
    ) async {
      await pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Говорите — отпустите, когда всё'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      // Nothing to press: the finger is already on the one control there is.
      expect(find.text('Готово'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Говорите — отпустите, когда всё'), findsNothing);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
    });

    testWidgets('sliding the finger off cancels', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 600));

      await gesture.moveBy(const Offset(0, 300));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dictated, isEmpty);
      expect(recorder.cancelCount, 1);
      expect(recognizer.transcribeCount, 0);
    });
  });

  group('tapping', () {
    testWidgets('a short press locks the recording instead of scolding', (
      tester,
    ) async {
      // This is the press that used to answer "Держите кнопку, пока говорите" --
      // the app telling somebody off for the one gesture a phone has.
      await pump(tester);

      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();

      expect(find.text('Держите кнопку, пока говорите.'), findsNothing);
      expect(find.text('Идёт запись'), findsOneWidget);
      expect(find.text('Готово'), findsOneWidget);
      expect(recorder.recording, isTrue);
    });

    testWidgets('the clock counts the seconds up', (tester) async {
      await pump(tester);

      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();

      expect(find.text('0:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('0:07'), findsOneWidget);

      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(dictated, <String>['Купить кабель']);
    });

    testWidgets('"Отменить" throws the recording away', (tester) async {
      await pump(tester);

      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(dictated, isEmpty);
      expect(recorder.cancelCount, 1);
      expect(recognizer.transcribeCount, 0);
    });

    testWidgets('a forgotten microphone stops itself at the ceiling', (
      tester,
    ) async {
      // The one failure mode a held button cannot have. What is recorded up to
      // the limit is still recognised -- throwing away two minutes of speech
      // because nobody noticed a limit would be the worse answer.
      await pump(tester);

      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(VoiceDictation.ceiling);
      await tester.pumpAndSettle();

      expect(recorder.stopCount, 1);
      expect(dictated, <String>['Купить кабель']);
    });
  });

  group('when it does not work', () {
    testWidgets('a refused microphone is said in the panel, with no retry', (
      tester,
    ) async {
      recorder.permitted = false;
      await pump(tester);

      await hold(tester);

      expect(dictated, isEmpty);
      expect(find.textContaining('микрофон'), findsOneWidget);
      // Saying it again cannot grant a permission, so it is not offered.
      expect(find.text('Ещё раз'), findsNothing);

      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(find.textContaining('микрофон'), findsNothing);
    });

    testWidgets('silence offers another go from the same panel', (
      tester,
    ) async {
      recognizer.text = '';
      await pump(tester);

      await hold(tester);
      expect(find.text('Ничего не расслышали.'), findsOneWidget);

      recognizer.text = 'Купить кабель';
      await tester.tap(find.text('Ещё раз'));
      await tester.pump();

      // Straight back into a locked recording: the user just pressed a button
      // to get here and has no finger on anything to hold.
      expect(find.text('Идёт запись'), findsOneWidget);

      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(dictated, <String>['Купить кабель']);
    });
  });

  testWidgets('no model, no microphone on screen', (tester) async {
    // A button that answers "сначала скачайте 163 МБ" is a button that lies
    // about what it does; the download lives in Settings.
    await pump(tester, modelReady: false);

    expect(mic, findsNothing);
  });

  testWidgets('two fields on one screen: only the pressed one lights up', (
    tester,
  ) async {
    final title = <String>[];
    final body = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceRecorderProvider.overrideWithValue(recorder),
          speechRecognizerProvider.overrideWithValue(recognizer),
          voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DictatedField(onText: title.add, field: const TextField()),
                DictatedField(onText: body.add, field: const TextField()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(mic.first));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();

    // One recording, one panel -- not one per microphone on screen.
    expect(find.text('Идёт запись'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();

    expect(title, <String>['Купить кабель']);
    expect(body, isEmpty);
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

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

class _MissingModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => const VoiceModelMissing();
}
