import type { Task } from "../lib/types";
import { formatReminderDate, isReminderDue } from "../lib/reminders";
import "./TaskRow.css";

interface TaskRowProps {
  task: Task;
}

/**
 * One status indicator per task, in position order. Visual hierarchy (must
 * stay unambiguous at a glance):
 *   current (pending + isCurrent) > blocked > done > pending (not current)
 */
export function TaskRow({ task }: TaskRowProps) {
  if (task.isCurrent) {
    return (
      <div className="task-row task-row--current">
        <span className="task-dot task-dot--current" aria-hidden="true" />
        <span className="task-row__title">{task.title}</span>
      </div>
    );
  }

  if (task.status === "blocked") {
    const due = task.remindAt ? isReminderDue(task.remindAt) : false;
    return (
      <div className="task-row task-row--blocked" title={task.title}>
        <span className="task-dot task-dot--blocked" aria-hidden="true" />
        {task.remindAt && (
          <span className={`task-row__reminder${due ? " task-row__reminder--due" : ""}`}>
            {due ? `❗ проверить · ${formatReminderDate(task.remindAt)}` : `напомнить ${formatReminderDate(task.remindAt)}`}
          </span>
        )}
      </div>
    );
  }

  if (task.status === "done") {
    return (
      <div className="task-row task-row--done" title={task.title}>
        <span className="task-dot task-dot--done" aria-hidden="true" />
      </div>
    );
  }

  return (
    <div className="task-row task-row--pending" title={task.title}>
      <span className="task-dot task-dot--pending" aria-hidden="true" />
    </div>
  );
}
