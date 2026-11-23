import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/goals.dart';
import '../../models/goal.dart';
import '../../models/task_status.dart';
import '../../navigation/app_routes.dart';
import '../../navigation/goal_routes.dart';
import '../../providers/focus_providers.dart';
import '../../providers/goal_providers.dart';
import '../../screens/goals_screen.dart'
    show
        ExpiredGoalActions,
        GoalProgressSegments,
        DashedRRectPainter,
        goalGradient,
        goalShadow;
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../mutation_feedback.dart';
import 'crown.dart';
import 'goal_icons.dart';
import 'goal_link_sheet.dart';

/// The goal block of the work mode (`design/goals-ideas-spec.md`, п. 2;
/// `design/reference/Focus-Goals.html`, `Desk-Focus-Goals.html`): the active
/// contour's goals in slots -- title, why, progress, the window's end and the
/// next step to take -- above the set, and the other contours' goals folded
/// into one line under it.
///
/// What the block shows when there is nothing in the slots:
///
/// - goals on the bench only: the dashed «Слоты свободны · Поставить цель»;
/// - no goals in this contour at all (owner's decision, 24.11): no block, only
///   a small «Цели» entry to the goals screen;
/// - contours unknown (an older server, a failed read): nothing at all.

/// The active contour's goals in slots, in their order.
List<GoalView> _slotted(List<GoalView> goals, String contourId) => <GoalView>[
  for (final goal in goals)
    if (goal.contourId == contourId && goal.inSlot) goal,
];

/// Phone: the block (or its empty forms) and the other contours' line.
class WorkGoals extends ConsumerWidget {
  const WorkGoals({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeContourProvider);
    if (active == null) return const SizedBox.shrink();
    final goals = ref.watch(goalListProvider);
    final slotted = _slotted(goals, active.id);
    final anyInContour = goals.any((goal) => goal.contourId == active.id);

    final Widget top;
    if (slotted.isNotEmpty) {
      top = Container(
        margin: const EdgeInsets.fromLTRB(Insets.gutter, 4, Insets.gutter, 0),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          gradient: goalGradient,
          borderRadius: BorderRadius.circular(Radii.goal),
          boxShadow: goalShadow,
        ),
        child: Column(
          children: <Widget>[
            for (final (index, goal) in slotted.indexed) ...<Widget>[
              if (index > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.goalWellLine,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: GoalBlockItem(goal: goal),
              ),
            ],
          ],
        ),
      );
    } else if (anyInContour) {
      top = const _FreeSlotsPlate();
    } else {
      top = const _GoalsEntry();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        top,
        OtherContoursGoals(activeContourId: active.id),
      ],
    );
  }
}

/// Desktop: «ЦЕЛИ · Работа» with the other contours' line on its right, and
/// one card per goal in a strip.
class WorkGoalsStrip extends ConsumerWidget {
  const WorkGoalsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeContourProvider);
    if (active == null) return const SizedBox.shrink();
    final goals = ref.watch(goalListProvider);
    final slotted = _slotted(goals, active.id);
    final anyInContour = goals.any((goal) => goal.contourId == active.id);

    if (slotted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: anyInContour
                  ? const _FreeSlotsPlate(margin: EdgeInsets.zero)
                  : const Align(
                      alignment: Alignment.centerLeft,
                      child: _GoalsEntry(margin: EdgeInsets.zero),
                    ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: OtherContoursGoals(
                activeContourId: active.id,
                inline: true,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 32,
            child: Row(
              children: <Widget>[
                Text(
                  'ЦЕЛИ · ${active.name}'.toUpperCase(),
                  style: AppText.sectionLabel.copyWith(fontSize: 12.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OtherContoursGoals(
                      activeContourId: active.id,
                      inline: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final (index, goal) in slotted.indexed) ...<Widget>[
                  if (index > 0) const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      decoration: BoxDecoration(
                        gradient: goalGradient,
                        borderRadius: BorderRadius.circular(Radii.goal),
                        boxShadow: goalShadow,
                      ),
                      child: GoalBlockItem(goal: goal, wide: true),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One goal of the block: title, why and window, progress, and the step (or
/// the three answers to an expired window).
class GoalBlockItem extends ConsumerWidget {
  const GoalBlockItem({required this.goal, this.wide = false, super.key});

  final GoalView goal;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left = windowLeftLabel(goal.windowEndsAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          onTap: () => unawaited(openGoal(context, goal.id)),
          child: SizedBox(
            height: wide ? 24 : 22,
            child: Row(
              children: <Widget>[
                CrownIcon(size: wide ? 18 : 16, color: AppColors.crown),
                SizedBox(width: wide ? 10 : 8),
                Expanded(
                  child: Text(
                    goal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.goalTitle.copyWith(
                      fontSize: wide ? 17 : 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (goal.progress.total > 0)
                  Text(
                    '${goal.progress.done}/${goal.progress.total}',
                    style: AppText.goalCount.copyWith(
                      fontSize: wide ? 14 : 13,
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: wide ? 4 : 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: goal.windowExpired
                  ? Text(
                      windowExpiredLabel(goal.windowEndsAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.goalExpired,
                      ),
                    )
                  : Text(
                      goal.why ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.goalWhy.copyWith(
                        fontSize: wide ? 13.5 : 13,
                      ),
                    ),
            ),
            if (!goal.windowExpired && left != null) ...<Widget>[
              const SizedBox(width: 10),
              Text(
                left,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: wide ? 12.5 : 12,
                  color: AppColors.voiceMuted,
                ),
              ),
            ],
          ],
        ),
        if (goal.progress.total > 0) ...<Widget>[
          SizedBox(height: wide ? 10 : 8),
          GoalProgressSegments(goal: goal),
        ],
        SizedBox(height: wide ? 12 : 10),
        if (goal.windowExpired)
          ExpiredGoalActions(goal: goal, wide: wide)
        else
          _StepWell(goal: goal, wide: wide),
      ],
    );
  }
}

/// «ШАГ» and the step, with the white «в работу» button (or «в работе»).
class _StepWell extends ConsumerWidget {
  const _StepWell({required this.goal, required this.wide});

  final GoalView goal;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = goal.nextStep;
    final inSet =
        step != null && ref.watch(focusedTaskIdsProvider).contains(step.id);

    final Widget text;
    if (step == null) {
      final blocked = goal.allBlocked;
      text = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('ШАГ', style: AppText.goalLabel),
          const SizedBox(height: 2),
          Text(
            'Обсудить, что дальше',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.goalStep.copyWith(fontSize: wide ? 15 : 14.5),
          ),
          Text(
            blocked ? 'всё заблокировано' : 'в цели нет открытых задач',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: blocked
                  ? AppColors.waitingDotOnInk
                  : AppColors.voiceMuted,
            ),
          ),
        ],
      );
    } else {
      text = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('ШАГ', style: AppText.goalLabel),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  step.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.goalStep.copyWith(fontSize: wide ? 15 : 14.5),
                ),
              ),
              Text(
                ' · ${step.projectName}',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: wide ? 12.5 : 12,
                  color: AppColors.voiceMuted,
                ),
              ),
            ],
          ),
        ],
      );
    }

    final Widget action;
    if (step == null) {
      action = _WhiteRound(
        tooltip: 'Добавить задачу в цель',
        icon: Icons.add,
        wide: wide,
        onTap: () => unawaited(showGoalLinkSheet(context, ref, goal: goal)),
      );
    } else if (inSet) {
      action = Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.goalWellLine,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'в работе',
            style: TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppColors.onInk,
            ),
          ),
        ),
      );
    } else {
      action = _WhiteRound(
        tooltip: 'Взять шаг в работу',
        icon: Icons.adjust,
        wide: wide,
        onTap: () => unawaited(
          runMutation(
            context,
            () => ref.read(focusSetProvider.notifier).takeStep(step),
            failure: 'Не удалось взять шаг в работу.',
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (step == null || step.status == TaskStatus.done) {
            unawaited(openGoal(context, goal.id));
          } else {
            unawaited(
              AppRoutes.openTask(
                context,
                projectId: step.projectId,
                taskId: step.id,
              ),
            );
          }
        },
        child: Container(
          constraints: BoxConstraints(minHeight: wide ? 56 : 52),
          padding: EdgeInsets.fromLTRB(wide ? 16 : 14, 4, 6, 4),
          decoration: BoxDecoration(
            color: AppColors.goalWell,
            border: Border.all(color: AppColors.goalWellLine),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: text),
              const SizedBox(width: 10),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

class _WhiteRound extends StatelessWidget {
  const _WhiteRound({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.wide,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final size = wide ? 44.0 : 40.0;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: Targets.minimum,
        height: Targets.minimum,
        child: Center(
          child: Material(
            color: AppColors.onInk,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  icon,
                  size: wide ? 21 : 20,
                  color: AppColors.voiceBackground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Слоты свободны · Поставить цель»: the contour has goals, none in a slot.
class _FreeSlotsPlate extends StatelessWidget {
  const _FreeSlotsPlate({
    this.margin = const EdgeInsets.fromLTRB(Insets.gutter, 4, Insets.gutter, 0),
  });

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: CustomPaint(
        painter: const DashedRRectPainter(radius: 18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => unawaited(openGoals(context)),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Row(
              children: <Widget>[
                CrownIcon(size: 16, color: AppColors.crownMuted),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Слоты свободны',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                Text(
                  'Поставить цель',
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.indigoLink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// No goals in the active contour at all: a small way to the goals screen
/// instead of a block (owner's decision).
class _GoalsEntry extends StatelessWidget {
  const _GoalsEntry({
    this.margin = const EdgeInsets.fromLTRB(Insets.gutter - 4, 0, 0, 0),
  });

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => unawaited(openGoals(context)),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, Targets.minimum),
            foregroundColor: AppColors.inkSoft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          icon: const CrownIcon(size: 13, color: AppColors.crownMuted),
          label: const Text('Цели'),
        ),
      ),
    );
  }
}

/// Session memory of the folded line's state ("запоминается локально").
final ValueNotifier<bool> _othersOpen = ValueNotifier<bool>(false);

/// The other contours' goals in slots: one folded line, opening into light
/// rows. Nothing can be taken into work from here -- that contour is not the
/// one in force. Nothing at all when the other contours have no goals in
/// slots.
class OtherContoursGoals extends ConsumerWidget {
  const OtherContoursGoals({
    required this.activeContourId,
    this.inline = false,
    super.key,
  });

  final String activeContourId;

  /// Desktop: the line sits beside the strip's heading, opening a menu.
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contours = ref.watch(contourListProvider);
    final goals = ref.watch(goalListProvider);
    final others = <GoalView>[
      for (final contour in contours)
        if (contour.id != activeContourId)
          ..._slotted(goals, contour.id),
    ];
    if (others.isEmpty) return const SizedBox.shrink();
    final names = <String, String>{
      for (final contour in contours) contour.id: contour.name,
    };
    final first = others.first;

    Widget line(bool open) => SizedBox(
      height: Targets.minimum,
      child: Row(
        mainAxisSize: inline ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          const CrownIcon(size: 13, color: AppColors.crownMuted),
          const SizedBox(width: 8),
          Text(
            names[first.contourId] ?? '',
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.inkSoft,
            ),
          ),
          Flexible(
            child: Text(
              ' · ${first.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: AppColors.muted,
              ),
            ),
          ),
          if (others.length > 1)
            Text(
              ' +${others.length - 1}',
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.muted,
              ),
            ),
          const SizedBox(width: 4),
          Icon(
            open ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: AppColors.muted,
          ),
        ],
      ),
    );

    if (inline) {
      return PopupMenuButton<String>(
        tooltip: 'Цели других контуров',
        position: PopupMenuPosition.under,
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (id) => unawaited(openGoal(context, id)),
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          for (final goal in others)
            PopupMenuItem<String>(
              value: goal.id,
              height: 52,
              child: _OtherRowContent(goal: goal),
            ),
        ],
        child: line(false),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _othersOpen,
      builder: (context, open, _) => Padding(
        padding: const EdgeInsets.fromLTRB(Insets.gutter, 8, Insets.gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            InkWell(
              onTap: () => _othersOpen.value = !open,
              child: line(open),
            ),
            if (open)
              for (final goal in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.card,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: AppColors.line),
                      borderRadius: BorderRadius.circular(Radii.row),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.row),
                      onTap: () => unawaited(openGoal(context, goal.id)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          height: 52,
                          child: _OtherRowContent(goal: goal),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _OtherRowContent extends StatelessWidget {
  const _OtherRowContent({required this.goal});

  final GoalView goal;

  @override
  Widget build(BuildContext context) {
    final step = goal.nextStep;
    return Row(
      children: <Widget>[
        const CrownChip(bright: false),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                goal.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  color: AppColors.ink,
                ),
              ),
              Text(
                step?.title ?? 'Обсудить, что дальше',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w500,
                  fontSize: 12.5,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
