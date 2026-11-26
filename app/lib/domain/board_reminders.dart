import '../models/board_project.dart';
import '../models/task_status.dart';
import 'reminder_schedule.dart';

/// The one line F2/F4 needs in order to hand real data to the F1 scheduler.
///
/// Kept out of `reminder_schedule.dart` so that file stays free of the wire
/// models: the scheduler is testable with three synthetic rows and does not need
/// to know that a board exists.
///
/// A reminder exists for every task that is **not done** and has a `remindAt`
/// **with a time** (`design/today-history-contract.md`): the date says when
/// the owner gets to the task, and only a named moment («встретить курьера в
/// 15:00») pushes. A blocker and a plain open task alike. A `done` task with
/// a leftover date is not a reminder -- there is nothing left to be reminded
/// about.
List<TaskReminder> remindersFromBoard(Iterable<BoardProject> board) {
  final reminders = <TaskReminder>[];

  for (final entry in board) {
    for (final task in entry.tasks) {
      final remindAt = task.remindAt;
      if (task.status == TaskStatus.done || remindAt == null) continue;
      if (reminderTimeFromString(task.remindTime) == null) continue;

      reminders.add(
        TaskReminder(
          taskId: task.id,
          taskTitle: task.title,
          remindAt: remindAt,
          remindTime: task.remindTime,
          projectName: entry.project.name,
        ),
      );
    }
  }

  return List<TaskReminder>.unmodifiable(reminders);
}
