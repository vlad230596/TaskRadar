import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/reminder_schedule.dart';
import 'archive_providers.dart';
import 'board_providers.dart';
import 'reminder_providers.dart';

part 'notification_link_providers.g.dart';

/// "The user tapped a reminder; open that task" -- the whole of it, minus the
/// widget that does the pushing (F4).
///
/// ## The two paths, and why only one of them is obvious
///
/// A notification tap reaches a Flutter app in two completely different ways:
///
/// - **the app was alive** (foreground, or in the background with the process
///   still around): `flutter_local_notifications` invokes the response callback
///   registered at `initialize`. This is the path every tutorial shows and the
///   only one that a phone with the app open will ever exercise, which is why it
///   is the one that gets built and the one that proves nothing.
/// - **the app was not running**: the tap *starts the process*. The response
///   callback is **not** invoked for it -- the plugin says so in as many words
///   -- and the tap is readable only through `getNotificationAppLaunchDetails`.
///   Miss it and the deep link fails silently in exactly the situation this
///   whole iteration exists for: 09:00, phone on the table, app swiped away
///   overnight.
///
/// [NotificationLinkBridge] wires both into one entry point. Everything below it
/// is unaware of which one a request came from.
///
/// ## Why this graph starts only once the user is signed in
///
/// The bridge is created by the signed-in half of the app (see
/// `widgets/notification_link_scope.dart`), not at startup. Resolving a task
/// means reading the board, and reading the board while signed out means a 401,
/// which the app-wide handler turns into a sign-out -- a notification tap would
/// bounce a logged-out user around for nothing.
///
/// Nothing is lost by waiting: a tap that arrives before a handler exists is
/// buffered by the gateway, and the launch payload is read out of the launch
/// intent, which does not expire. The user signs in, the scope mounts, and the
/// link resolves then.

/// Where a pending "open this task" request has got to.
@immutable
sealed class NotificationLinkState {
  const NotificationLinkState();

  /// The task this state is about, or null when there is nothing pending.
  String? get taskId => null;

  /// True when the widget layer has something to do about it.
  bool get isTerminal => false;
}

/// Nothing pending.
class NotificationLinkIdle extends NotificationLinkState {
  const NotificationLinkIdle();
}

/// A task id is known and the board is being consulted. Deliberately a state
/// rather than a bare in-flight future: on a cold start over mobile data this
/// can last a couple of seconds, and it is the difference between "the app
/// ignored my tap" and "the app is working on it".
class NotificationLinkResolving extends NotificationLinkState {
  const NotificationLinkResolving(this.taskId);

  @override
  final String taskId;
}

/// Resolved: this task lives in this project. The widget navigates and acks.
class NotificationLinkReady extends NotificationLinkState {
  const NotificationLinkReady({required this.taskId, required this.projectId});

  @override
  final String taskId;
  final String projectId;

  @override
  bool get isTerminal => true;
}

/// The board is current and the task is not in it -- deleted, or the reminder is
/// simply older than the task it was about.
///
/// A distinct state from [NotificationLinkUnreachable] because the two have
/// opposite advice: this one is over (there is nothing to retry), the other is a
/// network problem worth trying again.
class NotificationLinkNotFound extends NotificationLinkState {
  const NotificationLinkNotFound(this.taskId);

  @override
  final String taskId;

  @override
  bool get isTerminal => true;
}

/// The task could not be found **and the app could not confirm that**: no
/// network, no snapshot, or a refresh that failed.
///
/// Reported separately so the message is "нет связи" rather than "задача
/// удалена" -- telling someone their task is gone when the truth is that the
/// train went into a tunnel is the worst available answer.
class NotificationLinkUnreachable extends NotificationLinkState {
  const NotificationLinkUnreachable(this.taskId, this.error);

  @override
  final String taskId;
  final Object? error;

  @override
  bool get isTerminal => true;
}

/// Holds the pending request and resolves it against the board.
@Riverpod(keepAlive: true)
class NotificationLink extends _$NotificationLink {
  @override
  NotificationLinkState build() => const NotificationLinkIdle();

  /// A request identity, so a second tap while the first is still resolving
  /// cannot have its answer overwritten by the first one landing late.
  int _generation = 0;

  /// Entry point for both paths. [payload] is the raw notification payload;
  /// anything that is not one of ours is ignored (the bench's diagnostic
  /// notifications carry `bench:` payloads and must not navigate anywhere).
  void requestFromPayload(String? payload) {
    final taskId = taskIdFromPayload(payload);
    if (taskId == null) {
      debugPrint('Notification payload is not a task reminder: $payload');
      return;
    }
    open(taskId);
  }

  /// Resolves [taskId] to a project and publishes the outcome.
  ///
  /// The order of the attempts is the point:
  ///
  /// 1. **what is already on screen**, cache included. This is the offline path
  ///    and the fast path at once -- a board drawn from the snapshot holds every
  ///    task, so a reminder tapped with no signal still opens the right project,
  ///    instantly.
  /// 2. **one board refresh.** Reached when the task is not in what we hold,
  ///    which most often means we hold nothing yet (cold start) and sometimes
  ///    means the board is stale.
  /// 3. **the archive.** A project can be archived after its alarm was armed;
  ///    the task still exists and still opens. Worth one more request rather
  ///    than telling the user their task was deleted when it was not.
  ///
  /// A failure at step 2 short-circuits to [NotificationLinkUnreachable]: with a
  /// refresh that did not land, "not found" would be a guess.
  Future<void> open(String taskId) async {
    final generation = ++_generation;
    state = NotificationLinkResolving(taskId);

    void publish(NotificationLinkState next) {
      // A newer request (or an ack) has taken over; this answer is stale.
      if (generation != _generation || !ref.mounted) return;
      state = next;
    }

    // 1. Whatever is on screen, including the snapshot.
    final onScreen = boardRowsOrNull(ref.read(boardViewProvider));
    if (onScreen != null) {
      final projectId = projectIdForTask(onScreen, taskId);
      if (projectId != null) {
        publish(NotificationLinkReady(taskId: taskId, projectId: projectId));
        return;
      }
    }

    // 2. Ask the server. `refresh` never throws -- the outcome is in the
    // provider's own state afterwards.
    await ref.read(boardProvider.notifier).refresh();
    if (generation != _generation || !ref.mounted) return;

    final live = ref.read(boardProvider);
    if (live.hasError || !live.hasValue) {
      publish(NotificationLinkUnreachable(taskId, live.error));
      return;
    }

    final fresh = live.requireValue.projects;
    final projectId = projectIdForTask(fresh, taskId);
    if (projectId != null) {
      publish(NotificationLinkReady(taskId: taskId, projectId: projectId));
      return;
    }

    // 3. The archive. Invalidated first because it is not `keepAlive` but may
    // still be alive behind an open archive screen, and a cached answer from
    // before this reminder was armed would be worse than no answer.
    try {
      ref.invalidate(archivedBoardProvider);
      final archived = await ref.read(archivedBoardProvider.future);
      final archivedProjectId = projectIdForTask(archived, taskId);
      if (archivedProjectId != null) {
        publish(
          NotificationLinkReady(taskId: taskId, projectId: archivedProjectId),
        );
        return;
      }
    } catch (error) {
      // The active board answered, so the network is up and this is something
      // else. Still not grounds to claim the task is gone.
      debugPrint('Archive lookup for $taskId failed: $error');
      publish(NotificationLinkUnreachable(taskId, error));
      return;
    }

    publish(NotificationLinkNotFound(taskId));
  }

  /// "I have dealt with this." Called by the widget after it has navigated or
  /// shown the message, so the same request cannot be acted on twice -- which
  /// is what would otherwise happen every time the board rebuilds.
  void ack() {
    _generation++;
    state = const NotificationLinkIdle();
  }
}

/// Subscribes to both tap paths exactly once, and feeds them to
/// [NotificationLink].
///
/// A provider rather than something in `initState` for the reason the reminder
/// bridge gives: it is `keepAlive`, so it registers once per app run no matter
/// how many times the screen that watches it is rebuilt or re-mounted. Watching
/// it from a widget that is only mounted while signed in is what keeps the whole
/// thing behind the session switch.
@Riverpod(keepAlive: true)
Future<void> notificationLinkBridge(Ref ref) async {
  final gateway = ref.watch(notificationGatewayProvider);

  /*
   * The cold path, and deliberately the first thing awaited.
   *
   * It is consuming and read exactly once per app run -- see
   * `NotificationGateway.takeLaunchPayload` for why asking twice would
   * double-navigate on Android.
   *
   * Awaiting it first also buys the ordering this function needs for a second
   * reason: registering the tap handler below replays whatever the gateway
   * buffered, which writes to another provider, and Riverpod forbids that
   * *during* a build. Past the first `await` this build has already returned
   * its future, so the restriction no longer applies.
   */
  final launch = await gateway.takeLaunchPayload();
  if (!ref.mounted) return;

  final link = ref.read(notificationLinkProvider.notifier);

  // The warm path. Anything buffered while nobody was listening arrives now, so
  // a tap during startup is not lost.
  gateway.setTapHandler(link.requestFromPayload);

  if (launch != null) {
    debugPrint('App launched from notification: $launch');
    link.requestFromPayload(launch);
  }
}
