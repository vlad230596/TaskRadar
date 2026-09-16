import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/app.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/home_screen.dart';
import 'package:taskradar/screens/login_screen.dart';
import 'package:taskradar/screens/splash_screen.dart';

import 'support/fake_backend.dart';
import 'support/fake_token_storage.dart';
import 'support/fixtures.dart';

/// End-to-end-ish tests of the one navigation rule the app has: the root widget
/// shows the splash, the login screen or the board depending on session state,
/// and nothing else navigates.
void main() {
  late FakeBackend backend;
  late FakeTokenStorage storage;

  setUp(() {
    backend = FakeBackend();
    storage = FakeTokenStorage();
  });

  Future<void> pumpApp(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          tokenStorageProvider.overrideWithValue(storage),
        ],
        child: const TaskRadarApp(),
      ),
    );
  }

  /// Pumps a few frames without `pumpAndSettle`, which would hang on the
  /// splash screen's indefinitely animating progress indicator.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('shows the splash while the session is being resolved', (tester) async {
    storage.token = 'stored.jwt';

    // Hold the probe open so the loading state is observable.
    final probe = Completer<ResponseBody>();
    backend.responder = (_) => probe.future;

    await pumpApp(tester);
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing, reason: 'no login flash on start');

    // Release it before the test ends: dio arms a receive-timeout timer per
    // request, and flutter_test fails a test that leaves a timer pending.
    probe.complete(jsonResponse(<String, dynamic>{'ok': true}));
    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('no token -> login screen', (tester) async {
    await pumpApp(tester);
    await settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('valid token -> the signed-in screen', (tester) async {
    storage.token = 'stored.jwt';
    backend.alwaysRespond(<String, dynamic>{'ok': true});

    await pumpApp(tester);
    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Сессия жива'), findsOneWidget);
  });

  testWidgets('expired token -> login screen', (tester) async {
    storage.token = 'expired.jwt';
    backend.alwaysRespond(unauthorizedJson(), statusCode: 401);

    await pumpApp(tester);
    await settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(storage.token, isNull);
  });

  testWidgets('a wrong password is shown inline and keeps the user on the form', (
    tester,
  ) async {
    backend.alwaysRespond(
      unauthorizedJson(message: 'Invalid email or password'),
      statusCode: 401,
    );

    await pumpApp(tester);
    await settle(tester);

    await tester.enterText(find.byType(TextFormField).first, 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'wrong');
    await tester.tap(find.text('Войти'));
    await settle(tester);

    expect(find.text('Неверный email или пароль'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('an unreachable server says so, rather than blaming the password', (
    tester,
  ) async {
    backend.alwaysFailToConnect();

    await pumpApp(tester);
    await settle(tester);

    await tester.enterText(find.byType(TextFormField).first, 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.text('Войти'));
    await settle(tester);

    expect(
      find.text('Не удалось подключиться к серверу. Попробуйте ещё раз.'),
      findsOneWidget,
    );
  });

  testWidgets('empty fields are rejected without a request', (tester) async {
    await pumpApp(tester);
    await settle(tester);

    await tester.tap(find.text('Войти'));
    await settle(tester);

    expect(find.text('Введите email'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('a successful login lands on the signed-in screen', (tester) async {
    backend.responder = (RequestOptions options) => switch (options.path) {
      '/auth/login' => jsonResponse(loginOkJson()),
      _ => throw StateError('unexpected ${options.path}'),
    };

    await pumpApp(tester);
    await settle(tester);

    await tester.enterText(find.byType(TextFormField).first, 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.text('Войти'));
    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(storage.token, 'jwt.token.value');
  });

  testWidgets('logging out returns to the login screen and clears the token', (
    tester,
  ) async {
    storage.token = 'stored.jwt';
    backend.responder = (RequestOptions options) => switch (options.path) {
      '/auth/me' => jsonResponse(<String, dynamic>{'ok': true}),
      '/auth/logout' => jsonResponse(<String, dynamic>{'ok': true}),
      _ => throw StateError('unexpected ${options.path}'),
    };

    await pumpApp(tester);
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Выйти'));
    await settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(storage.token, isNull);
  });
}
