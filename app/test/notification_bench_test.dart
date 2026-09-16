import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/notifications/notification_gateway.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/notification_bench_screen.dart';

import 'support/fake_notification_gateway.dart';

/// The bench screen is the actual deliverable of F1 -- if its buttons are wired
/// to nothing, the evening on the phone is wasted and nobody finds out until
/// they are standing there with the phone.
///
/// These are smoke tests of the wiring, not of the UI's looks.
void main() {
  late FakeNotificationGateway gateway;

  setUp(() {
    gateway = FakeNotificationGateway();

    // `flutter_timezone` is a platform channel and would otherwise throw
    // MissingPluginException, sending NotificationTimeZone down its
    // fixed-offset fallback path and making these tests depend on the machine's
    // clock settings. Pinning it keeps them the same everywhere.
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (MethodCall call) async =>
              call.method == 'getLocalTimezone' ? 'Europe/Moscow' : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  Future<void> pumpBench(WidgetTester tester) async {
    // The bench is a long scrolling page and the default 800x600 test viewport
    // puts most of it off-screen, where `tap()` cannot reach. Give the test a
    // tall window instead of scrolling before every interaction.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [notificationGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: NotificationBenchScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the permission state it was given', (tester) async {
    await pumpBench(tester);

    expect(find.text('выдано'), findsNWidgets(2));
  });

  testWidgets('warns loudly when notifications are switched off', (tester) async {
    gateway.permissionState = const NotificationPermissionState(
      notificationsEnabled: false,
      canScheduleExactAlarms: false,
    );

    await pumpBench(tester);

    expect(find.text('НЕ выдано'), findsNWidgets(2));
    expect(find.textContaining('могут опоздать на часы'), findsOneWidget);
  });

  testWidgets('the synthetic set reaches the OS queue', (tester) async {
    await pumpBench(tester);

    await tester.tap(find.text('Заполнить (5 задач)'));
    await tester.pumpAndSettle();

    // Two of the five rows are deliberately unschedulable (a past date and a
    // malformed one), and "today" depends on the wall clock, so assert on the
    // rows that are unambiguous rather than on a count.
    expect(gateway.queue.keys, contains(notificationIdForTask('synthetic-tomorrow')));
    expect(gateway.queue.keys, contains(notificationIdForTask('synthetic-in-3-days')));
    expect(
      gateway.queue.keys,
      isNot(contains(notificationIdForTask('synthetic-yesterday'))),
    );
    expect(find.textContaining('битая дата'), findsOneWidget);
  });

  testWidgets('removing a task removes its alarm', (tester) async {
    await pumpBench(tester);

    await tester.tap(find.text('Заполнить (5 задач)'));
    await tester.pumpAndSettle();
    final before = gateway.queue.length;

    // The synthetic set starts with rows that may never have been armed at all:
    // the past-dated one never is, and the *today* one only is while the
    // configured hour has not gone by yet -- so before 09:00 local two drops
    // remove an alarm and after 09:00 they remove nothing. Dropping three times
    // reaches "tomorrow", which is armed at every hour of the day, and makes
    // this assertion independent of when the suite happens to run.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Убрать первую'));
      await tester.pumpAndSettle();
    }

    expect(gateway.queue.length, lessThan(before));
  });

  testWidgets('"cancel everything" empties the queue', (tester) async {
    await pumpBench(tester);

    await tester.tap(find.text('Заполнить (5 задач)'));
    await tester.pumpAndSettle();
    expect(gateway.queue, isNotEmpty);

    await tester.tap(find.text('Отменить все уведомления'));
    await tester.pumpAndSettle();

    expect(gateway.queue, isEmpty);
    expect(gateway.cancelAllCount, 1);
  });

  testWidgets('the pending queue is shown, not inferred', (tester) async {
    await pumpBench(tester);
    expect(find.text('Очередь пуста.'), findsOneWidget);

    await tester.tap(find.text('Заполнить (5 задач)'));
    await tester.pumpAndSettle();

    // The queue section reads the gateway back rather than echoing what the app
    // believes it scheduled -- that difference is the whole diagnostic value.
    expect(find.text('Очередь пуста.'), findsNothing);
    expect(find.textContaining('task:synthetic-tomorrow'), findsOneWidget);
  });
}
