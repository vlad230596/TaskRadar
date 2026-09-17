import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/voice/voice_model.dart';
import 'package:taskradar/widgets/dictate_button.dart';

import 'support/fake_voice.dart';

/// The dictation gesture on screen (F9): hold, speak, release.
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
            body: DictateButton(onText: dictated.add),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Presses the button, holds it for [held], and releases.
  Future<void> hold(
    WidgetTester tester, {
    Duration held = const Duration(seconds: 2),
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DictateButton)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(held);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('holding records and the text lands in the field', (tester) async {
    await pump(tester);

    await hold(tester);

    expect(dictated, <String>['Купить кабель']);
    expect(recorder.startCount, 1);
    expect(recorder.stopCount, 1);
  });

  testWidgets('the icon says it is listening while the button is down', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DictateButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle();

    // ...and stops saying it afterwards.
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('a brush of the button is not an empty phrase', (tester) async {
    // Without the minimum hold this produces "ничего не расслышали", which
    // reads as a broken feature rather than a missed tap.
    await pump(tester);

    await hold(tester, held: const Duration(milliseconds: 100));

    expect(dictated, isEmpty);
    expect(recognizer.transcribeCount, 0);
    expect(find.text('Держите кнопку, пока говорите.'), findsOneWidget);
  });

  testWidgets('sliding the finger off cancels', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DictateButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await gesture.moveBy(const Offset(0, 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dictated, isEmpty);
    expect(recorder.cancelCount, 1);
    expect(recognizer.transcribeCount, 0);
  });

  testWidgets('a refused microphone is said out loud, once', (tester) async {
    recorder.permitted = false;
    await pump(tester);

    await hold(tester);

    expect(dictated, isEmpty);
    expect(find.textContaining('микрофон'), findsOneWidget);
    // And the button is not stuck in an error state afterwards.
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
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
