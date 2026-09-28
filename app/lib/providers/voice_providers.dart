import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../voice/speech_recognizer.dart';
import '../voice/voice_model.dart';
import '../voice/voice_model_store.dart';
import '../voice/voice_recorder.dart';
import 'capture_queue_providers.dart';

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

  /// The disk probe kicked off by [build], while it is still running.
  ///
  /// Kept so [resolved] can wait for it. See that method for why the difference
  /// between "not installed" and "not answered yet" turned out to matter.
  Future<void>? _probing;

  @override
  VoiceModelState build() {
    // No probe on web: the store behind it is `path_provider` plus `dart:io`,
    // which answers `MissingPluginException` in a browser, and the answer is
    // known without asking anyway.
    if (kIsWeb) return const VoiceModelUnsupported();
    _probing = _probe();
    return const VoiceModelUnknown();
  }

  VoiceModel get model => VoiceModel.gigaAmV3Punct;

  /// The state, once the startup probe has actually answered.
  ///
  /// ## The third face of "запускается не с первого раза"
  ///
  /// [build] cannot answer synchronously -- finding out whether 236 MB of
  /// weights are on disk is a filesystem round trip -- so it returns
  /// [VoiceModelUnknown] and answers properly a moment later. Every *reader* of
  /// this provider then has to decide what `Unknown` means, and for a while the
  /// answer was "the microphone does not exist yet", which is why the first tap
  /// of a cold start used to land on nothing.
  ///
  /// F12 put the microphone in the navigation bar, so the tap now lands on
  /// something -- and the bug simply moved: `VoiceDictation.start` read the
  /// state, saw `Unknown`, and said "модель ещё не скачана" about a model that
  /// was sitting on the disk. Press again a second later and it worked.
  ///
  /// So the question is asked properly: wait for the probe, then answer. It
  /// costs the first press of a session a few milliseconds and it costs every
  /// later press nothing, because the probe has long since finished and this
  /// returns immediately.
  Future<VoiceModelState> resolved() async {
    final probing = _probing;
    if (probing != null) await probing;
    return state;
  }

  Future<void> _probe() async {
    final installed = await ref.read(voiceModelStoreProvider).installed(model);
    _probing = null;
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

/// Whether a dictation can actually record anything right now.
///
/// ## What changed in F12, and why the microphone no longer disappears
///
/// This used to decide whether the microphone was **on screen at all**: no
/// model, no button, on the reasoning that a button answering "сначала скачайте
/// 163 МБ" lies about what it does.
///
/// That reasoning was right about the button and wrong about the layout, and
/// the layout is now the problem. The microphone has become a fixed part of the
/// shell -- the fourth item of the bottom bar, the bottom of the desktop rail,
/// *"микрофон живёт в одном месте"* -- and a navigation item that is sometimes
/// missing is a navigation bar whose other three items move. Worse, it is
/// missing for the first few hundred milliseconds of **every cold start**,
/// because [VoiceModelInstallation] answers `VoiceModelUnknown` until a disk
/// probe comes back. A tap in that window landed on nothing at all, which is
/// one of the two halves of "запускается не с первого раза".
///
/// So the button is always there, and this now answers a different question:
/// may [VoiceDictation.start] open the microphone. A tap with no model still
/// gets a truthful answer -- it just gets it on the dictation screen, in a
/// sentence, next to the way to fix it, instead of by the control quietly not
/// existing.
@riverpod
bool canDictate(Ref ref) =>
    ref.watch(voiceModelInstallationProvider) is VoiceModelReady;

/// What the microphone is doing right now.
///
/// ## Why there is no `owner` any more
///
/// There used to be one, and it was the right answer to the question F9 had: a
/// microphone beside every text field means several on one screen, and the
/// state had to say whose recording was running or two panels would claim the
/// same one.
///
/// F12 removes the question rather than the answer. There is exactly one
/// microphone in the app, it is a fixed part of the shell, and pressing it
/// opens a screen that owns the whole display until it is dismissed. Nothing
/// can be dictating "somewhere else" while that screen is up, so a token
/// distinguishing between places has nothing left to distinguish.
///
/// Where the text goes is still a real question -- the sandbox, a project, the
/// field that opened the screen -- and it is asked on the screen, above the
/// text, where it can be *changed* before "Готово". That is a property of the
/// destination, not of the microphone, so it lives in the screen rather than
/// here.
sealed class DictationState {
  const DictationState();
}

class DictationIdle extends DictationState {
  const DictationIdle();
}

/// The screen is up and the microphone is being opened: permission, then the
/// input device.
///
/// ## Why this state exists at all, which is the whole bug
///
/// It is the visible half of the race. Opening the microphone means asking the
/// platform for permission and then for the input device -- on a first run that
/// is a system dialog, and on every run it is two channel round trips. The old
/// code did all of that **inside a press gesture** and threw the answer away if
/// the gesture ended first, which on the first ever press it always did: the
/// permission dialog takes the window focus, Flutter delivers a pointer cancel,
/// `onTapCancel` awaited the half-finished start and then immediately cancelled
/// the recording it had just produced. Press once, nothing; press again,
/// works -- exactly the complaint.
///
/// Making it a state makes it impossible to throw away: the screen is already
/// open, it says "Включаю микрофон", and whatever the platform answers becomes
/// either [DictationRecording] or [DictationFailed] on a screen that is still
/// there to show it.
class DictationStarting extends DictationState {
  const DictationStarting();
}

/// The microphone is open and audio is being captured.
///
/// [elapsed] is counted here rather than by the widget, and that split is not
/// arbitrary: a screen computing `DateTime.now().difference(startedAt)` looks
/// right on a phone and never advances in a widget test, because
/// `tester.pump(Duration)` moves the framework's clock and not the wall clock.
/// A periodic timer moves with both, so the seconds the user reads are the same
/// seconds a test can assert on.
class DictationRecording extends DictationState {
  const DictationRecording({required this.elapsed, required this.modelLoading});

  final Duration elapsed;

  /// How long until [VoiceDictation.ceiling] stops the recording by itself.
  Duration get left {
    final left = VoiceDictation.ceiling - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether the screen should be counting down to the ceiling -- see
  /// [VoiceDictation.warning].
  bool get nearCeiling => left <= VoiceDictation.warning;

  /// True while the recogniser's weights are still being read.
  ///
  /// Surfaced rather than hidden because the spec asks for it in words:
  /// *"звук пишется с первого кадра, а не после готовности модели"*. The
  /// recording is real and complete either way -- the load only has to finish
  /// before [VoiceDictation.finish] can transcribe it -- but a first phrase
  /// after a cold start waits several seconds at the end, and a screen that
  /// said nothing about it looked exactly like one that had hung.
  final bool modelLoading;
}

/// The recording has ended and the model is working.
///
/// ## Why it says how far it has got
///
/// Because with a ten-minute ceiling "the seconds the model takes" became
/// tens of seconds, and a spinner that turns for forty seconds is
/// indistinguishable from one that will turn forever. The recogniser works in
/// pieces of half a minute or less (see `voice/audio_chunker.dart`), so there
/// is a real count to show -- "3 из 8" and a bar that fills -- and the words of
/// the finished pieces, which are the best proof that it is working at all.
class DictationRecognising extends DictationState {
  const DictationRecognising({
    required this.length,
    this.done = 0,
    this.total = 0,
    this.partialText = '',
    this.remaining,
  });

  /// How long the recording being recognised was. Shown so the screen does not
  /// go blank in the seconds the model takes: the number the user watched
  /// counting up stays on screen instead of resetting to nothing.
  final Duration length;

  /// Pieces recognised so far, out of [total]. [total] is zero until the
  /// recording has been cut -- which includes the wait for a model that is
  /// still loading.
  final int done;
  final int total;

  /// The text of the [done] pieces, joined. Not yet delivered anywhere: the
  /// sink hears the whole text once, at the end.
  final String partialText;

  /// A guess at how long the rest will take, from how long the pieces so far
  /// took. Null until there is a piece to guess from.
  final Duration? remaining;

  /// [done] over [total], or null while the total is not known yet.
  double? get fraction => total == 0 ? null : done / total;
}

class DictationFailed extends DictationState {
  const DictationFailed(this.message, {this.retryable = true});

  final String message;

  /// Whether saying it again could work. False for the two failures that are
  /// about the device rather than the phrase -- no permission, no model --
  /// where an "Ещё раз" button would only fail the same way again.
  final bool retryable;
}

/// The dictation: start, speak, stop, get text.
///
/// ## Why this is a state machine and not three awaits in the widget
///
/// Because every step of it can end somewhere other than "text": permission
/// refused, a model still loading when the recording ends, a phrase the
/// recogniser heard as silence, a recording that ran into the ceiling. Each of
/// those needs a different thing said to the user, and a widget holding that in
/// local state would end up with the same machine, spelled less clearly and
/// untested.
///
/// ## What F12 took out: the gesture
///
/// There used to be two gestures on one button -- hold to record, tap to
/// "lock" a recording that carries on by itself -- and a 350 ms timer deciding
/// which one had happened. That was the second half of complaint number two
/// ("непонятно, тап это или удержание"), and it is gone entirely. There is one
/// gesture: a tap, which opens a screen on which recording has **already
/// started**. Nothing here knows about presses any more.
///
/// ## The three ordering defects this rework fixes
///
/// All three were real, all three could produce "запускается не с первого
/// раза", and none of them would have been fixed by changing the gesture alone:
///
/// 1. **The permission dialog raced the gesture.** See [DictationStarting].
///    Fixed by there being no gesture to race: the screen is already open, and
///    `start` is called by a widget that stays mounted for the whole answer.
/// 2. **A failing weight load became an unhandled asynchronous error** and was
///    then retried concurrently. `_ensureLoaded` was fired with `unawaited` and
///    cleared its own dedupe handle in `whenComplete`, so a `load()` that threw
///    escaped into the zone *and* left [finish] free to start a second load of
///    the same 236 MB. See [_ensureLoaded].
/// 3. **`state` was assigned after `await` with no liveness check.** Closing
///    the screen while the permission dialog was up disposed this notifier, and
///    the assignment that followed threw out of a future nobody was holding.
///    Every await below is now followed by a `ref.mounted` check.
///
/// ## Why the text is delivered through a sink instead of returned
///
/// Because the thing that ends a dictation is not the thing that started it:
/// "Готово", a tap on the text area, and [ceiling] all finish the same
/// recording, and only the opener knows where the words belong. The opener
/// hands its own insertion callback over, and whoever ends it delivers to the
/// same place.
@riverpod
class VoiceDictation extends _$VoiceDictation {
  /// The longest a single dictation can run.
  ///
  /// With no held button there is nothing physically stopping a recording that
  /// was started and then forgotten -- a screen left open in a pocket.
  ///
  /// It was two minutes, and that turned out to be a limit on thinking out
  /// loud: people do dictate a whole plan while walking, and the old ceiling
  /// ended it mid-sentence. Ten minutes is about 1 500 words and 19 MB of WAV;
  /// what made it affordable is the recogniser working in pieces off the UI
  /// isolate (see `voice/speech_recognizer.dart`), so the minute or so the
  /// model spends on it is a progress bar rather than a frozen screen.
  static const Duration ceiling = Duration(minutes: 10);

  /// How long before [ceiling] the screen starts counting down.
  ///
  /// Reaching the ceiling is not a failure -- what was said is recognised like
  /// any other phrase -- but being stopped mid-sentence with no warning feels
  /// like one. Half a minute is enough to finish the thought.
  static const Duration warning = Duration(seconds: 30);

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

  /// True while a recognition runs with nobody left to hand its text to: the
  /// screen that started it was closed. See [detach].
  bool _detached = false;

  /// Told how a [detach]ed recognition ended, in a sentence for a snackbar.
  void Function(String message)? _announce;

  /// Which attempt is the current one.
  ///
  /// ## Why a counter and not just `ref.mounted`
  ///
  /// Because abandoning a dictation is not the same as tearing the provider
  /// down. Dismissing the screen while the permission dialog is up runs
  /// [cancel], which sets the state to idle -- but this notifier is still very
  /// much alive, so an in-flight [start] would sail past every `ref.mounted`
  /// check, open the microphone nobody asked for any more, and publish
  /// `DictationRecording` over the idle the user just chose. The *next* press
  /// would then find the machine "already running" and do nothing, which is the
  /// first-press bug reappearing one layer down.
  ///
  /// So every attempt carries a number, [cancel] bumps it, and a `start` whose
  /// number is stale gives up and closes whatever it managed to open.
  int _attempt = 0;

  /// Opens the microphone, delivering the eventual text to [sink].
  ///
  /// Returns false if nothing is being recorded (no permission, or the model is
  /// not ready), with the reason already published as state. The caller is a
  /// screen that is already on display, so it does not have to do anything with
  /// the answer -- the state it can see is the answer.
  Future<bool> start({required void Function(String text) sink}) async {
    // A dictation from a screen that was closed is still being recognised
    // (see [detach]), and this is a screen opened meanwhile. It takes the
    // text over rather than starting a second recording on top of the first:
    // the words land in front of the user, who is looking, instead of in the
    // sandbox behind their back. Nothing is recorded -- the screen shows the
    // recognition it has adopted, and then the words.
    if (state is DictationRecognising && _detached) {
      _sink = sink;
      _detached = false;
      _announce = null;
      return false;
    }

    // Re-entry is a no-op rather than a failure. The screen calls this from
    // `initState`, and a rebuild that called it twice must not end the
    // recording that is already running.
    if (state is DictationStarting ||
        state is DictationRecording ||
        state is DictationRecognising) {
      return false;
    }

    // Published before the first await, so the screen has something to say
    // during the seconds the platform may take. This is the fix for defect
    // (1): the answer can no longer arrive with nobody left to receive it.
    state = const DictationStarting();
    final attempt = ++_attempt;
    // A brand-new dictation may retry a load that failed last time -- the user
    // may have reinstalled the model since. Within one dictation it does not;
    // see [_ensureLoaded].
    _loadFailure = null;

    // Awaited, not read. On the first press of a session the startup probe may
    // not have answered yet, and reading a snapshot of it would report "модель
    // не скачана" about a model that is on the disk -- see
    // [VoiceModelInstallation.resolved]. Every later press finds it settled and
    // pays nothing.
    final model = await ref
        .read(voiceModelInstallationProvider.notifier)
        .resolved();
    if (!ref.mounted || attempt != _attempt) return false;
    if (model is! VoiceModelReady) {
      state = const DictationFailed(
        'Модель распознавания ещё не скачана — её ставят в настройках.',
        retryable: false,
      );
      return false;
    }

    final recorder = ref.read(voiceRecorderProvider);

    final permitted = await recorder.ensurePermission();
    // Defect (3). On a first run the line above is a system dialog, and the
    // user can dismiss this screen while it is up -- which either disposes this
    // notifier (and the assignment below would throw out of a future nobody is
    // holding) or merely abandons the attempt (see [_attempt]).
    if (!ref.mounted || attempt != _attempt) return false;
    if (!permitted) {
      state = const DictationFailed(
        'Нужен доступ к микрофону — разрешите его в настройках системы.',
        retryable: false,
      );
      return false;
    }

    try {
      await recorder.start();
    } catch (error) {
      debugPrint('Could not start recording: $error');
      if (!ref.mounted || attempt != _attempt) return false;
      state = const DictationFailed('Не удалось включить запись.');
      return false;
    }
    if (!ref.mounted || attempt != _attempt) {
      // The screen went away, or the user pressed "Отменить", between the
      // permission and the device. The microphone is open and nobody owns it,
      // so close it rather than leave the platform holding the input.
      unawaited(recorder.cancel());
      return false;
    }

    _sink = sink;
    _detached = false;
    _announce = null;
    _elapsed = Duration.zero;
    _startClock();

    // Loading the weights takes seconds on the first go, and the natural moment
    // to pay for it is while the user is still speaking: by the time the
    // recording ends the model is usually already in memory. `finish` waits for
    // it if it has not finished, and the screen says so meanwhile.
    final loading = _ensureLoaded(model.installed);
    state = DictationRecording(
      elapsed: Duration.zero,
      modelLoading: !ref.read(speechRecognizerProvider).isLoaded,
    );
    unawaited(
      loading.then((_) {
        // Only to take the "грузится модель" line off the screen. The recording
        // itself never waited for this.
        if (!ref.mounted) return;
        final current = state;
        if (current is! DictationRecording || !current.modelLoading) return;
        state = DictationRecording(
          elapsed: current.elapsed,
          modelLoading: false,
        );
      }),
    );

    return true;
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state;
      if (current is! DictationRecording) return;

      _elapsed += const Duration(seconds: 1);
      if (_elapsed >= ceiling) {
        // Not an error and not silent: the phrase recorded so far is real and
        // gets recognised like any other. Throwing away ten minutes of speech
        // because the user did not notice a limit would be the worse answer.
        unawaited(finish());
        return;
      }

      state = DictationRecording(
        elapsed: _elapsed,
        modelLoading: current.modelLoading,
      );
    });
  }

  /// The one in-flight weight load, or null when there is none.
  Future<void>? _loading;

  /// Why the last load failed, kept so a second attempt is not started blindly.
  Object? _loadFailure;

  /// Loads the recogniser's weights at most once, and never lets the failure
  /// escape as an unhandled asynchronous error.
  ///
  /// ## Defect (2), in detail
  ///
  /// The previous version was three lines:
  ///
  /// ```dart
  /// return _loading ??= recognizer.load(installed)
  ///     .whenComplete(() => _loading = null);
  /// ```
  ///
  /// and it was called as `unawaited(_ensureLoaded(...))`. Two things go wrong
  /// together when `load` throws -- a corrupt download, a file the archive did
  /// not contain, an ONNX runtime that refuses the model:
  ///
  /// - the returned future completes with an error that `unawaited` explicitly
  ///   promises nobody will handle, so it reaches the zone handler. In a test
  ///   that fails the test; in release it is a crash report for something the
  ///   user experienced as "запись не сработала";
  /// - `whenComplete` clears the handle, so the failure leaves no trace, and
  ///   `finish` -- which calls this again -- starts a **second** load of the
  ///   same 236 MB. On a phone two concurrent loads of that size is not a
  ///   slow path, it is the process being killed.
  ///
  /// Both are fixed by the same change: the handle is kept until the load is
  /// known to have succeeded, the failure is remembered, and the future handed
  /// out never completes with an error -- callers ask [_loadFailure] instead.
  /// [finish] turns that into a sentence; nothing else has to care.
  Future<void> _ensureLoaded(InstalledVoiceModel installed) {
    final recognizer = ref.read(speechRecognizerProvider);
    if (recognizer.isLoaded) return Future<void>.value();

    // Already tried, already failed, within this dictation. The second caller
    // is always [finish], and starting a second 236 MB load of weights that
    // have just refused to load is the half of defect (2) that costs memory
    // rather than a log line. [start] clears this, so the *next* dictation
    // tries again -- the model may have been reinstalled in between.
    if (_loadFailure != null) return Future<void>.value();

    return _loading ??= recognizer
        .load(installed)
        .then<void>((_) {
          _loadFailure = null;
        })
        .catchError((Object error) {
          debugPrint('Could not load the speech model: $error');
          _loadFailure = error;
        })
        // Cleared only here, i.e. once the attempt has fully settled either
        // way, so two callers inside the same attempt share one load.
        .whenComplete(() => _loading = null);
  }

  /// Ends the recording and recognises it, delivering the text to the sink the
  /// dictation was started with.
  ///
  /// Reached from "Готово", from a tap on the text area, and from [ceiling].
  /// All three mean the same thing and there is deliberately only one path.
  ///
  /// ## Why the provider is kept alive for the length of it
  ///
  /// It is auto-disposed with the screen, and the screen can be closed while
  /// the pieces are still being recognised -- which on a ten-minute recording
  /// is the better part of a minute nobody wants to spend watching a bar.
  /// Disposed, it would unload the recogniser under the transcription and the
  /// dictation would be gone. So from the moment the recording stops until
  /// its text has gone somewhere, the provider -- and with it the recorder,
  /// the recogniser and the file -- stays; see [detach] for where the text
  /// goes when the screen is not there to take it.
  Future<void> finish() async {
    if (state is! DictationRecording) return;

    final keepAlive = ref.keepAlive();
    try {
      await _finish();
    } finally {
      keepAlive.close();
    }
  }

  Future<void> _finish() async {
    final length = _elapsed;
    _clock?.cancel();
    _clock = null;

    final recorder = ref.read(voiceRecorderProvider);
    final path = await recorder.stop();
    if (!ref.mounted) return;
    if (path == null) {
      _fail(
        const DictationFailed('Запись не получилась — попробуйте ещё раз.'),
      );
      return;
    }

    state = DictationRecognising(length: length);
    try {
      final model = ref.read(voiceModelInstallationProvider);
      if (model is VoiceModelReady) await _ensureLoaded(model.installed);
      if (!ref.mounted) return;

      // See [_ensureLoaded]: a failed load is a value here rather than an
      // exception, and it gets its own sentence. "Не удалось распознать" would
      // send the user to try the same phrase again against weights that will
      // not load this time either.
      if (_loadFailure != null) {
        _fail(
          const DictationFailed(
            'Модель не загрузилась — переустановите её в настройках.',
            retryable: false,
          ),
        );
        return;
      }

      final clock = Stopwatch()..start();
      final text = await ref
          .read(speechRecognizerProvider)
          .transcribe(
            path,
            onProgress: (progress) {
              if (!ref.mounted || state is! DictationRecognising) return;
              final left = progress.total - progress.done;
              state = DictationRecognising(
                length: length,
                done: progress.done,
                total: progress.total,
                partialText: progress.text,
                // Pieces are of roughly equal length by construction, so the
                // average so far is a fair price for each of the rest.
                remaining: progress.done > 0 && left > 0
                    ? clock.elapsed * (left / progress.done)
                    : null,
              );
            },
          );
      if (!ref.mounted) return;

      if (text.isEmpty) {
        // Not an error: a screen opened by accident, or a phrase the model
        // heard as silence. Saying "ничего не расслышали" is the difference
        // between "it is broken" and "say it again".
        _fail(const DictationFailed('Ничего не расслышали.'));
        return;
      }

      if (_detached) {
        await _deliverToSandbox(text, recorder, path);
        return;
      }

      state = const DictationIdle();
      _sink?.call(text);
      // Delivered: the file has done its job, and a recording of somebody's
      // thoughts is not something to leave lying in a cache.
      await recorder.discard(path);
    } catch (error) {
      debugPrint('Recognition failed: $error');
      if (!ref.mounted) return;
      _fail(const DictationFailed('Не удалось распознать запись.'));
    }
  }

  /// [failure] as the state, and -- for a [detach]ed dictation, whose screen
  /// is gone -- said in the snackbar instead, since there is no screen left
  /// to say it on.
  void _fail(DictationFailed failure) {
    state = failure;
    if (!_detached) return;
    final announce = _announce;
    _detached = false;
    _announce = null;
    announce?.call('Диктовка не распознана: ${_lowerFirst(failure.message)}');
  }

  static String _lowerFirst(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

  /// The text of a dictation whose screen was closed, into the sandbox.
  ///
  /// The sandbox whatever the screen was aimed at. The capture queue is the
  /// one destination that is always valid: a project may have been archived
  /// meanwhile, and a field -- a task, a note, a line -- was on a screen that
  /// is gone, so there is nobody left to hand the words to. From the sandbox
  /// they are one tap from anywhere.
  ///
  /// The recording is deleted only once the line is on disk: if the capture
  /// fails, the file is the only copy left of what was said.
  Future<void> _deliverToSandbox(
    String text,
    VoiceRecorder recorder,
    String path,
  ) async {
    final announce = _announce;
    _detached = false;
    _announce = null;
    state = const DictationIdle();
    try {
      await ref.read(captureQueueProvider.notifier).capture(text);
    } catch (error) {
      debugPrint('Could not keep a detached dictation: $error');
      announce?.call('Диктовку не удалось записать в песочницу.');
      return;
    }
    await recorder.discard(path);
    announce?.call('Диктовка распознана — в песочнице');
  }

  /// The screen that started this dictation is going away while it is still
  /// being recognised. The recognition carries on (see [finish]); its text
  /// goes to the sandbox rather than to the screen, and [announce] is told
  /// how it ended, in words for a snackbar.
  ///
  /// Returns false when there is nothing under way to carry on with -- the
  /// recording is not being recognised, so closing the screen loses nothing
  /// that is not already on it.
  bool detach({void Function(String message)? announce}) {
    if (state is! DictationRecognising) return false;
    _sink = null;
    _detached = true;
    _announce = announce;
    return true;
  }

  /// "Отменить", or the screen being dismissed mid-phrase.
  ///
  /// Accepts [DictationStarting] as well as [DictationRecording]: closing the
  /// screen while the permission dialog is up has to leave the machine idle, or
  /// the next tap would find it "already running" and do nothing -- which is
  /// the old first-press bug wearing a different hat.
  Future<void> cancel() async {
    final current = state;
    if (current is! DictationRecording && current is! DictationStarting) return;

    // Bumped first: whatever `start` is still waiting on -- a permission
    // dialog, the input device -- is now answering a question nobody is asking,
    // and must not publish a recording over this idle.
    _attempt++;
    _clock?.cancel();
    _clock = null;
    state = const DictationIdle();
    await ref.read(voiceRecorderProvider).cancel();
  }

  /// "Ещё раз" after a failure: the same sink, straight back into a recording.
  ///
  /// The user has just pressed a button to get here, and asking them to leave
  /// the screen and come back to repeat one sentence is exactly the kind of
  /// small tax that stops people using a feature at all.
  Future<void> retry() async {
    final current = state;
    final sink = _sink;
    if (current is! DictationFailed || !current.retryable || sink == null) {
      return;
    }
    state = const DictationIdle();
    await start(sink: sink);
  }

  /// Clears a reported failure, so the next press starts clean.
  void acknowledge() {
    if (state is DictationFailed) state = const DictationIdle();
  }
}
