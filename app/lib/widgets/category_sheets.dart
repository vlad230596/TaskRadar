import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_category.dart';
import '../providers/project_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'mutation_feedback.dart';
import 'project_name_dialog.dart';

/// The answer of [pickTaskCategory]: the chosen category's id, or null for
/// "без категории". The picker itself returns null for "closed, nothing
/// chosen", which is why the choice is wrapped.
typedef CategoryChoice = ({String? categoryId});

/// Asks which of the project's categories a task belongs to.
///
/// A bottom sheet with every category, "Без категории" and "Новая категория…"
/// -- the last one creates the category and picks it in one go, because the
/// moment a task does not fit any group is exactly when the group is invented.
Future<CategoryChoice?> pickTaskCategory(
  BuildContext context, {
  required String projectId,
  required String? current,
}) {
  return showModalBottomSheet<CategoryChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CategoryPicker(projectId: projectId, current: current),
  );
}

/// The list of the project's categories, to add, rename and delete them.
Future<void> showCategoryManager(
  BuildContext context, {
  required String projectId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CategoryManager(projectId: projectId),
  );
}

/// The name of a new category, then the category itself, or null when the
/// dialog was cancelled or the server refused (it has said why already).
Future<TaskCategory?> createCategoryInteractively(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
}) async {
  final name = await askForCategoryName(
    context,
    title: 'Новая категория',
    confirmLabel: 'Создать',
  );
  if (name == null || !context.mounted) return null;
  return runMutationFor<TaskCategory>(
    context,
    () => ref.read(projectCategoriesProvider(projectId).notifier).create(name),
    failure: 'Не удалось создать категорию.',
  );
}

class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({required this.projectId, required this.current});

  final String projectId;
  final String? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(projectCategoriesProvider(projectId)).value ??
        const <TaskCategory>[];

    Widget option(String label, String? id) => ListTile(
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      leading: Icon(
        id == null ? Icons.label_off_outlined : Icons.label_outline,
        color: AppColors.muted,
      ),
      trailing: current == id
          ? const Icon(Icons.check, color: AppColors.indigoLink)
          : null,
      selected: current == id,
      onTap: () => Navigator.of(context).pop((categoryId: id)),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Категория', style: AppText.screenTight),
            ),
            for (final category in categories)
              option(category.name, category.id),
            option('Без категории', null),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add, color: AppColors.indigoLink),
              title: Text(
                'Новая категория…',
                style: AppText.action.copyWith(color: AppColors.indigoLink),
              ),
              onTap: () async {
                final navigator = Navigator.of(context);
                final created = await createCategoryInteractively(
                  context,
                  ref,
                  projectId: projectId,
                );
                if (created != null && navigator.mounted) {
                  navigator.pop((categoryId: created.id));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryManager extends ConsumerWidget {
  const _CategoryManager({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectCategoriesProvider(projectId));
    final categories = async.value ?? const <TaskCategory>[];
    final notifier = ref.read(projectCategoriesProvider(projectId).notifier);

    Future<void> rename(TaskCategory category) async {
      final name = await askForCategoryName(
        context,
        title: 'Переименовать категорию',
        confirmLabel: 'Сохранить',
        initialName: category.name,
      );
      if (name == null || !context.mounted) return;
      await runMutation(
        context,
        () => notifier.rename(category, name),
        failure: 'Не удалось переименовать категорию.',
      );
    }

    Future<void> delete(TaskCategory category) async {
      final ok = await confirmDestructive(
        context,
        title: 'Удалить категорию «${category.name}»?',
        message: 'Задачи останутся в проекте, без категории.',
      );
      if (!ok || !context.mounted) return;
      await runMutation(
        context,
        () => notifier.remove(category),
        failure: 'Не удалось удалить категорию.',
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
              child: Text('Категории проекта', style: AppText.screenTight),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Задачи в списке собираются под своими категориями. '
                'Категорию задачи выбирают на её экране.',
                style: AppText.hint,
              ),
            ),
            if (async.isLoading && categories.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (async.hasError && categories.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Не удалось загрузить категории.',
                  style: AppText.hint,
                ),
              ),
            for (final category in categories)
              ListTile(
                leading: const Icon(
                  Icons.label_outline,
                  color: AppColors.muted,
                ),
                title: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => unawaited(rename(category)),
                trailing: IconButton(
                  tooltip: 'Удалить категорию',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(delete(category)),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add, color: AppColors.indigoLink),
              title: Text(
                'Новая категория…',
                style: AppText.action.copyWith(color: AppColors.indigoLink),
              ),
              onTap: () => unawaited(
                createCategoryInteractively(context, ref, projectId: projectId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
