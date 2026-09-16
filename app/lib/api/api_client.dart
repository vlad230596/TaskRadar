import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// Called once, app-wide, when any request comes back 401.
typedef UnauthorizedHandler = void Function();

/// The single place that talks HTTP to the TaskRadar backend.
///
/// Port of `frontend/src/lib/api.ts`. The three jobs it inherits from that file:
///
/// 1. centralise JSON encode/decode and error handling, so no screen ever sees a
///    status code;
/// 2. centralise the app-wide reaction to a dead session -- register a handler
///    once (see `SessionNotifier`) and every present and future caller gets
///    "401 -> back to the login screen" for free, without knowing about routing;
/// 3. carry credentials automatically.
///
/// Point 3 is where the native client diverges from the web one. `api.ts` sends
/// `credentials: "include"` and lets the browser attach the httpOnly session
/// cookie. Here the token is held by the app itself (see `TokenStorage`) and
/// goes out as `Authorization: Bearer <token>`.
class ApiClient {
  /// Installs the interceptors on [dio]. Tests construct this with a `Dio` whose
  /// `httpClientAdapter` is faked, which is why the dependency is injected
  /// rather than created inside.
  ApiClient(this.dio) {
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  /// The configuration used by the running app.
  factory ApiClient.forBaseUrl(String baseUrl) {
    return ApiClient(
      Dio(
        BaseOptions(
          baseUrl: baseUrl,

          // Timeouts matter much more here than in the browser build: on a phone
          // with one bar, dio's default of "wait forever" turns a dead server
          // into a spinner that never resolves. These are generous enough for a
          // cold VPS and short enough that the user learns something is wrong.
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),

          responseType: ResponseType.json,
          contentType: Headers.jsonContentType,

          // Hand every response to our own code instead of letting dio decide
          // which statuses are "errors". [_mapError] then produces one of the
          // three exception types from api_exception.dart, so the error surface
          // of this class does not depend on dio's defaults.
          validateStatus: (status) => status != null && status >= 200 && status < 300,
        ),
      ),
    );
  }

  /// `RequestOptions.extra` key carrying the per-call opt-out from the global
  /// 401 handler. Using `extra` (rather than a parameter threaded through the
  /// interceptor) is what lets the handler stay a single interceptor while
  /// individual calls can still exempt themselves.
  static const String _skipUnauthorizedHandlerKey = 'taskradar.skipUnauthorizedHandler';

  final Dio dio;

  String? _token;
  UnauthorizedHandler? _onUnauthorized;

  /// Sets (or, with null, clears) the bearer token used by subsequent requests.
  ///
  /// Kept in memory rather than read from secure storage per request: every read
  /// is a platform-channel round trip to the Android Keystore, and the board
  /// screen fires several requests in a row.
  void setToken(String? token) {
    // Normalise "" to null so an empty string can never reach the header logic
    // below -- see the comment there for why that would be actively harmful.
    _token = (token == null || token.isEmpty) ? null : token;
  }

  /// Registers the app-wide "the session is gone" reaction. Called once at
  /// startup; a later call replaces the previous handler.
  void setUnauthorizedHandler(UnauthorizedHandler? handler) {
    _onUnauthorized = handler;
  }

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _token;

    /*
     * Either send a well-formed Authorization header or send none at all.
     *
     * @fastify/jwt looks at `Authorization: Bearer <token>` *before* the session
     * cookie, but a malformed header is not a soft failure it recovers from --
     * it does not fall back to the cookie, it just answers 401. So emitting
     * `Bearer ` with an empty or placeholder token would be strictly worse than
     * emitting nothing: it would break even a request that could have succeeded
     * some other way, and it would do so with the same opaque 401 body as a
     * genuinely expired session, which is very hard to tell apart in the field.
     */
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    } else {
      // Defensive: an interceptor list is shared, and a stale header surviving
      // a logout would keep sending a token the app believes it has forgotten.
      options.headers.remove('Authorization');
    }

    /*
     * A request with no body must not claim to have a JSON one.
     *
     * `BaseOptions.contentType` above is `application/json`, and dio applies it
     * to every request whether or not there is anything to send. Fastify's JSON
     * parser then rejects the result outright:
     *
     *     400 Body cannot be empty when content-type is set to 'application/json'
     *
     * which means **every `DELETE` in this client** -- delete a task, delete a
     * note -- fails, along with the bodiless `POST /projects/:id/archive` that
     * F4 will need. It is invisible in tests that fake the transport, because a
     * fake does not care what the content-type says; it shows up the first time
     * the app deletes something against a real server. Found exactly that way,
     * by `test/live_project_contract_test.dart`.
     */
    if (options.data == null) {
      options.headers.remove(Headers.contentTypeHeader);
    }

    handler.next(options);
  }

  void _onError(DioException error, ErrorInterceptorHandler handler) {
    final isUnauthorized = error.response?.statusCode == 401;
    final skip = error.requestOptions.extra[_skipUnauthorizedHandlerKey] == true;

    if (isUnauthorized && !skip) {
      _onUnauthorized?.call();
    }

    // The caller still gets the error: the global handler decides what happens
    // to the *session*, not what this particular call returns. [request] turns
    // it into an [UnauthorizedException] a moment later.
    handler.next(error);
  }

  /// Performs a request and returns its decoded JSON body, cast to [T].
  ///
  /// [T] is the shape the endpoint documents -- `Map<String, dynamic>` for the
  /// object responses, `List<dynamic>` for `GET /board`, which answers with a
  /// bare array.
  ///
  /// Set [skipUnauthorizedHandler] when a 401 from this specific call is an
  /// expected answer rather than evidence that the session died. There are
  /// exactly two such calls, both in `AuthApi`; see the comments there.
  Future<T> request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    bool skipUnauthorizedHandler = false,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          extra: <String, dynamic>{
            _skipUnauthorizedHandlerKey: skipUnauthorizedHandler,
          },
        ),
      );

      // 204 and an empty 200 both arrive as a null body. Callers that expect
      // nothing back declare `T` as `void`/`dynamic`; a caller that declared a
      // real shape and got nothing has hit a contract change and should fail
      // loudly here rather than three frames later with a null dereference.
      final data = response.data;
      if (data == null) {
        if (null is T) return null as T;
        throw ApiException(
          response.statusCode,
          'Empty response body where ${T.toString()} was expected',
        );
      }

      if (data is! T) {
        throw ApiException(
          response.statusCode,
          'Unexpected response shape: got ${data.runtimeType}, expected $T',
          data,
        );
      }

      return data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool skipUnauthorizedHandler = false,
  }) {
    return request<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      skipUnauthorizedHandler: skipUnauthorizedHandler,
    );
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    bool skipUnauthorizedHandler = false,
  }) {
    return request<T>(
      'POST',
      path,
      body: body,
      skipUnauthorizedHandler: skipUnauthorizedHandler,
    );
  }

  Future<T> patch<T>(String path, {Object? body}) {
    return request<T>('PATCH', path, body: body);
  }

  Future<T> delete<T>(String path) {
    return request<T>('DELETE', path);
  }

  /// Turns dio's single catch-all exception into the three cases callers care
  /// about. Mirrors the status checks at the bottom of `apiRequest` in `api.ts`.
  ApiException _mapError(DioException error) {
    final response = error.response;

    if (response == null) {
      // No status code at all: connection refused, DNS failure, timeout, the
      // phone's radio off. Explicitly *not* an auth problem -- see the note on
      // [NetworkException].
      return NetworkException(
        _networkMessage(error.type),
        cause: error.error ?? error,
      );
    }

    if (response.statusCode == 401) {
      return UnauthorizedException(response.data);
    }

    return ApiException(
      response.statusCode,
      _extractMessage(response.data, response.statusMessage ?? 'Request failed'),
      response.data,
    );
  }

  static String _networkMessage(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'The server did not respond in time';
      case DioExceptionType.connectionError:
        return 'Could not reach the server';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      case DioExceptionType.badCertificate:
        return 'The server presented an invalid TLS certificate';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return 'Network error';
    }
  }

  /// The backend's error bodies are `{ error, message }` (see
  /// `backend/src/lib/authGuard.ts` and the central error handler), so prefer
  /// `message` and fall back to the status line.
  static String _extractMessage(Object? body, String fallback) {
    if (body is Map && body['message'] is String) {
      return body['message'] as String;
    }
    return fallback;
  }
}

/// Convenience constructor for the app (as opposed to tests), using the base URL
/// baked in at build time.
ApiClient createConfiguredApiClient() => ApiClient.forBaseUrl(AppConfig.apiBaseUrl);
