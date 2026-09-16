import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/project_summary.dart';
import '../models/board_project.dart';
import '../providers/archive_providers.dart';
import '../widgets/mutation_feedback.dart';

/// The archive: projects taken off the board, and the only place a project can
/// be deleted from (F4).
///
/// ## Why deleting lives here and nowhere else
///
/// The backend refuses to delete an active project
/// (`backend/src/domain/projectDeleteGuard.ts`), and that ordering is copied
/// from Trello on purpose (`../../project-tracker-brief.md`): the reversible
/// step is frequent and the irreversible one is rare, so they must not be the
/// same gesture in the same place. Putting delete in the archive rather than on
/// the board means reaching it takes a deliberate detour -- which is the point.
///
/// The list is plain rows rather than board cards. A card exists to answer "what
/// is happening in this project"; an archived project is one nothing is
/// happening in, and the only questions left are "what was it" and "how far did
/// it get".
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archivedBoardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(archivedBoardProvider),
        child: switch (archive) {
          AsyncData(:final value) when value.isEmpty => const _Message(
            icon: Icons.inventory_2_outlined,
            title: 'Архив пуст',
            body:
                'Проект попадает сюда из его собственного экрана — «В архив» '
                'в меню сверху. С доски он при этом исчезает, а напоминания '
                'его задач перестают приходить.',
          ),

          AsyncData(:final value) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: value.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _ArchivedProjectTile(entry: value[index]),
          ),

          AsyncError(:final error) => _Message(
            icon: Icons.cloud_off,
            title: 'Не удалось загрузить архив',
            body:
                '${describeApiError(error)}\n\nАрхив не кэшируется локально — '
                'он нужен только когда связь есть.',
          ),

          _ => const _Message(icon: null, title: 'Загружаем архив…', body: ''),
        },
      ),
    );
  }
}

class _ArchivedProjectTile extends ConsumerWidget {
  const _ArchivedProjectTile({required this.entry});

  final BoardProject entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ProjectSummary.of(entry);

    return ListTile(
      title: Text(entry.project.name),
      subtitle: Text(
        'Задач: ${summary.doneCount} из ${summary.totalCount} сделано',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => _unarchive(context, ref),
            icon: const Icon(Icons.unarchive_outlined, size: 18),
            label: const Text('Вернуть'),
          ),
          IconButton(
            tooltip: 'Удалить навсегда',
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_forever_outlined),
            color: Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    );
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) {
    return runMutation(
      context,
      () => ref
          .read(projectLifecycleProvider.notifier)
          .unarchive(entry.project.id),
      failure: 'Не удалось вернуть проект из архива.',
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmByTyping(
      context,
      title: 'Удалить проект навсегда?',
      message:
          'Будут удалены сам проект «${entry.project.name}», все его задачи '
          '(${entry.tasks.length}) и все его заметки. Отменить это нельзя, '
          'и копии на сервере не остаётся.',
      expected: entry.project.name,
      fieldLabel: 'Введите название проекта, чтобы подтвердить',
    );
    if (!confirmed || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(projectLifecycleProvider.notifier).delete(entry.project),
      failure: 'Не удалось удалить проект.',
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  /// Null draws a progress indicator instead -- the loading state.
  final IconData? icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Still a scrollable, so pull-to-refresh works on an empty or failed
    // archive -- the two states from which a person most wants to retry.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon == null)
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  else
                    Icon(
                      icon,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
