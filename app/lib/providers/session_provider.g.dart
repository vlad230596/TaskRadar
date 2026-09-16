// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the answer to "is there a live session?" and every transition into and
/// out of one.
///
/// The single place that writes the token to disk, hands it to [ApiClient], and
/// throws it away again. Screens never touch [TokenStorage] directly.

@ProviderFor(Session)
final sessionProvider = SessionProvider._();

/// Owns the answer to "is there a live session?" and every transition into and
/// out of one.
///
/// The single place that writes the token to disk, hands it to [ApiClient], and
/// throws it away again. Screens never touch [TokenStorage] directly.
final class SessionProvider
    extends $AsyncNotifierProvider<Session, SessionStatus> {
  /// Owns the answer to "is there a live session?" and every transition into and
  /// out of one.
  ///
  /// The single place that writes the token to disk, hands it to [ApiClient], and
  /// throws it away again. Screens never touch [TokenStorage] directly.
  SessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionHash();

  @$internal
  @override
  Session create() => Session();
}

String _$sessionHash() => r'5291d007d8c940e7c45f691bf1d3f71647ef0d97';

/// Owns the answer to "is there a live session?" and every transition into and
/// out of one.
///
/// The single place that writes the token to disk, hands it to [ApiClient], and
/// throws it away again. Screens never touch [TokenStorage] directly.

abstract class _$Session extends $AsyncNotifier<SessionStatus> {
  FutureOr<SessionStatus> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SessionStatus>, SessionStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SessionStatus>, SessionStatus>,
              AsyncValue<SessionStatus>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
