import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_schedule.dart';
import '../models/board_project.dart';
import '../notifications/notification_gateway.dart';
import '../models/task_status.dart';
import '../models/today_history.dart';
import 'board_providers.dart';
import 'reminder_providers.dart';
import 'today_providers.dart';

/// The weekly review's one push (`design/today-history-contract.md`,
/// «Уведомления»; spec §10.8).
///
/// Armed at the moment the review falls due -- the server's `nextAt` from
/// `/reviews/status`, which already follows the owner's `reviewWeekday` /
/// `reviewTime` -- and only while it is ahead. A review that is already due
/// gets no push at all: a missed review is the dot on «История», never a
/// repeat. Recording a review moves `nextAt` a week on, and the push with it.
///
/// Its own id ([reviewNotificationId], below the task range) and payload
/// ([reviewPayload]): the task resync never sweeps it, and a tap opens
/// «История» with the card.

/// What the push should be: null for "nothing armed".
@immutable
class ReviewPush {
  const ReviewPush({required this.fireAt, required this.body});

  final DateTime fireAt;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is ReviewPush && other.fireAt == fireAt && other.body == body;

  @override
  int get hashCode => Object.hash(fireAt, body);
}

/// «Пересмотр недели».
const String reviewPushTitle = 'Пересмотр недели';

/// «Закрыто 23 · 5 минут на неделю вперёд», or the second half alone when
/// the count is not known.
String reviewPushBody(int? closed) => closed == null
    ? '5 минут на неделю вперёд'
    : 'Закрыто $closed · 5 минут на неделю вперёд';

/// Closed since [since], counted on the board the app holds -- cheap, and
/// offline too. Archived projects are not on the board, so the number can
/// fall short of the review's own by their closings; it is a push text, not
/// the review's record.
int closedOnBoardSince(List<BoardProject> board, String? since) {
  final from = since == null ? null : DateTime.tryParse(since);
  var count = 0;
  for (final project in board) {
    for (final task in project.tasks) {
      if (task.status != TaskStatus.done) continue;
      final doneAt = DateTime.tryParse(task.doneAt ?? '');
      if (doneAt == null) continue;
      if (from == null || doneAt.isAfter(from)) count++;
    }
  }
  return count;
}

/// The push for [status] at [now]: none while due (or unknown), none when the
/// moment has gone by.
ReviewPush? reviewPushFor(
  ReviewStatus status, {
  required DateTime now,
  int? closed,
}) {
  if (status.due) return null;
  final next = DateTime.tryParse(status.nextAt ?? '');
  if (next == null || !next.isAfter(now)) return null;
  return ReviewPush(fireAt: next, body: reviewPushBody(closed));
}

/// Keeps the OS queue's review push in step with the status and the board.
/// Subscribed by `ReminderBridgeScope`, next to the task reminders.
final reviewPushBridgeProvider = Provider<void>((ref) {
  ReviewPush? armed;
  var initialised = false;
  var chain = Future<void>.value();

  Future<void> apply(ReviewPush? wanted) async {
    if (initialised && wanted == armed) return;
    final gateway = ref.read(notificationGatewayProvider);
    if (!gateway.support.schedulesReminders) return;
    try {
      await gateway.initialize();
      if (wanted == null) {
        await gateway.cancel(reviewNotificationId);
      } else {
        final zone = await ref.read(notificationTimeZoneProvider.future);
        final permissions = await gateway.permissions();
        await gateway.schedule(
          id: reviewNotificationId,
          title: reviewPushTitle,
          body: wanted.body,
          fireAt: tz.TZDateTime.from(wanted.fireAt, zone.location),
          exact: permissions.scheduleMode == NotificationScheduleMode.exact,
          payload: reviewPayload,
        );
      }
      armed = wanted;
      initialised = true;
    } catch (error) {
      debugPrint('Review push sync failed: $error');
    }
  }

  void sync() {
    final status = ref.read(reviewStatusStateProvider).value;
    // Unknown (still loading, or the server never answered): leave whatever
    // was armed by an earlier run alone rather than cancel it on a guess.
    if (status == null) return;
    final board = ref.read(boardViewProvider);
    final wanted = reviewPushFor(
      status,
      now: DateTime.now(),
      closed: board is BoardReady
          ? closedOnBoardSince(board.projects, status.lastAt)
          : null,
    );
    chain = chain.then((_) => apply(wanted));
  }

  ref.listen(reviewStatusStateProvider, (_, _) => sync());
  ref.listen(boardViewProvider, (_, _) => sync());
  // Settings move the due moment: the status provider re-reads on a save
  // (`OwnerSettingsState.save`), which lands here through the first listen.
  Future.microtask(() {
    if (ref.mounted) sync();
  });
});
