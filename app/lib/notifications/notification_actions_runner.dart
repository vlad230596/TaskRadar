import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../api/api_client.dart';
import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../api/patch_field.dart';
import '../api/project_api.dart';
import '../domain/geofence_plan.dart';
import '../domain/notification_actions.dart';
import '../domain/reminder_schedule.dart';
import '../geofence/geofence_store.dart';
import '../models/board_project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../providers/outbox_providers.dart';
import '../storage/board_snapshot_store.dart';
import '../storage/capture_queue_store.dart' show PendingCapture;
import '../storage/outbox_store.dart';
import '../storage/token_storage.dart';
import 'local_notification_gateway.dart';
import 'notification_action_log.dart';
import 'notification_action_port.dart';
import 'notification_gateway.dart';
import 'notification_time_zone.dart';

/// «Выполнено» and «Завтра» pressed on a notification, when the press lands
/// outside the app.
///
/// ## The path of a press on Android
///
/// The buttons are `showsUserInterface: false`, so the press neither unlocks
/// the phone nor opens the app. `flutter_local_notifications` handles it in
/// a `BroadcastReceiver` that starts a Flutter engine of its own and calls
/// [onNotificationActionInBackground] there -- **always**, whether or not the
/// app is running. So the first question this isolate asks is whether there
/// is an app to hand the press to:
///
/// 1. **the app is alive** (signed in, its graph up): the press is forwarded
///    over a port the app registered ([notificationActionPortName]) and the
///    app does the write exactly as a tap on the row would --
///    `ProjectTasks.setStatus` / `setRemindAt`, so the list on screen, the
///    board, the working set and the alarms all follow, and with no network
///    the write goes to the outbox like any other. The app acks; that is
///    the end here.
/// 2. **no app answered** within [forwardTimeout] (not running, or signed
///    out): [HeadlessReminderActions] does the write itself, from what is on
///    disk -- the token from secure storage, the task from the board
///    snapshot -- straight to `PATCH /tasks/:id`. The server journals it like
///    any status change (it is the same request). With no network the very
///    same outbox entry the app would have made is appended to the outbox
///    file, and the app sends it on its next start, so «Выполнено» pressed in
///    a tunnel still lands.
///
/// The ack matters: a port name can outlive the isolate that registered it
/// (a killed process leaves no unregister behind), and a message sent to a
/// dead port is dropped without an error. Without a reply the press would
/// vanish exactly when the app was swiped away -- the main case.
@pragma('vm:entry-point')
void onNotificationActionInBackground(NotificationResponse response) {
  unawaited(_runInBackground(response));
}

Future<void> _runInBackground(NotificationResponse response) async {
  ensureBackgroundIsolateReady();

  final request = NotificationActionRequest.parse(
    actionId: response.actionId,
    payload: response.payload,
  );
  if (request == null) {
    debugPrint(
      'Notification action ignored: action=${response.actionId} '
      'payload=${response.payload}',
    );
    // Recorded for the bench, whose test notification has the real buttons
    // on a payload that is not a task: proof the press got this far.
    final actionId = response.actionId;
    if (actionId != null) {
      await FileNotificationActionLog().add(
        NotificationActionRecord(
          at: DateTime.now(),
          action: actionId,
          taskId: response.payload ?? '',
          outcome: 'не задача — ничего не делаем',
          where: 'фон',
        ),
      );
    }
    return;
  }

  try {
    if (await forwardNotificationAction(request)) return;
    await HeadlessReminderActions.standard().run(request, now: DateTime.now());
  } catch (error, stackTrace) {
    // Nobody to tell: there is no UI. `adb logcat` shows it.
    debugPrint('Notification action $request failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

/// What became of one press. [summary] is the line the bench shows.
@immutable
class NotificationActionOutcome {
  const NotificationActionOutcome._(this.kind, this.summary);

  const NotificationActionOutcome.sent()
    : this._(NotificationActionOutcomeKind.sent, 'отправлено');

  const NotificationActionOutcome.queued()
    : this._(
        NotificationActionOutcomeKind.queued,
        'нет сети — в очереди, уйдёт, когда появится связь',
      );

  const NotificationActionOutcome.local(String summary)
    : this._(NotificationActionOutcomeKind.sent, summary);

  const NotificationActionOutcome.ignored(String reason)
    : this._(NotificationActionOutcomeKind.ignored, reason);

  const NotificationActionOutcome.failed(String reason)
    : this._(NotificationActionOutcomeKind.failed, reason);

  final NotificationActionOutcomeKind kind;
  final String summary;

  @override
  String toString() => 'NotificationActionOutcome(${kind.name}: $summary)';
}

enum NotificationActionOutcomeKind { sent, queued, ignored, failed }

/// A task as the board snapshot has it, with its project's name.
typedef SnapshotTask = ({Task task, String projectName});

/// Finds [taskId] in [snapshot], or null.
SnapshotTask? findInSnapshot(BoardSnapshot? snapshot, String taskId) {
  for (final row in snapshot?.projects ?? const <BoardProject>[]) {
    for (final task in row.tasks) {
      if (task.id == taskId) return (task: task, projectName: row.project.name);
    }
  }
  return null;
}

/// The no-app half (see the file comment): a press done from disk and the
/// network alone, no Riverpod graph.
class HeadlessReminderActions {
  HeadlessReminderActions({
    required TokenStorage tokens,
    required ApiClient client,
    required BoardSnapshotStore snapshots,
    required OutboxStore outbox,
    required NotificationGateway gateway,
    required GeofenceStore geofences,
    required Future<tz.Location> Function() location,
    NotificationActionLog? log,
  }) : _tokens = tokens,
       _client = client,
       _snapshots = snapshots,
       _outbox = outbox,
       _gateway = gateway,
       _geofences = geofences,
       _location = location,
       _log = log;

  /// Everything real, as the background isolate needs it.
  factory HeadlessReminderActions.standard() => HeadlessReminderActions(
    tokens: TokenStorage(),
    client: createConfiguredApiClient(),
    snapshots: BoardSnapshotStore(),
    outbox: OutboxStore(),
    gateway: LocalNotificationGateway(),
    geofences: FileGeofenceStore(),
    location: () async => (await NotificationTimeZone.resolve()).location,
    log: FileNotificationActionLog(),
  );

  final TokenStorage _tokens;
  final ApiClient _client;
  final BoardSnapshotStore _snapshots;
  final OutboxStore _outbox;
  final NotificationGateway _gateway;
  final GeofenceStore _geofences;
  final Future<tz.Location> Function() _location;
  final NotificationActionLog? _log;

  Future<NotificationActionOutcome> run(
    NotificationActionRequest request, {
    required DateTime now,
  }) async {
    final outcome = await _run(request, now);
    debugPrint('Notification action $request (background): $outcome');
    await _log?.add(
      NotificationActionRecord(
        at: now,
        action: request.action.id,
        taskId: request.taskId,
        outcome: outcome.summary,
        where: 'фон',
      ),
    );
    return outcome;
  }

  Future<NotificationActionOutcome> _run(
    NotificationActionRequest request,
    DateTime now,
  ) async {
    final taskId = request.taskId;

    // A place has nothing on the server to change.
    if (request.action == ReminderAction.placeTomorrow) {
      await snoozePlace(
        _geofences,
        taskId,
        until: placeSnoozeUntil(now),
        now: now,
      );
      return const NotificationActionOutcome.local('место молчит до завтра');
    }

    final token = await _tokens.read();
    if (token == null) {
      return const NotificationActionOutcome.ignored('нет входа в приложение');
    }
    _client.setToken(token);
    final api = ProjectApi(_client);

    SnapshotTask? known;
    try {
      known = findInSnapshot(await _snapshots.read(), taskId);
    } catch (error) {
      debugPrint('Board snapshot unreadable: $error');
    }

    switch (request.action) {
      case ReminderAction.done:
        // The date stays, as in `ProjectTasks.setStatus`: a closed task
        // dated today is part of «Сегодня N из M», and raises no alarm.
        final outcome = await _write(
          known: known,
          taskId: taskId,
          body: <String, Object?>{'status': TaskStatus.done.name},
          checked: const <String>{'status'},
          send: () => api.updateTask(taskId, status: TaskStatus.done),
        );
        if (_landed(outcome)) {
          // The date alarm, if one is still queued (a place notification
          // answered before the day), and the place notification itself.
          await _quietly(() => _gateway.cancel(notificationIdForTask(taskId)));
          await _quietly(() => _gateway.cancel(geofenceNotificationId(taskId)));
          // The zone stays registered until the app next syncs; keep it
          // from ringing about a finished task until then.
          await snoozePlace(
            _geofences,
            taskId,
            until: now.add(placeQuietAfterDone),
            now: now,
          );
        }
        return outcome;

      case ReminderAction.tomorrow:
        if (known?.task.status == TaskStatus.done) {
          return const NotificationActionOutcome.ignored('задача уже сделана');
        }
        final target = postponeToTomorrow(
          remindTime: known?.task.remindTime,
          now: now,
        );
        final outcome = await _write(
          known: known,
          taskId: taskId,
          // The time of day is left as the server has it: the date moves.
          body: <String, Object?>{'remindAt': target.date},
          checked: const <String>{'remindAt'},
          send: () => api.updateTask(
            taskId,
            remindAt: PatchField<String>.to(target.date),
          ),
        );
        if (_landed(outcome)) {
          await _armTomorrow(taskId, known, target, now);
        }
        return outcome;

      case ReminderAction.placeTomorrow:
        throw StateError('handled above');
    }
  }

  static bool _landed(NotificationActionOutcome outcome) =>
      outcome.kind == NotificationActionOutcomeKind.sent ||
      outcome.kind == NotificationActionOutcomeKind.queued;

  /// The write, online first; with no network, the outbox file.
  Future<NotificationActionOutcome> _write({
    required SnapshotTask? known,
    required String taskId,
    required Map<String, Object?> body,
    required Set<String> checked,
    required Future<Object?> Function() send,
  }) async {
    try {
      await send();
      return const NotificationActionOutcome.sent();
    } on NetworkException {
      final entry = known == null
          // Not in the snapshot (a task made on the laptop since the phone
          // last saw the board): queued without `expected`, which the
          // server applies unconditionally.
          ? OutboxEntry(
              key: PendingCapture.newKey(),
              kind: OutboxKind.editTask,
              projectId: '',
              taskId: taskId,
              title: 'Задача из уведомления',
              body: body,
              createdAt: DateTime.now(),
            )
          : outboxEditEntry(base: known.task, body: body, checked: checked);
      try {
        await _outbox.write(<OutboxEntry>[...await _outbox.read(), entry]);
      } catch (error) {
        return NotificationActionOutcome.failed(
          'нет сети, и записать в очередь не удалось: $error',
        );
      }
      return const NotificationActionOutcome.queued();
    } on ApiException catch (error) {
      return NotificationActionOutcome.failed(describeApiError(error));
    }
  }

  /// Arms tomorrow's alarm for a postponed task. The app would do this on
  /// its next resync; done here because the app may not be opened before
  /// then, and a postponed reminder that never comes back is a dismissal.
  Future<void> _armTomorrow(
    String taskId,
    SnapshotTask? known,
    ({String date, String? time}) target,
    DateTime now,
  ) async {
    try {
      final location = await _location();
      // A date-only task does not push, postponed or not.
      final fireAt = reminderFireTime(
        remindAt: target.date,
        remindTime: target.time,
        location: location,
        now: tz.TZDateTime.from(now, location),
      );
      if (fireAt == null) return;

      await _gateway.initialize();
      final permissions = await _gateway.permissions();
      await _gateway.schedule(
        id: notificationIdForTask(taskId),
        title: known?.projectName ?? 'TaskRadar',
        body: known?.task.title ?? 'Напоминание о задаче',
        fireAt: fireAt,
        exact: permissions.scheduleMode == NotificationScheduleMode.exact,
        payload: reminderPayload(taskId),
        actions: dateReminderActions,
      );
    } catch (error) {
      debugPrint('Could not arm tomorrow\'s reminder for $taskId: $error');
    }
  }

  static Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } catch (error) {
      debugPrint('Notification cancel failed: $error');
    }
  }
}
