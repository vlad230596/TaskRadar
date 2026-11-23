import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/goals.dart';
import '../../models/goal.dart';
import '../../navigation/goal_routes.dart';
import '../../providers/goal_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'goal_icons.dart';
import 'goal_picker_sheet.dart';

/// The crown on a task (`design/goals-ideas-spec.md`, п. 1): a task that
/// serves a goal carries it; bright when one of its goals is of the active
/// contour, muted otherwise. One crown however many goals.

/// The goals a task serves right now, live from the goals list.
List<TaskGoalRef> watchTaskGoals(
  WidgetRef ref,
  String taskId,
  List<TaskGoalRef> sent,
) => goalsOfTask(ref.watch(taskGoalIndexProvider), taskId, sent);

/// The crown level of a task, live.
CrownLevel watchCrown(WidgetRef ref, String taskId, List<TaskGoalRef> sent) =>
    crownLevel(
      watchTaskGoals(ref, taskId, sent),
      ref.watch(activeContourIdProvider),
    );

/// The chip: 22x22, r 7, crown 13 (sizes as given).
class CrownChip extends StatelessWidget {
  const CrownChip({
    required this.bright,
    this.size = 22,
    this.iconSize = 13,
    this.radius = Radii.crownChip,
    this.onDark = false,
    super.key,
  });

  final bool bright;
  final double size;
  final double iconSize;
  final double radius;

  /// On a dark surface: bright on `goalEnd`, muted on `voiceLine`.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    if (onDark) {
      fill = bright ? AppColors.goalEnd : AppColors.voiceLine;
    } else {
      fill = bright ? AppColors.crownChip : AppColors.crownMutedChip;
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CrownIcon(
        size: iconSize,
        color: bright ? AppColors.crown : AppColors.crownMuted,
      ),
    );
  }
}

/// A task's crown with its 44x44 target: tap or long press opens «В целях».
/// Draws nothing for a task without goals.
class TaskCrown extends ConsumerWidget {
  const TaskCrown({
    required this.taskId,
    required this.goals,
    this.size = 22,
    this.iconSize = 13,
    this.chipless = false,
    this.target = Targets.minimum,
    super.key,
  });

  final String taskId;

  /// The goals as the server sent them with the task.
  final List<TaskGoalRef> goals;
  final double size;
  final double iconSize;

  /// The planning screen's current task: a bare crown, `crownOnLight` or
  /// `crownMuted`, no chip.
  final bool chipless;

  /// The tap target's side.
  final double target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = watchCrown(ref, taskId, goals);
    if (level == CrownLevel.none) return const SizedBox.shrink();
    final bright = level == CrownLevel.bright;
    final Widget mark = chipless
        ? CrownIcon(
            size: iconSize,
            color: bright ? AppColors.crownOnLight : AppColors.crownMuted,
          )
        : CrownChip(bright: bright, size: size, iconSize: iconSize);
    return Semantics(
      button: true,
      label: bright ? 'В целях' : 'В целях другого контура',
      child: InkResponse(
        radius: target / 2,
        onTap: () => unawaited(showCrownMenu(context, ref, taskId, goals)),
        onLongPress: () =>
            unawaited(showCrownMenu(context, ref, taskId, goals)),
        child: SizedBox(
          width: target,
          height: target,
          child: Center(child: mark),
        ),
      ),
    );
  }
}

/// «В ЦЕЛЯХ»: the goals of a task, each opening its goal, and «Связать с
/// целью…» last.
Future<void> showCrownMenu(
  BuildContext context,
  WidgetRef ref,
  String taskId,
  List<TaskGoalRef> sent,
) async {
  final goals = goalsOfTask(ref.read(taskGoalIndexProvider), taskId, sent);
  final contours = <String, String>{
    for (final contour in ref.read(contourListProvider))
      contour.id: contour.name,
  };
  final active = ref.read(activeContourIdProvider);
  final box = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final position = RelativeRect.fromRect(
    origin & box.size,
    Offset.zero & overlay.size,
  );

  final choice = await showMenu<String>(
    context: context,
    position: position,
    color: AppColors.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    items: <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        enabled: false,
        height: 36,
        child: Text('В ЦЕЛЯХ', style: AppText.sectionLabel),
      ),
      for (final goal in goals)
        PopupMenuItem<String>(
          value: goal.id,
          height: 48,
          child: Row(
            children: <Widget>[
              CrownChip(
                bright: active == null || goal.contourId == active,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (contours[goal.contourId] != null) ...<Widget>[
                const SizedBox(width: 10),
                Text(
                  contours[goal.contourId]!,
                  style: AppText.chip.copyWith(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: _linkChoice,
        height: 48,
        child: Text(
          'Связать с целью…',
          style: TextStyle(
            fontFamily: AppFonts.text,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: AppColors.indigoLink,
          ),
        ),
      ),
    ],
  );
  if (choice == null || !context.mounted) return;
  if (choice == _linkChoice) {
    await linkTaskToGoals(
      context,
      ref,
      taskId: taskId,
      current: <String>{for (final goal in goals) goal.id},
    );
    return;
  }
  await openGoal(context, choice);
}

const String _linkChoice = '__link__';
