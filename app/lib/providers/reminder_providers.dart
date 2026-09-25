import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/reminder_schedule.dart';
import '../notifications/local_notification_gateway.dart';
import '../notifications/notification_gateway.dart';
import '../notifications/notification_time_zone.dart';
import '../notifications/reminder_scheduler.dart';
import 'dependencies.dart';

part 'reminder_providers.g.dart';

/// Riverpod wiring for the reminder machinery.
///
/// The shape to notice: [reminderSync] *watches* [reminderTargets] and
/// [reminderSettings]. Nobody calls "reschedule" after changing either of them
/// -- changing them **is** the reschedule. That is the property F4 needs: the
/// board provider will replace the targets after every `GET /board` and the
/// queue follows, with no second place that has to remember to fire.
///
/// Everything here is `keepAlive: true` for the same reason as
/// `dependencies.dart`: these own platform resources and a background sync must
/// not depend on some screen still being on-stage.

@Riverpod(keepAlive: true)
NotificationGateway notificationGateway(Ref ref) => LocalNotificationGateway();

/// The device's timezone, resolved once. See [NotificationTimeZone].
@Riverpod(keepAlive: true)
Future<NotificationTimeZone> notificationTimeZone(Ref ref) =>
    NotificationTimeZone.resolve();

/// The same zone, as the IANA name the server's dictation parser takes (F14).
/// A provider of its own so the dictation screen can be tested without the
/// timezone platform channel.
@Riverpod(keepAlive: true)
Future<String> deviceTimeZoneName(Ref ref) async =>
    (await ref.watch(notificationTimeZoneProvider.future)).ianaName;

/// The hour reminders fire at, persisted (F4).
///
/// ## Why this became asynchronous
///
/// F1 kept it in memory with a default and said the only F4 change would be
/// where `build()` reads from. It is one step bigger than that, and the step is
/// worth taking: reading from disk is a future, so the choice is between
///
/// - publishing the default immediately and overwriting it when the store
///   answers -- which arms the whole queue at 09:00, then cancels and re-arms it
///   at the saved hour a few milliseconds later, on every single cold start; or
/// - making the settle part of the value, so [ReminderSync] simply waits.
///
/// The second is both cheaper and honest, and it costs nothing downstream:
/// [reminderSync] is already async (the plugin and the timezone are), so one
/// more awaited input changes no consumer's shape. The property F1 built the
/// graph around is untouched -- changing this **is** the reschedule, and nothing
/// calls the scheduler.
///
/// A store that cannot be read is not an error state: [SettingsStore] answers
/// null and the default applies. A settings screen that showed a red error
/// because a preference file was missing would be absurd.
@Riverpod(keepAlive: true)
class ReminderSettings extends _$ReminderSettings {
  @override
  Future<ReminderTime> build() async =>
      await ref.watch(settingsStoreProvider).readReminderTime() ??
      ReminderTime.defaultMorning;

  /// Applies a new hour and persists it.
  ///
  /// The state is set **before** the write and is not rolled back if the write
  /// throws. That is the opposite of the rule for server writes (see
  /// `project_providers.dart`), and deliberately so: there is no other party
  /// here to disagree with, the user's choice is a fact about this session
  /// whether or not the disk accepted it, and re-arming alarms at the hour they
  /// asked for is strictly better than re-arming them at the old one. The only
  /// thing lost by a failed write is the value surviving a restart, which is
  /// what the thrown error is for -- the caller reports it.
  Future<void> setTime(ReminderTime time) async {
    state = AsyncData(time);
    await ref.read(settingsStoreProvider).writeReminderTime(time);
  }
}

/// The set of reminders that *should* be armed right now.
///
/// The seam between F1 and the rest of the plan. F1's bench screen writes
/// synthetic rows here; F2/F4 will write `remindersFromBoard(board)` after each
/// refresh. Nothing downstream can tell the difference.
@Riverpod(keepAlive: true)
class ReminderTargets extends _$ReminderTargets {
  @override
  List<TaskReminder> build() => const <TaskReminder>[];

  void replaceWith(Iterable<TaskReminder> reminders) {
    state = List<TaskReminder>.unmodifiable(reminders);
  }

  void clear() => state = const <TaskReminder>[];
}

/// The scheduler, once the plugin is initialised and the timezone is known.
@Riverpod(keepAlive: true)
Future<ReminderScheduler> reminderScheduler(Ref ref) async {
  final gateway = ref.watch(notificationGatewayProvider);
  await gateway.initialize();
  final zone = await ref.watch(notificationTimeZoneProvider.future);

  return ReminderScheduler(gateway: gateway, location: zone.location);
}

/// Runs a resync whenever the targets or the configured hour change, and holds
/// the report of the last one.
@Riverpod(keepAlive: true)
class ReminderSync extends _$ReminderSync {
  @override
  Future<ReminderSyncReport> build() async {
    final scheduler = await ref.watch(reminderSchedulerProvider.future);

    return scheduler.sync(
      reminders: ref.watch(reminderTargetsProvider),
      at: await ref.watch(reminderSettingsProvider.future),
    );
  }

  /// Re-runs the resync against unchanged inputs.
  ///
  /// This is the one the foreground listener and (from F4) the background task
  /// call: the target set may not have changed, but the *OS queue* may have --
  /// a reboot, a force-stop, or an OEM battery sweep can empty it without the
  /// app hearing about it.
  Future<void> resync() async {
    // `invalidateSelf` + awaiting `future` rather than assigning a loading
    // state by hand: the previous report stays on screen until the new one is
    // ready, so the bench does not flash empty on every resume.
    ref.invalidateSelf();
    await future;
  }
}

/// What the OS has queued, read fresh.
///
/// Separate from [reminderSync] because the bench needs to re-read it without
/// triggering a resync -- "is it still there an hour later?" is a different
/// question from "arm it again".
@Riverpod(keepAlive: true)
Future<List<PendingNotification>> pendingNotifications(Ref ref) async {
  // Re-read after every resync. Without this the queue shown on screen is
  // whatever it was when the screen was first built, which is exactly the
  // stale-diagnostic trap this section exists to avoid -- a tester would be
  // reading a cached "empty" while the OS held three alarms. Invalidating this
  // provider on its own (the "перечитать очередь" button) still re-reads
  // without triggering a resync, which is the other question worth asking.
  await ref.watch(reminderSyncProvider.future);

  final scheduler = await ref.watch(reminderSchedulerProvider.future);
  return scheduler.pending();
}

/// Current permission state, without prompting.
@Riverpod(keepAlive: true)
class NotificationPermissions extends _$NotificationPermissions {
  @override
  Future<NotificationPermissionState> build() async {
    final gateway = ref.watch(notificationGatewayProvider);
    await gateway.initialize();
    return gateway.permissions();
  }

  /// Shows the system prompts. Must be called from a user gesture -- see
  /// [NotificationGateway.requestPermissions].
  Future<void> request() async {
    final gateway = ref.read(notificationGatewayProvider);
    await gateway.initialize();

    state = await AsyncValue.guard(gateway.requestPermissions);

    // A newly granted exact-alarm permission changes *how* alarms are armed, so
    // anything already in the queue was armed the wrong way. Re-arm it.
    if (state.value?.scheduleMode == NotificationScheduleMode.exact) {
      await ref.read(reminderSyncProvider.notifier).resync();
    }
  }
}
