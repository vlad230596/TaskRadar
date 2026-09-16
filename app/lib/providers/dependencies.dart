import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/board_api.dart';
import '../storage/token_storage.dart';

part 'dependencies.g.dart';

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

@Riverpod(keepAlive: true)
TokenStorage tokenStorage(Ref ref) => TokenStorage();

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) => createConfiguredApiClient();

@Riverpod(keepAlive: true)
AuthApi authApi(Ref ref) => AuthApi(ref.watch(apiClientProvider));

@Riverpod(keepAlive: true)
BoardApi boardApi(Ref ref) => BoardApi(ref.watch(apiClientProvider));
