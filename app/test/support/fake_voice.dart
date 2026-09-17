import 'dart:async';

import 'package:dio/dio.dart';
import 'package:taskradar/voice/speech_recognizer.dart';
import 'package:taskradar/voice/voice_model.dart';
import 'package:taskradar/voice/voice_model_store.dart';
import 'package:taskradar/voice/voice_recorder.dart';

/// In-memory stand-ins for the two platform halves of dictation (F9).
///
/// Both real implementations are FFI or a platform channel, neither of which
/// exists in the `flutter test` VM. What is worth testing sits above them: what
/// the gesture does when permission is refused, when the press was too short,
/// when the model heard silence, and whether the recogniser is loaded once
/// rather than on every phrase.

class FakeVoiceRecorder implements VoiceRecorder {
  /// What [ensurePermission] answers. False is the case where the user said no
  /// to the microphone, which must not end in a recording nobody stops.
  bool permitted = true;

  /// The path [stop] returns, or null for "nothing was captured" -- the shape
  /// of a recording that failed to start on the platform side.
  String? recordingPath = 'dictation.wav';

  /// Set to throw out of [start].
  Object? startFailure;

  bool recording = false;
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  int disposeCount = 0;

  @override
  Future<bool> ensurePermission() async => permitted;

  @override
  Future<String> start() async {
    startCount++;
    final failure = startFailure;
    if (failure != null) throw failure;
    recording = true;
    return recordingPath ?? 'dictation.wav';
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    recording = false;
    return recordingPath;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    recording = false;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class FakeSpeechRecognizer implements SpeechRecognizer {
  /// What [transcribe] returns. Empty string is "heard silence", which is a
  /// normal outcome rather than an error.
  String text = 'Купить кабель';

  /// Set to throw out of [transcribe].
  Object? transcribeFailure;

  /// Holds [load] open, so a test can release the button while the weights are
  /// still being read.
  Completer<void>? loadGate;

  int loadCount = 0;
  int unloadCount = 0;
  int transcribeCount = 0;
  bool _loaded = false;

  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> load(InstalledVoiceModel model) async {
    loadCount++;
    final gate = loadGate;
    if (gate != null) await gate.future;
    _loaded = true;
  }

  @override
  Future<String> transcribe(String wavPath) async {
    transcribeCount++;
    final failure = transcribeFailure;
    if (failure != null) throw failure;
    return text;
  }

  @override
  Future<void> unload() async {
    unloadCount++;
    _loaded = false;
  }
}

/// A model that is "installed" without anything being on disk.
InstalledVoiceModel fakeInstalledModel() => InstalledVoiceModel(
  model: VoiceModel.gigaAmV3Punct,
  modelPath: 'model.int8.onnx',
  tokensPath: 'tokens.txt',
  bytesOnDisk: 236000000,
);

/// An in-memory [VoiceModelStore].
///
/// The real one is covered against a real directory in
/// `voice_model_store_test.dart`; this exists so a screen test can say "the
/// model is there" / "the download fails" without 163 MB and a filesystem.
class FakeVoiceModelStore implements VoiceModelStore {
  FakeVoiceModelStore({this.present = false});

  bool present;

  /// Thrown out of [install]. The settings screen has to show the reason.
  Object? installFailure;

  /// Holds [install] open, so a test can look at the progress row.
  Completer<void>? installGate;

  int installCount = 0;
  int removeCount = 0;

  @override
  Future<InstalledVoiceModel?> installed(VoiceModel model) async =>
      present ? fakeInstalledModel() : null;

  @override
  Future<InstalledVoiceModel> install(
    VoiceModel model, {
    void Function(int received, int total)? onProgress,
    void Function()? onUnpacking,
    CancelToken? cancelToken,
  }) async {
    installCount++;
    onProgress?.call(1000, 2000);
    final gate = installGate;
    if (gate != null) await gate.future;

    final failure = installFailure;
    if (failure != null) throw failure;

    onUnpacking?.call();
    present = true;
    return fakeInstalledModel();
  }

  @override
  Future<void> remove(VoiceModel model) async {
    removeCount++;
    present = false;
  }
}
