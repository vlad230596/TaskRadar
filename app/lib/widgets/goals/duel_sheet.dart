import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/goals.dart';
import '../../models/goal.dart';
import '../../models/task.dart';
import '../../providers/focus_providers.dart';
import '../../providers/goal_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../mutation_feedback.dart';
import 'goal_icons.dart';

/// The duel (`design/goals-ideas-contract.md`, «Дуэль»;
/// `design/goals-ideas-spec.md`, п. 3): taking into work a task that serves
/// no goal of the active contour, while a goal of that contour has a next
/// step not yet in the set, first asks «Что берём?» -- this task, or the
/// goal's step. The choice is the owner's.

/// What a take ended with.
enum TakeOutcome {
  /// Nothing was taken (cancelled, or the write failed).
  none,

  /// The task itself.
  task,

  /// A goal's step instead.
  step,
}

/// The duel's answer.
enum DuelChoice { step, task }

/// The goals whose step would duel [task] right now (see [duelGoals]).
List<GoalView> duelCandidates(
  WidgetRef ref, {
  required String taskId,
  required List<TaskGoalRef> taskGoals,
}) {
  final set = ref.read(activeFocusSetProvider).value ?? const [];
  return duelGoals(
    taskId: taskId,
    taskGoals: goalsOfTask(ref.read(taskGoalIndexProvider), taskId, taskGoals),
    activeContourId: ref.read(activeContourIdProvider),
    goals: ref.read(goalListProvider),
    activeSetIds: <String>{for (final row in set) row.id},
    setSize: set.length,
    setLimit: kFocusSlots,
  );
}

/// Takes [task] into the active contour's set -- through the duel when the
/// rule says so. Every place a task can be put into the set calls this.
Future<TakeOutcome> takeIntoWork(
  BuildContext context,
  WidgetRef ref, {
  required Task task,
  required String projectName,
}) async {
  final notifier = ref.read(focusSetProvider.notifier);
  final candidates = duelCandidates(
    ref,
    taskId: task.id,
    taskGoals: task.goals,
  );
  if (candidates.isNotEmpty) {
    final messenger = ScaffoldMessenger.of(context);
    final answer = await showDuel(
      context,
      goals: candidates,
      taskTitle: task.title,
      projectName: projectName,
    );
    if (answer == null || !context.mounted) return TakeOutcome.none;
    if (answer.choice == DuelChoice.step) {
      final step = answer.goal.nextStep!;
      final ok = await runMutation(
        context,
        () => notifier.takeStep(step),
        failure: 'Не удалось взять шаг в работу.',
      );
      if (!ok) return TakeOutcome.none;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('В работе: ${step.title}')));
      return TakeOutcome.step;
    }
  }
  if (!context.mounted) return TakeOutcome.none;
  final ok = await runMutation(
    context,
    () => notifier.take(task, projectName: projectName),
    failure: 'Не удалось взять задачу в работу.',
  );
  return ok ? TakeOutcome.task : TakeOutcome.none;
}

/// The sheet itself. Null when dismissed (the cross, a swipe): nothing is
/// taken.
Future<({DuelChoice choice, GoalView goal})?> showDuel(
  BuildContext context, {
  required List<GoalView> goals,
  required String taskTitle,
  required String projectName,
}) {
  return showModalBottomSheet<({DuelChoice choice, GoalView goal})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.voiceBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
    ),
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: DuelSheet(
        goals: goals,
        taskTitle: taskTitle,
        projectName: projectName,
      ),
    ),
  );
}

/// «Что берём?». Public for the widget tests.
class DuelSheet extends StatefulWidget {
  const DuelSheet({
    required this.goals,
    required this.taskTitle,
    required this.projectName,
    super.key,
  });

  final List<GoalView> goals;
  final String taskTitle;
  final String projectName;

  @override
  State<DuelSheet> createState() => _DuelSheetState();
}

class _DuelSheetState extends State<DuelSheet> {
  int _index = 0;

  GoalView get _goal => widget.goals[_index % widget.goals.length];

  void _answer(DuelChoice choice) =>
      Navigator.of(context).pop((choice: choice, goal: _goal));

  @override
  Widget build(BuildContext context) {
    final goal = _goal;
    final step = goal.nextStep!;
    final other = widget.goals.length > 1
        ? widget.goals[(_index + 1) % widget.goals.length]
        : null;
    final left = windowLeftLabel(goal.windowEndsAt);
    final meta = <String>[
      step.projectName,
      if (goal.stepNumber != null)
        'шаг ${goal.stepNumber} из ${goal.tasks.length}',
      ?left,
    ].join(' · ');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.voiceLine,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Что берём?',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 19,
                      color: AppColors.voiceInk,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    tooltip: 'Отмена',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.voiceMuted),
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'У цели есть шаг, которого нет в наборе.',
            style: TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: AppColors.voiceMuted,
            ),
          ),
          const SizedBox(height: 18),
          // The goal: glowing, first and largest.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.goalRaised, AppColors.goalEnd],
              ),
              border: Border.all(color: const Color(0x73FFC94D), width: 1.5),
              borderRadius: BorderRadius.circular(Radii.goal),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text('ЦЕЛЬ', style: AppText.goalLabel),
                    const SizedBox(width: 8),
                    const CrownIcon(size: 14, color: AppColors.crown),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        goal.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.voiceBright,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  step.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.duelStep,
                ),
                if ((goal.why ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: AppColors.crown, width: 3),
                      ),
                    ),
                    child: Text(
                      goal.why!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w500,
                        fontSize: 14.5,
                        height: 1.35,
                        color: AppColors.voiceBright,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppColors.voiceMuted,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: () => _answer(DuelChoice.step),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.onInk,
                      foregroundColor: AppColors.voiceBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    icon: const CrownIcon(
                      size: 20,
                      color: AppColors.voiceBackground,
                    ),
                    label: const Text('Беру шаг цели'),
                  ),
                ),
              ],
            ),
          ),
          if (other != null)
            InkWell(
              onTap: () => setState(() => _index++),
              child: SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Другая цель: ${other.title} →',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: AppColors.voiceBright,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Row(
            children: <Widget>[
              Expanded(child: Divider(color: AppColors.voiceLine, height: 1)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'или',
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.voiceMuted,
                  ),
                ),
              ),
              Expanded(child: Divider(color: AppColors.voiceLine, height: 1)),
            ],
          ),
          const SizedBox(height: 14),
          // The task asked for.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.voiceWell,
              border: Border.all(color: AppColors.voiceLine),
              borderRadius: BorderRadius.circular(Radii.panel),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 28,
                    maxWidth: 220,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.railActive,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    widget.projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.voiceBright,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.taskTitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w500,
                    fontSize: 17,
                    height: 1.35,
                    color: AppColors.voiceInk,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => _answer(DuelChoice.task),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: AppColors.voiceBright,
                      side: const BorderSide(color: AppColors.voiceLine),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    child: const Text('Всё равно эту'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
