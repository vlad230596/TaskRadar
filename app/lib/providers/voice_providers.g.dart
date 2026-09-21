// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(voiceModelStore)
final voiceModelStoreProvider = VoiceModelStoreProvider._();

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

final class VoiceModelStoreProvider
    extends
        $FunctionalProvider<VoiceModelStore, VoiceModelStore, VoiceModelStore>
    with $Provider<VoiceModelStore> {
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
  VoiceModelStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceModelStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceModelStoreHash();

  @$internal
  @override
  $ProviderElement<VoiceModelStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VoiceModelStore create(Ref ref) {
    return voiceModelStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoiceModelStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoiceModelStore>(value),
    );
  }
}

String _$voiceModelStoreHash() => r'41edcd24e1fc27b9c0e7ce14de4f8f50bca97855';

/// The microphone. Disposed with the screen that used it, so the platform
/// releases the input device rather than holding it for the app's lifetime.

@ProviderFor(voiceRecorder)
final voiceRecorderProvider = VoiceRecorderProvider._();

/// The microphone. Disposed with the screen that used it, so the platform
/// releases the input device rather than holding it for the app's lifetime.

final class VoiceRecorderProvider
    extends $FunctionalProvider<VoiceRecorder, VoiceRecorder, VoiceRecorder>
    with $Provider<VoiceRecorder> {
  /// The microphone. Disposed with the screen that used it, so the platform
  /// releases the input device rather than holding it for the app's lifetime.
  VoiceRecorderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceRecorderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceRecorderHash();

  @$internal
  @override
  $ProviderElement<VoiceRecorder> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VoiceRecorder create(Ref ref) {
    return voiceRecorder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoiceRecorder value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoiceRecorder>(value),
    );
  }
}

String _$voiceRecorderHash() => r'3c5529ee31dd9f3441761ab5f657301833676d74';

/// The recogniser. Same lifetime as [voiceRecorder] and for a bigger reason:
/// loaded, it holds hundreds of megabytes of weights, and that has to go back
/// when the user leaves the screen.

@ProviderFor(speechRecognizer)
final speechRecognizerProvider = SpeechRecognizerProvider._();

/// The recogniser. Same lifetime as [voiceRecorder] and for a bigger reason:
/// loaded, it holds hundreds of megabytes of weights, and that has to go back
/// when the user leaves the screen.

final class SpeechRecognizerProvider
    extends
        $FunctionalProvider<
          SpeechRecognizer,
          SpeechRecognizer,
          SpeechRecognizer
        >
    with $Provider<SpeechRecognizer> {
  /// The recogniser. Same lifetime as [voiceRecorder] and for a bigger reason:
  /// loaded, it holds hundreds of megabytes of weights, and that has to go back
  /// when the user leaves the screen.
  SpeechRecognizerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'speechRecognizerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$speechRecognizerHash();

  @$internal
  @override
  $ProviderElement<SpeechRecognizer> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SpeechRecognizer create(Ref ref) {
    return speechRecognizer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SpeechRecognizer value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SpeechRecognizer>(value),
    );
  }
}

String _$speechRecognizerHash() => r'ffd3e3d87256d44f0377397775fd8b982404636e';

/// Is the speech model on this device, and getting it here if not.

@ProviderFor(VoiceModelInstallation)
final voiceModelInstallationProvider = VoiceModelInstallationProvider._();

/// Is the speech model on this device, and getting it here if not.
final class VoiceModelInstallationProvider
    extends $NotifierProvider<VoiceModelInstallation, VoiceModelState> {
  /// Is the speech model on this device, and getting it here if not.
  VoiceModelInstallationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceModelInstallationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceModelInstallationHash();

  @$internal
  @override
  VoiceModelInstallation create() => VoiceModelInstallation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoiceModelState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoiceModelState>(value),
    );
  }
}

String _$voiceModelInstallationHash() =>
    r'324736dafa7899dd10a22c5660a127e5656e8cb9';

/// Is the speech model on this device, and getting it here if not.

abstract class _$VoiceModelInstallation extends $Notifier<VoiceModelState> {
  VoiceModelState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<VoiceModelState, VoiceModelState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VoiceModelState, VoiceModelState>,
              VoiceModelState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
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

@ProviderFor(canDictate)
final canDictateProvider = CanDictateProvider._();

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

final class CanDictateProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
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
  CanDictateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canDictateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canDictateHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return canDictate(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$canDictateHash() => r'50b1c45973d088a817e8ce12084a9e03bfdefc76';

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

@ProviderFor(VoiceDictation)
final voiceDictationProvider = VoiceDictationProvider._();

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
final class VoiceDictationProvider
    extends $NotifierProvider<VoiceDictation, DictationState> {
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
  VoiceDictationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceDictationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceDictationHash();

  @$internal
  @override
  VoiceDictation create() => VoiceDictation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DictationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DictationState>(value),
    );
  }
}

String _$voiceDictationHash() => r'c74c50670fbfd7937bdae2cddb0014b072ccaeaa';

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

abstract class _$VoiceDictation extends $Notifier<DictationState> {
  DictationState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<DictationState, DictationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DictationState, DictationState>,
              DictationState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
