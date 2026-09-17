import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'support/fake_voice.dart';

/// The dictation gesture (F9), everywhere it ends somewhere other than text.
///
/// The happy path is one line; the reason this file exists is the rest of them.
/// A microphone that fails silently is worse than no microphone: the user
/// believes they wrote something down, which is the exact failure the sandbox
/// exists to prevent.
void main() {
  late FakeVoiceRecorder recorder;
  late FakeSpeechRecognizer recognizer;

  setUp(() {
    recorder = FakeVoiceRecorder();
    recognizer = FakeSpeechRecognizer();
  });

  ProviderContainer makeContainer({bool modelReady = true}) {
    final container = ProviderContainer(
      overrides: [
        voiceRecorderProvider.overrideWithValue(recorder),
        speechRecognizerProvider.overrideWithValue(recognizer),
        if (modelReady)
          voiceModelInstallationProvider.overrideWith(_ReadyModel.new)
        else
          voiceModelInstallationProvider.overrideWith(_MissingModel.new),
      ],
    );
    addTearDown(container.dispose);
    // A listener, not just a read: the dictation provider is auto-disposed, and
    // without one it would be torn down (and its state reset to idle) between
    // the press and the release -- which is also exactly what would happen on
    // screen if nothing watched it.
    container.listen(voiceDictationProvider, (_, _) {});
    return container;
  }

  group('a phrase that works', () {
    test('records, recognises, and hands back the text', () async {
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      expect(await dictation.start(), isTrue);
      expect(container.read(voiceDictationProvider), isA<DictationRecording>());

      final text = await dictation.stopAndTranscribe();

      expect(text, 'Купить кабель');
      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
      expect(recorder.recording, isFalse);
    });

    test('loads the model once across several phrases', () async {
      // Loading costs seconds and hundreds of megabytes; dictation is a gesture
      // people repeat three times in a row while walking.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      for (var i = 0; i < 3; i++) {
        await dictation.start();
        await dictation.stopAndTranscribe();
      }

      expect(recognizer.loadCount, 1);
      expect(recognizer.transcribeCount, 3);
    });

    test('a release during loading waits instead of failing', () async {
      // The first press pays for the load, and a short phrase can easily end
      // before the weights are in memory.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      final gate = Completer<void>();
      recognizer.loadGate = gate;

      await dictation.start();
      final pending = dictation.stopAndTranscribe();
      // One turn of the loop, so the recorder has stopped and the state has
      // moved on -- but the weights are still held by the gate.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(voiceDictationProvider), isA<DictationRecognising>());

      gate.complete();
      expect(await pending, 'Купить кабель');
    });
  });

  group('the ways it ends without text', () {
    test('no microphone permission: says so, records nothing', () async {
      recorder.permitted = false;
      final container = makeContainer();

      expect(await container.read(voiceDictationProvider.notifier).start(), isFalse);

      final state = container.read(voiceDictationProvider);
      expect(state, isA<DictationFailed>());
      expect((state as DictationFailed).message, contains('микрофон'));
      expect(recorder.startCount, 0);
    });

    test('no model: refuses before touching the microphone', () async {
      final container = makeContainer(modelReady: false);

      expect(await container.read(voiceDictationProvider.notifier).start(), isFalse);

      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
      expect(recorder.startCount, 0);
    });

    test('the recording never happened: reported, not left hanging', () async {
      recorder.recordingPath = null;
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await dictation.start();

      expect(await dictation.stopAndTranscribe(), isNull);
      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
    });

    test('silence is "ничего не расслышали", not an error', () async {
      // A button held by accident, or a phrase the model heard as nothing. The
      // difference between "it is broken" and "say it again".
      recognizer.text = '';
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await dictation.start();

      expect(await dictation.stopAndTranscribe(), isNull);
      final state = container.read(voiceDictationProvider);
      expect((state as DictationFailed).message, contains('расслышали'));
    });

    test('a recogniser that throws does not leave the button spinning', () async {
      recognizer.transcribeFailure = StateError('onnxruntime said no');
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await dictation.start();

      expect(await dictation.stopAndTranscribe(), isNull);
      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
    });

    test('a failed start is not a recording', () async {
      recorder.startFailure = Exception('the device is busy');
      final container = makeContainer();

      expect(await container.read(voiceDictationProvider.notifier).start(), isFalse);
      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
    });

    test('cancelling throws the audio away and says nothing', () async {
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await dictation.start();

      await dictation.cancel();

      expect(recorder.cancelCount, 1);
      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
      expect(recognizer.transcribeCount, 0);
    });

    test('a failure is cleared once it has been said', () async {
      recorder.permitted = false;
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await dictation.start();

      dictation.acknowledge();

      // A microphone stuck in a red error state is something the user has to
      // dismiss for no reason.
      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
    });

    test('stopping when nothing is recording does nothing at all', () async {
      final container = makeContainer();

      expect(
        await container.read(voiceDictationProvider.notifier).stopAndTranscribe(),
        isNull,
      );
      expect(recorder.stopCount, 0);
    });
  });

  group('the button appears only with a model', () {
    test('ready means yes', () async {
      expect(makeContainer().read(canDictateProvider), isTrue);
    });

    test('missing means no', () async {
      // A microphone button that answers "сначала скачайте 163 МБ" is a button
      // that lies about what it does.
      expect(makeContainer(modelReady: false).read(canDictateProvider), isFalse);
    });
  });
}

/// The installation provider with the disk probe replaced by an answer.
class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

class _MissingModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => const VoiceModelMissing();
}
