import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/board_api.dart';
import '../api/project_api.dart';
import '../api/inbox_api.dart';
import '../api/scope_api.dart';
import '../storage/board_snapshot_store.dart';
import '../storage/capture_queue_store.dart';
import '../storage/settings_store.dart';
import '../storage/token_storage.dart';
import '../storage/web_stores.dart';

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
@Riverpod(keepAlive: true)
BoardSnapshotStore boardSnapshotStore(Ref ref) =>
    kIsWeb ? WebBoardSnapshotStore() : BoardSnapshotStore();

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
@Riverpod(keepAlive: true)
CaptureQueueStore captureQueueStore(Ref ref) =>
    kIsWeb ? WebCaptureQueueStore() : CaptureQueueStore();

/// Persisted user preferences (F4): currently the reminder hour.
///
/// Here rather than in `reminder_providers.dart` for the same reason as
/// [tokenStorage] and [boardSnapshotStore]: it owns a platform channel, so it
/// must not be re-created per screen and tests must be able to replace it with
/// something that does not have one.
@Riverpod(keepAlive: true)
SettingsStore settingsStore(Ref ref) => PreferencesSettingsStore();

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) => createConfiguredApiClient();

@Riverpod(keepAlive: true)
AuthApi authApi(Ref ref) => AuthApi(ref.watch(apiClientProvider));

@Riverpod(keepAlive: true)
BoardApi boardApi(Ref ref) => BoardApi(ref.watch(apiClientProvider));

/// The read-and-write half of the API (F3): one project, its tasks, its notes.
///
/// `keepAlive` like its siblings even though the screens that use it come and
/// go: it is a stateless wrapper around the shared [ApiClient], and letting it
/// be rebuilt per screen would cost an allocation to achieve nothing.
@Riverpod(keepAlive: true)
ProjectApi projectApi(Ref ref) => ProjectApi(ref.watch(apiClientProvider));

/// The scope endpoints (F7). Same shape and same reasoning as [projectApi]: a
/// stateless wrapper around the shared [ApiClient].
@Riverpod(keepAlive: true)
ScopeApi scopeApi(Ref ref) => ScopeApi(ref.watch(apiClientProvider));

/// The sandbox endpoints (F8). Same shape and reasoning as [projectApi].
@Riverpod(keepAlive: true)
InboxApi inboxApi(Ref ref) => InboxApi(ref.watch(apiClientProvider));
