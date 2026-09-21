import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminders.dart';
import '../domain/task_age.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../navigation/app_routes.dart';
import '../providers/project_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'glance.dart';
import 'mutation_feedback.dart';

/// The task half of the project screen: rows you can read, and one way to add
/// one (F12).
///
/// ## What went, and why
///
/// The inline composer at the top of this list is gone. It was a one-line
/// `TextField` with a microphone beside it, and it was the literal subject of
/// complaint number one -- "в композере видно два-три слова". The brief is
/// explicit that the new screens must not have one. Adding a task now opens
/// `TaskScreen.draft`, which is the same 252 px field the task screen uses.
///
/// That trades one navigation for readable text, and the trade is smaller than
/// it looks: the gesture that justified the inline field (five sentences, five
/// Enters, "empty my head into the list") is now the microphone, which files
/// straight into a project without opening any screen at all.
///
/// The inline *title* editor inside each row is gone for the same reason, and
/// the description dialog with it: both are the task screen now.
///
/// ## What stayed
///
/// - **Edits are optimistic**, as they have been since F3: the row flips
///   immediately and rolls back on failure. On mobile data the wait reads as a
///   dead tap.
/// - **Dragging is scoped to a handle.** A whole-row drag target fights with
///   every tap inside the row, and on touch it also fights with scrolling.
/// - **Changing a status into `blocked` offers the date immediately.** Left as
///   two gestures the app fills up with dateless blockers -- tasks that are
///   stuck and will never say so again.
///
/// ## The one thing F13 will want back
///
/// `design/reference/Project.html` puts a "взять в работу" target on the right
/// of each row, where the drag handle is here. It cannot be built yet:
/// `Task.focusedAt` is F11's and the work mode that reads it is F13's, and a
/// button that does nothing is worse than no button. When it arrives the handle
/// has to move -- a long press on the row is the obvious home for it, which is
/// also where `ReorderableListView` puts its default.
class TaskListView extends ConsumerWidget {
  const TaskListView({
    required this.projectId,
    required this.tasks,
    this.highlightTaskId,
    this.now,
    super.key,
  });

  final String projectId;

  /// In server order. Never re-sorted -- see [Task.position].
  final List<Task> tasks;

  /// A task to draw attention to, from a caller that was about one specific
  /// task (F4: a reminder). See `navigation/app_routes.dart`.
  final String? highlightTaskId;

  /// Fixes "today" for tests, threaded to [isReminderDue].
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(projectTasksProvider(projectId).notifier).refresh(),
      child: ReorderableListView.builder(
        // The list must scroll even when it is shorter than the viewport, or
        // pull-to-refresh on a two-task project does nothing.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          12,
          Insets.gutter,
          32,
        ),

        // A footer rather than a header, unlike the composer it replaces: it is
        // no longer a field you type into repeatedly, it is the end of the
        // list, and the end of the list is where "and one more" belongs.
        footer: Padding(
          padding: EdgeInsets.only(top: tasks.isEmpty ? 0 : 8),
          child: Column(
            children: <Widget>[
              if (tasks.isEmpty) const _NoTasksYet(),
              _AddTaskButton(projectId: projectId),
            ],
          ),
        ),

        // Flutter's own handles are a grip on the trailing edge, added to every
        // row. Ours is switched off for a row the server has not confirmed yet,
        // which the default cannot express.
        buildDefaultDragHandles: false,

        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return Padding(
            // Keyed by id for the reorder animation.
            key: ValueKey<String>(task.id),
            padding: const EdgeInsets.only(bottom: 8),
            child: TaskRow(
              projectId: projectId,
              task: task,
              index: index,
              isHighlighted: task.id == highlightTaskId,
              now: now,
            ),
          );
        },
        onReorder: (oldIndex, newIndex) {
          // No `await`, no error handling here: `move` is optimistic, so the
          // list has already settled into its new order by the time this
          // returns, and a failure rolls it back and reports itself.
          runMutation(
            context,
            () => ref
                .read(projectTasksProvider(projectId).notifier)
                .move(oldIndex, newIndex),
            failure: 'Не удалось сохранить порядок задач.',
          );
        },
      ),
    );
  }
}

/// One task: status on the left, the text in the middle, the grip on the right.
///
/// 56 px minimum and more when the row has a second line, which is what the
/// reference specifies (58-66 px depending on what the row has to say).
class TaskRow extends ConsumerWidget {
  const TaskRow({
    required this.projectId,
    required this.task,
    required this.index,
    this.isHighlighted = false,
    this.now,
    super.key,
  });

  final String projectId;
  final Task task;
  final int index;
  final bool isHighlighted;
  final DateTime? now;

  /// True while this row exists only as an optimistic prediction. Its id is not
  /// one the server knows, so every operation on it would 404 -- the controls
  /// are hidden rather than disabled, because a greyed-out row for the ~50 ms
  /// this lasts is more noise than a plain one.
  bool get _unconfirmed => isOptimisticId(task.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = task.status == TaskStatus.blocked;
    final done = task.status == TaskStatus.done;
    final current = task.isCurrent;

    final age = daysSinceMovement(
      task.updatedAt,
      createdAt: task.createdAt,
      now: now,
    );

    return Container(
      decoration: BoxDecoration(
        color: blocked ? AppColors.waitingFill : AppColors.card,
        border: Border.all(
          color: isHighlighted
              ? AppColors.indigoLink
              : blocked
              ? AppColors.waitingLine
              // The current task carries a heavier border rather than a tint:
              // it is the sentence that restores the context, and a tint alone
              // disappears at a glance in sunlight.
              : current
              ? AppColors.lineStrong
              : AppColors.line,
          width: isHighlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _StatusTarget(
            projectId: projectId,
            task: task,
            enabled: !_unconfirmed,
            now: now,
          ),
          Expanded(
            child: InkWell(
              onTap: _unconfirmed
                  ? null
                  : () => AppRoutes.openTask(
                      context,
                      projectId: projectId,
                      taskId: task.id,
                    ),
              child: Container(
                constraints: const BoxConstraints(minHeight: Targets.row),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (current
                                        ? AppText.taskTitleCurrent
                                        : AppText.taskTitle)
                                    .copyWith(
                                      // Struck through rather than hidden: a
                                      // done task is still part of the record
                                      // of what happened here.
                                      decoration: done
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: done ? AppColors.muted : null,
                                    ),
                          ),
                        ),
                        // No second line to put it on, so it rides at the end
                        // of the title -- and never wraps or shrinks. See
                        // `widgets/glance.dart`.
                        if (!current && !blocked) ...<Widget>[
                          const SizedBox(width: 10),
                          AgeChip(days: age, showIcon: false),
                        ],
                      ],
                    ),
                    if (current) ...<Widget>[
                      const SizedBox(height: 6),
                      _Meta(
                        icon: Icons.arrow_forward,
                        text: 'следующая',
                        colour: AppColors.indigoLink,
                      ),
                    ] else if (blocked) ...<Widget>[
                      const SizedBox(height: 6),
                      _Meta(
                        icon: Icons.notifications_none,
                        text: _blockedLine(task, age, now),
                        colour: AppColors.waitingInk,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_unconfirmed)
            const SizedBox(
              width: 48,
              height: Targets.row,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            ReorderableDragStartListener(
              index: index,
              child: const Tooltip(
                message: 'Перетащить задачу',
                child: SizedBox(
                  width: 48,
                  height: Targets.row,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: AppColors.lineStrong,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "23.09 · ждёт 3 д", or just one half of it.
String _blockedLine(Task task, int? age, DateTime? now) {
  final remindAt = task.remindAt;
  final waited = age == null ? null : 'ждёт ${formatAgeShort(age)}';

  if (remindAt == null) {
    // A blocked task with no date is a task that will never ask again, and
    // saying so is the only thing that gets a date onto it.
    return waited == null ? 'без даты' : '$waited · без даты';
  }

  final date = formatReminderDate(remindAt);
  final label = isReminderDue(remindAt, now: now) ? 'пора · $date' : date;
  return waited == null ? label : '$label · $waited';
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.colour});

  final IconData icon;
  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 13, color: colour),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.chip.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// The 48x56 target on the left: what the task's status is, and the one-tap way
/// to change it.
///
/// A tap toggles done, which is the change that actually happens dozens of
/// times a day; a long press opens the full three-way choice, which happens
/// once in a while. Putting the rare one behind the common one is the opposite
/// of the old popup menu, where marking something done cost a menu.
class _StatusTarget extends ConsumerWidget {
  const _StatusTarget({
    required this.projectId,
    required this.task,
    required this.enabled,
    required this.now,
  });

  final String projectId;
  final Task task;
  final bool enabled;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = switch (task.status) {
      TaskStatus.done => const Icon(
        Icons.check_circle,
        size: 26,
        color: AppColors.done,
      ),
      TaskStatus.blocked => const Icon(
        Icons.pause_circle_outline,
        size: 26,
        color: AppColors.waitingInk,
      ),
      TaskStatus.pending => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.lineStrong, width: 2),
        ),
      ),
    };

    return Tooltip(
      message: switch (task.status) {
        TaskStatus.done => 'Сделана — вернуть в очередь',
        TaskStatus.blocked => 'Блокер — снять',
        TaskStatus.pending => 'Отметить сделанной',
      },
      child: InkWell(
        onTap: enabled ? () => unawaited(_toggle(context, ref)) : null,
        onLongPress: enabled ? () => unawaited(_choose(context, ref)) : null,
        child: SizedBox(
          width: 48,
          height: Targets.row,
          child: Center(child: circle),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) {
    final next = task.status == TaskStatus.done
        ? TaskStatus.pending
        : TaskStatus.done;
    return setTaskStatus(context, ref, projectId: projectId, task: task, status: next);
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<TaskStatus>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final status in taskStatusOrder)
              ListTile(
                leading: Icon(
                  switch (status) {
                    TaskStatus.pending => Icons.circle_outlined,
                    TaskStatus.blocked => Icons.pause_circle_outline,
                    TaskStatus.done => Icons.check_circle_outline,
                  },
                ),
                title: Text(taskStatusLabel[status]!),
                trailing: status == task.status
                    ? const Icon(Icons.check, color: AppColors.indigoLink)
                    : null,
                onTap: () => Navigator.of(context).pop(status),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await setTaskStatus(
      context,
      ref,
      projectId: projectId,
      task: task,
      status: chosen,
    );
  }
}

/// `pending -> blocked -> done` is the order a task actually travels in, and it
/// puts the destructive-feeling "done" at the far end. Same order as the React
/// client's `STATUS_ORDER`, so muscle memory survives the migration.
const List<TaskStatus> taskStatusOrder = <TaskStatus>[
  TaskStatus.pending,
  TaskStatus.blocked,
  TaskStatus.done,
];

const Map<TaskStatus, String> taskStatusLabel = <TaskStatus, String>{
  TaskStatus.pending: 'В очереди',
  TaskStatus.blocked: 'Блокер',
  TaskStatus.done: 'Сделано',
};

/// Changes a task's status, and offers the date when the change is *into*
/// `blocked` on a task that has none.
///
/// Shared by the row and by the task screen, because the chaining rule is the
/// product's rather than either screen's: "блокер" and "жду до вторника" are
/// one thought, and splitting them is what fills the app with dateless
/// blockers.
Future<void> setTaskStatus(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required Task task,
  required TaskStatus status,
}) async {
  final wasBlocked = task.status == TaskStatus.blocked;
  final hadDate = task.remindAt != null;

  final ok = await runMutation(
    context,
    () => ref
        .read(projectTasksProvider(projectId).notifier)
        .setStatus(task, status),
    failure: 'Не удалось изменить статус.',
  );
  if (!ok || !context.mounted) return;
  if (status != TaskStatus.blocked || wasBlocked || hadDate) return;

  // Read fresh: `task` is the row from before the status change, and
  // `setRemindAt` refuses a row that is not blocked.
  final rows = ref.read(projectTasksProvider(projectId)).value;
  final fresh = rows?.where((row) => row.id == task.id).firstOrNull;
  if (fresh == null) return;

  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
    helpText: 'Когда напомнить',
    cancelText: 'Отмена',
    confirmText: 'Готово',
  );
  if (picked == null || !context.mounted) return;

  await runMutation(
    context,
    () => ref
        .read(projectTasksProvider(projectId).notifier)
        .setRemindAt(fresh, calendarDateForApi(picked)),
    failure: 'Не удалось сохранить дату напоминания.',
  );
}

class _AddTaskButton extends StatelessWidget {
  const _AddTaskButton({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.muted,
          side: const BorderSide(color: AppColors.lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card),
          ),
        ),
        onPressed: () => AppRoutes.openNewTask(context, projectId: projectId),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Задача'),
      ),
    );
  }
}

class _NoTasksYet extends StatelessWidget {
  const _NoTasksYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.checklist_rtl,
            size: 36,
            color: AppColors.lineStrong,
          ),
          const SizedBox(height: 12),
          Text('Задач пока нет', style: AppText.projectName),
          const SizedBox(height: 6),
          Text(
            'Кнопка ниже заводит первую, а микрофон в углу — надиктует её.',
            textAlign: TextAlign.center,
            style: AppText.hint,
          ),
        ],
      ),
    );
  }
}
