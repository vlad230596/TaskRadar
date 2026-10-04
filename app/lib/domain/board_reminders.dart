import '../models/board_project.dart';
import '../models/task_status.dart';
import 'reminder_schedule.dart';

/// The one line F2/F4 needs in order to hand real data to the F1 scheduler.
///
/// Kept out of `reminder_schedule.dart` so that file stays free of the wire
/// models: the scheduler is testable with three synthetic rows and does not need
/// to know that a board exists.
///
/// A reminder exists for every task that is **not done** and has a `remindAt`:
/// a blocker ("ждём кабель, спросить завтра") and a plain open task ("вернуться
/// к этому в пятницу") alike. A `done` task with a leftover date is not a
/// reminder -- there is nothing left to be reminded about.
List<TaskReminder> remindersFromBoard(Iterable<BoardProject> board) {
  final reminders = <TaskReminder>[];

  for (final entry in board) {
    for (final task in entry.tasks) {
      final remindAt = task.remindAt;
      if (task.status == TaskStatus.done || remindAt == null) continue;

      reminders.add(
        TaskReminder(
          taskId: task.id,
          taskTitle: task.title,
          remindAt: remindAt,
          projectName: entry.project.name,
        ),
      );
    }
  }

  return List<TaskReminder>.unmodifiable(reminders);
}
