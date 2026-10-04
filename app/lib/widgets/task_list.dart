import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/reminders.dart';
import '../domain/task_age.dart';
import '../domain/task_reorder.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../navigation/app_routes.dart';
import '../providers/focus_providers.dart';
import '../providers/project_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'glance.dart';
import 'mutation_feedback.dart';
import 'overflow_fade_text.dart';

/// The task half of the project screen: rows you can read, and one way to add
/// one (F12).
///
/// ## What went, and why
///
/// The inline composer at the top of this list is gone. It was a one-line
/// `TextField` with a microphone beside it, and it was the literal subject of
/// complaint number one -- "в композере видно два-три слова". The brief is
/// explicit that the new screens must not have one. Adding a task now opens
/// `TaskScreen.draft`, which is the same field the task screen uses -- two
/// lines at least, growing with its text.
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
/// - **Changing a status into `blocked` offers the date immediately.** Left as
///   two gestures the app fills up with dateless blockers -- tasks that are
///   stuck and will never say so again.
///
/// ## Что изменилось в F13: справа в строке — «взять в работу»
///
/// `design/reference/Project.html` ставит на правый край строки мишень «взять в
/// работу» — ровно туда, где до сих пор была ручка перетаскивания. Две мишени
/// 48 px рядом в строке высотой 56 не помещаются, и выбор между ними не стоит
/// обсуждения: набор собирают каждый день, а порядок задач внутри проекта
/// меняют изредка.
///
/// Перетаскивание при этом **не потеряно**: оно переехало на долгое нажатие по
/// тексту строки ([ReorderableDelayedDragStartListener]) — туда же, куда его по
/// умолчанию кладёт сам `ReorderableListView` на тач-устройствах. Это и было
/// предсказано в комментарии F12 («a long press on the row is the obvious home
/// for it»). Долгое нажатие по кружку статуса слева по-прежнему открывает выбор
/// статуса: две разные мишени, два разных долгих нажатия.
///
/// ## Разделы (F15): «в работе», «открытые», «выполнено»
///
/// Список больше не рисуется в серверном порядке одной лентой. Сверху — задачи
/// из набора работы, под ними — открытые (`pending` и `blocked`, в серверном
/// порядке), в самом низу — свёрнутая строка «Выполнено · N». Раньше взятая в
/// работу задача ничем, кроме цвета значка, не отличалась, а сделанные
/// занимали место среди тех, что ещё предстоит сделать.
///
/// **Перетаскивать можно только внутри открытых.** Порядок задач — это порядок
/// «что делать дальше» (`isCurrent` — первая `pending`), и смысл он имеет только
/// для открытых: задачу в работе поставили туда по другой причине, а сделанную
/// переставлять незачем. Перетаскивание *между* разделами значило бы смену
/// статуса или набора жестом, у которого для этого есть свои кнопки. Поэтому
/// открытый раздел — единственный [SliverReorderableList], а его индексы
/// переводятся в индексы всего списка через [mapSectionReorder]: сервер
/// по-прежнему хранит один порядок на проект.
///
/// Раздел «выполнено» свёрнут при каждом входе на экран и не запоминается:
/// история проекта нужна изредка, а открывать экран ради неё каждый раз —
/// нет.
class TaskListView extends ConsumerStatefulWidget {
  const TaskListView({
    required this.projectId,
    required this.projectName,
    required this.tasks,
    this.highlightTaskId,
    this.now,
    super.key,
  });

  final String projectId;

  /// Имя проекта — для оптимистичной строки набора: экран работы подписывает им
  /// каждую задачу, а `GET /focus` пришлёт настоящее кругом позже.
  final String projectName;

  /// In server order. Never re-sorted -- see [Task.position].
  final List<Task> tasks;

  /// A task to draw attention to, from a caller that was about one specific
  /// task (F4: a reminder). See `navigation/app_routes.dart`.
  final String? highlightTaskId;

  /// Fixes "today" for tests, threaded to [isReminderDue].
  final DateTime? now;

  @override
  ConsumerState<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<TaskListView> {
  /// Свёрнут при каждом входе — см. заметку к [TaskListView].
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks;
    final sections = TaskSections.of(tasks, ref.watch(focusedTaskIdsProvider));

    // A heading is worth its line only when there is another section to tell
    // this one apart from.
    final labelled = sections.inWork.isNotEmpty || sections.done.isNotEmpty;

    Widget padded(Widget sliver) => SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
      sliver: sliver,
    );

    Widget row(Task task, {int index = 0, bool reorderable = false}) =>
        Padding(
          // Keyed by id for the reorder animation.
          key: ValueKey<String>(task.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: TaskRow(
            projectId: widget.projectId,
            projectName: widget.projectName,
            task: task,
            index: index,
            reorderable: reorderable,
            inWork: sections.inWork.contains(task),
            isHighlighted: task.id == widget.highlightTaskId,
            now: widget.now,
          ),
        );

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(projectTasksProvider(widget.projectId).notifier).refresh(),
      // A CustomScrollView rather than `ReorderableListView`: only one of the
      // three sections is draggable, and a [SliverReorderableList] inside the
      // one scrollable keeps what the old list had -- scrolling, pull to
      // refresh and auto-scroll near the edge during a drag.
      child: CustomScrollView(
        // The list must scroll even when it is shorter than the viewport, or
        // pull-to-refresh on a two-task project does nothing.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (sections.inWork.isNotEmpty) ...<Widget>[
            padded(
              const SliverToBoxAdapter(
                child: _SectionLabel('В РАБОТЕ', colour: AppColors.indigoLink),
              ),
            ),
            padded(
              SliverList.list(
                children: <Widget>[
                  for (final task in sections.inWork) row(task),
                ],
              ),
            ),
          ],
          if (sections.open.isNotEmpty) ...<Widget>[
            if (labelled)
              padded(
                const SliverToBoxAdapter(
                  child: _SectionLabel('ОТКРЫТЫЕ', colour: AppColors.muted),
                ),
              ),
            padded(
              SliverReorderableList(
                itemCount: sections.open.length,
                itemBuilder: (context, index) => row(
                  sections.open[index],
                  index: index,
                  reorderable: true,
                ),
                proxyDecorator: _liftedRow,
                onReorder: (oldIndex, newIndex) {
                  final full = mapSectionReorder(
                    sections.openIndices,
                    oldIndex,
                    newIndex,
                  );
                  if (full == null) return;
                  // No `await`, no error handling here: `move` is optimistic,
                  // so the list has already settled into its new order by the
                  // time this returns, and a failure rolls it back and reports
                  // itself.
                  runMutation(
                    context,
                    () => ref
                        .read(projectTasksProvider(widget.projectId).notifier)
                        .move(full.$1, full.$2),
                    failure: 'Не удалось сохранить порядок задач.',
                  );
                },
              ),
            ),
          ],

          // After the open tasks rather than at the very end: "and one more"
          // belongs where the open work ends, not under the history.
          padded(
            SliverToBoxAdapter(
              child: Column(
                children: <Widget>[
                  if (tasks.isEmpty) const _NoTasksYet(),
                  _AddTaskButton(projectId: widget.projectId),
                ],
              ),
            ),
          ),

          if (sections.done.isNotEmpty) ...<Widget>[
            padded(
              SliverToBoxAdapter(
                child: _DoneToggle(
                  count: sections.done.length,
                  expanded: _showDone,
                  onTap: () => setState(() => _showDone = !_showDone),
                ),
              ),
            ),
            if (_showDone)
              padded(
                SliverList.list(
                  children: <Widget>[
                    for (final task in sections.done) row(task),
                  ],
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// The row being dragged, lifted off the list. `ReorderableListView` drew this
/// itself; a bare [SliverReorderableList] leaves it to the caller.
Widget _liftedRow(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Material(
      color: Colors.transparent,
      elevation: 6 * Curves.easeOut.transform(animation.value),
      shadowColor: const Color(0x331B2050),
      borderRadius: BorderRadius.circular(Radii.card),
      child: child,
    ),
    child: child,
  );
}

/// The project's tasks, split the way the screen draws them.
///
/// - [inWork]: in the Work-mode focus set and not done, in server order;
/// - [open]: every other task that is not done (`pending` and `blocked`), in
///   server order, with [openIndices] their indices in the full list;
/// - [done]: done, in server order.
///
/// A done task that is somehow still in the set (the server drops it in the
/// same transaction, but the set is re-read a moment later) is done first: the
/// struck-through row belongs with the history, not at the top.
class TaskSections {
  const TaskSections._({
    required this.inWork,
    required this.open,
    required this.openIndices,
    required this.done,
  });

  factory TaskSections.of(List<Task> tasks, Set<String> focused) {
    final inWork = <Task>[];
    final open = <Task>[];
    final openIndices = <int>[];
    final done = <Task>[];
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (task.status == TaskStatus.done) {
        done.add(task);
      } else if (focused.contains(task.id)) {
        inWork.add(task);
      } else {
        open.add(task);
        openIndices.add(i);
      }
    }
    return TaskSections._(
      inWork: inWork,
      open: open,
      openIndices: openIndices,
      done: done,
    );
  }

  final List<Task> inWork;
  final List<Task> open;
  final List<int> openIndices;
  final List<Task> done;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
      child: Text(
        text,
        style: AppText.sectionLabel.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: colour,
        ),
      ),
    );
  }
}

/// "Выполнено · N" with a chevron: the done section, folded.
class _DoneToggle extends StatelessWidget {
  const _DoneToggle({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        button: true,
        expanded: expanded,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.card),
          child: SizedBox(
            height: Targets.minimum,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Выполнено · $count',
                  style: AppText.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
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
    required this.projectName,
    required this.task,
    required this.index,
    this.reorderable = true,
    this.inWork = false,
    this.isHighlighted = false,
    this.now,
    super.key,
  });

  final String projectId;
  final String projectName;
  final Task task;

  /// Position inside the enclosing [SliverReorderableList]; meaningless when
  /// [reorderable] is false.
  final int index;

  /// Whether a long press on the text starts a drag. Only the open section's
  /// rows are -- see [TaskListView].
  final bool reorderable;

  /// Drawn in the "в работе" section: an indigo border, which is what makes
  /// the section read as a different kind of row rather than a heading.
  final bool inWork;
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

    final title = OverflowFadeText(
      task.title,
      maxLines: 3,
      style: (current ? AppText.taskTitleCurrent : AppText.taskTitle).copyWith(
        // Struck through rather than hidden: a done task is still part of the
        // record of what happened here.
        decoration: done ? TextDecoration.lineThrough : null,
        color: done ? AppColors.muted : null,
      ),
    );

    final body = InkWell(
      onTap: _unconfirmed
          ? null
          : () => AppRoutes.openTask(
              context,
              projectId: projectId,
              taskId: task.id,
            ),
      child: Container(
        constraints: BoxConstraints(
          minHeight: done ? Targets.minimum : Targets.row,
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: title),
                // No second line to put it on, so it rides at the end of the
                // title -- and never wraps or shrinks. See `widgets/glance.dart`.
                // Not on a done row: how long a finished task sat still is not
                // a question anyone asks.
                if (!current && !blocked && !done) ...<Widget>[
                  const SizedBox(width: 10),
                  AgeChip(days: age, showIcon: false),
                ],
              ],
            ),
            if (current) ...<Widget>[
              const SizedBox(height: 6),
              _Meta(
                icon: Icons.arrow_forward,
                text: _reminderSuffix('следующая', task, now),
                colour: AppColors.indigoLink,
              ),
            ] else if (!blocked && !done && task.remindAt != null) ...<Widget>[
              const SizedBox(height: 6),
              _Meta(
                icon: Icons.notifications_none,
                text: _reminderSuffix('', task, now),
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
    );

    return Container(
      decoration: BoxDecoration(
        // A done row is a line of history, not a card: no fill, no border, the
        // same as the reference's done list.
        color: done
            ? Colors.transparent
            : blocked
            ? AppColors.waitingFill
            : AppColors.card,
        border: Border.all(
          color: isHighlighted
              ? AppColors.indigoLink
              : inWork
              ? AppColors.indigo
              : done
              ? Colors.transparent
              : blocked
              ? AppColors.waitingLine
              // The current task carries a heavier border rather than a tint:
              // it is the sentence that restores the context, and a tint alone
              // disappears at a glance in sunlight.
              : current
              ? AppColors.lineStrong
              : AppColors.line,
          width: isHighlighted
              ? 2
              : inWork
              ? 1.5
              : 1,
        ),
        borderRadius: BorderRadius.circular(Radii.card),
        // `Project.html` gives the current row `0 1px 2px rgba(27,32,80,0.06)`
        // and nothing else on the screen a shadow. The heavier border above was
        // carrying that job alone, and against `#DEDEE8` one step of grey is
        // not enough to find the row without reading it -- which is the whole
        // point of marking it.
        boxShadow: current && !blocked && !isHighlighted
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0F1B2050),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _StatusTarget(
            projectId: projectId,
            projectName: projectName,
            task: task,
            enabled: !_unconfirmed,
            now: now,
          ),
          Expanded(
            // Долгое нажатие по тексту — перетаскивание. Задержанный слушатель,
            // а не обычный: обычный забирал бы жест у прокрутки списка.
            child: reorderable
                ? ReorderableDelayedDragStartListener(
                    enabled: !_unconfirmed,
                    index: index,
                    child: body,
                  )
                : body,
          ),
          if (done)
            // Nothing to take into work: the server drops a finished task from
            // the set, so the target would be a button that undoes itself.
            const SizedBox(width: 12)
          else if (_unconfirmed)
            const SizedBox(
              width: Targets.minimum,
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
            _FocusTarget(task: task, projectName: projectName),
        ],
      ),
    );
  }
}

/// Мишень справа в строке: взять задачу в работу или убрать из набора.
///
/// Два кольца — тот же значок, которым в приложении обозначен режим работы
/// (`Icons.adjust`, нижняя панель и левый рельс).
///
/// ## Почему взятая задача — плашка, а не цвет (F15)
///
/// До F15 два состояния отличались только цветом значка, чернила против
/// второго плана, и человек так и не заметил, что кнопка что-то делает. Теперь
/// невзятая задача — контурное кольцо на 44 px мишени, а взятая — залитая
/// индиго плашка «В работе» со словом: состояние читается без сравнения с
/// соседней строкой. Нажатие подтверждается снэкбаром, потому что строка при
/// этом уезжает в другой раздел списка и без слов это выглядит как пропажа.
///
/// Предела в пять здесь нет. Пять — правило экрана сбора, где видно весь набор
/// сразу; здесь, внутри одного проекта, видно одну строку, и отказ «уже пять»
/// был бы сообщением про экран, которого человек не видит. Набор из шести,
/// собранный так, — это прокручивающийся экран работы, и он это переживёт.
class _FocusTarget extends ConsumerWidget {
  const _FocusTarget({required this.task, required this.projectName});

  final Task task;
  final String projectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inFocus = ref.watch(focusedTaskIdsProvider).contains(task.id);

    return Tooltip(
      message: inFocus ? 'Убрать из набора' : 'Взять в работу',
      child: inFocus
          ? Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: SizedBox(
                height: Targets.minimum,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => unawaited(_toggle(context, ref, inFocus)),
                  child: const Center(child: FocusPill()),
                ),
              ),
            )
          : InkWell(
              customBorder: const CircleBorder(),
              onTap: () => unawaited(_toggle(context, ref, inFocus)),
              child: const SizedBox(
                width: Targets.minimum,
                height: Targets.row,
                child: Icon(Icons.adjust, size: 20, color: AppColors.muted),
              ),
            ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool inFocus) async {
    // Both resolved before the await: the row moves to another section the
    // moment the optimistic write lands, and this element goes with it.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final notifier = ref.read(focusSetProvider.notifier);

    final ok = await runMutation(
      context,
      () => inFocus
          ? notifier.drop(task.id)
          : notifier.take(task, projectName: projectName),
      failure: inFocus
          ? 'Не удалось убрать задачу из набора.'
          : 'Не удалось взять задачу в работу.',
    );
    if (!ok || !messenger.mounted) return;

    if (inFocus) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Убрана из работы')));
      return;
    }
    _offerUndo(
      messenger,
      'Взята в работу',
      () => container.read(focusSetProvider.notifier).drop(task.id),
    );
  }
}

/// «В работе» on indigo: the in-focus state of the row's right-hand target.
///
/// Public so that tests (and any other list that shows the set) can find the
/// one shape that means "this task is in today's set".
class FocusPill extends StatelessWidget {
  const FocusPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const ShapeDecoration(
        color: AppColors.indigo,
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.adjust, size: 14, color: AppColors.onInk),
          const SizedBox(width: 5),
          Text(
            'В работе',
            style: AppText.chip.copyWith(color: AppColors.onInk),
          ),
        ],
      ),
    );
  }
}

/// A confirmation with "Отменить" on it.
///
/// [undo] is run through the [ProviderContainer] rather than a widget's `ref`:
/// by the time anyone taps the action, the row that offered it has moved to a
/// different section and its element is gone.
void _offerUndo(
  ScaffoldMessengerState messenger,
  String message,
  Future<void> Function() undo,
) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        // Since Flutter 3.3x a snackbar with an action stays until dismissed
        // unless told otherwise. A confirmation that never leaves is noise.
        persist: false,
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => unawaited(() async {
            try {
              await undo();
            } catch (error) {
              if (!messenger.mounted) return;
              messenger
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      'Не удалось отменить. ${describeApiError(error)}',
                    ),
                  ),
                );
            }
          }()),
        ),
      ),
    );
}

/// [lead] followed by the reminder date of an open, unblocked row
/// ("следующая · 23.09", "пора · 23.09"); just [lead] when there is no date.
String _reminderSuffix(String lead, Task task, DateTime? now) {
  final remindAt = task.remindAt;
  if (remindAt == null) return lead;
  final date = formatReminderDate(remindAt);
  final label = isReminderDue(remindAt, now: now) ? 'пора · $date' : date;
  return lead.isEmpty ? label : '$lead · $label';
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
///
/// ## The check plays *before* the write (F15)
///
/// Since the list has sections, a task marked done leaves the open section for
/// the folded "Выполнено" the moment the optimistic write lands -- so an
/// animation played after it would be played on a row nobody can see any more.
/// The circle therefore fills and pops first (~a quarter of a second), and only
/// then is the status sent. What follows is "Сделано · Отменить", because a
/// row that vanishes on a tap needs a way back that does not involve finding
/// it in the history.
class _StatusTarget extends ConsumerStatefulWidget {
  const _StatusTarget({
    required this.projectId,
    required this.projectName,
    required this.task,
    required this.enabled,
    required this.now,
  });

  final String projectId;
  final String projectName;
  final Task task;
  final bool enabled;
  final DateTime? now;

  @override
  ConsumerState<_StatusTarget> createState() => _StatusTargetState();
}

class _StatusTargetState extends ConsumerState<_StatusTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  /// 1 -> 0.8 -> 1.15 -> 1: pressed in, then the check lands.
  late final Animation<double> _scale = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: Tween(begin: 1, end: 0.8), weight: 30),
      TweenSequenceItem<double>(tween: Tween(begin: 0.8, end: 1.15), weight: 40),
      TweenSequenceItem<double>(tween: Tween(begin: 1.15, end: 1), weight: 30),
    ],
  ).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));

  /// True while the check is showing ahead of the write.
  bool _completing = false;

  Task get task => widget.task;

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _completing ? TaskStatus.done : task.status;
    final circle = switch (shown) {
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
        TaskStatus.done => 'Сделана — открыть снова',
        TaskStatus.blocked => 'Блокер — снять',
        TaskStatus.pending => 'Отметить сделанной',
      },
      child: InkWell(
        onTap: widget.enabled && !_completing
            ? () => unawaited(
                _commit(
                  task.status == TaskStatus.done
                      ? TaskStatus.pending
                      : TaskStatus.done,
                ),
              )
            : null,
        onLongPress: widget.enabled && !_completing
            ? () => unawaited(_choose())
            : null,
        child: SizedBox(
          width: 48,
          height: Targets.row,
          child: Center(
            child: ScaleTransition(scale: _scale, child: circle),
          ),
        ),
      ),
    );
  }

  Future<void> _commit(TaskStatus next) async {
    final previous = task;
    // Resolved up front: once the status lands, this row lives in another
    // section and this element is gone -- see [_offerUndo].
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final wasInFocus = ref.read(focusedTaskIdsProvider).contains(task.id);

    if (next == TaskStatus.done) {
      setState(() => _completing = true);
      await _pop.forward(from: 0);
      if (!mounted) return;
    }

    final ok = await setTaskStatus(
      context,
      ref,
      projectId: widget.projectId,
      task: previous,
      status: next,
    );
    if (mounted && _completing) setState(() => _completing = false);
    if (!ok || next != TaskStatus.done || !messenger.mounted) return;

    _offerUndo(
      messenger,
      'Сделано',
      () => _restore(
        container,
        projectId: widget.projectId,
        projectName: widget.projectName,
        previous: previous,
        wasInFocus: wasInFocus,
      ),
    );
  }

  Future<void> _choose() async {
    final chosen = await showModalBottomSheet<TaskStatus>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final status in taskStatusOrder)
              ListTile(
                leading: Icon(switch (status) {
                  TaskStatus.pending => Icons.circle_outlined,
                  TaskStatus.blocked => Icons.pause_circle_outline,
                  TaskStatus.done => Icons.check_circle_outline,
                }),
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
    if (chosen == null || chosen == task.status || !mounted) return;
    await _commit(chosen);
  }
}

/// Puts a task back the way it was before "сделано": its status, the reminder
/// date that closing it cleared, and its place in the focus set that
/// closing it cost it on the server.
///
/// Not [setTaskStatus]: that one needs a live `BuildContext` and `WidgetRef`,
/// and the row that offered the undo has been disposed by the time anyone taps
/// it. It would also ask for a date, which is the opposite of restoring one.
Future<void> _restore(
  ProviderContainer container, {
  required String projectId,
  required String projectName,
  required Task previous,
  required bool wasInFocus,
}) async {
  final tasks = container.read(projectTasksProvider(projectId).notifier);

  Task? fresh() => container
      .read(projectTasksProvider(projectId))
      .value
      ?.where((row) => row.id == previous.id)
      .firstOrNull;

  final now = fresh();
  if (now == null) return;
  await tasks.setStatus(now, previous.status);

  final remindAt = previous.remindAt;
  if (previous.status != TaskStatus.done &&
      remindAt != null &&
      remindAt.length >= 10) {
    final reopened = fresh();
    if (reopened != null && reopened.status != TaskStatus.done) {
      // The `YYYY-MM-DD` prefix is the calendar date; see [calendarDateForApi].
      await tasks.setRemindAt(reopened, remindAt.substring(0, 10));
    }
  }

  if (wasInFocus) {
    final reopened = fresh();
    if (reopened != null) {
      await container
          .read(focusSetProvider.notifier)
          .take(reopened, projectName: projectName);
    }
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
  TaskStatus.pending: 'Открыта',
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
///
/// Returns whether the status write itself succeeded (the date that may follow
/// is its own write, reported on its own).
Future<bool> setTaskStatus(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required Task task,
  required TaskStatus status,
}) async {
  final wasBlocked = task.status == TaskStatus.blocked;
  final hadDate = task.remindAt != null;

  // Читаем до записи: после неё задача может уже покинуть набор, и спросить
  // «была ли она там» будет не у кого.
  final wasInFocus = ref.read(focusedTaskIdsProvider).contains(task.id);
  // И сам набор тоже до записи: строка, из которой это вызвано, после неё
  // может переехать в другой раздел списка (F15), и её `ref` умрёт вместе с
  // ней.
  final focus = ref.read(focusSetProvider.notifier);

  final ok = await runMutation(
    context,
    () => ref
        .read(projectTasksProvider(projectId).notifier)
        .setStatus(task, status),
    failure: 'Не удалось изменить статус.',
  );
  if (!ok) return false;

  /*
   * Набор мог измениться от этой записи, и не по своей воле: закрытая задача
   * выходит из него **на сервере**, в той же транзакции
   * (`backend/src/domain/taskEvents.ts` — `leavesFocus`), именно чтобы телефону
   * не пришлось досылать второй запрос. Клиент об этом узнать может только
   * перечитав набор; блокер из набора не выводит, но меняет то, как строка в нём
   * выглядит, поэтому перечитываем в обоих случаях.
   *
   * Только для задачи, которая в наборе была: у остальных (то есть почти у всех)
   * это стоило бы лишнего запроса на каждое «сделано».
   */
  if (wasInFocus) {
    unawaited(focus.refresh());
  }

  if (!context.mounted) return true;
  if (status != TaskStatus.blocked || wasBlocked || hadDate) return true;

  // Read fresh: `task` is the row from before the status change, and
  // `setRemindAt` refuses a row that is not blocked.
  final rows = ref.read(projectTasksProvider(projectId)).value;
  final fresh = rows?.where((row) => row.id == task.id).firstOrNull;
  if (fresh == null) return true;

  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
    helpText: 'Когда напомнить',
    cancelText: 'Отмена',
    confirmText: 'Готово',
  );
  if (picked == null || !context.mounted) return true;

  await runMutation(
    context,
    () => ref
        .read(projectTasksProvider(projectId).notifier)
        .setRemindAt(fresh, calendarDateForApi(picked)),
    failure: 'Не удалось сохранить дату напоминания.',
  );
  return true;
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
