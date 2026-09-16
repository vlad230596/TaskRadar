import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/storage/settings_store.dart';

import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';

/// The reminder hour: storing it, applying it, and -- the part that matters --
/// the fact that changing it **is** the reschedule (F4).
///
/// F1 built the provider graph so that nothing ever calls "reschedule": the
/// scheduler watches the target set and the configured hour, so writing either
/// re-arms the queue. F4 is the first iteration where a *person* can change the
/// hour, which is the first time that property is load-bearing rather than
/// tidy, so it is pinned here.
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
    projectName: 'Дача',
  );

  group('reading the stored hour', () {
    test('an empty store means the 09:00 default', () async {
      final container = makeContainer();

      expect(
        await container.read(reminderSettingsProvider.future),
        ReminderTime.defaultMorning,
      );
      expect(settings.readCount, 1);
    });

    test('a saved hour wins over the default', () async {
      settings.time = const ReminderTime(7, 30);
      final container = makeContainer();

      expect(
        await container.read(reminderSettingsProvider.future),
        const ReminderTime(7, 30),
      );
    });

    test(
      'the first alarm is armed at the saved hour, not at 09:00 first',
      () async {
        // The reason `ReminderSettings.build` is async at all: publishing the
        // default and correcting it a moment later would arm every alarm at
        // 09:00 and immediately re-arm it, on every cold start.
        settings.time = const ReminderTime(7, 30);
        final container = makeContainer();

        container.read(reminderTargetsProvider.notifier).replaceWith(
          const <TaskReminder>[target],
        );
        await container.read(reminderSyncProvider.future);

        expect(gateway.scheduleCalls, hasLength(1));
        expect(gateway.scheduleCalls.single.fireAt.hour, 7);
        expect(gateway.scheduleCalls.single.fireAt.minute, 30);
      },
    );
  });

  group('changing the hour', () {
    test('persists it', () async {
      final container = makeContainer();
      await container.read(reminderSettingsProvider.future);

      await container
          .read(reminderSettingsProvider.notifier)
          .setTime(const ReminderTime(8, 15));

      expect(settings.writes, <ReminderTime>[const ReminderTime(8, 15)]);
      expect(settings.time, const ReminderTime(8, 15));
    });

    test('re-arms the whole queue at the new hour, with nobody calling the '
        'scheduler', () async {
      final container = makeContainer();
      container.read(reminderTargetsProvider.notifier).replaceWith(
        const <TaskReminder>[target],
      );
      await container.read(reminderSyncProvider.future);

      expect(gateway.scheduleCalls.single.fireAt.hour, 9);

      await container
          .read(reminderSettingsProvider.notifier)
          .setTime(const ReminderTime(6, 45));
      await container.read(reminderSyncProvider.future);

      expect(
        gateway.scheduleCalls,
        hasLength(2),
        reason: 'the setting changed, so the alarm was armed again',
      );
      expect(gateway.scheduleCalls.last.fireAt.hour, 6);
      expect(gateway.scheduleCalls.last.fireAt.minute, 45);
      // Same task, so the same stable id: a re-arm replaces rather than
      // duplicates. Two alarms for one task at two hours would be the failure.
      expect(gateway.queue, hasLength(1));
      expect(gateway.queue.keys.single, notificationIdForTask('tsk_1'));
    });

    test(
      'a failed write still applies the hour, and reports the failure',
      () async {
        final container = makeContainer();
        await container.read(reminderSettingsProvider.future);
        settings.writeFailure = StateError('disk full');

        await expectLater(
          container
              .read(reminderSettingsProvider.notifier)
              .setTime(const ReminderTime(5, 0)),
          throwsStateError,
        );

        // The user's choice is a fact about this session whether or not the disk
        // took it, and arming at the hour they asked for beats arming at the old
        // one. Only surviving a restart is lost -- which is what the throw (and
        // the message the screen shows) is for.
        expect(
          container.read(reminderSettingsProvider).value,
          const ReminderTime(5, 0),
        );
      },
    );
  });

  group('changing remindAt', () {
    test('re-arms at the new date without touching the hour', () async {
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
              projectName: 'Дача',
            ),
          ]);
      await container.read(reminderSyncProvider.future);

      expect(gateway.scheduleCalls.last.fireAt.day, 4);
      expect(gateway.scheduleCalls.last.fireAt.hour, 9);
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

  group('PreferencesSettingsStore, against the real package', () {
    // The fake above stands in for the store everywhere else; this is the one
    // place the actual encoding is exercised, because "two ints under these
    // keys" is a format that outlives the app's memory.
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('writes and reads back the same time', () async {
      final store = PreferencesSettingsStore();
      expect(await store.readReminderTime(), isNull);

      await store.writeReminderTime(const ReminderTime(7, 5));
      expect(await store.readReminderTime(), const ReminderTime(7, 5));
    });

    test('a half-written pair is treated as nothing saved', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferencesSettingsStore.hourKey: 7,
      });

      expect(await PreferencesSettingsStore().readReminderTime(), isNull);
    });

    test('an out-of-range value is discarded rather than armed', () async {
      // `ReminderTime`'s asserts are compiled out of a release build, so the
      // range check has to live in the store or a hand-edited preferences file
      // could arm alarms at hour 47.
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferencesSettingsStore.hourKey: 47,
        PreferencesSettingsStore.minuteKey: 0,
      });

      expect(await PreferencesSettingsStore().readReminderTime(), isNull);
    });

    test('a missing platform channel costs the default, not a crash', () async {
      // The `flutter test` VM with no mock values: `getAll` answers
      // MissingPluginException. That must read as "nothing saved".
      final store = PreferencesSettingsStore(
        preferences: () => throw MissingPluginException('no implementation'),
      );

      expect(await store.readReminderTime(), isNull);
    });
  });
}
