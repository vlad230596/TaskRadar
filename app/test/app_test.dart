import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/app.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/screens/login_screen.dart';
import 'package:taskradar/screens/splash_screen.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_token_storage.dart';
import 'support/fixtures.dart';

/// End-to-end-ish tests of the one navigation rule the app has: the root widget
/// shows the splash, the login screen or the board depending on session state,
/// and nothing else navigates.
void main() {
  late FakeBackend backend;
  late FakeTokenStorage storage;
  late FakeBoardSnapshotStore snapshots;

  setUp(() {
    backend = FakeBackend();
    storage = FakeTokenStorage();
    snapshots = FakeBoardSnapshotStore();
  });

  Future<void> pumpApp(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          tokenStorageProvider.overrideWithValue(storage),
          // The board is the signed-in screen now, and it reads a snapshot file
          // through `path_provider` -- a platform channel the test VM does not
          // have.
          boardSnapshotStoreProvider.overrideWithValue(snapshots),
          // Likewise: the board screen brings the reminder bridge up, which
          // initialises the notification plugin. The real gateway degrades to
          // "this platform cannot do reminders" in the test VM, but these tests
          // are about navigation and should not depend on that.
          notificationGatewayProvider.overrideWithValue(FakeNotificationGateway()),
          // Likewise a platform channel: the reminder hour is persisted from F4
          // on, and `reminderSync` waits for it before arming anything.
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        child: const TaskRadarApp(),
      ),
    );
  }

  /// Pumps a few frames without `pumpAndSettle`, which would hang on the
  /// splash screen's indefinitely animating progress indicator.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// Signs out through the board's overflow menu.
  ///
  /// F4 moved "Выйти" off the app bar and behind that menu -- five icons in a
  /// row on a phone is unreadable, and the one next to an accidental tap should
  /// not be the one that ends the session.
  Future<void> signOut(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await settle(tester);
  }

  /// A responder covering the endpoints a signed-in cold start hits.
  void respondToSignedInStartup() {
    backend.responder = (RequestOptions options) => switch (options.path) {
      '/auth/me' => jsonResponse(<String, dynamic>{'ok': true}),
      '/auth/login' => jsonResponse(loginOkJson()),
      '/auth/logout' => jsonResponse(<String, dynamic>{'ok': true}),
      '/board' => jsonResponse(boardJson()),
      _ => throw StateError('unexpected ${options.path}'),
    };
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
    // Both /auth/me and the board request that follows it are served from here.
    respondToSignedInStartup();
    probe.complete(jsonResponse(<String, dynamic>{'ok': true}));
    await settle(tester);

    expect(find.byType(ShellScreen), findsOneWidget);
  });

  testWidgets('no token -> login screen', (tester) async {
    await pumpApp(tester);
    await settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('valid token -> the board, drawn from the wire', (tester) async {
    storage.token = 'stored.jwt';
    respondToSignedInStartup();

    await pumpApp(tester);
    await settle(tester);

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(find.text('TaskRadar'), findsWidgets);
    expect(find.text('Каркас Flutter'), findsOneWidget, reason: 'current task');
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
    respondToSignedInStartup();

    await pumpApp(tester);
    await settle(tester);

    await tester.enterText(find.byType(TextFormField).first, 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.text('Войти'));
    await settle(tester);

    expect(find.byType(ShellScreen), findsOneWidget);
    expect(storage.token, 'jwt.token.value');
  });

  testWidgets('logging out returns to the login screen and clears the token', (
    tester,
  ) async {
    storage.token = 'stored.jwt';
    respondToSignedInStartup();

    await pumpApp(tester);
    await settle(tester);
    expect(find.byType(ShellScreen), findsOneWidget);

    await signOut(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(storage.token, isNull);
  });

  testWidgets('signing in again refetches the board rather than reusing it', (
    tester,
  ) async {
    // The board provider is keepAlive, so re-mounting the screen is not enough
    // to make it refetch. A session that ended and was re-established must not
    // put the pre-logout board back on screen labelled as live.
    storage.token = 'stored.jwt';
    var boardCalls = 0;
    backend.responder = (RequestOptions options) => switch (options.path) {
      '/auth/me' => jsonResponse(<String, dynamic>{'ok': true}),
      '/auth/logout' => jsonResponse(<String, dynamic>{'ok': true}),
      '/auth/login' => jsonResponse(loginOkJson()),
      '/board' => jsonResponse(<dynamic>[
        boardProjectJson(
          id: 'prj_1',
          name: ++boardCalls == 1 ? 'До выхода' : 'После входа',
        ),
      ]),
      _ => throw StateError('unexpected ${options.path}'),
    };

    await pumpApp(tester);
    await settle(tester);
    expect(find.text('До выхода'), findsOneWidget);

    await signOut(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.text('Войти'));
    await settle(tester);

    expect(find.text('После входа'), findsOneWidget);
    expect(find.text('До выхода'), findsNothing);
  });
}
