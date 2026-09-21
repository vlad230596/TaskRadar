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

/// The board's read cache (F2). Lives here rather than in `board_providers.dart`
/// for the same reason as [tokenStorage]: it owns a path on disk and a
/// `path_provider` platform channel, so it must not be re-created per screen,
/// and tests must be able to replace it with something that does not touch the
/// filesystem.
///
/// The browser gets a different implementation rather than a disabled one: the
/// file store's `path_provider` channel does not exist there at all. See
/// `../storage/web_stores.dart` for what the two have in common and where they
/// honestly differ.

@ProviderFor(boardSnapshotStore)
final boardSnapshotStoreProvider = BoardSnapshotStoreProvider._();

/// The board's read cache (F2). Lives here rather than in `board_providers.dart`
/// for the same reason as [tokenStorage]: it owns a path on disk and a
/// `path_provider` platform channel, so it must not be re-created per screen,
/// and tests must be able to replace it with something that does not touch the
/// filesystem.
///
/// The browser gets a different implementation rather than a disabled one: the
/// file store's `path_provider` channel does not exist there at all. See
/// `../storage/web_stores.dart` for what the two have in common and where they
/// honestly differ.

final class BoardSnapshotStoreProvider
    extends
        $FunctionalProvider<
          BoardSnapshotStore,
          BoardSnapshotStore,
          BoardSnapshotStore
        >
    with $Provider<BoardSnapshotStore> {
  /// The board's read cache (F2). Lives here rather than in `board_providers.dart`
  /// for the same reason as [tokenStorage]: it owns a path on disk and a
  /// `path_provider` platform channel, so it must not be re-created per screen,
  /// and tests must be able to replace it with something that does not touch the
  /// filesystem.
  ///
  /// The browser gets a different implementation rather than a disabled one: the
  /// file store's `path_provider` channel does not exist there at all. See
  /// `../storage/web_stores.dart` for what the two have in common and where they
  /// honestly differ.
  BoardSnapshotStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'boardSnapshotStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$boardSnapshotStoreHash();

  @$internal
  @override
  $ProviderElement<BoardSnapshotStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BoardSnapshotStore create(Ref ref) {
    return boardSnapshotStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BoardSnapshotStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BoardSnapshotStore>(value),
    );
  }
}

String _$boardSnapshotStoreHash() =>
    r'1efd1e4aadfdfafcaa1d4653fca34b2d35efb9cb';

/// The offline capture queue (F8.1): lines written down on this device that
/// the server has not acknowledged yet.
///
/// Here for the same reason as [boardSnapshotStore] -- it owns a path on disk
/// and a `path_provider` platform channel -- and for one more that is specific
/// to it: this file is the only copy of a line captured with no network, so a
/// second instance writing the same path from another provider scope would be a
/// way to lose one.
///
/// On web this is the `localStorage`-backed twin, and the substitution is
/// load-bearing rather than tidy: the file store throws on every write in a
/// browser, and this store's writes are the ones the capture screen turns into
/// "не удалось записать".

@ProviderFor(captureQueueStore)
final captureQueueStoreProvider = CaptureQueueStoreProvider._();

/// The offline capture queue (F8.1): lines written down on this device that
/// the server has not acknowledged yet.
///
/// Here for the same reason as [boardSnapshotStore] -- it owns a path on disk
/// and a `path_provider` platform channel -- and for one more that is specific
/// to it: this file is the only copy of a line captured with no network, so a
/// second instance writing the same path from another provider scope would be a
/// way to lose one.
///
/// On web this is the `localStorage`-backed twin, and the substitution is
/// load-bearing rather than tidy: the file store throws on every write in a
/// browser, and this store's writes are the ones the capture screen turns into
/// "не удалось записать".

final class CaptureQueueStoreProvider
    extends
        $FunctionalProvider<
          CaptureQueueStore,
          CaptureQueueStore,
          CaptureQueueStore
        >
    with $Provider<CaptureQueueStore> {
  /// The offline capture queue (F8.1): lines written down on this device that
  /// the server has not acknowledged yet.
  ///
  /// Here for the same reason as [boardSnapshotStore] -- it owns a path on disk
  /// and a `path_provider` platform channel -- and for one more that is specific
  /// to it: this file is the only copy of a line captured with no network, so a
  /// second instance writing the same path from another provider scope would be a
  /// way to lose one.
  ///
  /// On web this is the `localStorage`-backed twin, and the substitution is
  /// load-bearing rather than tidy: the file store throws on every write in a
  /// browser, and this store's writes are the ones the capture screen turns into
  /// "не удалось записать".
  CaptureQueueStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'captureQueueStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$captureQueueStoreHash();

  @$internal
  @override
  $ProviderElement<CaptureQueueStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CaptureQueueStore create(Ref ref) {
    return captureQueueStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CaptureQueueStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CaptureQueueStore>(value),
    );
  }
}

String _$captureQueueStoreHash() => r'b16af3d3fe18d9dc421b237c7c7b4a196d1f51f7';

/// Persisted user preferences (F4): currently the reminder hour.
///
/// Here rather than in `reminder_providers.dart` for the same reason as
/// [tokenStorage] and [boardSnapshotStore]: it owns a platform channel, so it
/// must not be re-created per screen and tests must be able to replace it with
/// something that does not have one.

@ProviderFor(settingsStore)
final settingsStoreProvider = SettingsStoreProvider._();

/// Persisted user preferences (F4): currently the reminder hour.
///
/// Here rather than in `reminder_providers.dart` for the same reason as
/// [tokenStorage] and [boardSnapshotStore]: it owns a platform channel, so it
/// must not be re-created per screen and tests must be able to replace it with
/// something that does not have one.

final class SettingsStoreProvider
    extends $FunctionalProvider<SettingsStore, SettingsStore, SettingsStore>
    with $Provider<SettingsStore> {
  /// Persisted user preferences (F4): currently the reminder hour.
  ///
  /// Here rather than in `reminder_providers.dart` for the same reason as
  /// [tokenStorage] and [boardSnapshotStore]: it owns a platform channel, so it
  /// must not be re-created per screen and tests must be able to replace it with
  /// something that does not have one.
  SettingsStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsStoreHash();

  @$internal
  @override
  $ProviderElement<SettingsStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SettingsStore create(Ref ref) {
    return settingsStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsStore>(value),
    );
  }
}

String _$settingsStoreHash() => r'fc6e4d6b835941fdeca07545e3d09d378f5a0068';

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

/// The read-and-write half of the API (F3): one project, its tasks, its notes.
///
/// `keepAlive` like its siblings even though the screens that use it come and
/// go: it is a stateless wrapper around the shared [ApiClient], and letting it
/// be rebuilt per screen would cost an allocation to achieve nothing.

@ProviderFor(projectApi)
final projectApiProvider = ProjectApiProvider._();

/// The read-and-write half of the API (F3): one project, its tasks, its notes.
///
/// `keepAlive` like its siblings even though the screens that use it come and
/// go: it is a stateless wrapper around the shared [ApiClient], and letting it
/// be rebuilt per screen would cost an allocation to achieve nothing.

final class ProjectApiProvider
    extends $FunctionalProvider<ProjectApi, ProjectApi, ProjectApi>
    with $Provider<ProjectApi> {
  /// The read-and-write half of the API (F3): one project, its tasks, its notes.
  ///
  /// `keepAlive` like its siblings even though the screens that use it come and
  /// go: it is a stateless wrapper around the shared [ApiClient], and letting it
  /// be rebuilt per screen would cost an allocation to achieve nothing.
  ProjectApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectApiHash();

  @$internal
  @override
  $ProviderElement<ProjectApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProjectApi create(Ref ref) {
    return projectApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectApi>(value),
    );
  }
}

String _$projectApiHash() => r'f8c88df174ac22584db6055743cf9b67cb664f4d';

/// The scope endpoints (F7). Same shape and same reasoning as [projectApi]: a
/// stateless wrapper around the shared [ApiClient].

@ProviderFor(scopeApi)
final scopeApiProvider = ScopeApiProvider._();

/// The scope endpoints (F7). Same shape and same reasoning as [projectApi]: a
/// stateless wrapper around the shared [ApiClient].

final class ScopeApiProvider
    extends $FunctionalProvider<ScopeApi, ScopeApi, ScopeApi>
    with $Provider<ScopeApi> {
  /// The scope endpoints (F7). Same shape and same reasoning as [projectApi]: a
  /// stateless wrapper around the shared [ApiClient].
  ScopeApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scopeApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scopeApiHash();

  @$internal
  @override
  $ProviderElement<ScopeApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ScopeApi create(Ref ref) {
    return scopeApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScopeApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScopeApi>(value),
    );
  }
}

String _$scopeApiHash() => r'0fdefd2cdd41b1cbbcf2d58faceee6f7efcbe2d5';

/// The sandbox endpoints (F8). Same shape and reasoning as [projectApi].

@ProviderFor(inboxApi)
final inboxApiProvider = InboxApiProvider._();

/// The sandbox endpoints (F8). Same shape and reasoning as [projectApi].

final class InboxApiProvider
    extends $FunctionalProvider<InboxApi, InboxApi, InboxApi>
    with $Provider<InboxApi> {
  /// The sandbox endpoints (F8). Same shape and reasoning as [projectApi].
  InboxApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxApiHash();

  @$internal
  @override
  $ProviderElement<InboxApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  InboxApi create(Ref ref) {
    return inboxApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InboxApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InboxApi>(value),
    );
  }
}

String _$inboxApiHash() => r'5186d371cd119c20528bb433b056e668465cb4e1';
