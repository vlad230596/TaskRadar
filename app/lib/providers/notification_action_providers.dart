import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notification_actions.dart';
import '../geofence/geofence_store.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../notifications/notification_action_log.dart';
import '../notifications/notification_action_port.dart';
import '../notifications/notification_actions_runner.dart';
import 'archive_providers.dart';
import 'board_providers.dart';
import 'focus_providers.dart';
import 'geofence_providers.dart';
import 'project_providers.dart';
import 'reminder_providers.dart';

/// «Выполнено» and «Завтра» pressed on a notification while the app is alive
/// -- the half of `notification_actions_runner.dart` that has a provider
/// graph to work with.
///
/// ## Why the running app does the write itself
///
/// A press handled by the background isolate alone would reach the server,
/// and the app on screen would never hear of it: the row would stay open
/// until the next refresh, the alarm would stay armed, and an offline press
/// would land in the outbox file behind the back of the [Outbox] that holds
/// the same file in memory. Routing it through [ProjectTasks] instead makes a
/// button press *the same thing* as a tap on the row's circle: the optimistic
/// row, the reconcile, the board, the working set, the outbox when there is
/// no network, and the alarms following the board.

/// Where presses handled in this isolate are recorded for the bench.
final notificationActionLogProvider = Provider<NotificationActionLog>(
  (ref) => FileNotificationActionLog(),
);

/// Carries out one press; its state is the outcome of the last one.
final notificationActionsProvider =
    NotifierProvider<NotificationActions, NotificationActionOutcome?>(
      NotificationActions.new,
    );

class NotificationActions extends Notifier<NotificationActionOutcome?> {
  @override
  NotificationActionOutcome? build() => null;

  /// Carries out [request]. Never throws: the press came from a notification
  /// and there is no button handler up the stack to report to -- the outcome
  /// is the state, and goes to the log.
  Future<NotificationActionOutcome> handle(
    NotificationActionRequest request, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    NotificationActionOutcome outcome;
    try {
      outcome = await _handle(request, at);
    } catch (error, stackTrace) {
      debugPrint('Notification action $request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      outcome = NotificationActionOutcome.failed('$error');
    }
    debugPrint('Notification action $request (app): $outcome');
    if (ref.mounted) state = outcome;
    await ref
        .read(notificationActionLogProvider)
        .add(
          NotificationActionRecord(
            at: at,
            action: request.action.id,
            taskId: request.taskId,
            outcome: outcome.summary,
            where: 'приложение',
          ),
        );
    return outcome;
  }

  Future<NotificationActionOutcome> _handle(
    NotificationActionRequest request,
    DateTime now,
  ) async {
    final taskId = request.taskId;
    final geofences = ref.read(geofenceStoreProvider);

    if (request.action == ReminderAction.placeTomorrow) {
      await snoozePlace(
        geofences,
        taskId,
        until: placeSnoozeUntil(now),
        now: now,
      );
      return const NotificationActionOutcome.local('место молчит до завтра');
    }

    final task = await _locate(taskId);
    if (task == null) {
      return const NotificationActionOutcome.ignored('задача не найдена');
    }

    // [ProjectTasks] is per screen and disposed when nobody watches it; held
    // open for the write, so its reconcile reaches the board instead of
    // landing in a provider that is already gone.
    final tasks = projectTasksProvider(task.projectId);
    final hold = ref.listen(tasks, (_, _) {});
    try {
      final notifier = ref.read(tasks.notifier);
      switch (request.action) {
        case ReminderAction.done:
          if (task.status == TaskStatus.done) {
            return const NotificationActionOutcome.ignored(
              'задача уже сделана',
            );
          }
          final wasInFocus = ref.read(focusedTaskIdsProvider).contains(taskId);
          final written = await notifier.setStatus(task, TaskStatus.done);
          // Closing a task takes it out of the working set on the server;
          // the set on screen learns it by re-reading (see `setTaskStatus`).
          if (wasInFocus) {
            unawaited(ref.read(focusSetProvider.notifier).refresh());
          }
          // A finished task's zone is dropped by the next geofence sync; with
          // no network that waits for the outbox, so keep it quiet meanwhile.
          await snoozePlace(
            geofences,
            taskId,
            until: now.add(placeQuietAfterDone),
            now: now,
          );
          return _outcomeOf(written);

        case ReminderAction.tomorrow:
          if (task.status == TaskStatus.done) {
            return const NotificationActionOutcome.ignored(
              'задача уже сделана',
            );
          }
          final target = postponeToTomorrow(
            remindTime: task.remindTime,
            now: now,
          );
          // The alarm follows by itself: the board takes the new date (or
          // the outbox overlay does, offline) and `reminderSync` re-arms.
          final written = await notifier.setRemindAt(
            task,
            target.date,
            time: target.time,
          );
          return _outcomeOf(written);

        case ReminderAction.placeTomorrow:
          throw StateError('handled above');
      }
    } finally {
      hold.close();
    }
  }

  static NotificationActionOutcome _outcomeOf(WriteOutcome written) =>
      written == WriteOutcome.queued
      ? const NotificationActionOutcome.queued()
      : const NotificationActionOutcome.sent();

  /// The task as the app knows it: the project list if it is loaded (the
  /// freshest copy), else the board -- cache included, which is what makes a
  /// press with no network work -- else one board refresh.
  Future<Task?> _locate(String taskId) async {
    Task? inBoard() {
      final rows = boardRowsOrNull(ref.read(boardViewProvider));
      final projectId = rows == null ? null : projectIdForTask(rows, taskId);
      if (projectId == null) return null;

      final loaded = ref.exists(projectTasksProvider(projectId))
          ? ref.read(projectTasksProvider(projectId)).value
          : null;
      for (final row in loaded ?? const <Task>[]) {
        if (row.id == taskId) return row;
      }
      for (final project in rows!) {
        for (final row in project.tasks) {
          if (row.id == taskId) return row;
        }
      }
      return null;
    }

    final known = inBoard();
    if (known != null) return known;
    await ref.read(boardProvider.notifier).refresh();
    if (!ref.mounted) return null;
    return inBoard();
  }
}

/// Connects both ways a press reaches this isolate to [NotificationActions]:
/// the gateway's own callback (Windows, and any press the plugin delivers to
/// the app) and the port the background isolate forwards Android presses
/// over.
///
/// Watched by `NotificationLinkScope`, so it exists exactly while the user is
/// signed in -- the port is withdrawn on sign-out, and a press then is done by
/// the background isolate with the stored token instead.
final notificationActionBridgeProvider = Provider.autoDispose<void>((ref) {
  final actions = ref.read(notificationActionsProvider.notifier);
  void onRequest(NotificationActionRequest request) =>
      unawaited(actions.handle(request));

  final gateway = ref.read(notificationGatewayProvider);
  gateway.setActionHandler(onRequest);
  ref.onDispose(
    () => gateway.setActionHandler(
      (request) =>
          debugPrint('Notification action $request while signed out: ignored'),
    ),
  );

  if (kIsWeb) return;
  try {
    ref.onDispose(listenForNotificationActions(onRequest));
  } catch (error) {
    // No isolate name server (a test VM without the engine, say): presses
    // are then done by the background isolate alone, which still works.
    debugPrint('Notification action port unavailable: $error');
  }
});
