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
sealed class DictationState {
  const DictationState();
}

class DictationIdle extends DictationState {
  const DictationIdle();
}

class DictationRecording extends DictationState {
  const DictationRecording();
}

/// The button has been released and the model is working.
class DictationRecognising extends DictationState {
  const DictationRecognising();
}

class DictationFailed extends DictationState {
  const DictationFailed(this.message);

  final String message;
}

/// The dictation gesture: hold, speak, release, get text.
///
/// ## Why this is a state machine and not three awaits in the widget
///
/// Because every step of it can end somewhere other than "text": permission
/// refused, a press too short to be speech, a release while the model is still
/// loading, a phrase the recogniser heard as silence. Each of those needs a
/// different thing said to the user, and a widget holding that in local state
/// would end up with the same machine, spelled less clearly and untested.
@riverpod
class VoiceDictation extends _$VoiceDictation {
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

    return const DictationIdle();
  }

  /// Called when the button goes down. Returns false if nothing is being
  /// recorded (no permission, or the model is not ready), with the reason
  /// already published as state.
  Future<bool> start() async {
    if (state is DictationRecording || state is DictationRecognising) {
      return false;
    }

    final model = ref.read(voiceModelInstallationProvider);
    if (model is! VoiceModelReady) {
      state = const DictationFailed('Модель распознавания ещё не скачана.');
      return false;
    }

    final recorder = ref.read(voiceRecorderProvider);
    if (!await recorder.ensurePermission()) {
      state = const DictationFailed(
        'Нужен доступ к микрофону — разрешите его в настройках системы.',
      );
      return false;
    }

    try {
      await recorder.start();
    } catch (error) {
      debugPrint('Could not start recording: $error');
      state = const DictationFailed('Не удалось включить запись.');
      return false;
    }

    // Loading the weights takes seconds on the first go, and the natural moment
    // to pay for it is while the user is still speaking: by the time the button
    // comes up the model is usually already in memory. Unawaited on purpose --
    // `stop` waits for it if it has not finished.
    unawaited(_ensureLoaded(model.installed));

    state = const DictationRecording();
    return true;
  }

  Future<void>? _loading;

  Future<void> _ensureLoaded(InstalledVoiceModel installed) {
    final recognizer = ref.read(speechRecognizerProvider);
    if (recognizer.isLoaded) return Future<void>.value();
    return _loading ??= recognizer
        .load(installed)
        .whenComplete(() => _loading = null);
  }

  /// Called when the button comes up. Returns the recognised text, or null when
  /// there is nothing to insert (and then the state says why).
  Future<String?> stopAndTranscribe() async {
    if (state is! DictationRecording) return null;

    final recorder = ref.read(voiceRecorderProvider);
    final path = await recorder.stop();
    if (path == null) {
      state = const DictationFailed('Запись не получилась — попробуйте ещё раз.');
      return null;
    }

    state = const DictationRecognising();
    try {
      final model = ref.read(voiceModelInstallationProvider);
      if (model is VoiceModelReady) await _ensureLoaded(model.installed);

      final text = await ref.read(speechRecognizerProvider).transcribe(path);
      if (!ref.mounted) return null;

      if (text.isEmpty) {
        // Not an error: a button held by accident, or a phrase the model heard
        // as silence. Saying "ничего не расслышали" is the difference between
        // "it is broken" and "say it again".
        state = const DictationFailed('Ничего не расслышали.');
        return null;
      }

      state = const DictationIdle();
      return text;
    } catch (error) {
      debugPrint('Recognition failed: $error');
      if (!ref.mounted) return null;
      state = const DictationFailed('Не удалось распознать запись.');
      return null;
    }
  }

  /// The finger slid off the button, or the screen went away mid-phrase.
  Future<void> cancel() async {
    if (state is! DictationRecording) return;
    await ref.read(voiceRecorderProvider).cancel();
    if (!ref.mounted) return;
    state = const DictationIdle();
  }

  /// Clears a reported failure, so the next press starts clean.
  void acknowledge() {
    if (state is DictationFailed) state = const DictationIdle();
  }
}
