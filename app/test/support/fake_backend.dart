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

  /// Simulates "the server is not there": no response, no status code.
  void alwaysFailToConnect() {
    responder = (options) => throw DioException.connectionError(
      requestOptions: options,
      reason: 'simulated connection failure',
    );
  }

  Future<ResponseBody> _handle(RequestOptions options) async {
    requests.add(options);
    final responder = this.responder;
    if (responder == null) {
      throw StateError(
        'FakeBackend got an unexpected ${options.method} ${options.path} '
        'with no responder configured',
      );
    }
    return responder(options);
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
