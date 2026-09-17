import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../models/board_project.dart';
import '../models/inbox_item.dart';
import '../models/scope.dart';
import '../providers/archive_providers.dart';
import '../providers/board_providers.dart';
import '../providers/inbox_providers.dart';
import '../providers/scope_providers.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/project_name_dialog.dart';

/// The sandbox (F8): write it down now, sort it later.
///
/// ## Two jobs, one screen, in this order
///
/// **Capture** is at the top and owns the keyboard: the field autofocuses, it
/// keeps focus after each line, and it is the first thing on screen. That is
/// the gesture the whole feature exists for -- "надо не забыть" arriving while
/// walking, where every extra decision is a chance to write nothing down at
/// all.
///
/// **Sorting** is the list under it, processed oldest first because the line at
/// risk of rotting is the one that has waited longest. Each line can become a
/// task in an existing project, become a project of its own, be corrected, or
/// be thrown away -- and nothing else. There is deliberately no way to complete
/// or schedule a line while it is here: an item you can work on is an item you
/// never file, and a pile that has quietly become a second task list is the
/// failure this screen has to avoid.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  static const String title = 'Песочница';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: Column(
        children: [
          const _Composer(),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
              child: switch (inbox) {
                AsyncData(:final value) when value.isEmpty => const _Message(
                  icon: Icons.inbox_outlined,
                  title: 'Песочница пуста',
                  body:
                      'Сюда попадает то, что записано на ходу, — одной строкой '
                      'и без выбора проекта. Разобрать можно потом: строчка '
                      'станет задачей в проекте или новым проектом.',
                ),

                AsyncData(:final value) => ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _InboxTile(item: value[index]),
                ),

                AsyncError(:final error) => _Message(
                  icon: Icons.cloud_off,
                  title: 'Не удалось загрузить песочницу',
                  body: describeApiError(error),
                  action: TextButton.icon(
                    onPressed: () => ref.read(inboxProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Повторить'),
                  ),
                ),

                _ => const _Message(
                  icon: null,
                  title: 'Загружаем песочницу…',
                  body: '',
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The capture field. The reason this screen exists.
class _Composer extends ConsumerStatefulWidget {
  const _Composer();

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    /*
     * The field is cleared only *after* the server has taken the line, which is
     * the opposite of the task composer in `widgets/task_list.dart` -- and the
     * difference is deliberate.
     *
     * A task typed inside a project is created optimistically because the row
     * appearing instantly is what makes "empty my head into the list" feel like
     * one gesture, and a failure there rolls the row back in front of someone
     * who is looking at that list.
     *
     * Capture is the case where that trade is wrong. The whole promise of the
     * sandbox is "it is written down now"; a line that appears and then
     * evaporates on a train breaks exactly that promise, and there is no
     * offline queue to fall back on. So the text stays in the field until it is
     * safely stored, and a failure leaves it there to be sent again.
     */
    final ok = await runMutation(
      context,
      () => ref.read(inboxProvider.notifier).capture(text),
      failure: 'Не удалось записать в песочницу.',
    );
    if (!ok || !mounted) return;

    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              // Opens the keyboard with the screen: this screen is reached in
              // order to type, and a tap spent putting the caret in the field
              // is a tap spent on nothing.
              autofocus: true,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Что не забыть…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Записать',
            onPressed: _submit,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _InboxTile extends ConsumerWidget {
  const _InboxTile({required this.item});

  final InboxItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(item.text),
      // The whole row files it: that is what this screen is for, and a target
      // the size of a row beats one the size of an icon.
      onTap: () => _file(context, ref),
      trailing: PopupMenuButton<_ItemAction>(
        tooltip: 'Что сделать со строчкой',
        onSelected: (action) => switch (action) {
          _ItemAction.file => _file(context, ref),
          _ItemAction.edit => _edit(context, ref),
          _ItemAction.discard => _discard(context, ref),
        },
        itemBuilder: (_) => const <PopupMenuEntry<_ItemAction>>[
          PopupMenuItem<_ItemAction>(
            value: _ItemAction.file,
            child: ListTile(
              leading: Icon(Icons.moving),
              title: Text('В проект'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<_ItemAction>(
            value: _ItemAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Поправить текст'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem<_ItemAction>(
            value: _ItemAction.discard,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Выбросить'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  /// Picks a project (or makes one) and files the line into it.
  Future<void> _file(BuildContext context, WidgetRef ref) async {
    final target = await showDialog<_FileTarget>(
      context: context,
      builder: (_) => _ProjectPicker(text: item.text),
    );
    if (target == null || !context.mounted) return;

    var projectId = target.projectId;
    var projectName = target.projectName;

    if (target.isNewProject) {
      // "Задача, для которой проекта ещё нет" -- the second reason the sandbox
      // exists. Two requests rather than a server-side "promote": creating a
      // project is an operation that already exists and already lands in the
      // right scope, and inventing a combined endpoint would duplicate its
      // rules (the name, the scope, the board refresh) on the server.
      final name = await askForProjectName(
        context,
        title: 'Новый проект',
        confirmLabel: 'Создать',
        // The captured line is usually the project's name, or nearly.
        initialName: item.text,
      );
      if (name == null || !context.mounted) return;

      final scopeId = ref.read(activeScopeProvider)?.id;
      final created = await runMutationFor(
        context,
        () => ref
            .read(projectLifecycleProvider.notifier)
            .create(name, scopeId: scopeId),
        failure: 'Не удалось создать проект.',
      );
      if (created == null || !context.mounted) return;

      projectId = created.id;
      projectName = created.name;
    }

    await runMutation(
      context,
      () => ref.read(inboxProvider.notifier).file(item, projectId: projectId!),
      success: 'Задача добавлена в «$projectName».',
      failure: 'Не удалось перенести в проект.',
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final text = await askForProjectName(
      context,
      title: 'Поправить строчку',
      confirmLabel: 'Сохранить',
      initialName: item.text,
      hint: 'Что не забыть',
    );
    if (text == null || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(inboxProvider.notifier).edit(item, text),
      failure: 'Не удалось изменить строчку.',
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    // A plain yes/no: this is one sentence, typed recently, and the
    // type-the-name confirmation that guards deleting a project would be
    // theatre. It is still a confirmation, because the line cannot be recovered
    // and the menu item sits next to two harmless ones.
    final confirmed = await confirmDestructive(
      context,
      title: 'Выбросить строчку?',
      message: '«${item.text}» исчезнет насовсем — вернуть будет нельзя.',
      confirmLabel: 'Выбросить',
    );
    if (!confirmed || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(inboxProvider.notifier).discard(item),
      failure: 'Не удалось выбросить строчку.',
    );
  }
}

enum _ItemAction { file, edit, discard }

/// What the picker returns: an existing project, or the intent to make one.
class _FileTarget {
  const _FileTarget.existing(this.projectId, this.projectName)
    : isNewProject = false;
  const _FileTarget.newProject() : projectId = null, projectName = null, isNewProject = true;

  final String? projectId;
  final String? projectName;
  final bool isNewProject;
}

/// Where to file a line.
///
/// Built from the board the client already holds -- every project of every
/// scope, which is exactly what the sandbox needs and exactly what
/// `scope_providers.dart` explains the client keeps in memory anyway. No
/// request, and no scope filter: a line captured without deciding which part of
/// life it belongs to must not be filed through a switcher that has already
/// decided.
class _ProjectPicker extends ConsumerWidget {
  const _ProjectPicker({required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(boardViewProvider);
    final scopes = ref.watch(scopesProvider).value ?? const <Scope>[];
    final projects = view is BoardReady
        ? view.projects
        : const <BoardProject>[];

    return SimpleDialog(
      title: const Text('В какой проект'),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(context).pop(const _FileTarget.newProject()),
          child: const ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('Новый проект…'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const Divider(height: 1),

        if (projects.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text('Проектов пока нет — заведите первый.'),
          )
        else
          // Grouped by scope, in the switcher's order, but only when there is
          // more than one scope: a single heading over the whole list would be
          // a label that says nothing.
          for (final scope in _scopeOrder(scopes, projects)) ...[
            if (scopes.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                child: Text(
                  scope?.name ?? 'Без скоупа',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final entry in projects.where(
              (p) => p.project.scopeId == scope?.id,
            ))
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(
                  _FileTarget.existing(entry.project.id, entry.project.name),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(entry.project.name),
                ),
              ),
          ],
      ],
    );
  }

  /// The scopes that actually hold a project here, in switcher order, plus
  /// `null` at the end if some project's scope is unknown to this client (a
  /// scope created on another device since the last `GET /scopes`).
  List<Scope?> _scopeOrder(List<Scope> scopes, List<BoardProject> projects) {
    final known = <Scope?>[
      for (final scope in scopes)
        if (projects.any((p) => p.project.scopeId == scope.id)) scope,
    ];
    final orphaned = projects.any(
      (p) => !scopes.any((scope) => scope.id == p.project.scopeId),
    );
    return <Scope?>[...known, if (orphaned) null];
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
                  if (action != null) ...[
                    const SizedBox(height: 12),
                    action!,
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
