import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// The microphone, behind an interface (F9).
///
/// An interface for the same reason `NotificationGateway` is one: the
/// implementation is a platform channel that answers `MissingPluginException`
/// in the `flutter test` VM, and the logic worth testing -- what the button
/// does when permission is refused, when the recording is too short, when the
/// user slides their finger off to cancel -- lives above it.
abstract interface class VoiceRecorder {
  /// Whether the app may record, asking the user if it has not been asked yet.
  Future<bool> ensurePermission();

  /// Starts recording. Returns the path being written to.
  Future<String> start();

  /// Stops, and returns the finished file, or null if nothing was captured.
  Future<String?> stop();

  /// Stops and throws away whatever was recorded.
  Future<void> cancel();

  Future<void> dispose();
}

/// [VoiceRecorder] over `package:record`.
///
/// ## Why 16 kHz mono WAV, specifically
///
/// Because that is what the recogniser eats. GigaAM, like every NeMo model in
/// this family, is trained on 16 kHz mono; handing it 44.1 kHz stereo means
/// resampling somewhere, and the "somewhere" would be Dart code doing signal
/// processing badly. WAV rather than a compressed container for the same
/// reason: `sherpa_onnx.readWave` reads exactly this, and a phrase held for ten
/// seconds is 320 KB -- there is nothing to save by compressing it and then
/// decoding it again a second later.
class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder({AudioRecorder? recorder, Future<Directory> Function()? directory})
    : _recorder = recorder ?? AudioRecorder(),
      _directory = directory ?? getTemporaryDirectory;

  final AudioRecorder _recorder;
  final Future<Directory> Function() _directory;

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );

  String? _path;

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<String> start() async {
    final directory = await _directory();
    // One fixed name in the *cache* directory, overwritten every time: the file
    // exists for the handful of seconds between releasing the button and the
    // text appearing, and a directory slowly filling with recordings of
    // somebody's private thoughts is not a feature.
    final path =
        '${directory.path}${Platform.pathSeparator}taskradar-dictation.wav';
    await _recorder.start(_config, path: path);
    return _path = path;
  }

  @override
  Future<String?> stop() async {
    final path = await _recorder.stop();
    _path = null;
    return path;
  }

  @override
  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (error) {
      debugPrint('Could not cancel the recording: $error');
    }
    await _discard();
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
    await _discard();
  }

  Future<void> _discard() async {
    final path = _path;
    _path = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Could not delete the dictation file: $error');
    }
  }
}
