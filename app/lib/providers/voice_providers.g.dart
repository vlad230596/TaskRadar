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
    r'2bd913407db451d138c78daeb9f7db471e919677';

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

/// Whether the microphone button should be on screen at all.
///
/// False while the model is missing on purpose: the button's job is to record,
/// and one that answers "сначала скачайте 163 МБ" is a button that lies about
/// what it does. Offering the download is Settings' job, and the composer says
/// so in a line of text instead.

@ProviderFor(canDictate)
final canDictateProvider = CanDictateProvider._();

/// Whether the microphone button should be on screen at all.
///
/// False while the model is missing on purpose: the button's job is to record,
/// and one that answers "сначала скачайте 163 МБ" is a button that lies about
/// what it does. Offering the download is Settings' job, and the composer says
/// so in a line of text instead.

final class CanDictateProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the microphone button should be on screen at all.
  ///
  /// False while the model is missing on purpose: the button's job is to record,
  /// and one that answers "сначала скачайте 163 МБ" is a button that lies about
  /// what it does. Offering the download is Settings' job, and the composer says
  /// so in a line of text instead.
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

/// The dictation gesture: hold, speak, release, get text.
///
/// ## Why this is a state machine and not three awaits in the widget
///
/// Because every step of it can end somewhere other than "text": permission
/// refused, a press too short to be speech, a release while the model is still
/// loading, a phrase the recogniser heard as silence. Each of those needs a
/// different thing said to the user, and a widget holding that in local state
/// would end up with the same machine, spelled less clearly and untested.

@ProviderFor(VoiceDictation)
final voiceDictationProvider = VoiceDictationProvider._();

/// The dictation gesture: hold, speak, release, get text.
///
/// ## Why this is a state machine and not three awaits in the widget
///
/// Because every step of it can end somewhere other than "text": permission
/// refused, a press too short to be speech, a release while the model is still
/// loading, a phrase the recogniser heard as silence. Each of those needs a
/// different thing said to the user, and a widget holding that in local state
/// would end up with the same machine, spelled less clearly and untested.
final class VoiceDictationProvider
    extends $NotifierProvider<VoiceDictation, DictationState> {
  /// The dictation gesture: hold, speak, release, get text.
  ///
  /// ## Why this is a state machine and not three awaits in the widget
  ///
  /// Because every step of it can end somewhere other than "text": permission
  /// refused, a press too short to be speech, a release while the model is still
  /// loading, a phrase the recogniser heard as silence. Each of those needs a
  /// different thing said to the user, and a widget holding that in local state
  /// would end up with the same machine, spelled less clearly and untested.
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

String _$voiceDictationHash() => r'3077831e1435b2f339cec08d5b6f22a36c916d63';

/// The dictation gesture: hold, speak, release, get text.
///
/// ## Why this is a state machine and not three awaits in the widget
///
/// Because every step of it can end somewhere other than "text": permission
/// refused, a press too short to be speech, a release while the model is still
/// loading, a phrase the recogniser heard as silence. Each of those needs a
/// different thing said to the user, and a widget holding that in local state
/// would end up with the same machine, spelled less clearly and untested.

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
