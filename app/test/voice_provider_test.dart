import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'support/fake_voice.dart';

/// The dictation state machine (F9), everywhere it ends somewhere other than
/// text.
///
/// The happy path is one line; the reason this file exists is the rest of them.
/// A microphone that fails silently is worse than no microphone: the user
/// believes they wrote something down, which is the exact failure the sandbox
/// exists to prevent.
void main() {
  late FakeVoiceRecorder recorder;
  late FakeSpeechRecognizer recognizer;
  late List<String> spoken;

  /// Stands in for the field a dictation belongs to. Opaque by design -- the
  /// notifier never looks inside it, it only has to come back unchanged.
  final Object field = Object();

  setUp(() {
    recorder = FakeVoiceRecorder();
    recognizer = FakeSpeechRecognizer();
    spoken = <String>[];
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

  /// Starts a dictation the way a field does, with somewhere for the text to go.
  Future<bool> begin(VoiceDictation dictation, {bool locked = false}) =>
      dictation.start(owner: field, sink: spoken.add, locked: locked);

  group('a phrase that works', () {
    test('records, recognises, and delivers the text to the field', () async {
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      expect(await begin(dictation), isTrue);
      expect(container.read(voiceDictationProvider), isA<DictationRecording>());

      await dictation.finish();

      expect(spoken, <String>['Купить кабель']);
      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
      expect(recorder.recording, isFalse);
    });

    test('says which field it belongs to, from the first press', () async {
      // Two microphones can be on one screen (a note has a title and a body),
      // and only the one that was pressed may light up.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      await begin(dictation);
      expect(container.read(voiceDictationProvider).owner, same(field));

      await dictation.finish();
      expect(container.read(voiceDictationProvider).owner, isNull);
    });

    test('loads the model once across several phrases', () async {
      // Loading costs seconds and hundreds of megabytes; dictation is a gesture
      // people repeat three times in a row while walking.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      for (var i = 0; i < 3; i++) {
        await begin(dictation);
        await dictation.finish();
      }

      expect(recognizer.loadCount, 1);
      expect(recognizer.transcribeCount, 3);
      expect(spoken, hasLength(3));
    });

    test('a release during loading waits instead of failing', () async {
      // The first press pays for the load, and a short phrase can easily end
      // before the weights are in memory.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      final gate = Completer<void>();
      recognizer.loadGate = gate;

      await begin(dictation);
      final pending = dictation.finish();
      // One turn of the loop, so the recorder has stopped and the state has
      // moved on -- but the weights are still held by the gate.
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(voiceDictationProvider),
        isA<DictationRecognising>(),
      );

      gate.complete();
      await pending;
      expect(spoken, <String>['Купить кабель']);
    });
  });

  group('locking', () {
    test('a locked recording is the same recording, running alone', () async {
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      await begin(dictation);
      expect(
        (container.read(voiceDictationProvider) as DictationRecording).locked,
        isFalse,
      );

      dictation.lock();

      final state = container.read(voiceDictationProvider) as DictationRecording;
      expect(state.locked, isTrue);
      // Locking is a change of who ends it, not a restart: the microphone was
      // never touched.
      expect(recorder.startCount, 1);
      expect(recorder.stopCount, 0);
    });

    test('locking something that is not recording does nothing', () async {
      final container = makeContainer();
      container.read(voiceDictationProvider.notifier).lock();

      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
    });
  });

  group('the ways it ends without text', () {
    test('no microphone permission: says so, records nothing', () async {
      recorder.permitted = false;
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      expect(await begin(dictation), isFalse);

      final state = container.read(voiceDictationProvider);
      expect(state, isA<DictationFailed>());
      expect((state as DictationFailed).message, contains('микрофон'));
      // Nothing to retry: saying it again cannot grant a permission.
      expect(state.retryable, isFalse);
      expect(recorder.startCount, 0);
    });

    test('no model: refuses before touching the microphone', () async {
      final container = makeContainer(modelReady: false);
      final dictation = container.read(voiceDictationProvider.notifier);

      expect(await begin(dictation), isFalse);

      final state = container.read(voiceDictationProvider);
      expect(state, isA<DictationFailed>());
      expect((state as DictationFailed).retryable, isFalse);
      expect(recorder.startCount, 0);
    });

    test('the recording never happened: reported, not left hanging', () async {
      recorder.recordingPath = null;
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);

      await dictation.finish();

      expect(spoken, isEmpty);
      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
    });

    test('silence is "ничего не расслышали", not an error', () async {
      // A button pressed by accident, or a phrase the model heard as nothing.
      // The difference between "it is broken" and "say it again".
      recognizer.text = '';
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);

      await dictation.finish();

      expect(spoken, isEmpty);
      final state = container.read(voiceDictationProvider) as DictationFailed;
      expect(state.message, contains('расслышали'));
      // ...and this one *is* worth another go, from the same panel.
      expect(state.retryable, isTrue);
    });

    test('"ещё раз" reopens the microphone for the same field', () async {
      recognizer.text = '';
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);
      await dictation.finish();

      recognizer.text = 'Купить кабель';
      await dictation.retry();

      final state = container.read(voiceDictationProvider);
      expect(state, isA<DictationRecording>());
      expect(state.owner, same(field));
      // Locked, because the user got here by pressing a button rather than by
      // holding one, and there is no finger on anything to release.
      expect((state as DictationRecording).locked, isTrue);

      await dictation.finish();
      expect(spoken, <String>['Купить кабель']);
    });

    test('"ещё раз" is refused for a failure it cannot fix', () async {
      recorder.permitted = false;
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);

      await dictation.retry();

      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
      expect(recorder.startCount, 0);
    });

    test('a recogniser that throws does not leave the panel spinning', () async {
      recognizer.transcribeFailure = StateError('onnxruntime said no');
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);

      await dictation.finish();

      expect(spoken, isEmpty);
      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
    });

    test('a failed start is not a recording', () async {
      recorder.startFailure = Exception('the device is busy');
      final container = makeContainer();

      expect(
        await begin(container.read(voiceDictationProvider.notifier)),
        isFalse,
      );
      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
    });

    test('cancelling throws the audio away and says nothing', () async {
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);

      await dictation.cancel();

      expect(recorder.cancelCount, 1);
      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
      expect(recognizer.transcribeCount, 0);
      expect(spoken, isEmpty);
    });

    test('a failure is cleared once it has been said', () async {
      recorder.permitted = false;
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);

      dictation.acknowledge();

      // A microphone stuck in a red error state is something the user has to
      // dismiss for no reason.
      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
    });

    test('finishing when nothing is recording does nothing at all', () async {
      final container = makeContainer();

      await container.read(voiceDictationProvider.notifier).finish();

      expect(recorder.stopCount, 0);
      expect(spoken, isEmpty);
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
