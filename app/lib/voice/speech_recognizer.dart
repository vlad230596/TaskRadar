import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice_model.dart';

/// Turning a recorded phrase into text, on the device (F9).
///
/// Behind an interface for the usual reason -- the implementation is FFI into a
/// native library that does not exist in the `flutter test` VM -- and for one
/// more: this is the seam where a different engine would be swapped in
/// (the system recogniser as a stopgap, a smaller model on a weak phone), and
/// the screens above should never learn which one they are talking to.
abstract interface class SpeechRecognizer {
  /// Loads [model] into memory. Slow (seconds), and worth doing once.
  Future<void> load(InstalledVoiceModel model);

  /// Transcribes a 16 kHz mono WAV file. Returns the text, possibly empty.
  Future<String> transcribe(String wavPath);

  /// Frees the model. The recogniser can be [load]ed again afterwards.
  Future<void> unload();

  /// Whether a model is currently in memory.
  bool get isLoaded;
}

/// [SpeechRecognizer] over `sherpa_onnx` / onnxruntime.
///
/// ## Why the recogniser is kept alive
///
/// Loading the graph costs seconds and a few hundred megabytes of resident
/// memory; the first inference after a load is also markedly slower than the
/// ones after it. Dictation is a hold-and-release gesture that people repeat --
/// three thoughts in a row while walking -- so the object stays loaded while
/// the screen that uses it is open and is freed when that screen goes away.
/// `VoiceDictation` in `../providers/voice_providers.dart` owns that lifetime.
///
/// ## What runs where
///
/// `decode` is a blocking FFI call on the isolate that makes it, which here is
/// the UI isolate: the recognizer holds native pointers that cannot be sent to
/// another isolate, and keeping a dedicated worker isolate alive with its own
/// copy of the model would double the memory the whole feature is trying to
/// justify. A short phrase decodes in well under a second on a current phone,
/// and the UI is showing a spinner during it -- but this is a real trade, and
/// the honest test is the one the plan names: measure the latency on the actual
/// device before assuming it is fine.
class SherpaSpeechRecognizer implements SpeechRecognizer {
  sherpa.OfflineRecognizer? _recognizer;

  static bool _bindingsReady = false;

  @override
  bool get isLoaded => _recognizer != null;

  @override
  Future<void> load(InstalledVoiceModel model) async {
    if (_recognizer != null) return;

    if (!_bindingsReady) {
      // Idempotent in practice, but doing it once keeps a second dictation
      // screen from paying for a library resolve.
      await sherpa.initBindingsAsync();
      _bindingsReady = true;
    }

    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(model: model.modelPath),
        tokens: model.tokensPath,
        // One thread per core is tempting and wrong on a phone: the big cores
        // are shared with the UI, and the difference on a five-second phrase is
        // tens of milliseconds against a visibly jankier app. Two is the
        // compromise, and the number to revisit with a real measurement.
        numThreads: 2,
        debug: false,
      ),
    );

    _recognizer = sherpa.OfflineRecognizer(config);
  }

  @override
  Future<String> transcribe(String wavPath) async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw StateError('the speech model is not loaded');
    }
    if (!File(wavPath).existsSync()) {
      throw StateError('there is no recording at $wavPath');
    }

    final wave = sherpa.readWave(wavPath);
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      // Native memory: the `finally` is not politeness. A throw between here
      // and the free would leak the stream for the lifetime of the process.
      stream.free();
    }
  }

  @override
  Future<void> unload() async {
    try {
      _recognizer?.free();
    } catch (error) {
      debugPrint('Could not free the speech recogniser: $error');
    }
    _recognizer = null;
  }
}
