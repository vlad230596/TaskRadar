// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dictation_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The server's roster of models (`backend/src/domain/modelRoster.ts`), for
/// the settings.
///
/// Not kept alive: it is read when the screen opens, and health that is an
/// hour old is exactly the stale answer a settings screen must not give.

@ProviderFor(AiModelsSetting)
final aiModelsSettingProvider = AiModelsSettingProvider._();

/// The server's roster of models (`backend/src/domain/modelRoster.ts`), for
/// the settings.
///
/// Not kept alive: it is read when the screen opens, and health that is an
/// hour old is exactly the stale answer a settings screen must not give.
final class AiModelsSettingProvider
    extends $AsyncNotifierProvider<AiModelsSetting, AiModels> {
  /// The server's roster of models (`backend/src/domain/modelRoster.ts`), for
  /// the settings.
  ///
  /// Not kept alive: it is read when the screen opens, and health that is an
  /// hour old is exactly the stale answer a settings screen must not give.
  AiModelsSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'aiModelsSettingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiModelsSettingHash();

  @$internal
  @override
  AiModelsSetting create() => AiModelsSetting();
}

String _$aiModelsSettingHash() => r'5369a4f12a739dc079cf4f63084cd93f2dd2a14d';

/// The server's roster of models (`backend/src/domain/modelRoster.ts`), for
/// the settings.
///
/// Not kept alive: it is read when the screen opens, and health that is an
/// hour old is exactly the stale answer a settings screen must not give.

abstract class _$AiModelsSetting extends $AsyncNotifier<AiModels> {
  FutureOr<AiModels> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AiModels>, AiModels>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AiModels>, AiModels>,
              AsyncValue<AiModels>,
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

/// "Отправить в несколько" (`backend/src/domain/modelRoster.ts`): parses ask
/// the first two models of the server's list at once, and the answers can be
/// switched between. Remembered between parses, as agreed; off at first.

@ProviderFor(AiMultiSetting)
final aiMultiSettingProvider = AiMultiSettingProvider._();

/// "Отправить в несколько" (`backend/src/domain/modelRoster.ts`): parses ask
/// the first two models of the server's list at once, and the answers can be
/// switched between. Remembered between parses, as agreed; off at first.
final class AiMultiSettingProvider
    extends $AsyncNotifierProvider<AiMultiSetting, bool> {
  /// "Отправить в несколько" (`backend/src/domain/modelRoster.ts`): parses ask
  /// the first two models of the server's list at once, and the answers can be
  /// switched between. Remembered between parses, as agreed; off at first.
  AiMultiSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiMultiSettingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiMultiSettingHash();

  @$internal
  @override
  AiMultiSetting create() => AiMultiSetting();
}

String _$aiMultiSettingHash() => r'df1f90051472064fe5d4fc86b93ffc58e339ce43';

/// "Отправить в несколько" (`backend/src/domain/modelRoster.ts`): parses ask
/// the first two models of the server's list at once, and the answers can be
/// switched between. Remembered between parses, as agreed; off at first.

abstract class _$AiMultiSetting extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
