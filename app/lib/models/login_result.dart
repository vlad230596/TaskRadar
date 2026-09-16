import 'package:freezed_annotation/freezed_annotation.dart';

part 'login_result.freezed.dart';
part 'login_result.g.dart';

/// Body of a successful `POST /auth/login`.
///
/// The backend also sets the httpOnly session cookie, exactly as it did for the
/// React client; this body copy exists for native clients, where a cookie jar
/// would have to be bolted onto the HTTP client and separately persisted on
/// desktop. See the long comment in `backend/src/routes/auth.ts`.
@freezed
abstract class LoginResult with _$LoginResult {
  const factory LoginResult({
    required bool ok,
    required String token,

    /// Token lifetime in **seconds** (30 days).
    ///
    /// Seconds, not milliseconds: `@fastify/jwt` / fast-jwt interpret a numeric
    /// `expiresIn` as seconds, and the route echoes the same number back. Mixing
    /// the two units up would produce an expiry 1000x off in either direction,
    /// which is exactly the kind of bug that only shows up a month later.
    required int expiresIn,
  }) = _LoginResult;

  const LoginResult._();

  factory LoginResult.fromJson(Map<String, dynamic> json) => _$LoginResultFromJson(json);

  Duration get lifetime => Duration(seconds: expiresIn);
}
