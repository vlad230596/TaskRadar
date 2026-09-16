import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/reminder_schedule.dart';
import '../notifications/local_notification_gateway.dart';
import '../notifications/notification_gateway.dart';
import '../notifications/notification_time_zone.dart';
import '../notifications/reminder_scheduler.dart';

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

/// The hour reminders fire at.
///
/// In memory only for F1. F4 adds the settings screen and persists it; when it
/// does, the only change here is where `build()` reads its initial value from --
/// every consumer already re-syncs on change.
@Riverpod(keepAlive: true)
class ReminderSettings extends _$ReminderSettings {
  @override
  ReminderTime build() => ReminderTime.defaultMorning;

  void setTime(ReminderTime time) => state = time;
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
      at: ref.watch(reminderSettingsProvider),
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
