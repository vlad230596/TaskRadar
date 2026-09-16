import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../models/scope.dart';
import '../providers/scope_providers.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/project_name_dialog.dart';

/// Managing the scopes themselves (F7): create, rename, reorder, delete.
///
/// ## Why this is a screen and not a dialog
///
/// Reordering is a drag, and a drag needs a list that owns its own scroll --
/// the same mechanical argument that made the task list a `ReorderableListView`
/// on a screen of its own. It is also somewhere you go about as often as the
/// settings screen, so a screen costs nothing.
///
/// ## Why deleting asks for nothing
///
/// A scope holds no work: the server refuses to delete one that still has
/// projects in it (archived ones included), so by the time a delete can
/// succeed, the thing being deleted is a name and a position. The
/// type-the-name confirmation that guards deleting a *project* would be
/// ceremony here -- and the two must not look alike, precisely because one of
/// them destroys months of tasks and notes and the other does not.
///
/// What is worth showing is the refusal, in words, when the scope is not empty.
class ScopesScreen extends ConsumerWidget {
  const ScopesScreen({super.key});

  static const String title = 'Скоупы';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopes = ref.watch(scopesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Скоуп'),
      ),
      body: switch (scopes) {
        AsyncData(:final value) => _ScopeList(scopes: value),

        AsyncError(:final error) => _Message(
          icon: Icons.cloud_off,
          title: 'Не удалось загрузить скоупы',
          body: describeApiError(error),
          action: TextButton.icon(
            onPressed: () => ref.read(scopesProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Повторить'),
          ),
        ),

        _ => const _Message(icon: null, title: 'Загружаем скоупы…', body: ''),
      },
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await askForScopeName(
      context,
      title: 'Новый скоуп',
      confirmLabel: 'Создать',
    );
    if (name == null || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(scopesProvider.notifier).create(name),
      failure: 'Не удалось создать скоуп.',
    );
  }
}

class _ScopeList extends ConsumerWidget {
  const _ScopeList({required this.scopes});

  final List<Scope> scopes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ReorderableListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
          'Доска показывает один скоуп за раз. Порядок здесь — порядок '
          'переключателя над доской.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      itemCount: scopes.length,
      onReorder: (oldIndex, newIndex) {
        runMutation(
          context,
          () => ref.read(scopesProvider.notifier).move(oldIndex, newIndex),
          failure: 'Не удалось сохранить порядок скоупов.',
        );
      },
      itemBuilder: (context, index) {
        final scope = scopes[index];
        return _ScopeTile(
          key: ValueKey<String>(scope.id),
          scope: scope,
          index: index,
          projectCount: ref.watch(projectCountInScopeProvider(scope.id)),
        );
      },
    );
  }
}

class _ScopeTile extends ConsumerWidget {
  const _ScopeTile({
    required this.scope,
    required this.index,
    required this.projectCount,
    super.key,
  });

  final Scope scope;
  final int index;

  /// Active projects in this scope, for the subtitle. Null while the board has
  /// not loaded -- the count is context, not a fact the screen needs.
  final int? projectCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(scope.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: projectCount == null
          ? null
          : Text(
              projectCount == 0
                  ? 'Проектов нет'
                  : 'Проектов на доске: $projectCount',
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Переименовать',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: () => _rename(context, ref),
          ),
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await askForScopeName(
      context,
      title: 'Переименовать скоуп',
      confirmLabel: 'Переименовать',
      initialName: scope.name,
    );
    if (name == null || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(scopesProvider.notifier).rename(scope, name),
      failure: 'Не удалось переименовать скоуп.',
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // A plain yes/no. The dangerous version of this question -- type the name --
    // belongs to deleting a project, which takes its tasks and notes with it; a
    // scope that can be deleted at all is empty by the server's own rule.
    final confirmed = await confirmDestructive(
      context,
      title: 'Удалить скоуп?',
      message:
          '«${scope.name}» исчезнет из переключателя. Проекты не удаляются — '
          'скоуп с проектами сервер удалить не даст.',
      confirmLabel: 'Удалить',
    );
    if (!confirmed || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(scopesProvider.notifier).delete(scope),
      // The server's own words carry the two refusals ("still has projects",
      // "the last scope"), and `runMutation` shows them; this is the fallback
      // for everything else.
      failure: 'Не удалось удалить скоуп.',
    );
  }
}

/// A centred block of text, same as the other screens use.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData? icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
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
              Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
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
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
