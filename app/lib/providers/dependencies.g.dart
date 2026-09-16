// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dependencies.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's long-lived singletons, expressed as providers.
///
/// Everything here is `keepAlive: true`. These are not per-screen state: the
/// [ApiClient] holds the in-memory bearer token and the registered 401 handler,
/// so letting it be disposed when the last screen stops watching it would
/// silently log the user out on navigation. Same reasoning for [TokenStorage],
/// which owns a platform channel.
///
/// Tests override these with fakes via `ProviderScope(overrides: ...)`, which is
/// the only reason the API classes take their dependencies as constructor
/// arguments rather than reaching for globals.

@ProviderFor(tokenStorage)
final tokenStorageProvider = TokenStorageProvider._();

/// The app's long-lived singletons, expressed as providers.
///
/// Everything here is `keepAlive: true`. These are not per-screen state: the
/// [ApiClient] holds the in-memory bearer token and the registered 401 handler,
/// so letting it be disposed when the last screen stops watching it would
/// silently log the user out on navigation. Same reasoning for [TokenStorage],
/// which owns a platform channel.
///
/// Tests override these with fakes via `ProviderScope(overrides: ...)`, which is
/// the only reason the API classes take their dependencies as constructor
/// arguments rather than reaching for globals.

final class TokenStorageProvider
    extends $FunctionalProvider<TokenStorage, TokenStorage, TokenStorage>
    with $Provider<TokenStorage> {
  /// The app's long-lived singletons, expressed as providers.
  ///
  /// Everything here is `keepAlive: true`. These are not per-screen state: the
  /// [ApiClient] holds the in-memory bearer token and the registered 401 handler,
  /// so letting it be disposed when the last screen stops watching it would
  /// silently log the user out on navigation. Same reasoning for [TokenStorage],
  /// which owns a platform channel.
  ///
  /// Tests override these with fakes via `ProviderScope(overrides: ...)`, which is
  /// the only reason the API classes take their dependencies as constructor
  /// arguments rather than reaching for globals.
  TokenStorageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tokenStorageProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tokenStorageHash();

  @$internal
  @override
  $ProviderElement<TokenStorage> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TokenStorage create(Ref ref) {
    return tokenStorage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TokenStorage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TokenStorage>(value),
    );
  }
}

String _$tokenStorageHash() => r'a42816fb1cf5af728e44ff5c48bfcaf5dc6b12aa';

@ProviderFor(apiClient)
final apiClientProvider = ApiClientProvider._();

final class ApiClientProvider
    extends $FunctionalProvider<ApiClient, ApiClient, ApiClient>
    with $Provider<ApiClient> {
  ApiClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'apiClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$apiClientHash();

  @$internal
  @override
  $ProviderElement<ApiClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ApiClient create(Ref ref) {
    return apiClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ApiClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ApiClient>(value),
    );
  }
}

String _$apiClientHash() => r'9993599a7dafe320111738797c68e1f2e69e38c6';

@ProviderFor(authApi)
final authApiProvider = AuthApiProvider._();

final class AuthApiProvider
    extends $FunctionalProvider<AuthApi, AuthApi, AuthApi>
    with $Provider<AuthApi> {
  AuthApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authApiHash();

  @$internal
  @override
  $ProviderElement<AuthApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthApi create(Ref ref) {
    return authApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthApi>(value),
    );
  }
}

String _$authApiHash() => r'6728b4dea83518c83a38007056106c5d040a7568';

@ProviderFor(boardApi)
final boardApiProvider = BoardApiProvider._();

final class BoardApiProvider
    extends $FunctionalProvider<BoardApi, BoardApi, BoardApi>
    with $Provider<BoardApi> {
  BoardApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardApiHash();

  @$internal
  @override
  $ProviderElement<BoardApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BoardApi create(Ref ref) {
    return boardApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BoardApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BoardApi>(value),
    );
  }
}

String _$boardApiHash() => r'741164fa76ea375c3580da087f61898da58cc219';
