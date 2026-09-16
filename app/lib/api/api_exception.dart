/// Error types thrown by [ApiClient], ported from the `ApiError` /
/// `UnauthorizedError` pair in `frontend/src/lib/api.ts`.
///
/// The point of having named types rather than passing `DioException` around is
/// that callers get to branch on *meaning* ("the password was wrong", "there is
/// no network") instead of on transport details, and no screen has to import
/// `dio`. Everything above [ApiClient] deals in these three classes only.
library;

/// Any failed API call that came back from the server with a status code.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, [this.body]);

  /// HTTP status. Null only for [NetworkException], where no response arrived.
  final int? statusCode;

  /// Human-readable message. Taken from the response body's `message` field when
  /// the backend provided one (its error shape is `{ error, message }`), falling
  /// back to the status line.
  final String message;

  /// Decoded response body, kept for the rare caller that needs a field beyond
  /// `message` (e.g. a Zod validation error list from a 400).
  final Object? body;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// HTTP 401.
///
/// Split out as its own type for the same reason as in `api.ts`: it is the one
/// status with two completely different meanings depending on the call. On
/// `POST /auth/login` it means "wrong credentials" and is an ordinary, expected
/// outcome shown inline; anywhere else it means the session is gone and the app
/// has to fall back to the login screen. Callers distinguish those with
/// `on UnauthorizedException`, not by comparing integers.
class UnauthorizedException extends ApiException {
  UnauthorizedException([Object? body]) : super(401, 'Unauthorized', body);

  @override
  String toString() => 'UnauthorizedException: $message';
}

/// The request never reached the server, or the server never answered:
/// DNS failure, refused connection, timeout, dropped Wi-Fi.
///
/// This case has no equivalent in `api.ts` because a browser page and its API
/// are served from the same origin -- if the network is gone, so is the app. A
/// phone that is installed and running with no connectivity is the normal case
/// here, so it gets its own type: the UI wording differs ("нет связи с
/// сервером" vs "сервер ответил ошибкой") and, importantly, a network failure
/// must never be mistaken for an expired session and clear a perfectly good
/// token.
class NetworkException extends ApiException {
  NetworkException(String message, {this.cause}) : super(null, message);

  /// The underlying transport error, for logging.
  final Object? cause;

  @override
  String toString() => 'NetworkException: $message';
}
