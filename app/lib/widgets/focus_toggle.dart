import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../providers/focus_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'mutation_feedback.dart';

/// Takes [task] into the focus set, or drops it out -- whichever it is not.
///
/// The one write behind every "взять в работу" control, so that the list's
/// target, the task screen's button and whatever comes next say the same thing
/// when it fails. Same rule as the list's target: no limit of five here -- see
/// `_FocusTarget` in `task_list.dart` for why.
Future<void> toggleFocus(
  BuildContext context,
  WidgetRef ref, {
  required Task task,
  required String projectName,
}) {
  final inFocus = ref.read(focusedTaskIdsProvider).contains(task.id);
  final notifier = ref.read(focusSetProvider.notifier);
  return runMutation(
    context,
    () => inFocus
        ? notifier.drop(task.id)
        : notifier.take(task, projectName: projectName),
    failure: inFocus
        ? 'Не удалось убрать задачу из набора.'
        : 'Не удалось взять задачу в работу.',
  );
}

/// The full-width "Взять в работу" button of the task screen.
///
/// Outlined while the task is not in the set -- an offer; filled indigo once it
/// is -- a state, with the way back in the same words ("убрать из набора"). The
/// icon is the work mode's own (`Icons.adjust`), as on the list's target.
class FocusToggleButton extends ConsumerWidget {
  const FocusToggleButton({
    required this.task,
    required this.projectName,
    super.key,
  });

  final Task task;
  final String projectName;

  static const double height = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inFocus = ref.watch(focusedTaskIdsProvider).contains(task.id);
    void onPressed() => unawaited(
      toggleFocus(context, ref, task: task, projectName: projectName),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final label = AppText.action.copyWith(
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    );

    if (inFocus) {
      return SizedBox(
        height: height,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.indigo,
            foregroundColor: AppColors.onInk,
            shape: shape,
            textStyle: label,
          ),
          icon: const Icon(Icons.adjust, size: 20),
          label: const Text(
            'В работе · убрать из набора',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.indigoInk,
          side: const BorderSide(color: AppColors.indigo, width: 1.5),
          shape: shape,
          textStyle: label,
        ),
        icon: const Icon(Icons.adjust, size: 20),
        label: const Text(
          'Взять в работу',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
