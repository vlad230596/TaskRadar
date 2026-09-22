import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/project_badge.dart';
import '../domain/project_summary.dart';
import '../domain/task_age.dart';
import '../models/board_project.dart';
import '../models/scope.dart';
import '../navigation/app_routes.dart';
import '../providers/archive_providers.dart';
import '../providers/board_providers.dart';
import '../providers/focus_providers.dart';
import '../providers/inbox_providers.dart';
import '../providers/scope_providers.dart';
import '../providers/shell_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/glance.dart';
import '../widgets/mode_navigation.dart';
import 'shell_screen.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/project_name_dialog.dart';

/// Planning: every project, how old it is, and what is next in it (F12).
///
/// ## What this mode is for, and what it therefore hides
///
/// It is the mode you open in the morning to decide. So it shows the things a
/// decision is made from -- which projects exist, how long each has been
/// untouched, what the next task in each one is, and how big the sandbox
/// backlog has got -- and it shows nothing that is merely *true*: no closed
/// tasks, no archive, no history. Those live in the history mode, one tap away,
/// and keeping them out of here is the whole "экономия мыслетоплива" argument
/// in one screen.
///
/// ## Two equal layouts
///
/// A list ([_ProjectRow]) reads the *current task* of each project, which is
/// what you want with four projects. Tiles ([_ProjectTile]) fit twice as many
/// on a screen and answer "how much is in each", which is what you want with
/// fifteen. The spec calls them equal and the toggle is remembered
/// ([PlanLayoutPreference]) -- a preference that reset each launch would be the
/// app saying the list is the real one.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    /*
     * Watched for its lifetime, not its value (it has none).
     *
     * `boardReminderBridge` is what turns a refreshed board into an updated
     * alarm queue. It is `keepAlive`, but a Riverpod provider nobody subscribes
     * to is never *created*, so something has to be the first subscriber. This
     * screen is the right one: it is the mode the app opens in, and the bridge
     * is keepAlive so it outlives a switch to another mode.
     */
    ref.watch(boardReminderBridgeProvider);

    final view = ref.watch(boardViewProvider);
    final scope = ref.watch(activeScopeProvider);
    final layout = ref.watch(planLayoutPreferenceProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(boardProvider.notifier).refresh(),
      child: switch (view) {
        BoardLoading() => const _Filler(
          title: 'Загружаем доску…',
          body:
              'Если это первый запуск на этом устройстве, локального снимка '
              'ещё нет и приходится ждать сервер.',
        ),

        BoardUnavailable(:final error) => _Filler(
          icon: Icons.cloud_off,
          title: 'Не удалось загрузить доску',
          body:
              '${describeApiError(error)}\n\nЛокального снимка тоже нет — '
              'показать нечего. Потяните вниз или нажмите «Повторить».',
          action: const _RetryButton(),
        ),

        // Bounded on a wide window rather than stretched across it. A
        // project row is a name, one sentence and a strip of dots; at 1800 px
        // the dots end up a metre from the name they describe. The reference's
        // desktop plan solves this properly, with a sandbox panel beside
        // columns of projects -- that composition is F13's, and this is the
        // honest intermediate rather than a pretence at it.
        BoardReady() => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: _Board(view: view, scope: scope, layout: layout),
          ),
        ),
      },
    );
  }
}

/// The header of the planning mode: its name, the scope, and the layout toggle.
///
/// Above the scrollable rather than inside it. The mode's name is the answer to
/// "где я" and the toggle is how you get out of a layout you did not mean to
/// choose; both stop working if they scroll away, and a long board is exactly
/// when they are needed.
class PlanHeader extends ConsumerWidget {
  const PlanHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopes = ref.watch(scopesProvider).value ?? const <Scope>[];
    final active = ref.watch(activeScopeProvider);
    final layout = ref.watch(planLayoutPreferenceProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 18, Insets.gutter, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(AppMode.plan.title, style: AppText.mode),
                // Only with something to switch between. One scope is the
                // ordinary case and a picker offering a single option that is
                // already chosen is furniture -- the same rule the old
                // `ScopeSwitcher` followed, kept.
                if (scopes.length > 1 && active != null) ...<Widget>[
                  const SizedBox(height: 6),
                  _ScopePill(scopes: scopes, active: active),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _LayoutToggle(layout: layout),
          // The archive, the scopes, the settings and the way out. See
          // `ShellOverflowButton` for why it is here and not on the reference
          // page.
          const ShellOverflowButton(),
        ],
      ),
    );
  }
}

class _ScopePill extends ConsumerWidget {
  const _ScopePill({required this.scopes, required this.active});

  final List<Scope> scopes;
  final Scope active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<Scope>(
      tooltip: 'Какой экран проектов',
      position: PopupMenuPosition.under,
      onSelected: (scope) {
        if (scope.id == active.id) return;
        ref.read(selectedScopeIdProvider.notifier).select(scope.id);
      },
      itemBuilder: (_) => <PopupMenuEntry<Scope>>[
        for (final scope in scopes)
          PopupMenuItem<Scope>(value: scope, child: Text(scope.name)),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                active.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.chip.copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// List or tiles. Two 40x38 targets inside one 14 px trough, exactly as the
/// reference draws it.
class _LayoutToggle extends ConsumerWidget {
  const _LayoutToggle({required this.layout});

  final PlanLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ToggleHalf(
            icon: Icons.format_list_bulleted,
            label: 'Списком',
            active: layout == PlanLayout.list,
            onTap: () => ref
                .read(planLayoutPreferenceProvider.notifier)
                .select(PlanLayout.list),
          ),
          const SizedBox(width: 2),
          _ToggleHalf(
            icon: Icons.grid_view,
            label: 'Значками',
            active: layout == PlanLayout.tiles,
            onTap: () => ref
                .read(planLayoutPreferenceProvider.notifier)
                .select(PlanLayout.tiles),
          ),
        ],
      ),
    );
  }
}

class _ToggleHalf extends StatelessWidget {
  const _ToggleHalf({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: active ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(
              width: 40,
              height: 38,
              child: Icon(
                icon,
                size: 19,
                color: active ? AppColors.onInk : AppColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.view, required this.scope, required this.layout});

  final BoardReady view;
  final Scope? scope;
  final PlanLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Filtered here, on data the client already has (F7). See the long note in
    // `providers/scope_providers.dart` about why the board is never filtered on
    // the server.
    final projects = projectsInScope(view.projects, scope);
    final hiddenElsewhere = view.projects.length - projects.length;

    // Allocated over the *whole* board rather than the scope-filtered subset, so
    // that switching scope does not repaint the tiles that stayed on screen.
    final badgeColours = assignProjectBadgeColors(
      view.projects.map((entry) => entry.project.name),
    );

    return CustomScrollView(
      // Without this the list does not scroll when it is shorter than the
      // viewport, and pull-to-refresh on a two-project board does nothing.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        if (view.isStale || view.refreshError != null)
          SliverToBoxAdapter(child: _StaleBanner(view: view)),

        // The two fixed rows at the top: what is being worked on, and what is
        // waiting to be sorted. Both are *destinations*, not projects, so they
        // sit above the list in both layouts -- except that the tile layout
        // folds the sandbox into the grid as its first tile, which is what the
        // reference does and what keeps the grid from starting with a hole.
        const SliverToBoxAdapter(child: _FocusBar()),
        if (layout == PlanLayout.list)
          const SliverToBoxAdapter(child: _SandboxRow()),

        if (projects.isEmpty &&
            hiddenElsewhere == 0 &&
            layout == PlanLayout.list)
          const SliverToBoxAdapter(
            child: _Filler(
              icon: Icons.folder_open,
              title: 'Проектов пока нет',
              body:
                  'Кнопка «Проект» внизу заводит первый. Если проекты были и '
                  'пропали — посмотрите в архиве, он в настройках.',
              scrollable: false,
            ),
          )
        else if (projects.isEmpty && hiddenElsewhere > 0)
          SliverToBoxAdapter(
            child: _Filler(
              icon: Icons.workspaces_outline,
              title: 'Здесь пусто',
              body:
                  'В этом наборе проектов нет, а в остальных их '
                  '$hiddenElsewhere. Кнопка «Проект» внизу заведёт новый '
                  'именно здесь.',
              scrollable: false,
            ),
          )
        else if (layout == PlanLayout.tiles)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
            sliver: SliverGrid.count(
              crossAxisCount: isWideLayout(context) ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // 168 px tall at 179 px wide on a 390 px phone, which is what the
              // reference specifies as `grid-auto-rows: 168px`.
              childAspectRatio: 179 / 168,
              children: <Widget>[
                const _SandboxTile(),
                for (final entry in projects)
                  _ProjectTile(
                    key: ValueKey<String>(entry.project.id),
                    entry: entry,
                    badgeColor: badgeColours[entry.project.name],
                  ),
              ],
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
            sliver: SliverList.separated(
              itemCount: projects.length,
              separatorBuilder: (_, _) => const SizedBox(height: Insets.gap),
              itemBuilder: (context, index) => _ProjectRow(
                key: ValueKey<String>(projects[index].project.id),
                entry: projects[index],
              ),
            ),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              Insets.gap,
              Insets.gutter,
              24,
            ),
            child: _NewProjectButton(),
          ),
        ),
      ],
    );
  }
}

/// "В работе", with a dot per task in the set.
///
/// Точки — из `design/reference/Main.html`: девять пикселей янтаря на чернилах,
/// по одной на задачу набора. Больше полоска ничего и не говорит, и это
/// намеренно — «сколько я на себя взял» отвечается одним взглядом, а что именно
/// взято, показывает режим работы.
///
/// Пустой набор рисует не пустое место, а слова: полоска без точек и без
/// объяснения читалась бы как «не загрузилось».
///
/// Тап переключает режим, а не открывает экран поверх, — чтобы кнопка «назад»
/// продолжала значить «выйти из подэкрана» и никогда «назад на один режим».
class _FocusBar extends ConsumerWidget {
  const _FocusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taken = ref.watch(focusedTaskIdsProvider).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 0, Insets.gutter, 10),
      child: Material(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(Radii.row),
        child: InkWell(
          onTap: () =>
              ref.read(shellModeProvider.notifier).select(AppMode.work),
          borderRadius: BorderRadius.circular(Radii.row),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: <Widget>[
                const Icon(Icons.adjust, size: 20, color: AppColors.onInk),
                const SizedBox(width: 10),
                Text(
                  'В работе',
                  style: AppText.action.copyWith(color: AppColors.onInk),
                ),
                const SizedBox(width: 10),
                if (taken == 0)
                  Expanded(
                    child: Text(
                      'пусто — наберите задач',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: AppColors.voiceMuted,
                      ),
                    ),
                  )
                else
                  Expanded(child: _FocusDots(taken: taken)),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.onInk,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Точки набора внутри полоски «В работе»: 9 px янтаря на чернилах.
///
/// Янтарь, а не белое: белые точки на чернилах слились бы с белой же подписью
/// рядом, и полоска перестала бы отвечать на свой единственный вопрос с одного
/// взгляда. Тот же цвет отмечает набранное и на тёмной плитке песочницы.
class _FocusDots extends StatelessWidget {
  const _FocusDots({required this.taken});

  final int taken;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < taken; i++)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.waitingDotOnInk,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// The sandbox as a row: what is in it, how long it has been there.
///
/// The count is the whole point. A sandbox is a promise that a thought written
/// down there will be dealt with later, and the only thing that keeps that
/// promise is seeing, every morning, that three lines are still waiting. A
/// count that is missing while the request is in flight is right; a count that
/// says "0" and then changes to "3" is a small lie told on every cold start --
/// hence `inboxCount` being nullable.
class _SandboxRow extends ConsumerWidget {
  const _SandboxRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(inboxCountProvider);
    final oldest = _oldestSandboxDays(ref);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 0, Insets.gutter, 14),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.row),
        child: InkWell(
          onTap: () => AppRoutes.openInbox(context),
          borderRadius: BorderRadius.circular(Radii.row),
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(Radii.row),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.indigoFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inbox_outlined,
                    size: 19,
                    color: AppColors.indigoLink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('Песочница', style: AppText.action),
                      if (oldest != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          'не разобрано ${formatDays(oldest)}',
                          style: AppText.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                if (count != null && count > 0)
                  Text(
                    '$count',
                    style: AppText.number.copyWith(color: AppColors.alarm),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sandbox as the grid's first tile, dark so it does not read as a project.
class _SandboxTile extends ConsumerWidget {
  const _SandboxTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(inboxCountProvider) ?? 0;
    final newest = ref.watch(inboxProvider).value;
    final oldest = _oldestSandboxDays(ref);

    return Material(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(Radii.panel),
      child: InkWell(
        onTap: () => AppRoutes.openInbox(context),
        borderRadius: BorderRadius.circular(Radii.panel),
        child: Padding(
          padding: const EdgeInsets.all(Insets.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.railActive,
                      borderRadius: BorderRadius.circular(Radii.row),
                    ),
                    child: const Icon(
                      Icons.inbox_outlined,
                      size: 21,
                      color: AppColors.voiceBright,
                    ),
                  ),
                  const Spacer(),
                  if (count > 0)
                    Text(
                      '$count',
                      style: AppText.number.copyWith(
                        color: AppColors.waitingDotOnInk,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Песочница',
                style: AppText.action.copyWith(color: AppColors.onInk),
              ),
              if (newest != null && newest.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    newest.first.text,
                    // Two, not three: a 168 px tile holds a 40 px badge, a
                    // name, a footer and its padding, and the third line of
                    // preview is the one that overruns them.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.hint.copyWith(
                      fontSize: 12.5,
                      color: AppColors.voiceMuted,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if (oldest != null)
                Text(
                  'лежит ${formatDays(oldest)}',
                  maxLines: 1,
                  softWrap: false,
                  style: AppText.caption.copyWith(
                    fontSize: 11.5,
                    color: AppColors.waitingDotOnInk,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How long the oldest thing in the sandbox has been sitting there, or null
/// when it is empty (or has not loaded).
int? _oldestSandboxDays(WidgetRef ref) {
  final items = ref.watch(inboxProvider).value;
  if (items == null || items.isEmpty) return null;

  int? oldest;
  for (final item in items) {
    final days = daysSince(item.createdAt);
    if (days == null) continue;
    if (oldest == null || days > oldest) oldest = days;
  }
  return oldest;
}

/// One project, as a row: name, age, the task that is next, and the shape of
/// the list.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.entry, super.key});

  final BoardProject entry;

  @override
  Widget build(BuildContext context) {
    final summary = ProjectSummary.of(entry);
    final age = daysSinceMovement(
      entry.project.updatedAt,
      createdAt: entry.project.createdAt,
    );

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        onTap: () =>
            AppRoutes.openProject(context, projectId: entry.project.id),
        borderRadius: BorderRadius.circular(Radii.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // The *name* is what gives way when the row is too narrow,
                  // never the chip beside it. See the note on [AgeChip].
                  Expanded(
                    child: Text(
                      entry.project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.projectName,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AgeChip(days: age),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _currentLine(summary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(child: TaskDots(tasks: entry.tasks)),
                  TaskCount(done: summary.doneCount, total: summary.totalCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One project, as a tile: badge, count, the newest task, the shape of the
/// list.
class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.entry, this.badgeColor, super.key});

  final BoardProject entry;

  /// This project's share of the board-wide allocation. See
  /// [assignProjectBadgeColors]: a grid of tiles is exactly where two projects
  /// on one colour would be read as one.
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final summary = ProjectSummary.of(entry);
    final age = daysSinceMovement(
      entry.project.updatedAt,
      createdAt: entry.project.createdAt,
    );

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(Radii.panel),
      child: InkWell(
        onTap: () =>
            AppRoutes.openProject(context, projectId: entry.project.id),
        borderRadius: BorderRadius.circular(Radii.panel),
        child: Container(
          padding: const EdgeInsets.all(Insets.card),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(Radii.panel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ProjectBadge(name: entry.project.name, color: badgeColor),
                  const Spacer(),
                  Text('${summary.totalCount}', style: AppText.number),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      entry.project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.action,
                    ),
                  ),
                  // A blocker is the one fact worth a whole dot of its own on a
                  // tile this small: it is the difference between a project
                  // that is merely quiet and one that cannot move.
                  if (summary.hasBlocker) ...<Widget>[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.waitingDot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  _currentLine(summary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.hint.copyWith(fontSize: 12.5),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TaskDots(tasks: entry.tasks, size: 8, maxDots: 8),
                  ),
                  const SizedBox(width: 4),
                  if (age != null)
                    Text(
                      formatAgeShort(age),
                      maxLines: 1,
                      softWrap: false,
                      style: AppText.caption.copyWith(
                        fontSize: 11.5,
                        color: isStaleAge(age)
                            ? AppColors.waitingInk
                            : AppColors.muted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sentence under a project's name.
///
/// The three empty cases read very differently to a human and only one of them
/// is a call to action, which is why `ProjectSummary.emptiness` keeps them
/// apart rather than collapsing them into "—".
String _currentLine(ProjectSummary summary) {
  return switch (summary.emptiness) {
    ProjectEmptiness.hasCurrentTask => summary.currentTask!.title,
    ProjectEmptiness.noTasks => 'задач пока нет',
    ProjectEmptiness.allDone => 'всё сделано',
    ProjectEmptiness.allBlocked => 'всё ждёт',
  };
}

class _NewProjectButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.muted,
          side: const BorderSide(color: AppColors.lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card),
          ),
        ),
        onPressed: () => _createProject(context, ref),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Проект'),
      ),
    );
  }
}

/// Asks for a name and creates the project, then opens it.
///
/// Opening it is not a flourish: a project created here is empty, and the next
/// thing anyone does is type its first task. Landing back on the list instead
/// would mean finding the new card and tapping it, which is two gestures spent
/// on a question that was already answered.
Future<void> _createProject(BuildContext context, WidgetRef ref) async {
  final name = await askForProjectName(
    context,
    title: 'Новый проект',
    confirmLabel: 'Создать',
  );
  if (name == null || !context.mounted) return;

  // Into the scope currently on screen (F7). A project that landed somewhere
  // the user is not looking would be the worst possible answer to "where did it
  // go".
  final scopeId = ref.read(activeScopeProvider)?.id;

  String? createdId;
  final ok = await runMutation(context, () async {
    createdId =
        (await ref
                .read(projectLifecycleProvider.notifier)
                .create(name, scopeId: scopeId))
            .id;
  }, failure: 'Не удалось создать проект.');

  if (!ok || createdId == null || !context.mounted) return;
  await AppRoutes.openProject(context, projectId: createdId!);
}

/// "You are looking at the past, and here is how far into it."
///
/// The plan asks for this explicitly: a cached board that silently looks like a
/// live one is worse than no cache, because the user acts on yesterday's state
/// believing it is today's.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.view});

  final BoardReady view;

  @override
  Widget build(BuildContext context) {
    final failed = view.refreshError != null;

    final lines = <String>[
      if (failed) describeApiError(view.refreshError!),
      if (view.isStale)
        'Показан локальный снимок от ${formatUpdatedAt(view.updatedAt)}.'
      else
        'Данные от ${formatUpdatedAt(view.updatedAt)}.',
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(Insets.gutter, 0, Insets.gutter, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: failed ? AppColors.waitingFill : AppColors.indigoFill,
        border: Border.all(
          color: failed ? AppColors.waitingLine : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                failed ? Icons.cloud_off : Icons.history,
                size: 18,
                color: failed ? AppColors.waitingInk : AppColors.indigoInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failed ? 'Не удалось обновить' : 'Данные из кэша',
                  style: AppText.action.copyWith(
                    color: failed ? AppColors.waitingInk : AppColors.indigoInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            lines.join(' '),
            style: AppText.hint.copyWith(
              color: failed ? AppColors.waitingInk : AppColors.indigoInk,
            ),
          ),
          if (failed) ...<Widget>[
            const SizedBox(height: 4),
            const Align(alignment: Alignment.centerLeft, child: _RetryButton()),
          ],
        ],
      ),
    );
  }
}

class _RetryButton extends ConsumerWidget {
  const _RetryButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => ref.read(boardProvider.notifier).refresh(),
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Повторить'),
    );
  }
}

/// A centred block of text that still fills the viewport, so pull-to-refresh
/// works on top of it.
class _Filler extends StatelessWidget {
  const _Filler({
    required this.title,
    required this.body,
    this.icon,
    this.action,
    this.scrollable = true,
  });

  /// Null draws a progress indicator instead — the loading state.
  final IconData? icon;
  final String title;
  final String body;
  final Widget? action;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon == null)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppText.projectName),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: AppText.hint),
          if (action != null) ...<Widget>[const SizedBox(height: 12), action!],
        ],
      ),
    );

    if (!scrollable) return Center(child: content);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// "сегодня в 09:12" / "вчера в 21:40" / "14.09 в 08:05".
///
/// Relative wording for the two days that matter and an absolute date beyond
/// them: the question being answered is "is this stale enough to distrust?",
/// and "вчера" answers it instantly while "15.09" needs a moment of arithmetic.
/// Everything here is local wall-clock, which is the only clock the reader has.
String formatUpdatedAt(DateTime updatedAt, {DateTime? now}) {
  final local = updatedAt.toLocal();
  final today = (now ?? DateTime.now()).toLocal();

  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  final date = DateTime(local.year, local.month, local.day);
  final midnight = DateTime(today.year, today.month, today.day);
  final days = midnight.difference(date).inDays;

  return switch (days) {
    0 => 'сегодня в $time',
    1 => 'вчера в $time',
    _ =>
      '${local.day.toString().padLeft(2, '0')}.'
          '${local.month.toString().padLeft(2, '0')} в $time',
  };
}
