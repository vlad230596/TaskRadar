import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../api/api_exception.dart';
import '../../domain/goals.dart';
import '../../models/goal.dart';
import '../../models/task.dart';
import '../../navigation/goal_routes.dart';
import '../../providers/goal_providers.dart';
import '../../theme/tokens.dart';
import '../goals/crown.dart';
import '../goals/goal_icons.dart';
import '../goals/goal_picker_sheet.dart';
import 'attribute_bar.dart';
import 'editor_theme.dart';

/// The task editor's «Цели» (`design/goals-ideas-spec.md`, п. 6;
/// `design/reference/Edit-Goals.html`): a chip second in the attribute row,
/// and a section of the goals the task serves.
///
/// Goal writes are online-only (the contract): on an existing task a link or
/// an unlink is sent at once, like a checklist tick -- it is an action, not
/// an edit of text waiting for «Сохранить». On a new task the chosen goals
/// are held by the editor ([EditorGoals]) and linked once the server has the
/// task.

/// The goals chosen for a task that does not exist yet.
class EditorGoals extends ChangeNotifier {
  final Set<String> _ids = <String>{};

  Set<String> get ids => Set<String>.unmodifiable(_ids);

  bool get isEmpty => _ids.isEmpty;

  set ids(Set<String> value) {
    _ids
      ..clear()
      ..addAll(value);
    notifyListeners();
  }

  void remove(String id) {
    if (_ids.remove(id)) notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}

/// The goals to show for [task] (live), or for a new task its held [pending].
List<TaskGoalRef> editorTaskGoals(
  WidgetRef ref, {
  required Task? task,
  required EditorGoals pending,
}) {
  if (task != null) return watchTaskGoals(ref, task.id, task.goals);
  final goals = ref.watch(goalListProvider);
  return <TaskGoalRef>[
    for (final goal in goals)
      if (pending.ids.contains(goal.id))
        TaskGoalRef(id: goal.id, title: goal.title, contourId: goal.contourId),
  ];
}

/// The chip's label: «+ Цель», the goal's title, or «2 цели».
String goalChipLabel(List<TaskGoalRef> goals) {
  if (goals.isEmpty) return '+ Цель';
  if (goals.length == 1) return goals.single.title;
  return '${goals.length} ${goalsWord(goals.length)}';
}

/// The chip in the attribute row.
class GoalsChip extends ConsumerWidget {
  const GoalsChip({required this.task, required this.pending, super.key});

  final Task? task;
  final EditorGoals pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = editorTaskGoals(ref, task: task, pending: pending);
    final set = goals.isNotEmpty;
    return AttributeChip(
      icon: Icons.flag_outlined,
      leading: CrownIcon(
        size: 15,
        color: set ? AppColors.crown : AppColors.crownMuted,
      ),
      label: goalChipLabel(goals),
      filled: set,
      tooltip: 'Цели',
      onTap: () => unawaited(
        pickEditorGoals(context, ref, task: task, pending: pending),
      ),
    );
  }
}

/// «Связать с целью»: the picker, then the links (existing task) or the held
/// choice (new task).
Future<void> pickEditorGoals(
  BuildContext context,
  WidgetRef ref, {
  required Task? task,
  required EditorGoals pending,
}) async {
  if (task == null) {
    final chosen = await showGoalPicker(context, initial: pending.ids);
    if (chosen != null) pending.ids = chosen;
    return;
  }
  final current = goalsOfTask(
    ref.read(taskGoalIndexProvider),
    task.id,
    task.goals,
  );
  await linkTaskToGoals(
    context,
    ref,
    taskId: task.id,
    current: <String>{for (final goal in current) goal.id},
  );
}

/// What to say when a goal write fails: a missing network is named as such,
/// since goals have no offline queue.
String goalWriteFailure(String what, Object error) {
  if (error is NetworkException) {
    return 'Нужна сеть: цели меняются только онлайн.';
  }
  return '$what ${describeApiError(error)}';
}

/// Links a just-created task to the goals held for it. A task still in the
/// outbox has no server id yet, so its goals cannot be linked -- said so.
Future<void> linkCreatedTask(
  ScaffoldMessengerState messenger,
  Goals goals, {
  required String? taskId,
  required bool queued,
  required Set<String> goalIds,
}) async {
  if (goalIds.isEmpty) return;
  if (queued || taskId == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Цели — после отправки задачи: задача пока на телефоне, '
          'привяжите её к цели, когда уйдёт.',
        ),
      ),
    );
    return;
  }
  try {
    for (final id in goalIds) {
      await goals.linkTask(id, taskId);
    }
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(goalWriteFailure('Не удалось связать с целью.', error)),
      ),
    );
  }
}

/// The section «ЦЕЛИ»: not drawn while the task serves no goal (the editor's
/// "секции не рисуются пустыми"); the chip is the way in.
class GoalsSection extends ConsumerWidget {
  const GoalsSection({required this.task, required this.pending, super.key});

  final Task? task;
  final EditorGoals pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = editorTaskGoals(ref, task: task, pending: pending);
    if (goals.isEmpty) return const SizedBox.shrink();
    final active = ref.watch(activeContourIdProvider);
    final contours = <String, String>{
      for (final contour in ref.watch(contourListProvider))
        contour.id: contour.name,
    };
    final views = <String, GoalView>{
      for (final goal in ref.watch(goalListProvider)) goal.id: goal,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const EditorSectionLabel('ЦЕЛИ'),
          const SizedBox(height: 6),
          for (final goal in goals) ...<Widget>[
            _GoalRow(
              goal: goal,
              view: views[goal.id],
              taskId: task?.id,
              contourName: contours[goal.contourId],
              bright: active == null || goal.contourId == active,
              onUnlink: () => unawaited(_unlink(context, ref, goal)),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(
                pickEditorGoals(context, ref, task: task, pending: pending),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Связать с целью'),
              style: TextButton.styleFrom(
                foregroundColor: EditorColors.bright,
                minimumSize: const Size(0, Targets.minimum),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    TaskGoalRef goal,
  ) async {
    final task = this.task;
    if (task == null) {
      pending.remove(goal.id);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(goalsProvider.notifier).unlinkTask(goal.id, task.id);
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              goalWriteFailure('Не удалось отвязать от цели.', error),
            ),
          ),
        );
    }
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.goal,
    required this.view,
    required this.taskId,
    required this.contourName,
    required this.bright,
    required this.onUnlink,
  });

  final TaskGoalRef goal;
  final GoalView? view;
  final String? taskId;
  final String? contourName;
  final bool bright;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final view = this.view;
    final isStep = taskId != null && view?.nextStep?.id == taskId;
    final index = taskId == null || view == null
        ? -1
        : view.tasks.indexWhere((task) => task.id == taskId);
    final String? where = isStep
        ? null
        : index >= 0
        ? 'шаг ${index + 1} из ${view!.tasks.length}'
        : null;

    const meta = TextStyle(
      fontFamily: AppFonts.text,
      fontWeight: FontWeight.w600,
      fontSize: 12,
      color: EditorColors.muted,
    );
    final parts = <InlineSpan>[
      if (contourName != null) TextSpan(text: contourName),
      if (contourName != null && (isStep || where != null))
        const TextSpan(text: ' · '),
      if (isStep)
        const TextSpan(
          text: 'следующий шаг',
          style: TextStyle(color: AppColors.crown),
        ),
      if (where != null) TextSpan(text: where),
    ];

    return Material(
      color: EditorColors.well,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(openGoal(context, goal.id)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 12),
              CrownChip(
                bright: bright,
                onDark: true,
                size: 26,
                iconSize: 15,
                radius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        goal.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: EditorColors.ink,
                        ),
                      ),
                      if (parts.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(style: meta, children: parts),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Tooltip(
                message: 'Отвязать',
                child: InkResponse(
                  radius: 22,
                  onTap: onUnlink,
                  child: const SizedBox(
                    width: Targets.minimum,
                    height: Targets.minimum,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: EditorColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
