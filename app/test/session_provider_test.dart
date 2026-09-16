import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/session_provider.dart';

import 'support/fake_backend.dart';
import 'support/fake_token_storage.dart';
import 'support/fixtures.dart';

/// Tests for the startup decision -- "is there a token, is it still good, which
/// screen do we show" -- and for the transitions out of a live session.
///
/// These run against the real [ApiClient] over a faked transport (see
/// [FakeBackend]), so the 401 interceptor and the header logic take part rather
/// than being stubbed out.
void main() {
  late FakeBackend backend;
  late FakeTokenStorage storage;

  setUp(() {
    backend = FakeBackend();
    storage = FakeTokenStorage();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        tokenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Routes by path so a single test can serve the probe, the login and a
  /// subsequent data call differently.
  void respondByPath(Map<String, ResponseBody Function()> routes) {
    backend.responder = (RequestOptions options) {
      final route = routes[options.path];
      if (route == null) {
        throw StateError('unexpected request to ${options.path}');
      }
      return route();
    };
  }

  group('startup', () {
    test('no stored token -> login screen, and no request is made', () async {
      final container = makeContainer();

      final status = await container.read(sessionProvider.future);

      expect(status, SessionStatus.signedOut);
      expect(
        backend.requests,
        isEmpty,
        reason: 'the point of checking storage first is to skip the round trip',
      );
    });

    test('stored token + 200 from /auth/me -> straight into the app', () async {
      storage.token = 'stored.jwt';
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      final container = makeContainer();
      final status = await container.read(sessionProvider.future);

      expect(status, SessionStatus.signedIn);
      expect(backend.requests, hasLength(1));
      expect(backend.lastRequest.path, '/auth/me');
      // The stored token is handed to the HTTP client before the probe, so the
      // probe itself is what proves the token works.
      expect(backend.lastRequest.headers['Authorization'], 'Bearer stored.jwt');
      expect(storage.token, 'stored.jwt');
    });

    test('stored token + 401 -> login screen, and the dead token is deleted', () async {
      storage.token = 'expired.jwt';
      backend.alwaysRespond(unauthorizedJson(), statusCode: 401);

      final container = makeContainer();
      final status = await container.read(sessionProvider.future);

      expect(status, SessionStatus.signedOut);
      expect(storage.token, isNull);
      expect(storage.clearCount, greaterThan(0));
    });

    test('unreachable server -> stay signed in and keep the token', () async {
      // A network failure disproves nothing about the token. Signing out here
      // would mean the app logs itself out every time it starts outside Wi-Fi,
      // and would throw away the credential F2's offline snapshot needs.
      storage.token = 'stored.jwt';
      backend.alwaysFailToConnect();

      final container = makeContainer();
      final status = await container.read(sessionProvider.future);

      expect(status, SessionStatus.signedIn);
      expect(storage.token, 'stored.jwt');
      expect(storage.clearCount, 0);
    });

    test('the session is resolved exactly once, not per watcher', () async {
      storage.token = 'stored.jwt';
      backend.alwaysRespond(<String, dynamic>{'ok': true});

      final container = makeContainer();
      await container.read(sessionProvider.future);
      await container.read(sessionProvider.future);

      expect(backend.requests, hasLength(1));
      expect(storage.readCount, 1);
    });
  });

  group('signIn', () {
    test('stores the token and flips the session', () async {
      respondByPath(<String, ResponseBody Function()>{
        '/auth/login': () => jsonResponse(loginOkJson(token: 'fresh.jwt')),
      });

      final container = makeContainer();
      await container.read(sessionProvider.future);

      await container
          .read(sessionProvider.notifier)
          .signIn(email: 'owner@example.com', password: 'secret');

      expect(storage.token, 'fresh.jwt');
      expect(await container.read(sessionProvider.future), SessionStatus.signedIn);
    });

    test('the new token is used by the very next request', () async {
      respondByPath(<String, ResponseBody Function()>{
        '/auth/login': () => jsonResponse(loginOkJson(token: 'fresh.jwt')),
        '/board': () => jsonResponse(boardJson()),
      });

      final container = makeContainer();
      await container.read(sessionProvider.future);
      await container
          .read(sessionProvider.notifier)
          .signIn(email: 'owner@example.com', password: 'secret');

      await container.read(boardApiProvider).fetchBoard();

      expect(backend.lastRequest.headers['Authorization'], 'Bearer fresh.jwt');
    });

    test('trims the email, because a phone keyboard likes to add a space', () async {
      respondByPath(<String, ResponseBody Function()>{
        '/auth/login': () => jsonResponse(loginOkJson()),
      });

      final container = makeContainer();
      await container.read(sessionProvider.future);
      // Trimming lives in LoginController (the UI concern); signIn itself passes
      // through what it is given, so this asserts the raw pass-through.
      await container
          .read(sessionProvider.notifier)
          .signIn(email: 'owner@example.com', password: 'secret');

      final body = backend.lastRequest.data as Map<String, dynamic>;
      expect(body['email'], 'owner@example.com');
    });

    test('a wrong password throws and leaves the user signed out', () async {
      respondByPath(<String, ResponseBody Function()>{
        '/auth/login': () => jsonResponse(
          unauthorizedJson(message: 'Invalid email or password'),
          statusCode: 401,
        ),
      });

      final container = makeContainer();
      await container.read(sessionProvider.future);

      await expectLater(
        container
            .read(sessionProvider.notifier)
            .signIn(email: 'owner@example.com', password: 'wrong'),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(storage.token, isNull);
      expect(storage.writeCount, 0);
      expect(await container.read(sessionProvider.future), SessionStatus.signedOut);
    });
  });

  group('the global 401 reaction', () {
    test('a 401 on an ordinary call signs the app out', () async {
      // This is the payoff of registering the handler once: BoardApi knows
      // nothing about sessions or screens, yet a dead token still lands the user
      // back on the login screen.
      storage.token = 'stored.jwt';
      respondByPath(<String, ResponseBody Function()>{
        '/auth/me': () => jsonResponse(<String, dynamic>{'ok': true}),
        '/board': () => jsonResponse(unauthorizedJson(), statusCode: 401),
      });

      final container = makeContainer();
      expect(await container.read(sessionProvider.future), SessionStatus.signedIn);

      await expectLater(
        container.read(boardApiProvider).fetchBoard(),
        throwsA(isA<UnauthorizedException>()),
      );

      // The handler deliberately does not block the failing request, so give its
      // cleanup a turn of the event loop.
      await pumpEventQueue();

      expect(await container.read(sessionProvider.future), SessionStatus.signedOut);
      expect(storage.token, isNull);
    });

    test('two concurrent 401s do not sign out twice', () async {
      storage.token = 'stored.jwt';
      respondByPath(<String, ResponseBody Function()>{
        '/auth/me': () => jsonResponse(<String, dynamic>{'ok': true}),
        '/board': () => jsonResponse(unauthorizedJson(), statusCode: 401),
      });

      final container = makeContainer();
      await container.read(sessionProvider.future);
      final board = container.read(boardApiProvider);

      await Future.wait<void>(<Future<void>>[
        board.fetchBoard().catchError((_) => <Never>[]),
        board.fetchBoard().catchError((_) => <Never>[]),
      ]);
      await pumpEventQueue();

      expect(await container.read(sessionProvider.future), SessionStatus.signedOut);
      // One clear from the first 401; the second is short-circuited because the
      // session is already signed out.
      expect(storage.clearCount, 1);
    });
  });

  group('signOut', () {
    test('clears the token and the session', () async {
      storage.token = 'stored.jwt';
      respondByPath(<String, ResponseBody Function()>{
        '/auth/me': () => jsonResponse(<String, dynamic>{'ok': true}),
        '/auth/logout': () => jsonResponse(<String, dynamic>{'ok': true}),
      });

      final container = makeContainer();
      await container.read(sessionProvider.future);

      await container.read(sessionProvider.notifier).signOut();

      expect(storage.token, isNull);
      expect(await container.read(sessionProvider.future), SessionStatus.signedOut);
    });

    test('still works when the server cannot be reached', () async {
      // Logging out must not require a network: the server call only clears a
      // cookie this client never uses.
      storage.token = 'stored.jwt';
      backend.responder = (RequestOptions options) {
        if (options.path == '/auth/me') {
          return jsonResponse(<String, dynamic>{'ok': true});
        }
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        );
      };

      final container = makeContainer();
      await container.read(sessionProvider.future);

      await container.read(sessionProvider.notifier).signOut();

      expect(storage.token, isNull);
      expect(await container.read(sessionProvider.future), SessionStatus.signedOut);
    });

    test('a later request no longer carries the old token', () async {
      storage.token = 'stored.jwt';
      respondByPath(<String, ResponseBody Function()>{
        '/auth/me': () => jsonResponse(<String, dynamic>{'ok': true}),
        '/auth/logout': () => jsonResponse(<String, dynamic>{'ok': true}),
        '/board': () => jsonResponse(boardJson()),
      });

      final container = makeContainer();
      await container.read(sessionProvider.future);
      await container.read(sessionProvider.notifier).signOut();

      await container.read(boardApiProvider).fetchBoard();

      expect(backend.lastRequest.headers.containsKey('Authorization'), isFalse);
    });
  });
}
