import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/capture_queue_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'support/fake_backend.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_voice.dart';

/// The dictation state machine, everywhere it ends somewhere other than text.
///
/// The happy path is one line; the reason this file exists is the rest of them.
/// A microphone that fails silently is worse than no microphone: the user
/// believes they wrote something down, which is the exact failure the sandbox
/// exists to prevent.
///
/// ## What F12 added here
///
/// The `locking` group is gone, because there is no hold and therefore nothing
/// to lock. In its place is `the first press`, which covers the three ordering
/// defects that made the old version fail on the first press of a session --
/// see the long note on `VoiceDictation`. Each of the three has a test that
/// fails against the old implementation:
///
/// - the screen is told the microphone is opening **before** the platform is
///   asked, so the answer can never arrive with nobody to receive it;
/// - a dismissal during that window leaves the machine idle, so the *next*
///   press is not refused as "already running";
/// - a weight load that throws becomes a stated failure rather than an
///   unhandled asynchronous error plus a second concurrent load.
void main() {
  late FakeVoiceRecorder recorder;
  late FakeSpeechRecognizer recognizer;
  late List<String> spoken;

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
    // two calls -- which is also exactly what would happen on screen if nothing
    // watched it.
    container.listen(voiceDictationProvider, (_, _) {});
    return container;
  }

  /// Starts a dictation the way the screen does.
  Future<bool> begin(VoiceDictation dictation) =>
      dictation.start(sink: spoken.add);

  group('a phrase that works', () {
    test('records, recognises, and delivers the text', () async {
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      expect(await begin(dictation), isTrue);
      expect(container.read(voiceDictationProvider), isA<DictationRecording>());

      await dictation.finish();

      expect(spoken, <String>['Купить кабель']);
      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
      expect(recorder.recording, isFalse);
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

    test('a finish during loading waits instead of failing', () async {
      // The first phrase pays for the load, and a short one can easily end
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

    test('says so while the weights are still coming', () async {
      // The audio is written from the first frame; only the recognition at the
      // end needs the model. A screen that did not say this looked exactly like
      // one that had hung.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      final gate = Completer<void>();
      recognizer.loadGate = gate;

      await begin(dictation);
      expect(
        (container.read(voiceDictationProvider) as DictationRecording)
            .modelLoading,
        isTrue,
      );
      expect(recorder.recording, isTrue);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        (container.read(voiceDictationProvider) as DictationRecording)
            .modelLoading,
        isFalse,
      );
    });
  });

  group('the first press', () {
    test('the screen is told it is starting before the platform is asked', () async {
      // Defect (1). The old code did the permission check inside a press
      // gesture and discarded the result if the gesture ended first -- which,
      // on a first run, it always did: the system dialog takes the window
      // focus, Flutter delivers a pointer cancel, and the half-started
      // recording was cancelled the moment it appeared.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      final gate = Completer<void>();
      recorder.permissionGate = gate;

      final starting = begin(dictation);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(voiceDictationProvider), isA<DictationStarting>());
      expect(recorder.startCount, 0);

      gate.complete();
      expect(await starting, isTrue);
      expect(container.read(voiceDictationProvider), isA<DictationRecording>());
    });

    test('dismissing during the prompt leaves it idle, not half-started', () async {
      // ...and therefore the *next* press is not refused with "already
      // running", which is the old bug wearing a different hat.
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      final gate = Completer<void>();
      recorder.permissionGate = gate;

      unawaited(begin(dictation));
      await Future<void>.delayed(Duration.zero);
      await dictation.cancel();

      expect(container.read(voiceDictationProvider), isA<DictationIdle>());

      gate.complete();
      await Future<void>.delayed(Duration.zero);

      recorder.permissionGate = null;
      expect(await begin(dictation), isTrue);
    });

    test('it waits for the disk probe instead of guessing', () async {
      // The third face of the same bug, and the only one that needs the *real*
      // installation provider: `build` cannot answer synchronously (finding out
      // whether 236 MB are on disk is a filesystem round trip), so it answers
      // `VoiceModelUnknown` and corrects itself a moment later.
      //
      // A `start` that read that snapshot said "модель ещё не скачана" about a
      // model sitting on the disk. Press again a second later and it worked --
      // which is complaint number two, word for word.
      final container = ProviderContainer(
        overrides: [
          voiceRecorderProvider.overrideWithValue(recorder),
          speechRecognizerProvider.overrideWithValue(recognizer),
          voiceModelStoreProvider.overrideWithValue(
            FakeVoiceModelStore(present: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(voiceDictationProvider, (_, _) {});

      // The state the first press actually finds.
      expect(
        container.read(voiceModelInstallationProvider),
        isA<VoiceModelUnknown>(),
      );

      final dictation = container.read(voiceDictationProvider.notifier);
      expect(await dictation.start(sink: spoken.add), isTrue);
      expect(
        container.read(voiceDictationProvider),
        isA<DictationRecording>(),
      );
    });

    test('starting twice is a no-op, not a second recording', () async {
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      expect(await begin(dictation), isTrue);
      expect(await begin(dictation), isFalse);

      expect(recorder.startCount, 1);
      expect(container.read(voiceDictationProvider), isA<DictationRecording>());
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

    test('weights that will not load are said once, not loaded twice', () async {
      // Defect (2). The old `_ensureLoaded` was fired with `unawaited` and
      // cleared its dedupe handle in `whenComplete`, so a throwing `load`
      // escaped into the zone *and* left `finish` free to start a second load
      // of the same 236 MB. Both halves are asserted here: the failure is a
      // state, and the count is one.
      recognizer.loadFailure = StateError('onnxruntime said no');
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      await begin(dictation);
      await dictation.finish();

      expect(spoken, isEmpty);
      expect(recognizer.loadCount, 1);
      expect(recognizer.transcribeCount, 0);

      final state = container.read(voiceDictationProvider) as DictationFailed;
      expect(state.message, contains('Модель'));
      expect(state.retryable, isFalse);
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
      // A screen opened by accident, or a phrase the model heard as nothing.
      // The difference between "it is broken" and "say it again".
      recognizer.text = '';
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);

      await dictation.finish();

      expect(spoken, isEmpty);
      final state = container.read(voiceDictationProvider) as DictationFailed;
      expect(state.message, contains('расслышали'));
      // ...and this one *is* worth another go, on the same screen.
      expect(state.retryable, isTrue);
    });

    test('"ещё раз" reopens the microphone into the same sink', () async {
      recognizer.text = '';
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      await begin(dictation);
      await dictation.finish();

      recognizer.text = 'Купить кабель';
      await dictation.retry();

      expect(container.read(voiceDictationProvider), isA<DictationRecording>());

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

    test('a recogniser that throws does not leave the screen spinning', () async {
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

  group('whether it can record at all', () {
    test('ready means yes', () async {
      expect(makeContainer().read(canDictateProvider), isTrue);
    });

    test('missing means no', () async {
      // The *button* is still on screen -- it is a navigation item now, and one
      // that disappears is a bar whose other items move. What it no longer does
      // is record; the screen it opens says why.
      expect(makeContainer(modelReady: false).read(canDictateProvider), isFalse);
    });
  });

  group('a long recording', () {
    test('reports each piece as it is recognised, then delivers once', () async {
      // Ten minutes is tens of seconds of decoding. The state says how far it
      // has got and what has been heard so far; the sink still hears the whole
      // text exactly once, at the end.
      recognizer.chunks = const <String>['Первое.', 'Второе', ', третье.'];
      final gates = <Completer<void>>[
        Completer<void>(),
        Completer<void>(),
        Completer<void>(),
      ];
      recognizer.beforeChunk = (i) => gates[i].future;

      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      final seen = <DictationRecognising>[];
      container.listen(voiceDictationProvider, (_, next) {
        if (next is DictationRecognising) seen.add(next);
      });

      await begin(dictation);
      final pending = dictation.finish();
      await Future<void>.delayed(Duration.zero);

      var state = container.read(voiceDictationProvider) as DictationRecognising;
      expect((state.done, state.total), (0, 3));
      expect(state.partialText, isEmpty);
      expect(state.fraction, 0);

      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      state = container.read(voiceDictationProvider) as DictationRecognising;
      expect((state.done, state.total), (1, 3));
      expect(state.partialText, 'Первое.');
      expect(spoken, isEmpty);

      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      state = container.read(voiceDictationProvider) as DictationRecognising;
      expect(state.done, 2);
      expect(state.partialText, 'Первое. Второе');

      gates[2].complete();
      await pending;

      expect(container.read(voiceDictationProvider), isA<DictationIdle>());
      expect(spoken, <String>['Первое. Второе, третье.']);
      // Monotonic: the bar never goes backwards.
      final dones = seen.map((s) => s.done).toList();
      expect(dones, orderedEquals(<int>[...dones]..sort()));
      expect(seen.last.done, 3);
    });

    test('the length of the recording stays on screen throughout', () async {
      recognizer.chunks = const <String>['Раз.', 'Два.'];
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);
      final lengths = <Duration>{};
      container.listen(voiceDictationProvider, (_, next) {
        if (next is DictationRecognising) lengths.add(next.length);
      });

      await begin(dictation);
      await dictation.finish();

      expect(lengths, hasLength(1));
      expect(spoken, <String>['Раз. Два.']);
    });

    test('a piece that fails fails the whole, with nothing delivered', () async {
      // Half a text delivered as if it were the whole would be the worst of
      // the outcomes: the user would not know the rest was missing.
      recognizer.chunks = const <String>['Первое.', 'Второе.'];
      recognizer.beforeChunk = (i) async {
        if (i == 1) throw StateError('onnxruntime said no');
      };
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      await begin(dictation);
      await dictation.finish();

      expect(container.read(voiceDictationProvider), isA<DictationFailed>());
      expect(spoken, isEmpty);
    });

    test('the recording is thrown away only once its text is delivered', () async {
      final gate = Completer<void>();
      recognizer.chunks = const <String>['Первое.', 'Второе.'];
      recognizer.beforeChunk =
          (i) => i == 1 ? gate.future : Future<void>.value();
      final container = makeContainer();
      final dictation = container.read(voiceDictationProvider.notifier);

      await begin(dictation);
      final pending = dictation.finish();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.discarded, isEmpty);

      gate.complete();
      await pending;
      expect(spoken, <String>['Первое. Второе.']);
      expect(recorder.discarded, <String>['dictation.wav']);
    });

    test('the ceiling is ten minutes, with a warning half a minute before', () {
      expect(VoiceDictation.ceiling, const Duration(minutes: 10));

      const early = DictationRecording(
        elapsed: Duration(minutes: 9, seconds: 29),
        modelLoading: false,
      );
      const due = DictationRecording(
        elapsed: Duration(minutes: 9, seconds: 30),
        modelLoading: false,
      );
      expect(early.nearCeiling, isFalse);
      expect(due.nearCeiling, isTrue);
      expect(due.left, const Duration(seconds: 30));
    });
  });

  group('a screen closed mid-recognition', _closedMidRecognition);
}

/// A screen closed while its dictation is still being recognised: the
/// recognition carries on without it and the text lands in the sandbox.
void _closedMidRecognition() {
  late FakeVoiceRecorder recorder;
  late FakeSpeechRecognizer recognizer;
  late FakeCaptureQueueStore store;
  late FakeProjectBackend server;
  late Completer<void> gate;
  late List<String> spoken;

  setUp(() {
    recorder = FakeVoiceRecorder();
    gate = Completer<void>();
    recognizer = FakeSpeechRecognizer()
      ..chunks = const <String>['Первое.', 'Второе.']
      ..beforeChunk = (i) => i == 1 ? gate.future : Future<void>.value();
    store = FakeCaptureQueueStore();
    spoken = <String>[];
  });

  /// A container, and the screen's listener on the dictation -- closed by a
  /// test to stand for the screen going away.
  (ProviderContainer, ProviderSubscription<DictationState>) makeContainer() {
    final backend = FakeBackend();
    server = FakeProjectBackend(backend);
    final container = ProviderContainer(
      overrides: [
        voiceRecorderProvider.overrideWithValue(recorder),
        speechRecognizerProvider.overrideWithValue(recognizer),
        voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
        apiClientProvider.overrideWithValue(backend.client),
        captureQueueStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    final screen = container.listen(voiceDictationProvider, (_, _) {});
    return (container, screen);
  }

  test('carries on with nobody watching, and files the text in the sandbox', () async {
    final (container, screen) = makeContainer();
    final dictation = container.read(voiceDictationProvider.notifier);
    final said = <String>[];

    await dictation.start(sink: spoken.add);
    final pending = dictation.finish();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(voiceDictationProvider), isA<DictationRecognising>());

    // The screen goes: it hands the dictation over, and stops listening.
    expect(dictation.detach(announce: said.add), isTrue);
    screen.close();
    await Future<void>.delayed(Duration.zero);
    // Still alive, still holding the recording and the recogniser.
    expect(recognizer.unloadCount, 0);
    expect(recorder.discarded, isEmpty);

    gate.complete();
    await pending;
    // The capture's own send, so this test owns every future it started.
    await container.read(captureQueueProvider.notifier).flush();

    expect(spoken, isEmpty);
    expect(<String>[
      ...container.read(pendingCapturesProvider).map((e) => e.text),
      ...server.inbox.map((item) => item['text'] as String),
    ], <String>['Первое. Второе.']);
    expect(said, <String>['Диктовка распознана — в песочнице']);
    // Delivered, so now -- and only now -- the file goes.
    expect(recorder.discarded, <String>['dictation.wav']);
  });

  test('keeps the recording when the sandbox could not take the text', () async {
    final (container, screen) = makeContainer();
    final dictation = container.read(voiceDictationProvider.notifier);
    final said = <String>[];
    await container.read(captureQueueProvider.future);
    store.writeFailure = Exception('disk full');

    await dictation.start(sink: spoken.add);
    final pending = dictation.finish();
    await Future<void>.delayed(Duration.zero);
    dictation.detach(announce: said.add);
    screen.close();
    gate.complete();
    await pending;

    expect(said.single, contains('не удалось'));
    expect(recorder.discarded, isEmpty);
  });

  test('says so when the closed dictation heard nothing', () async {
    recognizer.chunks = const <String>['', ''];
    final (container, screen) = makeContainer();
    final dictation = container.read(voiceDictationProvider.notifier);
    final said = <String>[];

    await dictation.start(sink: spoken.add);
    final pending = dictation.finish();
    await Future<void>.delayed(Duration.zero);
    dictation.detach(announce: said.add);
    screen.close();
    gate.complete();
    await pending;

    expect(said.single, startsWith('Диктовка не распознана'));
    expect(store.queue, isEmpty);
  });

  test('a screen opened meanwhile takes the text over', () async {
    final (container, screen) = makeContainer();
    final dictation = container.read(voiceDictationProvider.notifier);
    final said = <String>[];
    final reopened = <String>[];

    await dictation.start(sink: spoken.add);
    final pending = dictation.finish();
    await Future<void>.delayed(Duration.zero);
    dictation.detach(announce: said.add);
    screen.close();

    // The microphone pressed again before the first dictation is done.
    container.listen(voiceDictationProvider, (_, _) {});
    expect(await dictation.start(sink: reopened.add), isFalse);
    expect(recorder.startCount, 1);

    gate.complete();
    await pending;
    expect(reopened, <String>['Первое. Второе.']);
    expect(store.queue, isEmpty);
    expect(said, isEmpty);
  });

  test('closing a screen with nothing being recognised hands nothing over', () async {
    final (container, _) = makeContainer();
    final dictation = container.read(voiceDictationProvider.notifier);
    expect(dictation.detach(), isFalse);
    await dictation.start(sink: spoken.add);
    expect(dictation.detach(), isFalse);
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
