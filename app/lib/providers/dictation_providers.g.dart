// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dictation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The model the server parses dictation with (F14), for the settings screen.
///
/// Not kept alive: it is read when the settings screen opens and nowhere else,
/// and a value cached from an hour ago would be exactly the stale answer a
/// settings screen must not give.

@ProviderFor(DictationModelSetting)
final dictationModelSettingProvider = DictationModelSettingProvider._();

/// The model the server parses dictation with (F14), for the settings screen.
///
/// Not kept alive: it is read when the settings screen opens and nowhere else,
/// and a value cached from an hour ago would be exactly the stale answer a
/// settings screen must not give.
final class DictationModelSettingProvider
    extends $AsyncNotifierProvider<DictationModelSetting, DictationModel> {
  /// The model the server parses dictation with (F14), for the settings screen.
  ///
  /// Not kept alive: it is read when the settings screen opens and nowhere else,
  /// and a value cached from an hour ago would be exactly the stale answer a
  /// settings screen must not give.
  DictationModelSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'dictationModelSettingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dictationModelSettingHash();

  @$internal
  @override
  DictationModelSetting create() => DictationModelSetting();
}

String _$dictationModelSettingHash() =>
    r'755c9c383bb5d1af257f22ae44606e516677d6a0';

/// The model the server parses dictation with (F14), for the settings screen.
///
/// Not kept alive: it is read when the settings screen opens and nowhere else,
/// and a value cached from an hour ago would be exactly the stale answer a
/// settings screen must not give.

abstract class _$DictationModelSetting extends $AsyncNotifier<DictationModel> {
  FutureOr<DictationModel> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<DictationModel>, DictationModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<DictationModel>, DictationModel>,
              AsyncValue<DictationModel>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The level AI processing starts at (`domain/ai_level.dart`), chosen in the
/// settings. Each parse screen starts from it and may move away from it for
/// one text -- "сильнее", "слабее" -- without changing it.
///
/// Like [ReminderSettings], the state is set before the write and kept if
/// the write fails: the choice holds for this session either way.

@ProviderFor(AiLevelSetting)
final aiLevelSettingProvider = AiLevelSettingProvider._();

/// The level AI processing starts at (`domain/ai_level.dart`), chosen in the
/// settings. Each parse screen starts from it and may move away from it for
/// one text -- "сильнее", "слабее" -- without changing it.
///
/// Like [ReminderSettings], the state is set before the write and kept if
/// the write fails: the choice holds for this session either way.
final class AiLevelSettingProvider
    extends $AsyncNotifierProvider<AiLevelSetting, int> {
  /// The level AI processing starts at (`domain/ai_level.dart`), chosen in the
  /// settings. Each parse screen starts from it and may move away from it for
  /// one text -- "сильнее", "слабее" -- without changing it.
  ///
  /// Like [ReminderSettings], the state is set before the write and kept if
  /// the write fails: the choice holds for this session either way.
  AiLevelSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiLevelSettingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiLevelSettingHash();

  @$internal
  @override
  AiLevelSetting create() => AiLevelSetting();
}

String _$aiLevelSettingHash() => r'8208a8fcba7e336ea890c7cfedb985647cc2307c';

/// The level AI processing starts at (`domain/ai_level.dart`), chosen in the
/// settings. Each parse screen starts from it and may move away from it for
/// one text -- "сильнее", "слабее" -- without changing it.
///
/// Like [ReminderSettings], the state is set before the write and kept if
/// the write fails: the choice holds for this session either way.

abstract class _$AiLevelSetting extends $AsyncNotifier<int> {
  FutureOr<int> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<int>, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<int>, int>,
              AsyncValue<int>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
