import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../voice/speech_recognizer.dart';
import '../voice/voice_model.dart';
import '../voice/voice_model_store.dart';
import '../voice/voice_recorder.dart';

part 'voice_providers.g.dart';

/// Voice input (F9), in three providers: where the model is, and what the
/// microphone is doing.
///
/// ## Why the singletons live here and not in `dependencies.dart`
///
/// Everything in `dependencies.dart` is needed by the app as a whole. These
/// three are the entire surface of one optional feature: on a machine that
/// never downloads the model, none of them is ever constructed. Keeping them
/// together with the state that uses them means the feature can be read -- or
/// removed -- in one place.

/// Where the model lives on disk. Owns `path_provider` and a `Dio` of its own
/// (deliberately *not* the app's [apiClient]: that one carries a bearer token
/// and a 401 interceptor, and a 163 MB download from GitHub must not send the
/// user's session anywhere).
@Riverpod(keepAlive: true)
VoiceModelStore voiceModelStore(Ref ref) => VoiceModelStore();

/// The microphone. Disposed with the screen that used it, so the platform
/// releases the input device rather than holding it for the app's lifetime.
@riverpod
VoiceRecorder voiceRecorder(Ref ref) {
  final recorder = RecordVoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
}

/// The recogniser. Same lifetime as [voiceRecorder] and for a bigger reason:
/// loaded, it holds hundreds of megabytes of weights, and that has to go back
/// when the user leaves the screen.
@riverpod
SpeechRecognizer speechRecognizer(Ref ref) {
  final recognizer = SherpaSpeechRecognizer();
  ref.onDispose(() => unawaited(recognizer.unload()));
  return recognizer;
}

/// Is the speech model on this device, and getting it here if not.
@Riverpod(keepAlive: true)
class VoiceModelInstallation extends _$VoiceModelInstallation {
  CancelToken? _cancel;

  @override
  VoiceModelState build() {
    // No probe on web: the store behind it is `path_provider` plus `dart:io`,
    // which answers `MissingPluginException` in a browser, and the answer is
    // known without asking anyway.
    if (kIsWeb) return const VoiceModelUnsupported();
    unawaited(_probe());
    return const VoiceModelUnknown();
  }

  VoiceModel get model => VoiceModel.gigaAmV3Punct;

  Future<void> _probe() async {
    final installed = await ref.read(voiceModelStoreProvider).installed(model);
    if (!ref.mounted) return;
    // A probe that finishes while a download is running must not overwrite it:
    // the download is the newer truth about the same question.
    if (state is VoiceModelInstalling) return;
    state = installed == null
        ? const VoiceModelMissing()
        : VoiceModelReady(installed);
  }

  /// Downloads and unpacks the model. Never throws -- the failure is the state.
  Future<void> install() async {
    if (state is VoiceModelUnsupported) return;
    if (state is VoiceModelInstalling || state is VoiceModelReady) return;

    final cancel = _cancel = CancelToken();
    state = const VoiceModelInstalling(
      receivedBytes: 0,
      totalBytes: -1,
      unpacking: false,
    );

    try {
      final installed = await ref
          .read(voiceModelStoreProvider)
          .install(
            model,
            cancelToken: cancel,
            onProgress: (received, total) {
              if (!ref.mounted || state is! VoiceModelInstalling) return;
              state = VoiceModelInstalling(
                receivedBytes: received,
                totalBytes: total,
                unpacking: false,
              );
            },
            onUnpacking: () {
              if (!ref.mounted || state is! VoiceModelInstalling) return;
              final current = state as VoiceModelInstalling;
              state = VoiceModelInstalling(
                receivedBytes: current.receivedBytes,
                totalBytes: current.totalBytes,
                unpacking: true,
              );
            },
          );
      if (!ref.mounted) return;
      state = VoiceModelReady(installed);
    } catch (error) {
      if (!ref.mounted) return;
      // A cancel is not a failure and must not be reported as one; everything
      // else keeps its message, because "не удалось" with no reason is useless
      // for something that can fail on the network, on disk space, or on a file
      // the archive did not contain.
      state = VoiceModelMissing(
        lastError: cancel.isCancelled ? null : _describe(error),
      );
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  /// Stops a download in progress. The half-file is cleaned up by the store.
  void cancelInstall() => _cancel?.cancel('cancelled by the user');

  /// Deletes the model. The recogniser is unloaded first: freeing the weights
  /// after deleting the file they came from is an ordering nobody has to think
  /// about twice.
  Future<void> remove() async {
    await ref.read(speechRecognizerProvider).unload();
    await ref.read(voiceModelStoreProvider).remove(model);
    if (!ref.mounted) return;
    state = const VoiceModelMissing();
  }

  String _describe(Object error) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.connectionError => 'нет связи с сервером модели',
        _ => 'сервер модели ответил ошибкой',
      };
    }
    return error.toString();
  }
}

/// Whether the microphone button should be on screen at all.
///
/// False while the model is missing on purpose: the button's job is to record,
/// and one that answers "сначала скачайте 163 МБ" is a button that lies about
/// what it does. Offering the download is Settings' job, and the composer says
/// so in a line of text instead.
@riverpod
bool canDictate(Ref ref) =>
    ref.watch(voiceModelInstallationProvider) is VoiceModelReady;

/// What the microphone is doing right now.
///
/// ## Why every state carries an [owner]
///
/// The microphone stopped being a fixture of the sandbox and became something
/// every text field has, so a screen can now hold more than one of them -- a
/// note has a title and a body. There is still exactly one microphone and one
/// state machine, so the state has to say *whose* dictation is running, or both
/// fields would light up and both panels would claim the same recording. The
/// owner is an opaque token minted by the widget that started it; nothing here
/// ever looks inside it.
sealed class DictationState {
  const DictationState();

  /// The field this dictation belongs to, or null when nothing is running.
  Object? get owner => null;
}

class DictationIdle extends DictationState {
  const DictationIdle();
}

/// The microphone is open.
///
/// [elapsed] is counted here rather than by the widget, and that split is not
/// arbitrary: a panel computing `DateTime.now().difference(startedAt)` looks
/// right on a phone and never advances in a widget test, because
/// `tester.pump(Duration)` moves the framework's clock and not the wall clock.
/// A periodic timer moves with both, so the seconds the user reads are the same
/// seconds a test can assert on.
class DictationRecording extends DictationState {
  const DictationRecording({
    required this.owner,
    required this.elapsed,
    required this.locked,
  });

  @override
  final Object owner;

  final Duration elapsed;

  /// True once the recording carries on by itself: the finger is off the button
  /// and only "Готово" -- or [VoiceDictation.ceiling] -- ends it. False means a
  /// finger is still holding the button down, and releasing it finishes the
  /// phrase.
  final bool locked;
}

/// The recording has ended and the model is working.
class DictationRecognising extends DictationState {
  const DictationRecognising({required this.owner, required this.length});

  @override
  final Object owner;

  /// How long the recording being recognised was. Shown so the panel does not
  /// go blank in the seconds the model takes: the number the user watched
  /// counting up stays on screen instead of resetting to nothing.
  final Duration length;
}

class DictationFailed extends DictationState {
  const DictationFailed(
    this.message, {
    required this.owner,
    this.retryable = true,
  });

  @override
  final Object owner;

  final String message;

  /// Whether saying it again could work. False for the two failures that are
  /// about the device rather than the phrase -- no permission, no model --
  /// where an "Ещё раз" button would only fail the same way again.
  final bool retryable;
}

/// The dictation gesture: start, speak, stop, get text.
///
/// ## Why this is a state machine and not three awaits in the widget
///
/// Because every step of it can end somewhere other than "text": permission
/// refused, a release while the model is still loading, a phrase the recogniser
/// heard as silence, a recording that ran into the ceiling. Each of those needs
/// a different thing said to the user, and a widget holding that in local state
/// would end up with the same machine, spelled less clearly and untested.
///
/// ## Why the text is delivered through a sink instead of returned
///
/// It used to be returned to the widget that held the button, which worked
/// while the only way to end a dictation was to lift the finger off that
/// button. It no longer is: a locked recording is ended from the panel, which
/// is a different widget and deliberately knows nothing about which field the
/// text belongs in. So the field hands its own insertion callback over when the
/// dictation starts, and whoever ends it -- the button, the panel, the ceiling
/// -- delivers to the same place.
@riverpod
class VoiceDictation extends _$VoiceDictation {
  /// The longest a single dictation can run.
  ///
  /// The ceiling exists for the locked recording specifically: a held button
  /// cannot be forgotten, whereas one that runs on its own can be started in a
  /// pocket and left there. Two minutes is well past "надо не забыть" -- it is
  /// around 300 words -- and it bounds both the file and the time the model
  /// spends on it, which on a phone is several seconds per minute of audio.
  static const Duration ceiling = Duration(minutes: 2);

  @override
  DictationState build() {
    /*
     * Watched rather than read on demand, and that is the lifetime rule for the
     * whole feature.
     *
     * Both of these are auto-disposed, and the recogniser holds hundreds of
     * megabytes of weights while it is loaded. Reaching for them with `read`
     * inside the methods would leave them with no listener at all: Riverpod
     * would dispose them between two phrases, unload the model, and the next
     * press would pay the multi-second load again -- on a gesture whose whole
     * point is that it is repeated three times in a row while walking.
     *
     * Watching here ties them to *this* provider, which the button watches in
     * turn. So: the weights are in memory exactly while a screen with a
     * microphone on it is open, and are freed when it goes away.
     */
    ref.watch(voiceRecorderProvider);
    ref.watch(speechRecognizerProvider);

    // A screen torn down mid-phrase must not leave a timer ticking into a
    // notifier that no longer exists.
    ref.onDispose(() {
      _clock?.cancel();
      _clock = null;
    });

    return const DictationIdle();
  }

  Timer? _clock;
  void Function(String text)? _sink;
  Duration _elapsed = Duration.zero;

  /// Opens the microphone for [owner], delivering the eventual text to [sink].
  ///
  /// [locked] is false for press-and-hold, where the finger still on the button
  /// is what ends it, and true when the recording is expected to carry on by
  /// itself.
  ///
  /// Returns false if nothing is being recorded (no permission, or the model is
  /// not ready), with the reason already published as state.
  Future<bool> start({
    required Object owner,
    required void Function(String text) sink,
    bool locked = false,
  }) async {
    if (state is DictationRecording || state is DictationRecognising) {
      return false;
    }

    final model = ref.read(voiceModelInstallationProvider);
    if (model is! VoiceModelReady) {
      state = DictationFailed(
        'Модель распознавания ещё не скачана.',
        owner: owner,
        retryable: false,
      );
      return false;
    }

    final recorder = ref.read(voiceRecorderProvider);
    if (!await recorder.ensurePermission()) {
      state = DictationFailed(
        'Нужен доступ к микрофону — разрешите его в настройках системы.',
        owner: owner,
        retryable: false,
      );
      return false;
    }

    try {
      await recorder.start();
    } catch (error) {
      debugPrint('Could not start recording: $error');
      state = DictationFailed('Не удалось включить запись.', owner: owner);
      return false;
    }

    // Loading the weights takes seconds on the first go, and the natural moment
    // to pay for it is while the user is still speaking: by the time the
    // recording ends the model is usually already in memory. Unawaited on
    // purpose -- `finish` waits for it if it has not finished.
    unawaited(_ensureLoaded(model.installed));

    _sink = sink;
    _elapsed = Duration.zero;
    _startClock();
    state = DictationRecording(
      owner: owner,
      elapsed: Duration.zero,
      locked: locked,
    );
    return true;
  }

  /// The finger came up early: the recording keeps going on its own.
  ///
  /// This is what the press that used to be scolded ("Держите кнопку, пока
  /// говорите") does instead. A tap was always a perfectly clear instruction;
  /// the only thing it lacked was a way to say when to stop, and the panel now
  /// provides one.
  void lock() {
    final current = state;
    if (current is! DictationRecording || current.locked) return;
    state = DictationRecording(
      owner: current.owner,
      elapsed: current.elapsed,
      locked: true,
    );
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state;
      if (current is! DictationRecording) return;

      _elapsed += const Duration(seconds: 1);
      if (_elapsed >= ceiling) {
        // Not an error and not silent: the phrase recorded so far is real and
        // gets recognised like any other. Throwing away two minutes of speech
        // because the user did not notice a limit would be the worse answer.
        unawaited(finish());
        return;
      }

      state = DictationRecording(
        owner: current.owner,
        elapsed: _elapsed,
        locked: current.locked,
      );
    });
  }

  Future<void>? _loading;

  Future<void> _ensureLoaded(InstalledVoiceModel installed) {
    final recognizer = ref.read(speechRecognizerProvider);
    if (recognizer.isLoaded) return Future<void>.value();
    return _loading ??= recognizer
        .load(installed)
        .whenComplete(() => _loading = null);
  }

  /// Ends the recording and recognises it, delivering the text to the sink the
  /// dictation was started with.
  Future<void> finish() async {
    final current = state;
    if (current is! DictationRecording) return;

    final owner = current.owner;
    final length = _elapsed;
    _clock?.cancel();
    _clock = null;

    final path = await ref.read(voiceRecorderProvider).stop();
    if (!ref.mounted) return;
    if (path == null) {
      state = DictationFailed(
        'Запись не получилась — попробуйте ещё раз.',
        owner: owner,
      );
      return;
    }

    state = DictationRecognising(owner: owner, length: length);
    try {
      final model = ref.read(voiceModelInstallationProvider);
      if (model is VoiceModelReady) await _ensureLoaded(model.installed);

      final text = await ref.read(speechRecognizerProvider).transcribe(path);
      if (!ref.mounted) return;

      if (text.isEmpty) {
        // Not an error: a button pressed by accident, or a phrase the model
        // heard as silence. Saying "ничего не расслышали" is the difference
        // between "it is broken" and "say it again".
        state = DictationFailed('Ничего не расслышали.', owner: owner);
        return;
      }

      state = const DictationIdle();
      _sink?.call(text);
    } catch (error) {
      debugPrint('Recognition failed: $error');
      if (!ref.mounted) return;
      state = DictationFailed('Не удалось распознать запись.', owner: owner);
    }
  }

  /// The finger slid off the button, or the user pressed "Отменить".
  Future<void> cancel() async {
    if (state is! DictationRecording) return;
    _clock?.cancel();
    _clock = null;
    await ref.read(voiceRecorderProvider).cancel();
    if (!ref.mounted) return;
    state = const DictationIdle();
  }

  /// "Ещё раз" from the failure panel: the same field, the same sink, straight
  /// into a recording that is already locked.
  ///
  /// The user has just pressed a button to get here, and asking them to find
  /// and hold a second one to repeat one sentence is exactly the kind of small
  /// tax that stops people using a feature at all.
  Future<void> retry() async {
    final current = state;
    final sink = _sink;
    if (current is! DictationFailed || !current.retryable || sink == null) {
      return;
    }
    state = const DictationIdle();
    await start(owner: current.owner, sink: sink, locked: true);
  }

  /// Clears a reported failure, so the next press starts clean.
  void acknowledge() {
    if (state is DictationFailed) state = const DictationIdle();
  }
}
