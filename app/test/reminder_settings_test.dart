import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';

import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';

/// The reminder graph after `design/today-history-contract.md`: only a task
/// with a time pushes, and changing the targets **is** the reschedule. The
/// F4 reminder hour is gone -- a date alone no longer rings at 09:00.
void main() {
  // Needed before any platform channel is mocked, and by
  // `SharedPreferences.setMockInitialValues` in the last group.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNotificationGateway gateway;
  late FakeSettingsStore settings;

  setUp(() {
    gateway = FakeNotificationGateway();
    settings = FakeSettingsStore();

    // `flutter_timezone` is a platform channel; pinning it keeps the fire times
    // below independent of the machine's clock settings.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
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

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        notificationGatewayProvider.overrideWithValue(gateway),
        settingsStoreProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A reminder far enough out that it is armed at every hour of the day, so
  /// these tests do not depend on when the suite runs.
  const target = TaskReminder(
    taskId: 'tsk_1',
    taskTitle: 'Жду кабель',
    remindAt: '2030-06-01T00:00:00.000Z',
    remindTime: '15:00',
    projectName: 'Дача',
  );

  group('only a time pushes', () {
    test('a timed reminder is armed at its time', () async {
      final container = makeContainer();
      container.read(reminderTargetsProvider.notifier).replaceWith(
        const <TaskReminder>[target],
      );
      await container.read(reminderSyncProvider.future);
      final call = gateway.scheduleCalls.single;
      expect(call.fireAt.hour, 15);
      expect(call.fireAt.minute, 0);
    });

    test('a date with no time schedules nothing -- no morning push', () async {
      final container = makeContainer();
      container
          .read(reminderTargetsProvider.notifier)
          .replaceWith(const <TaskReminder>[
            TaskReminder(
              taskId: 'tsk_2',
              taskTitle: 'Позвонить',
              remindAt: '2030-06-01T00:00:00.000Z',
              projectName: 'Дом',
            ),
          ]);
      final report = await container.read(reminderSyncProvider.future);
      expect(gateway.scheduleCalls, isEmpty);
      expect(gateway.queue, isEmpty);
      expect(report.schedule.skipped.single.reason, SkipReason.noTime);
    });

    test('taking the time off a task cancels its alarm', () async {
      final container = makeContainer();
      container.read(reminderTargetsProvider.notifier).replaceWith(
        const <TaskReminder>[target],
      );
      await container.read(reminderSyncProvider.future);
      expect(gateway.queue, hasLength(1));

      container
          .read(reminderTargetsProvider.notifier)
          .replaceWith(const <TaskReminder>[
            TaskReminder(
              taskId: 'tsk_1',
              taskTitle: 'Жду кабель',
              remindAt: '2030-06-01T00:00:00.000Z',
              projectName: 'Дача',
            ),
          ]);
      await container.read(reminderSyncProvider.future);
      expect(gateway.queue, isEmpty);
    });
  });

  group('changing remindAt', () {
    test('re-arms at the new date, keeping its time', () async {
      final container = makeContainer();
      container.read(reminderTargetsProvider.notifier).replaceWith(
        const <TaskReminder>[target],
      );
      await container.read(reminderSyncProvider.future);
      expect(gateway.scheduleCalls.single.fireAt.day, 1);
      expect(gateway.scheduleCalls.single.fireAt.month, 6);

      container
          .read(reminderTargetsProvider.notifier)
          .replaceWith(const <TaskReminder>[
            TaskReminder(
              taskId: 'tsk_1',
              taskTitle: 'Жду кабель',
              remindAt: '2030-06-04T00:00:00.000Z',
              remindTime: '15:00',
              projectName: 'Дача',
            ),
          ]);
      await container.read(reminderSyncProvider.future);

      expect(gateway.scheduleCalls.last.fireAt.day, 4);
      expect(gateway.scheduleCalls.last.fireAt.hour, 15);
      expect(gateway.queue, hasLength(1));
    });

    test('clearing remindAt cancels the alarm', () async {
      final container = makeContainer();
      container.read(reminderTargetsProvider.notifier).replaceWith(
        const <TaskReminder>[target],
      );
      await container.read(reminderSyncProvider.future);
      expect(gateway.queue, hasLength(1));

      // What the UI's "убрать дату" produces: the task is still blocked, but it
      // no longer has a reminder, so `remindersFromBoard` stops listing it.
      container
          .read(reminderTargetsProvider.notifier)
          .replaceWith(const <TaskReminder>[]);
      await container.read(reminderSyncProvider.future);

      expect(gateway.queue, isEmpty);
      expect(gateway.cancelledIds, <int>[notificationIdForTask('tsk_1')]);
    });
  });
}
