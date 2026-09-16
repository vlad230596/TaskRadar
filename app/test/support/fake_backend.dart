import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:taskradar/api/api_client.dart';

/// A stand-in for the TaskRadar backend, wired in at the lowest layer dio
/// exposes: its [HttpClientAdapter].
///
/// Swapping the adapter rather than mocking [ApiClient] itself is what makes
/// these tests worth running. Everything above the socket stays real -- the
/// interceptors, the `Authorization` header logic, `validateStatus`, dio's JSON
/// transformer and the DioException -> ApiException mapping are all exercised.
/// A mocked `ApiClient` would test nothing but the mock.
class FakeBackend {
  FakeBackend({String baseUrl = 'http://backend.test'})
    : client = ApiClient.forBaseUrl(baseUrl) {
    client.dio.httpClientAdapter = _FakeAdapter(_handle);
  }

  /// The client under test.
  final ApiClient client;

  /// Every request that reached the transport, in order. Assert on headers and
  /// query parameters through this.
  final List<RequestOptions> requests = <RequestOptions>[];

  /// Decides what each request gets back. Throw a [DioException] from here to
  /// simulate a transport failure.
  FutureOr<ResponseBody> Function(RequestOptions options)? responder;

  RequestOptions get lastRequest => requests.last;

  /// Convenience for the common case of one canned answer.
  void alwaysRespond(Object? body, {int statusCode = 200}) {
    responder = (_) => jsonResponse(body, statusCode: statusCode);
  }

  /// Awaited before every response, when set.
  ///
  /// The only way to observe an *optimistic* frame: hold the write open, assert
  /// that the UI already shows the prediction, then let the response through and
  /// assert that it settled. Without a hook like this the fake answers in the
  /// same microtask and the frame the user actually sees never exists in a test.
  Future<void> Function(RequestOptions options)? delay;

  /// Request paths (matched as substrings) that fail with a connection error
  /// while everything else is answered normally.
  ///
  /// "One endpoint is down and the rest are fine" is a real state on this screen
  /// -- the tasks and the notes are separate requests, and the screen is
  /// supposed to report the failure on the notes tab alone rather than replacing
  /// the whole project with an error page.
  final Set<String> failingPaths = <String>{};

  /// Simulates "the server is not there": no response, no status code.
  void alwaysFailToConnect() {
    responder = (options) => throw DioException.connectionError(
      requestOptions: options,
      reason: 'simulated connection failure',
    );
  }

  /// Registers a handler for one route.
  ///
  /// F3 is the first iteration where a single screen talks to five endpoints, so
  /// "one canned answer for everything" stopped being enough: a test that reads
  /// tasks *and* notes *and* the project needs three different bodies, and the
  /// alternative to routing is a hand-rolled `if (path.contains(...))` chain in
  /// every test file.
  ///
  /// [pathPattern] may contain `:name` segments, which match one path segment
  /// each and are handed to the handler as [RouteMatch.params]. Routes are tried
  /// in registration order, so a specific route registered first wins over a
  /// general one -- which matters for `/tasks/:id` versus `/tasks/:id/position`.
  ///
  /// An explicit [responder] still wins over every route, so
  /// [alwaysFailToConnect] can be dropped on top of a fully routed fake to
  /// simulate the network dying mid-test.
  void on(String method, String pathPattern, RouteResponder handler) {
    _routes.add(_Route(method, pathPattern, handler));
  }

  final List<_Route> _routes = <_Route>[];

  Future<ResponseBody> _handle(RequestOptions options) async {
    requests.add(options);

    final delay = this.delay;
    if (delay != null) await delay(options);

    if (failingPaths.any(options.path.contains)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'simulated connection failure for ${options.path}',
      );
    }

    final responder = this.responder;
    if (responder != null) return responder(options);

    for (final route in _routes) {
      final match = route.match(options);
      if (match != null) return route.handler(match);
    }

    throw StateError(
      'FakeBackend got an unexpected ${options.method} ${options.path} '
      'with no responder and no matching route',
    );
  }
}

/// A request that matched a route, with the path parameters pulled out.
class RouteMatch {
  const RouteMatch(this.options, this.params);

  final RequestOptions options;
  final Map<String, String> params;

  /// The decoded request body, or an empty map when there was none.
  ///
  /// This is what the "undefined vs null" assertions read: a key that is
  /// *absent* here is a key the client did not send, and a key present with a
  /// null value is an explicit clear. Those two are indistinguishable once a
  /// body has been folded into an object, which is why the tests look at the map.
  Map<String, dynamic> get body {
    final data = options.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String && data.isNotEmpty) {
      return (jsonDecode(data) as Map).cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }
}

typedef RouteResponder = FutureOr<ResponseBody> Function(RouteMatch match);

class _Route {
  _Route(this.method, this.pathPattern, this.handler);

  final String method;
  final String pathPattern;
  final RouteResponder handler;

  final List<String> _names = <String>[];

  /// Compiled on first use. `_compile` fills [_names] as it goes, and `late`
  /// is what guarantees that happens before anything reads them.
  late final RegExp _pattern = _compile(pathPattern, _names);

  static RegExp _compile(String pathPattern, List<String> names) {
    final source = pathPattern.split('/').map((segment) {
      if (!segment.startsWith(':')) return RegExp.escape(segment);
      names.add(segment.substring(1));
      return '([^/]+)';
    }).join('/');

    return RegExp('^$source\$');
  }

  RouteMatch? match(RequestOptions options) {
    if (options.method.toUpperCase() != method.toUpperCase()) return null;

    final found = _pattern.firstMatch(options.path);
    if (found == null) return null;

    return RouteMatch(options, <String, String>{
      for (var i = 0; i < _names.length; i++) _names[i]: found.group(i + 1)!,
    });
  }
}

/// Builds a JSON response body the way the real backend would send it --
/// including the `content-type` header, without which dio hands back a raw
/// string instead of decoded JSON and the tests would pass for the wrong reason.
ResponseBody jsonResponse(Object? body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handle);

  final Future<ResponseBody> Function(RequestOptions options) _handle;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handle(options);
  }

  @override
  void close({bool force = false}) {}
}
