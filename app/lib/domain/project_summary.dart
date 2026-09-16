import 'package:flutter/foundation.dart';

import '../models/board_project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import 'reminders.dart';

/// Everything one project card on the board shows, derived from one board row.
///
/// ## Why this is not computed inside the widget
///
/// The board screen's whole job (see `../README.md`: "восстановление
/// контекста") is to answer, per project and in one glance, *what is happening
/// here*. That answer is four small rules -- which task is current, how much is
/// done, is anything blocked, and has a reminder come due -- and every one of
/// them is a place to be quietly wrong: counting `blocked` as done, re-deriving
/// `isCurrent` locally, or comparing `remindAt` as an instant. Pulling them out
/// of the widget means they are covered by plain unit tests instead of by
/// widget tests that would have to read pixels to check a counter.
@immutable
class ProjectSummary {
  const ProjectSummary({
    required this.currentTask,
    required this.doneCount,
    required this.totalCount,
    required this.blockedTasks,
    required this.dueReminders,
    required this.nextReminderAt,
  });

  /// Reduces one `GET /board` row to what the card needs.
  ///
  /// [now] is threaded through to [isReminderDue] so a test can stand on a
  /// fixed day; production passes nothing and gets the real clock.
  factory ProjectSummary.of(BoardProject entry, {DateTime? now}) {
    var doneCount = 0;
    final blocked = <Task>[];
    final due = <Task>[];
    String? nextReminderAt;

    for (final task in entry.tasks) {
      if (task.status == TaskStatus.done) doneCount++;
      if (task.status != TaskStatus.blocked) continue;

      blocked.add(task);

      final remindAt = task.remindAt;
      if (remindAt == null) continue;

      final date = reminderCalendarDate(remindAt);
      // An unreadable date is skipped rather than shown: see [isReminderDue].
      if (date == null) continue;

      if (isReminderDue(remindAt, now: now)) due.add(task);

      // Earliest wins. Compared as `YYYY-MM-DD` strings for the same reason the
      // rest of this file does -- zero-padded big-endian dates sort
      // chronologically, and parsing them into instants is the trap.
      if (nextReminderAt == null || date.compareTo(nextReminderAt) < 0) {
        nextReminderAt = date;
      }
    }

    return ProjectSummary(
      // Straight from the server's flag, never re-derived. The rule lives in
      // `backend/src/domain/isCurrent.ts`; see the note on
      // `BoardProject.currentTask`.
      currentTask: entry.currentTask,
      doneCount: doneCount,
      totalCount: entry.tasks.length,
      blockedTasks: List<Task>.unmodifiable(blocked),
      dueReminders: List<Task>.unmodifiable(due),
      nextReminderAt: nextReminderAt,
    );
  }

  /// The task to work on next, or null when there is none (see [emptiness]).
  final Task? currentTask;

  /// How many of the project's tasks are `done`. `blocked` does not count:
  /// a blocked task is unfinished work, and folding it into "done" would make a
  /// stuck project look finished, which is the exact opposite of what this
  /// screen is for.
  final int doneCount;

  final int totalCount;

  /// Blocked tasks in `position` order, with or without a reminder date.
  final List<Task> blockedTasks;

  /// The subset of [blockedTasks] whose reminder date has arrived. These are
  /// the ones that want attention *today*.
  final List<Task> dueReminders;

  /// The earliest reminder date among the blocked tasks, as `YYYY-MM-DD`, or
  /// null if none of them carries a date. Used for the badge label.
  final String? nextReminderAt;

  int get blockedCount => blockedTasks.length;

  bool get hasBlocker => blockedTasks.isNotEmpty;

  bool get hasDueReminder => dueReminders.isNotEmpty;

  /// Fraction done, 0..1. Zero for a project with no tasks -- an empty project
  /// is at the start, not finished.
  double get progress => totalCount == 0 ? 0 : doneCount / totalCount;

  /// Why there is no current task, which the card turns into a sentence.
  ///
  /// The three cases read very differently to a human ("nothing here yet" vs
  /// "this project is finished" vs "this project is stuck"), and only the last
  /// one is a call to action -- so they are distinguished here rather than
  /// collapsed into one "—".
  ProjectEmptiness get emptiness {
    if (currentTask != null) return ProjectEmptiness.hasCurrentTask;
    if (totalCount == 0) return ProjectEmptiness.noTasks;
    if (doneCount == totalCount) return ProjectEmptiness.allDone;
    return ProjectEmptiness.allBlocked;
  }
}

/// See [ProjectSummary.emptiness].
enum ProjectEmptiness {
  hasCurrentTask,

  /// The project has no tasks at all.
  noTasks,

  /// Every task is done.
  allDone,

  /// Nothing is left that is neither done nor blocked -- the project is waiting
  /// on something external.
  allBlocked,
}
