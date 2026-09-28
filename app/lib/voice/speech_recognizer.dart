import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'audio_chunker.dart';
import 'voice_model.dart';

/// How far a transcription has got: [done] of [total] pieces, and what they
/// said so far.
///
/// Reported once with `done == 0` as soon as the recording has been cut, so
/// the screen knows how many steps there will be before the first one ends.
class TranscriptionProgress {
  const TranscriptionProgress({
    required this.done,
    required this.total,
    required this.text,
  });

  final int done;
  final int total;

  /// The pieces recognised so far, joined. Grows with [done].
  final String text;
}

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
  ///
  /// A long recording is recognised in pieces, and [onProgress] hears about
  /// each one as it finishes -- see [TranscriptionProgress].
  Future<String> transcribe(
    String wavPath, {
    void Function(TranscriptionProgress progress)? onProgress,
  });

  /// Frees the model. The recogniser can be [load]ed again afterwards.
  Future<void> unload();

  /// Whether a model is currently in memory.
  bool get isLoaded;
}

/// [SpeechRecognizer] over `sherpa_onnx` / onnxruntime, in an isolate of its
/// own.
///
/// ## Why the recogniser is kept alive
///
/// Loading the graph costs seconds and a few hundred megabytes of resident
/// memory; the first inference after a load is also markedly slower than the
/// ones after it. Dictation is a gesture people repeat -- three thoughts in a
/// row while walking -- so the model stays loaded while the screen that uses it
/// is open and is freed when that screen goes away. `VoiceDictation` in
/// `../providers/voice_providers.dart` owns that lifetime.
///
/// ## What runs where
///
/// `decode` is a blocking FFI call on the isolate that makes it. It used to be
/// made on the UI isolate, on the grounds that a short phrase decodes in well
/// under a second and a second worker would hold a second copy of the model.
/// Both halves stopped being true once a dictation could run for ten minutes:
/// that is tens of seconds of decoding, during which not one frame was drawn --
/// the spinner saying "Распознаю" froze with everything else.
///
/// So the recogniser now lives in a worker isolate, and it is created *there*:
/// the native pointers it holds cannot cross an isolate boundary, and nothing
/// else needs them. There is still only one copy of the weights -- the UI
/// isolate never loads any -- so the memory argument against a worker went
/// away with the move. What crosses the ports is paths going in and strings
/// coming out; even the samples are read from the file on the worker side, so
/// ten minutes of audio is never copied between isolates.
///
/// The worker is long-lived in the sense that matters: spawned by the first
/// [load], it keeps the model for every phrase until [unload], which frees the
/// model and ends the isolate.
class SherpaSpeechRecognizer implements SpeechRecognizer {
  _Worker? _worker;
  bool _loaded = false;

  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> load(InstalledVoiceModel model) async {
    if (_loaded) return;

    final worker = _worker ??= _Worker();
    await worker.request((id) => _Load(id, model.modelPath, model.tokensPath));
    // An [unload] that landed while the weights were loading has already
    // closed this worker; saying "loaded" now would be about a dead isolate.
    if (!identical(_worker, worker)) {
      throw StateError('the speech model was unloaded while loading');
    }
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    String wavPath, {
    void Function(TranscriptionProgress progress)? onProgress,
  }) async {
    final worker = _worker;
    if (worker == null || !_loaded) {
      throw StateError('the speech model is not loaded');
    }
    final result = await worker.request(
      (id) => _Transcribe(id, wavPath),
      onProgress: onProgress,
    );
    return result as String? ?? '';
  }

  @override
  Future<void> unload() async {
    final worker = _worker;
    _worker = null;
    _loaded = false;
    if (worker == null) return;
    try {
      await worker.shutdown();
    } catch (error) {
      debugPrint('Could not free the speech recogniser: $error');
    }
  }
}

// -- The UI side of the worker ----------------------------------------------

/// The ports to the recogniser's isolate, with one outstanding future per
/// request.
///
/// Requests carry an id because they can overlap: a [SherpaSpeechRecognizer.
/// unload] may arrive while a transcription is still running, and its answer
/// must not be mistaken for the transcription's.
class _Worker {
  _Worker() {
    _responses.listen(_handle);
    // Failed before anyone asked is not an unhandled error: the next request
    // hears about it.
    _commands.future.ignore();
    // A failed spawn fails whatever was waiting for the worker, rather than
    // leaving it waiting for a port that will never arrive.
    Isolate.spawn(
      _workerMain,
      _responses.sendPort,
      debugName: 'speech-recogniser',
      onError: _responses.sendPort,
      onExit: _responses.sendPort,
    ).then<void>((_) {}, onError: (Object error) => _close(error));
  }

  final ReceivePort _responses = ReceivePort('speech-recogniser');
  final Completer<SendPort> _commands = Completer<SendPort>();
  final Map<int, _Pending> _pending = <int, _Pending>{};
  int _nextId = 0;
  bool _closed = false;

  Future<Object?> request(
    _Command Function(int id) build, {
    void Function(TranscriptionProgress progress)? onProgress,
  }) async {
    if (_closed) throw StateError('the speech recogniser was unloaded');
    final id = _nextId++;
    final pending = _Pending(onProgress);
    _pending[id] = pending;
    try {
      final commands = await _commands.future;
      commands.send(build(id));
    } catch (error) {
      _pending.remove(id);
      rethrow;
    }
    return pending.completer.future;
  }

  /// Frees the model and ends the isolate.
  ///
  /// Waits for the worker to say it has freed the weights, because the caller
  /// may be about to delete the file they came from. If a piece of audio is
  /// mid-decode the worker finishes it first -- a native call cannot be
  /// interrupted, and killing the isolate under it would leak the model for the
  /// life of the process -- so the wait is bounded rather than short.
  Future<void> shutdown() async {
    if (_closed) return;
    try {
      await request(_Shutdown.new).timeout(const Duration(seconds: 60));
    } finally {
      _close(StateError('the speech recogniser was unloaded'));
    }
  }

  void _handle(Object? message) {
    switch (message) {
      case SendPort port:
        if (!_commands.isCompleted) _commands.complete(port);
      case _Progress(:final id, :final done, :final total, :final text):
        _pending[id]?.onProgress?.call(
          TranscriptionProgress(done: done, total: total, text: text),
        );
      case _Done(:final id, :final result):
        _pending.remove(id)?.completer.complete(result);
      case _Failed(:final id, :final message):
        _pending.remove(id)?.completer.completeError(StateError(message));
      case List<Object?> error:
        // An uncaught error in the worker: `[message, stack]`, as strings.
        _fail(StateError('speech isolate: ${error.first}'));
      case null:
        // The isolate has exited, by design or not. Nothing still waiting
        // will ever be answered.
        _close(StateError('the speech isolate has exited'));
    }
  }

  void _fail(Object error) {
    if (!_commands.isCompleted) _commands.completeError(error);
    final pending = _pending.values.toList();
    _pending.clear();
    for (final p in pending) {
      p.completer.completeError(error);
    }
  }

  void _close(Object error) {
    if (_closed) return;
    _closed = true;
    _fail(error);
    _responses.close();
  }
}

class _Pending {
  _Pending(this.onProgress);

  final void Function(TranscriptionProgress progress)? onProgress;
  final Completer<Object?> completer = Completer<Object?>();
}

// -- Messages ----------------------------------------------------------------
//
// Plain objects: the worker is spawned from this library, so both ends are in
// one isolate group and instances cross the port as they are.

sealed class _Command {
  const _Command(this.id);

  final int id;
}

final class _Load extends _Command {
  const _Load(super.id, this.modelPath, this.tokensPath);

  final String modelPath;
  final String tokensPath;
}

final class _Transcribe extends _Command {
  const _Transcribe(super.id, this.wavPath);

  final String wavPath;
}

final class _Shutdown extends _Command {
  const _Shutdown(super.id);
}

final class _Progress {
  const _Progress(this.id, this.done, this.total, this.text);

  final int id;
  final int done;
  final int total;
  final String text;
}

final class _Done {
  const _Done(this.id, this.result);

  final int id;
  final Object? result;
}

final class _Failed {
  const _Failed(this.id, this.message);

  final int id;
  final String message;
}

// -- The worker isolate ------------------------------------------------------

Future<void> _workerMain(SendPort replies) async {
  final commands = ReceivePort('speech-recogniser-commands');
  replies.send(commands.sendPort);
  final worker = _WorkerSide(replies);
  // `listen`, not `await for`: a shutdown has to be *heard* while a long
  // transcription is running, between two of its pieces, and `await for` would
  // hold it until the whole transcription had finished.
  commands.listen((message) {
    if (message is _Command) unawaited(worker.handle(message));
  });
}

class _WorkerSide {
  _WorkerSide(this._replies);

  final SendPort _replies;
  sherpa.OfflineRecognizer? _recognizer;
  bool _bindingsReady = false;

  /// True while a transcription is between pieces or inside one.
  bool _busy = false;

  /// The id of a shutdown that arrived while [_busy], answered once the
  /// current piece is done.
  int? _shutdownId;

  Future<void> handle(_Command command) async {
    try {
      switch (command) {
        case _Load():
          await _load(command);
          _replies.send(_Done(command.id, null));
        case _Transcribe():
          await _transcribe(command);
        case _Shutdown():
          _shutdownId = command.id;
          if (!_busy) _exit();
      }
    } catch (error) {
      _replies.send(_Failed(command.id, error.toString()));
    }
  }

  Future<void> _load(_Load command) async {
    if (_recognizer != null) return;

    if (!_bindingsReady) {
      // Per isolate: FFI bindings loaded on the UI isolate are not visible
      // here, and this isolate is the only one that uses them.
      await sherpa.initBindingsAsync();
      _bindingsReady = true;
    }

    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
          model: command.modelPath,
        ),
        tokens: command.tokensPath,
        // Still two, and still for the UI's sake even though the UI is on
        // another isolate now: isolates are threads on the same big cores, and
        // one thread per core would take the ones the raster thread is drawing
        // the progress bar on.
        numThreads: 2,
        debug: false,
      ),
    );

    _recognizer = sherpa.OfflineRecognizer(config);
  }

  Future<void> _transcribe(_Transcribe command) async {
    final recognizer = _recognizer;
    if (recognizer == null) throw StateError('the speech model is not loaded');
    if (!File(command.wavPath).existsSync()) {
      throw StateError('there is no recording at ${command.wavPath}');
    }

    _busy = true;
    try {
      final wave = sherpa.readWave(command.wavPath);
      final chunks = splitIntoChunks(
        wave.samples,
        sampleRate: wave.sampleRate > 0 ? wave.sampleRate : 16000,
      );
      _replies.send(_Progress(command.id, 0, chunks.length, ''));

      final texts = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        if (_shutdownId != null) {
          throw StateError('the speech recogniser was unloaded');
        }
        final chunk = chunks[i];
        final stream = recognizer.createStream();
        try {
          stream.acceptWaveform(
            samples: Float32List.sublistView(
              wave.samples,
              chunk.start,
              chunk.end,
            ),
            sampleRate: wave.sampleRate,
          );
          recognizer.decode(stream);
          texts.add(recognizer.getResult(stream).text.trim());
        } finally {
          // Native memory: the `finally` is not politeness. A throw between
          // here and the free would leak the stream for the life of the
          // process.
          stream.free();
        }
        _replies.send(
          _Progress(command.id, i + 1, chunks.length, joinChunkTexts(texts)),
        );
        // One turn of the event loop between pieces, so a shutdown sent
        // meanwhile is heard before the next one starts.
        await Future<void>.delayed(Duration.zero);
      }
      _replies.send(_Done(command.id, joinChunkTexts(texts)));
    } finally {
      _busy = false;
      if (_shutdownId != null) _exit();
    }
  }

  /// Frees the model and ends the isolate, answering the shutdown on the way
  /// out.
  Never _exit() {
    try {
      _recognizer?.free();
    } catch (error) {
      debugPrint('Could not free the speech recogniser: $error');
    }
    _recognizer = null;
    Isolate.exit(_replies, _Done(_shutdownId ?? -1, null));
  }
}
