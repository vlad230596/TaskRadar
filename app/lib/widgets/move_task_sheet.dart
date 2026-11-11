import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/scope.dart';
import '../models/task.dart';
import '../providers/board_providers.dart';
import '../providers/project_providers.dart';
import '../providers/scope_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'mutation_feedback.dart';

/// "Перенести в проект…": asks where [task] goes, moves it there, and says
/// where it went. Returns whether the task left this project -- sent, or
/// queued with no network -- so the caller can leave a screen whose every
/// control now addresses a row that is somewhere else.
///
/// Self-contained on purpose: the task screen calls this one function and
/// knows nothing about the picker or the wording.
Future<bool> moveTaskToAnotherProject(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  if (isOptimisticId(task.id)) {
    say(
      'Задача ещё не отправлена на сервер — перенести её можно, '
      'когда она уйдёт.',
    );
    return false;
  }

  final target = await pickTargetProject(
    context,
    currentProjectId: task.projectId,
  );
  if (target == null || !context.mounted) return false;

  final outcome = await runMutationFor<WriteOutcome>(
    context,
    () => ref
        .read(projectTasksProvider(task.projectId).notifier)
        .moveToProject(task, target.id),
    failure: 'Не удалось перенести задачу.',
  );
  if (outcome == null) return false;

  // The task disappears from here, so say where it went.
  say(
    outcome == WriteOutcome.queued
        ? 'Перенос в «${target.name}» сохранён на телефоне — уйдёт при связи.'
        : 'Задача перенесена в «${target.name}».',
  );
  return true;
}

/// The bottom sheet of projects a task can go to: every project on the board
/// (the archive is not offered -- a task moved there would vanish from sight)
/// except [currentProjectId]. Grouped by space when there is more than one.
/// Null when it was closed without a choice.
Future<Project?> pickTargetProject(
  BuildContext context, {
  required String currentProjectId,
}) {
  return showModalBottomSheet<Project>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ProjectPicker(currentProjectId: currentProjectId),
  );
}

class _ProjectPicker extends ConsumerWidget {
  const _ProjectPicker({required this.currentProjectId});

  final String currentProjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(boardViewProvider);
    final projects = board is BoardReady
        ? <Project>[
            for (final row in board.projects)
              if (row.project.id != currentProjectId &&
                  row.project.archivedAt == null)
                row.project,
          ]
        : const <Project>[];
    final scopes = ref.watch(hasMultipleScopesProvider)
        ? ref.watch(scopesProvider).value ?? const <Scope>[]
        : const <Scope>[];

    Widget option(Project project) => ListTile(
      leading: const Icon(Icons.folder_outlined, color: AppColors.muted),
      title: Text(project.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).pop(project),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: AppText.caption),
    );

    final children = <Widget>[];
    if (scopes.isEmpty) {
      children.addAll(projects.map(option));
    } else {
      final placed = <String>{};
      for (final scope in scopes) {
        final inScope = projects
            .where((project) => project.scopeId == scope.id)
            .toList();
        if (inScope.isEmpty) continue;
        children
          ..add(heading(scope.name))
          ..addAll(inScope.map(option));
        placed.addAll(inScope.map((project) => project.id));
      }
      // A project of a scope the list does not know yet: still offered.
      children.addAll(
        projects.where((p) => !placed.contains(p.id)).map(option),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Перенести в проект', style: AppText.screenTight),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Задача встанет в конец списка. Категория останется в этом '
                'проекте — в новом её можно выбрать заново.',
                style: AppText.hint,
              ),
            ),
            if (board is BoardLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (board is BoardUnavailable)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Не удалось загрузить список проектов.',
                  style: AppText.hint,
                ),
              )
            else if (projects.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Других проектов нет. Создайте проект на доске — и задачу '
                  'можно будет перенести туда.',
                  style: AppText.hint,
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}
