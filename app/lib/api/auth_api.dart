import '../models/login_result.dart';
import 'api_client.dart';

/// The `/auth/*` endpoints.
///
/// Thin on purpose: its whole job is to know the paths, the request shapes and
/// -- the part that actually matters -- which calls must opt out of the global
/// 401 handler.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  /// `POST /auth/login`.
  ///
  /// Throws [UnauthorizedException] on wrong credentials (the backend answers
  /// 401 with `{ error: "Unauthorized", message: "Invalid email or password" }`
  /// and no `token` field), and [NetworkException] if the server is unreachable.
  ///
  /// `skipUnauthorizedHandler` is the same opt-out the React login page uses,
  /// for the same reason: a 401 here means "wrong password", which is an
  /// expected outcome displayed next to the form, not a session that expired.
  /// Letting it through to the global handler would clear a token the user
  /// never had and bounce them to the screen they are already looking at.
  Future<LoginResult> login({required String email, required String password}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      body: <String, dynamic>{'email': email, 'password': password},
      skipUnauthorizedHandler: true,
    );
    return LoginResult.fromJson(json);
  }

  /// `GET /auth/me` -- the cheap "is this session still alive?" probe run at
  /// startup. Returns normally on 200, throws [UnauthorizedException] on 401.
  ///
  /// The response body is `{ ok: true }` and carries no identity at all (one
  /// user, and the token deliberately holds a minimal claim set), so there is
  /// nothing to return.
  ///
  /// This one also skips the global handler, and the reason is subtler than for
  /// login: this call *is* the session decision. Routing its 401 through "some
  /// other call discovered the session died" would mean the startup path both
  /// asks the question and reacts to its own answer from two directions at
  /// once. The caller handles it directly instead.
  Future<void> me() async {
    await _client.get<Map<String, dynamic>>(
      '/auth/me',
      skipUnauthorizedHandler: true,
    );
  }

  /// `POST /auth/logout`.
  ///
  /// Best-effort and close to pointless for this client: all it does server-side
  /// is clear the cookie, and a native client does not use the cookie. There is
  /// no session table, so the token itself stays valid until it expires either
  /// way -- the real logout is deleting it from secure storage. It is still
  /// called so that a shared browser session (the old React client on the same
  /// backend) is not left behind, and callers are expected to ignore failures.
  Future<void> logout() async {
    await _client.post<Map<String, dynamic>>('/auth/logout');
  }
}
