import '../models/board_project.dart';
import '../models/task_status.dart';
import 'reminder_schedule.dart';

/// The one line F2/F4 needs in order to hand real data to the F1 scheduler.
///
/// Kept out of `reminder_schedule.dart` so that file stays free of the wire
/// models: the scheduler is testable with three synthetic rows and does not need
/// to know that a board exists.
///
/// The rule is the one from `flutter-migration-plan.md`: a reminder exists for a
/// task that is **blocked** and has a `remindAt`. A `pending` or `done` task
/// with a leftover date is not a reminder -- the date only means something while
/// the task is waiting on something.
List<TaskReminder> remindersFromBoard(Iterable<BoardProject> board) {
  final reminders = <TaskReminder>[];

  for (final entry in board) {
    for (final task in entry.tasks) {
      final remindAt = task.remindAt;
      if (task.status != TaskStatus.blocked || remindAt == null) continue;

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
