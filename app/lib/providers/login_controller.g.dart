// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Submission state for the login form: idle / in flight / failed.
///
/// Kept separate from [Session] on purpose. The session is a long-lived fact
/// about the app; a failed login attempt is transient UI state that belongs to
/// one screen and should disappear with it. Folding "wrong password" into the
/// session's `AsyncValue` would make the session look like it was in an error
/// state when it is simply, correctly, signed out.

@ProviderFor(LoginController)
final loginControllerProvider = LoginControllerProvider._();

/// Submission state for the login form: idle / in flight / failed.
///
/// Kept separate from [Session] on purpose. The session is a long-lived fact
/// about the app; a failed login attempt is transient UI state that belongs to
/// one screen and should disappear with it. Folding "wrong password" into the
/// session's `AsyncValue` would make the session look like it was in an error
/// state when it is simply, correctly, signed out.
final class LoginControllerProvider
    extends $AsyncNotifierProvider<LoginController, void> {
  /// Submission state for the login form: idle / in flight / failed.
  ///
  /// Kept separate from [Session] on purpose. The session is a long-lived fact
  /// about the app; a failed login attempt is transient UI state that belongs to
  /// one screen and should disappear with it. Folding "wrong password" into the
  /// session's `AsyncValue` would make the session look like it was in an error
  /// state when it is simply, correctly, signed out.
  LoginControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loginControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loginControllerHash();

  @$internal
  @override
  LoginController create() => LoginController();
}

String _$loginControllerHash() => r'b4cb55830e41becf249e4fbc93af67f674c72809';

/// Submission state for the login form: idle / in flight / failed.
///
/// Kept separate from [Session] on purpose. The session is a long-lived fact
/// about the app; a failed login attempt is transient UI state that belongs to
/// one screen and should disappear with it. Folding "wrong password" into the
/// session's `AsyncValue` would make the session look like it was in an error
/// state when it is simply, correctly, signed out.

abstract class _$LoginController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
