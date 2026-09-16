import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/project_summary.dart';
import '../models/board_project.dart';
import '../models/project.dart';
import '../providers/archive_providers.dart';
import '../providers/project_providers.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/note_list.dart';
import '../widgets/project_name_dialog.dart';
import '../widgets/task_list.dart';

/// A project from the inside: its tasks and its notes (F3).
///
/// ## Addressed by id
///
/// The screen takes a [projectId] and loads everything itself rather than
/// receiving the board row it was opened from. That costs a lookup and buys the
/// thing F4 needs: the same screen opens from a notification tap on a cold start,
/// with no board in memory. See `../navigation/app_routes.dart`.
///
/// ## Tabs on a phone, two panes on the desktop
///
/// Tasks and notes are one screen in the React client, side by side. On a
/// narrow window they are tabs here, for a mechanical reason as much as a
/// layout one: the task list is a `ReorderableListView` and it must **be** the
/// scrollable in order to scroll, to pull-to-refresh, and to auto-scroll while
/// a row is being dragged near the edge. Two lists stacked in one scroll view
/// can only be achieved by shrink-wrapping both, which breaks all three. A tab
/// gives each its own viewport and costs one tap.
///
/// F6 puts them side by side where the window is wide enough
/// (`../widgets/adaptive_layout.dart`) -- which keeps that same property, since
/// each pane is still its own scrollable. See [_WideBody].
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({
    required this.projectId,
    this.highlightTaskId,
    super.key,
  });

  final String projectId;

  /// A task worth pointing at, when the caller was about one specific task.
  /// F4's reminder deep link supplies it; the board does not.
  final String? highlightTaskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(projectViewProvider(projectId));

    return switch (view) {
      ProjectLoading() => _Frame(
        title: 'Проект',
        child: _Message(
          icon: null,
          title: 'Загружаем проект…',
          body: 'Задачи и заметки грузятся отдельными запросами.',
        ),
      ),

      // Deliberately a distinct state from "failed". 404 here means the project
      // was deleted somewhere else -- typically an old notification pointing at
      // a project that no longer exists -- and "нет связи, попробуйте ещё" would
      // be a lie the user could retry forever.
      //
      // Archiving does *not* produce this: `getProjectOrThrow` checks existence
      // only, so an archived project opens normally and stays editable. Saying
      // "возможно, он в архиве" here would send the user looking in a place the
      // project cannot be.
      ProjectMissing() => const _Frame(
        title: 'Проект',
        child: _Message(
          icon: Icons.search_off,
          title: 'Проект не найден',
          body:
              'Похоже, его удалили — удаление необратимо и восстановить проект '
              'нельзя. Вернитесь на доску и обновите её.',
        ),
      ),

      ProjectUnavailable(:final error) => _Frame(
        title: 'Проект',
        child: _Message(
          icon: Icons.cloud_off,
          title: 'Не удалось открыть проект',
          body:
              '${describeApiError(error)}\n\nЛокального снимка с этим проектом '
              'тоже нет.',
          action: _RetryButton(projectId: projectId),
        ),
      ),

      ProjectReady() => _ProjectBody(
        view: view,
        projectId: projectId,
        highlightTaskId: highlightTaskId,
      ),
    };
  }
}

class _ProjectBody extends ConsumerWidget {
  const _ProjectBody({
    required this.view,
    required this.projectId,
    required this.highlightTaskId,
  });

  final ProjectReady view;
  final String projectId;
  final String? highlightTaskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(projectNotesProvider(projectId));
    final summary = ProjectSummary.of(
      BoardProject(project: view.project, tasks: view.tasks),
    );

    final tasksLabel = 'Задачи · ${summary.doneCount}/${summary.totalCount}';
    // The count appears only once the notes have actually loaded -- "Заметки ·
    // 0" while the request is still in flight reads as a fact about the project
    // rather than about the request.
    final notesLabel = notes.value == null
        ? 'Заметки'
        : 'Заметки · ${notes.requireValue.length}';

    final taskPane = TaskListView(
      projectId: projectId,
      tasks: view.tasks,
      highlightTaskId: highlightTaskId,
    );

    final notePane = switch (notes) {
      AsyncData(:final value) => NoteListView(
        projectId: projectId,
        notes: value,
      ),
      AsyncError(:final error) => _Message(
        icon: Icons.cloud_off,
        title: 'Не удалось загрузить заметки',
        body: describeApiError(error),
        action: TextButton.icon(
          onPressed: () =>
              ref.read(projectNotesProvider(projectId).notifier).refresh(),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Повторить'),
        ),
      ),
      _ => const _Message(icon: null, title: 'Загружаем заметки…', body: ''),
    };

    if (isWideLayout(context)) {
      return _WideBody(
        view: view,
        projectId: projectId,
        tasksLabel: tasksLabel,
        notesLabel: notesLabel,
        taskPane: taskPane,
        notePane: notePane,
      );
    }

    return DefaultTabController(
      // Tasks first, and first is the default. That is also the right landing
      // tab for F4's reminder deep link, which always names a *task* -- so
      // `highlightTaskId` needs no special case here.
      initialIndex: 0,
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(view.project.name),
          bottom: TabBar(
            tabs: <Widget>[Tab(text: tasksLabel), Tab(text: notesLabel)],
          ),
          actions: _projectActions(view),
        ),
        body: Column(
          children: [
            if (view.isStale || view.refreshError != null)
              _ProjectBanner(view: view, projectId: projectId),
            Expanded(
              child: TabBarView(children: <Widget>[taskPane, notePane]),
            ),
          ],
        ),
      ),
    );
  }
}

/// The desktop project screen: tasks and notes at the same time (F6).
///
/// ## Why this is not just the tabs with a wider tab strip
///
/// The tabs exist for a mechanical reason as much as a spatial one (see the
/// note on [ProjectScreen]), and that reason survives here: each pane is still
/// its own scrollable, so the task list is still the `ReorderableListView` that
/// scrolls, pulls to refresh and auto-scrolls during a drag. Two panes side by
/// side keep that property; two lists stacked in one scroll view would not.
///
/// What the width buys is the thing the notes are *for*. `../../README.md`
/// makes a project a first-class entity because it has a body -- the notes are
/// the context you are restoring, and reading them while looking at the task
/// list is the whole gesture. On a phone that costs a tab switch and the tab
/// switch is cheap; on a 1600px window, hiding half the screen to show one list
/// would be silly.
///
/// The panes do not share a scroll position, a refresh or a state of any kind.
/// They are the same two widgets the tabs hold, in a [Row].
class _WideBody extends StatelessWidget {
  const _WideBody({
    required this.view,
    required this.projectId,
    required this.tasksLabel,
    required this.notesLabel,
    required this.taskPane,
    required this.notePane,
  });

  final ProjectReady view;
  final String projectId;
  final String tasksLabel;
  final String notesLabel;
  final Widget taskPane;
  final Widget notePane;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(view.project.name),
        actions: _projectActions(view),
      ),
      body: Column(
        children: [
          if (view.isStale || view.refreshError != null)
            _ProjectBanner(view: view, projectId: projectId),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tasks get the larger half. Both panes are lists of one-line
                // rows, but the task rows carry controls (status, drag handle,
                // reminder date) that start colliding first, and the task list
                // is what the screen is opened for.
                Expanded(flex: 3, child: _Pane(label: tasksLabel, child: taskPane)),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(flex: 2, child: _Pane(label: notesLabel, child: notePane)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One half of the desktop layout: a label, and the list under it.
///
/// The label is what the tab strip said, and it says it for the same reason --
/// "Задачи · 2/7" is a fact about the project, not decoration, and losing it
/// when the window widens would mean the counter only exists on phones.
class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The app bar's right-hand side, shared by both layouts so that a control
/// cannot quietly exist on one width and not the other.
List<Widget> _projectActions(ProjectReady view) => <Widget>[
  if (view.isRefreshing)
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  // Archiving lives here rather than on the board card, because here is where
  // the decision is made: you archive a project after looking at what is left
  // in it, not while scrolling past it. It is also behind a menu rather than on
  // a button, since it is a once-a-month action.
  _ProjectMenu(project: view.project),
];

/// The project's own actions. Renaming, archiving, and -- for a project that is
/// already archived -- bringing it back.
///
/// Rename is first because it is the harmless one and archive is the one that
/// takes the project off the board; a menu that opens with its destructive item
/// under the thumb is a menu that gets mis-tapped.
///
/// It arrived after F4, with `PATCH /projects/:id` (B6). Before that a project's
/// entire write surface was `POST /projects` and the two archive routes, so a
/// typo in a name could only be fixed by deleting the project and losing its
/// tasks and notes with it.
class _ProjectMenu extends ConsumerWidget {
  const _ProjectMenu({required this.project});

  final Project project;

  bool get _archived => project.archivedAt != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_ProjectAction>(
      tooltip: 'Действия с проектом',
      onSelected: (action) => switch (action) {
        _ProjectAction.rename => _rename(context, ref),
        _ProjectAction.archive => _archive(context, ref),
        _ProjectAction.unarchive => _unarchive(context, ref),
      },
      itemBuilder: (_) => <PopupMenuEntry<_ProjectAction>>[
        const PopupMenuItem<_ProjectAction>(
          value: _ProjectAction.rename,
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Переименовать'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (_archived)
          const PopupMenuItem<_ProjectAction>(
            value: _ProjectAction.unarchive,
            child: ListTile(
              leading: Icon(Icons.unarchive_outlined),
              title: Text('Вернуть из архива'),
              contentPadding: EdgeInsets.zero,
            ),
          )
        else
          const PopupMenuItem<_ProjectAction>(
            value: _ProjectAction.archive,
            child: ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('В архив'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  /// No confirmation dialog, unlike the other two: a rename is reversible by
  /// renaming again, it is shown before the server has confirmed it, and it is
  /// put back with a message if the server refuses. The text field *is* the
  /// confirmation.
  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await askForProjectName(
      context,
      title: 'Переименовать проект',
      confirmLabel: 'Переименовать',
      initialName: project.name,
    );
    if (name == null || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(projectLifecycleProvider.notifier).rename(project, name),
      failure: 'Не удалось переименовать проект.',
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    // A plain yes/no, unlike deleting: archiving is reversible in one tap from
    // the archive screen, and the confirmation exists only so a mis-tap in a
    // menu does not silently take a project off the board.
    final confirmed = await confirmDestructive(
      context,
      title: 'Убрать проект с доски?',
      message:
          '«${project.name}» уйдёт в архив: с доски пропадёт, напоминания его '
          'задач приходить перестанут. Вернуть можно в любой момент.',
      confirmLabel: 'В архив',
    );
    if (!confirmed || !context.mounted) return;

    final navigator = Navigator.of(context);
    final ok = await runMutation(
      context,
      () => ref.read(projectLifecycleProvider.notifier).archive(project.id),
      failure: 'Не удалось архивировать проект.',
    );

    // Back to the board on success. Staying would leave the user inside a
    // project that is no longer on the board they came from, looking at a
    // screen whose every control still works -- which is true (an archived
    // project is still editable) and confusing.
    if (ok && navigator.canPop()) navigator.pop();
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) {
    return runMutation(
      context,
      () => ref.read(projectLifecycleProvider.notifier).unarchive(project.id),
      failure: 'Не удалось вернуть проект из архива.',
    );
  }
}

enum _ProjectAction { rename, archive, unarchive }

/// "What you are looking at is the cache / the last refresh failed."
///
/// Same contract as the board's banner and for the same reason: a list read out
/// of yesterday's snapshot that looks live is worse than no cache at all,
/// because every write made against it is a write against a state that may no
/// longer exist. Here it carries an extra warning the board's does not need --
/// while this is showing, a write is likely to fail, and that has to be said
/// before it does.
class _ProjectBanner extends ConsumerWidget {
  const _ProjectBanner({required this.view, required this.projectId});

  final ProjectReady view;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final failed = view.refreshError != null;

    final background = failed
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final foreground = failed
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;

    final text = <String>[
      if (failed) describeApiError(view.refreshError!),
      if (view.isStale)
        'Показан локальный снимок — изменения сейчас не сохранятся.'
      else if (failed)
        'Список задач может быть неактуален.',
    ].join(' ');

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            failed ? Icons.cloud_off : Icons.history,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
          _RetryButton(projectId: projectId, foreground: foreground),
        ],
      ),
    );
  }
}

class _RetryButton extends ConsumerWidget {
  const _RetryButton({required this.projectId, this.foreground});

  final String projectId;
  final Color? foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () {
        // Both halves, because both can be the thing that failed and the user
        // pressed one button. `projectHeader` is invalidated rather than
        // refreshed -- it has no notifier, being a plain future provider.
        ref.invalidate(projectHeaderProvider(projectId));
        ref.read(projectTasksProvider(projectId).notifier).refresh();
        ref.read(projectNotesProvider(projectId).notifier).refresh();
      },
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Повторить'),
      style: foreground == null
          ? null
          : TextButton.styleFrom(foregroundColor: foreground),
    );
  }
}

/// A scaffold for the states that have no project to put in the app bar.
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

/// A centred block of text. Same shape as the board's, duplicated rather than
/// shared because the board's version also has to be a scrollable for
/// pull-to-refresh and this one must not be.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  /// Null draws a progress indicator instead -- the loading state.
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
