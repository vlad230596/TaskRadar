import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_exception.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'session_provider.g.dart';

/// Where the app is, as far as authentication goes.
///
/// Only two values, and no `unknown`: "we do not know yet" is the *loading*
/// state of the surrounding `AsyncValue`, not a third status. Folding it in
/// would let a caller forget to handle it and render the login screen for a
/// frame on every cold start, which is exactly the flicker this split avoids.
enum SessionStatus { signedIn, signedOut }

/// Owns the answer to "is there a live session?" and every transition into and
/// out of one.
///
/// The single place that writes the token to disk, hands it to [ApiClient], and
/// throws it away again. Screens never touch [TokenStorage] directly.
@Riverpod(keepAlive: true)
class Session extends _$Session {
  /// Startup path: decide between the login screen and the app, and do it with
  /// at most one network request.
  ///
  /// - no stored token -> login, no request at all;
  /// - stored token + `GET /auth/me` 200 -> straight into the app;
  /// - stored token + 401 -> the token is expired or was signed with a rotated
  ///   secret; drop it and show login.
  @override
  Future<SessionStatus> build() async {
    final api = ref.watch(apiClientProvider);

    /*
     * Register the app-wide 401 reaction here, once, rather than at each call
     * site -- the same arrangement `frontend/src/lib/api.ts` describes and
     * `main.tsx` wires up. This notifier is the natural owner: it is keepAlive
     * (so registration happens once per app run), and reacting to a dead session
     * is literally its job, so there is no indirection through a router.
     *
     * Registering from *this* side, rather than having the ApiClient provider
     * reach for the session notifier, also keeps the dependency edge pointing
     * one way: session -> api client. The reverse would be a cycle in the
     * provider graph.
     */
    api.setUnauthorizedHandler(_handleUnauthorized);

    final token = await ref.read(tokenStorageProvider).read();
    if (token == null) {
      return SessionStatus.signedOut;
    }

    api.setToken(token);

    try {
      await ref.read(authApiProvider).me();
      return SessionStatus.signedIn;
    } on UnauthorizedException {
      await _forgetToken();
      return SessionStatus.signedOut;
    } on NetworkException catch (error) {
      /*
       * Offline at launch is NOT a reason to sign out.
       *
       * The token is valid for 30 days and nothing here disproved it -- the
       * server simply could not be reached (phone on mobile data while the dev
       * backend is on the LAN, VPS restarting, tunnel down). Clearing it would
       * punish the user for the network's problem and, worse, would make the
       * app unusable in exactly the situation F2's offline board snapshot is
       * being built for.
       *
       * So we stay optimistically signed in. If the token really is dead, the
       * first successful round trip will come back 401 and the handler
       * registered above will sign out properly then.
       */
      debugPrint('Session probe could not reach the server: ${error.message}');
      return SessionStatus.signedIn;
    }
  }

  /// Logs in and persists the token.
  ///
  /// Throws on failure ([UnauthorizedException] for wrong credentials,
  /// [NetworkException] for an unreachable server) so the login screen can show
  /// the right message; it does not fold the failure into [state], because a
  /// failed login attempt does not change the session -- the user was signed out
  /// before and still is.
  Future<void> signIn({required String email, required String password}) async {
    final result = await ref
        .read(authApiProvider)
        .login(email: email, password: password);

    // Persist before flipping the state: if writing to secure storage fails, the
    // user should see the login error rather than land in the app with a session
    // that silently will not survive a restart.
    await ref.read(tokenStorageProvider).write(result.token);
    ref.read(apiClientProvider).setToken(result.token);

    /*
     * Drop the cached board before letting the app back in.
     *
     * `Board` is keepAlive, and a provider that already holds a value does not
     * rebuild just because a screen re-mounted. So without this, a session that
     * ended (an expired token, an explicit logout) and was then re-established
     * would put the board fetched *before* it ended back on screen, labelled as
     * live, with nothing scheduled to refresh it until the user thought to pull
     * down.
     *
     * Invalidating here rather than in the sign-out paths is deliberate: at this
     * point the board screen is certainly not mounted (the login form is) and the
     * new token is already installed, so the rebuild cannot fire a request with
     * a token that has just been thrown away.
     *
     * The snapshot *file* is left alone on purpose -- it is this same user's
     * last good board, and drawing it instantly on the next cold start is the
     * entire reason it exists.
     */
    ref.invalidate(boardProvider);

    state = const AsyncData(SessionStatus.signedIn);
  }

  /// Signs out on purpose (the button).
  ///
  /// The server call is best-effort: all `POST /auth/logout` does is clear the
  /// cookie, which this client does not use, and there is no session table, so
  /// the token stays technically valid until it expires either way. Deleting it
  /// locally is the part that matters, and it must happen even when the network
  /// call fails -- otherwise "log out" would be impossible offline.
  Future<void> signOut() async {
    try {
      await ref.read(authApiProvider).logout();
    } on ApiException catch (error) {
      debugPrint('Ignoring failed logout call: ${error.message}');
    }
    await _forgetToken();
    state = const AsyncData(SessionStatus.signedOut);
  }

  /// The app-wide "the server says this session is gone" reaction.
  ///
  /// Called from inside a dio error interceptor, i.e. in the middle of somebody
  /// else's failing request. It therefore must not block that request or throw
  /// into it: the cleanup is started and deliberately not awaited, while the
  /// original call goes on to throw [UnauthorizedException] at its own caller.
  void _handleUnauthorized() {
    if (!ref.mounted) return;

    // Already signed out (e.g. two in-flight requests both 401'd) -- nothing to
    // do, and re-emitting the state would rebuild the login screen underneath
    // the user.
    if (state case AsyncData(value: SessionStatus.signedOut)) return;

    unawaited(_signOutFromExpiredSession());
  }

  Future<void> _signOutFromExpiredSession() async {
    await _forgetToken();
    if (!ref.mounted) return;
    state = const AsyncData(SessionStatus.signedOut);
  }

  /// Drops the token from both places it lives: the in-memory copy the HTTP
  /// client sends, and the encrypted store. Order matters only in that the
  /// in-memory one is cleared first, so no request can slip out with a token
  /// that has already been erased from disk.
  Future<void> _forgetToken() async {
    ref.read(apiClientProvider).setToken(null);
    await ref.read(tokenStorageProvider).clear();
  }
}
