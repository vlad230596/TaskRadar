import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/api/auth_api.dart';
import 'package:taskradar/api/board_api.dart';

import 'support/fake_backend.dart';
import 'support/fixtures.dart';

void main() {
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  group('bearer token', () {
    test('is not sent at all when there is no token', () {
      // Not "sent as an empty Bearer". @fastify/jwt prefers the Authorization
      // header over the cookie but does NOT fall back to the cookie when the
      // header is malformed -- it answers a flat 401. So "no token" must mean
      // "no header".
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      return backend.client.get<Map<String, dynamic>>('/auth/me').then((_) {
        expect(backend.lastRequest.headers.containsKey('Authorization'), isFalse);
      });
    });

    test('is sent as `Bearer <token>` once set', () async {
      backend.client.setToken('jwt.token.value');
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      await backend.client.get<Map<String, dynamic>>('/auth/me');

      expect(backend.lastRequest.headers['Authorization'], 'Bearer jwt.token.value');
    });

    test('an empty string is treated as no token, not as an empty header', () async {
      backend.client.setToken('');
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      await backend.client.get<Map<String, dynamic>>('/auth/me');

      expect(backend.lastRequest.headers.containsKey('Authorization'), isFalse);
    });

    test('clearing the token stops sending the header on later requests', () async {
      backend.client.setToken('jwt.token.value');
      backend.alwaysRespond(<String, dynamic>{'ok': true});
      await backend.client.get<Map<String, dynamic>>('/auth/me');

      backend.client.setToken(null);
      await backend.client.get<Map<String, dynamic>>('/auth/me');

      expect(backend.lastRequest.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('responses', () {
    test('200 returns the decoded body', () async {
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      final body = await backend.client.get<Map<String, dynamic>>('/auth/me');

      expect(body, <String, dynamic>{'ok': true});
    });

    test('a bare JSON array decodes as a List', () async {
      backend.alwaysRespond(boardJson());

      final body = await backend.client.get<List<dynamic>>('/board');

      expect(body, hasLength(2));
    });

    test('401 throws UnauthorizedException carrying the body', () async {
      backend.alwaysRespond(unauthorizedJson(), statusCode: 401);

      await expectLater(
        backend.client.get<Map<String, dynamic>>('/board'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('a non-401 error uses the backend `message` field', () async {
      backend.alwaysRespond(<String, dynamic>{
        'error': 'Bad Request',
        'message': 'name must not be empty',
      }, statusCode: 400);

      await expectLater(
        backend.client.post<Map<String, dynamic>>('/projects'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', 'name must not be empty'),
        ),
      );
    });

    test('an unreachable server throws NetworkException, not Unauthorized', () async {
      // The distinction matters: a NetworkException must never be allowed to
      // look like an expired session and clear a perfectly good token.
      backend.alwaysFailToConnect();

      await expectLater(
        backend.client.get<Map<String, dynamic>>('/auth/me'),
        throwsA(
          isA<NetworkException>().having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    });
  });

  group('global 401 handler', () {
    test('fires once per 401 and every caller gets it for free', () async {
      var calls = 0;
      backend.client.setUnauthorizedHandler(() => calls++);
      backend.alwaysRespond(unauthorizedJson(), statusCode: 401);

      await expectLater(
        BoardApi(backend.client).fetchBoard(),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(calls, 1);
    });

    test('does not fire for non-401 failures', () async {
      var calls = 0;
      backend.client.setUnauthorizedHandler(() => calls++);
      backend.alwaysRespond(<String, dynamic>{'message': 'boom'}, statusCode: 500);

      await expectLater(
        backend.client.get<Map<String, dynamic>>('/board'),
        throwsA(isA<ApiException>()),
      );

      expect(calls, 0);
    });

    test('does not fire for a network failure', () async {
      var calls = 0;
      backend.client.setUnauthorizedHandler(() => calls++);
      backend.alwaysFailToConnect();

      await expectLater(
        backend.client.get<Map<String, dynamic>>('/board'),
        throwsA(isA<NetworkException>()),
      );

      expect(calls, 0);
    });

    test('login opts out: a wrong password is not a dead session', () async {
      // This is the one exception the TS version calls out explicitly. A 401
      // from /auth/login means "неверный пароль", shown inline on the screen the
      // user is already looking at -- not a reason to tear down a session that
      // never existed.
      var calls = 0;
      backend.client.setUnauthorizedHandler(() => calls++);
      backend.alwaysRespond(
        unauthorizedJson(message: 'Invalid email or password'),
        statusCode: 401,
      );

      await expectLater(
        AuthApi(backend.client).login(email: 'a@b.c', password: 'nope'),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(calls, 0, reason: 'the login request must skip the global handler');
    });

    test('the startup probe opts out too', () async {
      // GET /auth/me *is* the session decision; routing its own answer back
      // through the global "session died" path would be circular.
      var calls = 0;
      backend.client.setUnauthorizedHandler(() => calls++);
      backend.alwaysRespond(unauthorizedJson(), statusCode: 401);

      await expectLater(
        AuthApi(backend.client).me(),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(calls, 0);
    });
  });

  group('endpoints', () {
    test('login posts email and password and parses the token', () async {
      backend.alwaysRespond(loginOkJson());

      final result = await AuthApi(backend.client).login(
        email: 'owner@example.com',
        password: 'secret',
      );

      expect(result.token, 'jwt.token.value');
      expect(backend.lastRequest.method, 'POST');
      expect(backend.lastRequest.path, '/auth/login');
      expect(backend.lastRequest.data, <String, dynamic>{
        'email': 'owner@example.com',
        'password': 'secret',
      });
    });

    test('logout tolerates a failing server', () async {
      backend.alwaysFailToConnect();

      // The API itself still throws; it is the session layer that swallows it.
      // Asserted here so the contract between the two stays explicit.
      await expectLater(
        AuthApi(backend.client).logout(),
        throwsA(isA<NetworkException>()),
      );
    });

    test('board sends archived as a string, matching the query schema', () async {
      backend.alwaysRespond(boardJson());

      await BoardApi(backend.client).fetchBoard();

      expect(backend.lastRequest.queryParameters, <String, dynamic>{
        'archived': 'false',
      });
    });

    test('board parses the response into models', () async {
      backend.alwaysRespond(boardJson());

      final board = await BoardApi(backend.client).fetchBoard(archived: true);

      expect(board.first.currentTask?.title, 'Каркас Flutter');
      expect(backend.lastRequest.queryParameters['archived'], 'true');
    });
  });

  group('content-type', () {
    test('a request with a body says it is JSON', () async {
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      await backend.client.post<Map<String, dynamic>>(
        '/projects',
        body: <String, dynamic>{'name': 'x'},
      );

      expect(
        backend.lastRequest.headers[Headers.contentTypeHeader],
        contains('application/json'),
      );
    });

    test('a request with no body does not', () async {
      // Regression guard for a bug that only a real server can show you.
      // `BaseOptions.contentType` is JSON, and dio applies it to every request
      // -- so a DELETE went out as `content-type: application/json` with an
      // empty body, and Fastify's JSON parser answered
      // "400 Body cannot be empty when content-type is set to
      // 'application/json'". Every delete in the app failed; no fake transport
      // noticed, because a fake does not read the header.
      backend.alwaysRespond(null, statusCode: 204);

      await backend.client.delete<dynamic>('/tasks/tsk_1');

      expect(
        backend.lastRequest.headers.containsKey(Headers.contentTypeHeader),
        isFalse,
      );
    });

    test('a bodiless POST does not either', () async {
      // The same shape, for `POST /projects/:id/archive` (F4) and anything else
      // that is a command rather than a payload.
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      await backend.client.post<Map<String, dynamic>>(
        '/projects/prj_1/archive',
      );

      expect(
        backend.lastRequest.headers.containsKey(Headers.contentTypeHeader),
        isFalse,
      );
    });
  });

  test('timeouts are configured, so a dead server cannot hang forever', () {
    final options = backend.client.dio.options;

    expect(options.connectTimeout, isNotNull);
    expect(options.receiveTimeout, isNotNull);
  });

  test('non-2xx never resolves successfully', () async {
    // Guards the validateStatus setting: if it ever widened, error bodies would
    // be handed to parsers as if they were data.
    backend.alwaysRespond(<String, dynamic>{'ok': false}, statusCode: 302);

    await expectLater(
      backend.client.get<Map<String, dynamic>>('/board'),
      throwsA(isA<ApiException>()),
    );
  });

  test('a DioException is never allowed to escape to callers', () async {
    backend.alwaysFailToConnect();

    try {
      await backend.client.get<Map<String, dynamic>>('/board');
      fail('expected a throw');
    } catch (error) {
      expect(error, isNot(isA<DioException>()));
      expect(error, isA<ApiException>());
    }
  });
}
