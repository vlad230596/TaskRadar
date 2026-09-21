// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The mode the app is in.
///
/// ## Why this is synchronous and the stored value arrives late
///
/// The obvious shape is `Future<AppMode>` -- read the preference, then build
/// the shell. That would put a spinner in front of the whole app on every cold
/// start in exchange for one `getString`, and on a slow first
/// `SharedPreferences.getInstance` that spinner is visible. Instead the mode
/// starts at [AppMode.plan] and the stored one is applied when it arrives,
/// which is a frame or two later and before anything is readable.
///
/// The ordering hazard that creates is real and handled: if the user taps
/// "Работа" inside that window, the restore must not drag them back. Hence
/// [_restored] -- an explicit choice wins over a late read, permanently.

@ProviderFor(ShellMode)
final shellModeProvider = ShellModeProvider._();

/// The mode the app is in.
///
/// ## Why this is synchronous and the stored value arrives late
///
/// The obvious shape is `Future<AppMode>` -- read the preference, then build
/// the shell. That would put a spinner in front of the whole app on every cold
/// start in exchange for one `getString`, and on a slow first
/// `SharedPreferences.getInstance` that spinner is visible. Instead the mode
/// starts at [AppMode.plan] and the stored one is applied when it arrives,
/// which is a frame or two later and before anything is readable.
///
/// The ordering hazard that creates is real and handled: if the user taps
/// "Работа" inside that window, the restore must not drag them back. Hence
/// [_restored] -- an explicit choice wins over a late read, permanently.
final class ShellModeProvider extends $NotifierProvider<ShellMode, AppMode> {
  /// The mode the app is in.
  ///
  /// ## Why this is synchronous and the stored value arrives late
  ///
  /// The obvious shape is `Future<AppMode>` -- read the preference, then build
  /// the shell. That would put a spinner in front of the whole app on every cold
  /// start in exchange for one `getString`, and on a slow first
  /// `SharedPreferences.getInstance` that spinner is visible. Instead the mode
  /// starts at [AppMode.plan] and the stored one is applied when it arrives,
  /// which is a frame or two later and before anything is readable.
  ///
  /// The ordering hazard that creates is real and handled: if the user taps
  /// "Работа" inside that window, the restore must not drag them back. Hence
  /// [_restored] -- an explicit choice wins over a late read, permanently.
  ShellModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellModeHash();

  @$internal
  @override
  ShellMode create() => ShellMode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppMode>(value),
    );
  }
}

String _$shellModeHash() => r'632cdd54509f4ee745d383d86f88cf0db05e8cd1';

/// The mode the app is in.
///
/// ## Why this is synchronous and the stored value arrives late
///
/// The obvious shape is `Future<AppMode>` -- read the preference, then build
/// the shell. That would put a spinner in front of the whole app on every cold
/// start in exchange for one `getString`, and on a slow first
/// `SharedPreferences.getInstance` that spinner is visible. Instead the mode
/// starts at [AppMode.plan] and the stored one is applied when it arrives,
/// which is a frame or two later and before anything is readable.
///
/// The ordering hazard that creates is real and handled: if the user taps
/// "Работа" inside that window, the restore must not drag them back. Hence
/// [_restored] -- an explicit choice wins over a late read, permanently.

abstract class _$ShellMode extends $Notifier<AppMode> {
  AppMode build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AppMode, AppMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppMode, AppMode>,
              AppMode,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Which way planning is drawing projects. Same restore-vs-tap rule as
/// [ShellMode].

@ProviderFor(PlanLayoutPreference)
final planLayoutPreferenceProvider = PlanLayoutPreferenceProvider._();

/// Which way planning is drawing projects. Same restore-vs-tap rule as
/// [ShellMode].
final class PlanLayoutPreferenceProvider
    extends $NotifierProvider<PlanLayoutPreference, PlanLayout> {
  /// Which way planning is drawing projects. Same restore-vs-tap rule as
  /// [ShellMode].
  PlanLayoutPreferenceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'planLayoutPreferenceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$planLayoutPreferenceHash();

  @$internal
  @override
  PlanLayoutPreference create() => PlanLayoutPreference();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlanLayout value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlanLayout>(value),
    );
  }
}

String _$planLayoutPreferenceHash() =>
    r'cecdd6a6d3238626cf606f06fa4d24ad232a3434';

/// Which way planning is drawing projects. Same restore-vs-tap rule as
/// [ShellMode].

abstract class _$PlanLayoutPreference extends $Notifier<PlanLayout> {
  PlanLayout build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PlanLayout, PlanLayout>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PlanLayout, PlanLayout>,
              PlanLayout,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
