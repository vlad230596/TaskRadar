import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminders.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../providers/project_providers.dart';
import 'mutation_feedback.dart';

/// The task half of the project screen: an inline composer on top and a
/// reorderable list under it.
///
/// Port of `frontend/src/components/TaskList.tsx` + `TaskListItem.tsx`, with two
/// deliberate departures from the React original:
///
/// - **Edits are optimistic here.** The React row waits for the server before it
///   flips a status button, and says so in its own comment. On a phone over
///   mobile data that wait is long enough to read as a dead tap, so F3 shows the
///   change immediately and rolls it back on failure (see `ProjectTasks`).
/// - **Dragging is scoped to a handle**, for exactly the reason the React file
///   spells out at length: a whole-row drag target fights with every tap inside
///   the row, and on touch it also fights with scrolling.
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

  /// A task to draw attention to, from a caller that was about one specific task
  /// (F4: a reminder notification). See `navigation/app_routes.dart`.
  final String? highlightTaskId;

  /// Fixes "today" for tests, threaded to [isReminderDue] exactly as the board
  /// card does it.
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
        padding: const EdgeInsets.only(bottom: 32),

        // The composer rides along as the list header rather than sitting in a
        // Column above it: inside the scrollable it scrolls away when you are
        // reading a long list, and -- more importantly -- a Column would leave
        // the ReorderableListView unbounded and force a shrink-wrap, which
        // breaks both scrolling and the drag auto-scroll.
        header: _TaskComposer(projectId: projectId),
        footer: tasks.isEmpty ? const _NoTasksYet() : null,

        // Flutter's own handles are a grip on the trailing edge, added to every
        // row. Ours is a leading grip that is switched off for a row the server
        // has not confirmed yet, which the default cannot express.
        buildDefaultDragHandles: false,

        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return _TaskRow(
            // Identity for the reorder animation *and* for the inline editor
            // state: keyed by id, a row keeps its half-typed title when the list
            // around it changes. Keyed by index it would inherit a neighbour's.
            key: ValueKey<String>(task.id),
            projectId: projectId,
            task: task,
            index: index,
            isHighlighted: task.id == highlightTaskId,
            now: now,
          );
        },
        onReorder: (oldIndex, newIndex) {
          // No `await`, no error handling here: `move` is optimistic, so the
          // list has already settled into its new order by the time this
          // returns, and a failure rolls it back and reports itself. The
          // gesture has nothing left to do.
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

/// Statuses in the order they are offered, which is *not* `TaskStatus.values`.
///
/// `pending -> blocked -> done` is the order a task actually travels in, and it
/// puts the destructive-feeling "done" at the far end. Same order as the React
/// client's `STATUS_ORDER`, so muscle memory survives the migration.
const List<TaskStatus> _statusOrder = <TaskStatus>[
  TaskStatus.pending,
  TaskStatus.blocked,
  TaskStatus.done,
];

const Map<TaskStatus, String> _statusLabel = <TaskStatus, String>{
  TaskStatus.pending: 'Ожидает',
  TaskStatus.blocked: 'Блокер',
  TaskStatus.done: 'Готово',
};

const Map<TaskStatus, IconData> _statusIcon = <TaskStatus, IconData>{
  TaskStatus.pending: Icons.radio_button_unchecked,
  TaskStatus.blocked: Icons.pause_circle_outline,
  TaskStatus.done: Icons.check_circle,
};

/// The inline "new task" field -- the primary way text gets into this app.
///
/// Optimised for the actual gesture, which is not "add one task" but "empty my
/// head into the list": the field keeps focus after submitting and the row
/// appears immediately above it, so a burst of five tasks is five sentences and
/// five Enters with nothing in between. That is also why the field is never
/// disabled while a create is in flight -- `ProjectTasks` serialises the writes
/// so it does not have to be.
class _TaskComposer extends ConsumerStatefulWidget {
  const _TaskComposer({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_TaskComposer> createState() => _TaskComposerState();
}

class _TaskComposerState extends ConsumerState<_TaskComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;

    // Cleared *before* the await, not after it: the point of this field is that
    // the next task can be typed while the previous one is still in flight. The
    // text is captured above, so a rollback does not need it back -- the row
    // disappearing plus the error message is the report.
    _controller.clear();
    _focus.requestFocus();

    await runMutation(
      context,
      () => ref
          .read(projectTasksProvider(widget.projectId).notifier)
          .create(title),
      failure: 'Не удалось добавить задачу.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Новая задача…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Добавить задачу',
            onPressed: _submit,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _NoTasksYet extends StatelessWidget {
  const _NoTasksYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.checklist_rtl,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('Задач пока нет', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Первая строка сверху — и она появится здесь.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One task.
class _TaskRow extends ConsumerStatefulWidget {
  const _TaskRow({
    required this.projectId,
    required this.task,
    required this.index,
    required this.isHighlighted,
    this.now,
    super.key,
  });

  final String projectId;
  final Task task;
  final int index;
  final bool isHighlighted;
  final DateTime? now;

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow> {
  bool _editingTitle = false;

  ProjectTasks get _tasks =>
      ref.read(projectTasksProvider(widget.projectId).notifier);

  /// True while this row exists only as an optimistic prediction. Its id is not
  /// one the server knows, so every operation on it would 404 -- the controls are
  /// hidden rather than disabled, because a greyed-out row for the ~50 ms this
  /// lasts is more noise than a plain one.
  bool get _unconfirmed => isOptimisticId(widget.task.id);

  Future<void> _setStatus(TaskStatus status) => runMutation(
    context,
    () => _tasks.setStatus(widget.task, status),
    failure: 'Не удалось изменить статус.',
  );

  Future<void> _commitTitle(String value) async {
    // Closed before the write, not after it: the optimistic list already shows
    // the new title, so keeping the editor open would show the same text twice
    // in two different widgets, and a rollback would leave a stale draft in the
    // field. A failure puts the old title back plus a message.
    setState(() => _editingTitle = false);
    await runMutation(
      context,
      () => _tasks.editTitle(widget.task, value),
      failure: 'Не удалось переименовать задачу.',
    );
  }

  Future<void> _editDescription() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _DescriptionDialog(task: widget.task),
    );
    if (value == null || !mounted) return; // cancelled

    await runMutation(
      context,
      // An empty string from the dialog means "I deleted the text", which is a
      // clear, not a "leave it alone". `editDescription` is where that becomes
      // an explicit wire `null`; see `PatchField`.
      () => _tasks.editDescription(widget.task, value.isEmpty ? null : value),
      failure: 'Не удалось сохранить описание.',
    );
  }

  Future<void> _delete() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Удалить задачу?',
      message:
          '«${widget.task.title}» будет удалена без возможности '
          'восстановления.',
    );
    if (!confirmed || !mounted) return;

    await runMutation(
      context,
      () => _tasks.remove(widget.task),
      failure: 'Не удалось удалить задачу.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final task = widget.task;

    final current = task.isCurrent;
    final done = task.status == TaskStatus.done;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        // The current task is tinted *and* carries a left bar. Two signals
        // rather than one because this is the single most important row on the
        // screen -- it is the sentence that restores the context (see
        // `../README.md`) -- and a tint alone disappears at a glance in
        // sunlight or in dark mode.
        color: current
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: widget.isHighlighted
            ? Border.all(color: scheme.tertiary, width: 2)
            : null,
      ),
      foregroundDecoration: current
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: scheme.primary, width: 4)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_unconfirmed)
              const SizedBox(
                width: 40,
                height: 40,
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
                index: widget.index,
                child: Tooltip(
                  message: 'Перетащить задачу',
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_indicator,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_editingTitle)
                    _InlineTitleField(
                      initialValue: task.title,
                      onSubmit: _commitTitle,
                      onCancel: () => setState(() => _editingTitle = false),
                    )
                  else
                    InkWell(
                      onTap: _unconfirmed
                          ? null
                          : () => setState(() => _editingTitle = true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          task.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: current ? FontWeight.w600 : null,
                            // Struck through rather than hidden: a done task is
                            // still part of the record of what happened here,
                            // which is what the whole project screen is for.
                            decoration: done
                                ? TextDecoration.lineThrough
                                : null,
                            color: done ? scheme.onSurfaceVariant : null,
                          ),
                        ),
                      ),
                    ),

                  if (task.description case final String description
                      when description.trim().isNotEmpty)
                    InkWell(
                      onTap: _unconfirmed ? null : _editDescription,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else if (!_unconfirmed)
                    TextButton.icon(
                      onPressed: _editDescription,
                      icon: const Icon(Icons.notes, size: 16),
                      label: const Text('описание'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 30),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: scheme.onSurfaceVariant,
                        textStyle: theme.textTheme.bodySmall,
                      ),
                    ),

                  if (task.status == TaskStatus.blocked)
                    _ReminderLine(task: task, now: widget.now),
                ],
              ),
            ),

            if (!_unconfirmed) ...[
              PopupMenuButton<TaskStatus>(
                tooltip: 'Статус: ${_statusLabel[task.status]}',
                icon: Icon(
                  _statusIcon[task.status],
                  color: switch (task.status) {
                    TaskStatus.done => scheme.primary,
                    TaskStatus.blocked => scheme.error,
                    TaskStatus.pending => scheme.onSurfaceVariant,
                  },
                ),
                onSelected: _setStatus,
                itemBuilder: (_) => <PopupMenuEntry<TaskStatus>>[
                  for (final status in _statusOrder)
                    CheckedPopupMenuItem<TaskStatus>(
                      value: status,
                      checked: status == task.status,
                      child: Text(_statusLabel[status]!),
                    ),
                ],
              ),
              IconButton(
                tooltip: 'Удалить задачу',
                onPressed: _delete,
                icon: const Icon(Icons.close),
                color: scheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The title editor: one line, Enter saves, Escape cancels, losing focus saves.
///
/// "Losing focus saves" is the same choice the React row made, and it is the
/// right one for a field you opened by tapping a word: tapping somewhere else is
/// how a person leaves it, and throwing the edit away at that moment is
/// surprising in a way that losing a sentence you just typed is unforgivable.
class _InlineTitleField extends StatefulWidget {
  const _InlineTitleField({
    required this.initialValue,
    required this.onSubmit,
    required this.onCancel,
  });

  final String initialValue;
  final void Function(String value) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_InlineTitleField> createState() => _InlineTitleFieldState();
}

class _InlineTitleFieldState extends State<_InlineTitleField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final FocusNode _focus = FocusNode();

  /// Guards against submitting twice -- Enter fires `onSubmitted` *and* then
  /// drops focus, and without this the second one sends a redundant PATCH.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_settled) return;
    _settled = true;
    widget.onSubmit(_controller.text);
  }

  void _cancel() {
    if (_settled) return;
    _settled = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(isDense: true),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}

/// The description editor.
///
/// A dialog rather than an inline growing text area: a description is several
/// lines of prose, and an inline editor inside a reorderable row would shove
/// every other row down the screen while it is open, on a phone, mid-thought.
class _DescriptionDialog extends StatefulWidget {
  const _DescriptionDialog({required this.task});

  final Task task;

  @override
  State<_DescriptionDialog> createState() => _DescriptionDialogState();
}

class _DescriptionDialogState extends State<_DescriptionDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.task.description ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Описание задачи'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 6,
        minLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Кто, что, к какому сроку…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          // Pops with null, which the caller reads as "changed nothing" -- as
          // opposed to popping with '', which means "erase the description".
          // Those are the two states `PatchField` exists to keep apart, and this
          // dialog is where the user picks between them.
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// The reminder date under a blocked task.
///
/// Read-only in F3: setting it needs a date picker, which is F4 together with
/// the notification wiring. It is *shown* now because a blocked task whose date
/// has arrived is the one row in the whole app that asks for action today, and
/// the project screen would be the odd one out if the board said so and this
/// did not.
class _ReminderLine extends StatelessWidget {
  const _ReminderLine({required this.task, this.now});

  final Task task;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remindAt = task.remindAt;

    if (remindAt == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Text(
          'Блокер без даты напоминания — дата появится на F4',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final due = isReminderDue(remindAt, now: now);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            due ? Icons.notifications_active : Icons.event,
            size: 15,
            color: due ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          // Flexible, not a bare Text: the row is `mainAxisSize.min`, so an
          // unconstrained Text would size to its natural width and overflow a
          // narrow column instead of ellipsising. A malformed `remindAt` is
          // printed verbatim by `formatReminderDate` (deliberately -- see
          // `domain/reminders.dart`), and that string can be any length at all.
          Flexible(
            child: Text(
              due
                  ? 'Напомнить · ${formatReminderDate(remindAt)}'
                  : 'Ждём до ${formatReminderDate(remindAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: due ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: due ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
