import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../models/goal.dart';
import '../../providers/goal_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../ime_text_controller.dart';
import 'goal_icons.dart';

/// «Связать с целью» (`design/goals-ideas-spec.md`, п. 6): a dark sheet of
/// every goal, grouped by contour -- slots first, then the bench -- with a
/// checkbox each, «+ Новая цель в «…»» at the bottom and «Готово».
///
/// Returns the chosen goal ids, or null when dismissed.
Future<Set<String>?> showGoalPicker(
  BuildContext context, {
  required Set<String> initial,
  String title = 'Связать с целью',
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.voiceBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
    ),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _GoalPicker(initial: initial, title: title),
    ),
  );
}

/// Picks goals for a task and applies the difference (online-only writes).
Future<void> linkTaskToGoals(
  BuildContext context,
  WidgetRef ref, {
  required String taskId,
  required Set<String> current,
}) async {
  final chosen = await showGoalPicker(context, initial: current);
  if (chosen == null || !context.mounted) return;
  await _applyLinks(
    context,
    ref,
    current: current,
    chosen: chosen,
    link: (goals, goalId) => goals.linkTask(goalId, taskId),
    unlink: (goals, goalId) => goals.unlinkTask(goalId, taskId),
  );
}

/// Picks goals for an idea and applies the difference.
Future<void> linkIdeaToGoals(
  BuildContext context,
  WidgetRef ref, {
  required String noteId,
  required Set<String> current,
}) async {
  final chosen = await showGoalPicker(context, initial: current);
  if (chosen == null || !context.mounted) return;
  await _applyLinks(
    context,
    ref,
    current: current,
    chosen: chosen,
    link: (goals, goalId) => goals.linkIdea(goalId, noteId),
    unlink: (goals, goalId) => goals.unlinkIdea(goalId, noteId),
  );
}

Future<void> _applyLinks(
  BuildContext context,
  WidgetRef ref, {
  required Set<String> current,
  required Set<String> chosen,
  required Future<GoalView> Function(Goals goals, String goalId) link,
  required Future<GoalView> Function(Goals goals, String goalId) unlink,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final goals = ref.read(goalsProvider.notifier);
  try {
    for (final id in chosen.difference(current)) {
      await link(goals, id);
    }
    for (final id in current.difference(chosen)) {
      await unlink(goals, id);
    }
  } catch (error) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось связать с целью. ${describeApiError(error)}',
          ),
        ),
      );
  }
}

class _GoalPicker extends ConsumerStatefulWidget {
  const _GoalPicker({required this.initial, required this.title});

  final Set<String> initial;
  final String title;

  @override
  ConsumerState<_GoalPicker> createState() => _GoalPickerState();
}

class _GoalPickerState extends ConsumerState<_GoalPicker> {
  late final Set<String> _chosen = <String>{...widget.initial};
  final TextEditingController _newTitle = ImeTextController();
  bool _creating = false;

  @override
  void dispose() {
    _newTitle.dispose();
    super.dispose();
  }

  Future<void> _create(String contourId) async {
    final title = _newTitle.text.trim();
    if (title.isEmpty || _creating) return;
    setState(() => _creating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final goal = await ref
          .read(goalsProvider.notifier)
          .create(contourId: contourId, title: title);
      if (!mounted) return;
      setState(() {
        _chosen.add(goal.id);
        _newTitle.clear();
      });
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось создать цель. ${describeApiError(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contours = ref.watch(contourListProvider);
    final goals = ref.watch(goalListProvider);
    final active = ref.watch(activeContourProvider);
    final target = active ?? (contours.isEmpty ? null : contours.first);

    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.voiceLine,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.title,
                  style: AppText.screenTight.copyWith(
                    color: AppColors.voiceInk,
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: AppColors.voiceMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: <Widget>[
              for (final contour in contours) ...<Widget>[
                if (contours.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                    child: Text(
                      contour.name.toUpperCase(),
                      style: AppText.sectionLabel.copyWith(
                        color: AppColors.voiceMuted,
                      ),
                    ),
                  ),
                for (final goal in <GoalView>[
                  ...goals.where((g) => g.contourId == contour.id && g.inSlot),
                  ...goals.where((g) => g.contourId == contour.id && g.onBench),
                ])
                  _PickRow(
                    goal: goal,
                    checked: _chosen.contains(goal.id),
                    onTap: () => setState(() {
                      if (!_chosen.remove(goal.id)) _chosen.add(goal.id);
                    }),
                  ),
              ],
              if (goals.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Целей пока нет — заведите первую ниже.',
                    style: AppText.voiceNote,
                  ),
                ),
              if (target != null) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.voiceWell,
                    border: Border.all(color: AppColors.voiceLine),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _newTitle,
                          style: const TextStyle(
                            fontFamily: AppFonts.text,
                            fontSize: 15,
                            color: AppColors.voiceInk,
                          ),
                          cursorColor: AppColors.voiceBright,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            hintText: '+ Новая цель в «${target.name}»',
                            hintStyle: const TextStyle(
                              fontFamily: AppFonts.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.voiceBright,
                            ),
                          ),
                          onSubmitted: (_) => unawaited(_create(target.id)),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Создать цель',
                        onPressed: _creating
                            ? null
                            : () => unawaited(_create(target.id)),
                        icon: const Icon(
                          Icons.add,
                          color: AppColors.voiceBright,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 64,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_chosen),
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
              child: const Text('Готово'),
            ),
          ),
        ),
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.goal,
    required this.checked,
    required this.onTap,
  });

  final GoalView goal;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 56,
        child: Row(
          children: <Widget>[
            _Check(checked: checked),
            const SizedBox(width: 12),
            CrownIcon(
              size: 16,
              color: goal.inSlot ? AppColors.crown : AppColors.crownMuted,
            ),
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
                      fontSize: 15,
                      color: AppColors.voiceInk,
                    ),
                  ),
                  if (goal.onBench)
                    const Text(
                      'на скамейке',
                      style: TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppColors.voiceMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 24 px checkbox for dark sheets: ring `voiceLine`, checked white with an
/// ink tick.
class _Check extends StatelessWidget {
  const _Check({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) => DarkCheck(checked: checked);
}

/// The dark sheets' checkbox (goal picker, «Задачи в цель»).
class DarkCheck extends StatelessWidget {
  const DarkCheck({required this.checked, super.key});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: checked ? AppColors.onInk : Colors.transparent,
        border: checked
            ? null
            : Border.all(color: AppColors.voiceLine, width: 2),
        borderRadius: BorderRadius.circular(7),
      ),
      child: checked
          ? const Icon(Icons.check, size: 18, color: AppColors.voiceBackground)
          : null,
    );
  }
}
