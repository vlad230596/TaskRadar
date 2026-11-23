import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../domain/project_badge.dart';
import '../../models/board_project.dart';
import '../../models/goal.dart';
import '../../models/task.dart';
import '../../models/task_status.dart';
import '../../providers/board_providers.dart';
import '../../providers/goal_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../glance.dart';
import '../ime_text_controller.dart';
import 'crown.dart';
import 'goal_icons.dart';
import 'goal_picker_sheet.dart';

/// «Задачи в цель» (`design/goals-ideas-spec.md`, п. 5; `Goal-Link.html`):
/// tasks of every project on the board, grouped by project, with a search, to
/// link to [goal]. Linked in the order they were ticked, at the end of the
/// goal.
Future<void> showGoalLinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required GoalView goal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.voiceBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
    ),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: GoalLinkSheet(goal: goal),
    ),
  );
}

/// The sheet's content. Public for the widget tests.
class GoalLinkSheet extends ConsumerStatefulWidget {
  const GoalLinkSheet({required this.goal, super.key});

  final GoalView goal;

  @override
  ConsumerState<GoalLinkSheet> createState() => _GoalLinkSheetState();
}

class _GoalLinkSheetState extends ConsumerState<GoalLinkSheet> {
  final ImeTextController _search = ImeTextController();

  /// Ticked task ids, in the order they were ticked.
  final List<String> _chosen = <String>[];
  bool _openOnly = true;
  String? _projectId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    if (_chosen.isEmpty || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final goals = ref.read(goalsProvider.notifier);
    try {
      for (final id in _chosen) {
        await goals.linkTask(widget.goal.id, id);
      }
      navigator.pop();
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось связать. ${describeApiError(error)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(boardViewProvider);
    final projects = view is BoardReady
        ? view.projects
        : const <BoardProject>[];
    final index = ref.watch(taskGoalIndexProvider);
    final active = ref.watch(activeContourIdProvider);
    final inGoal = <String>{for (final t in widget.goal.tasks) t.id};
    final goalProjects = <String>{
      for (final t in widget.goal.tasks) t.projectId,
    };
    final colors = assignProjectBadgeColors(
      projects.map((p) => p.project.name),
    );

    bool shown(Task task) =>
        !_openOnly ||
        task.status != TaskStatus.done ||
        inGoal.contains(task.id);

    // Projects where the goal already has tasks first, then by freshness.
    String freshest(BoardProject p) => p.tasks.fold<String>(
      p.project.updatedAt,
      (latest, t) => t.updatedAt.compareTo(latest) > 0 ? t.updatedAt : latest,
    );
    final ordered = <BoardProject>[...projects]
      ..sort((a, b) {
        final ag = goalProjects.contains(a.project.id) ? 0 : 1;
        final bg = goalProjects.contains(b.project.id) ? 0 : 1;
        if (ag != bg) return ag - bg;
        return freshest(b).compareTo(freshest(a));
      });
    final filtered = <BoardProject>[
      for (final p in ordered)
        if (_projectId == null || p.project.id == _projectId) p,
    ];

    final query = _search.text.trim().toLowerCase();
    final rows = <Widget>[];
    if (query.isNotEmpty) {
      for (final p in filtered) {
        for (final task in p.tasks) {
          if (!shown(task) || !task.title.toLowerCase().contains(query)) {
            continue;
          }
          rows.add(_row(task, index, active, inGoal, project: p.project.name));
        }
      }
    } else {
      for (final p in filtered) {
        final tasks = p.tasks.where(shown).toList();
        if (tasks.isEmpty) continue;
        rows.add(
          SizedBox(
            height: 40,
            child: Row(
              children: <Widget>[
                ProjectBadge(
                  name: p.project.name,
                  size: 22,
                  color: colors[p.project.name],
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    p.project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _groupName,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${tasks.length}', style: _groupCount),
              ],
            ),
          ),
        );
        for (final task in tasks) {
          rows.add(_row(task, index, active, inGoal));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.voiceLine,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Задачи в цель',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: AppColors.voiceInk,
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
          Row(
            children: <Widget>[
              const CrownIcon(size: 13, color: AppColors.crown),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.voiceMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: TextField(
              controller: _search,
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontSize: 15,
                color: AppColors.voiceInk,
              ),
              cursorColor: AppColors.voiceBright,
              decoration: InputDecoration(
                hintText: 'Найти задачу во всех проектах',
                hintStyle: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  color: Color(0xFF7F88C4),
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: Color(0xFF7F88C4),
                ),
                filled: true,
                fillColor: AppColors.voiceWell,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.voiceLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.voiceLevelHigh,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _FilterChip(
                label: 'Открытые',
                on: _openOnly,
                icon: _openOnly ? Icons.check : null,
                onTap: () => setState(() => _openOnly = !_openOnly),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: PopupMenuButton<String>(
                  tooltip: 'Проект',
                  color: AppColors.card,
                  onSelected: (id) =>
                      setState(() => _projectId = id.isEmpty ? null : id),
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: '',
                      child: Text('Все проекты'),
                    ),
                    for (final p in ordered)
                      PopupMenuItem<String>(
                        value: p.project.id,
                        child: Text(p.project.name),
                      ),
                  ],
                  child: _FilterChip(
                    label: _projectId == null
                        ? 'Все проекты'
                        : projects
                                  .where((p) => p.project.id == _projectId)
                                  .firstOrNull
                                  ?.project
                                  .name ??
                              'Проект',
                    on: _projectId != null,
                    trailing: Icons.expand_more,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      view is BoardReady
                          ? 'Ничего не нашлось.'
                          : 'Проекты ещё загружаются.',
                      style: AppText.voiceNote,
                    ),
                  )
                : ListView(children: rows),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 22),
            child: SizedBox(
              height: 64,
              child: FilledButton(
                onPressed: _chosen.isEmpty || _busy
                    ? null
                    : () => unawaited(_link()),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.onInk,
                  foregroundColor: AppColors.voiceBackground,
                  disabledBackgroundColor: AppColors.voiceLine,
                  disabledForegroundColor: AppColors.voiceMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                child: Text(
                  _chosen.isEmpty
                      ? 'Выберите задачи'
                      : 'Связать · ${_chosen.length}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    Task task,
    Map<String, List<TaskGoalRef>>? index,
    String? active,
    Set<String> inGoal, {
    String? project,
  }) {
    final already = inGoal.contains(task.id);
    final checked = already || _chosen.contains(task.id);
    final others = <TaskGoalRef>[
      for (final g in goalsOfTask(index, task.id, task.goals))
        if (g.id != widget.goal.id) g,
    ];
    final bright = others.any((g) => active == null || g.contourId == active);
    final subtitle = already ? 'уже в цели' : project;
    return Opacity(
      opacity: already ? 0.55 : 1,
      child: InkWell(
        onTap: already
            ? null
            : () => setState(() {
                if (!_chosen.remove(task.id)) _chosen.add(task.id);
              }),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: <Widget>[
              DarkCheck(checked: checked),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.title,
                        style: TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          height: 1.3,
                          color: task.status == TaskStatus.done
                              ? AppColors.voiceMuted
                              : AppColors.voiceInk,
                          decoration: task.status == TaskStatus.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontFamily: AppFonts.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.voiceMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (others.isNotEmpty) ...<Widget>[
                const SizedBox(width: 10),
                CrownChip(
                  bright: bright,
                  size: 18,
                  iconSize: 11,
                  radius: 6,
                  onDark: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.on,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final String label;
  final bool on;
  final IconData? icon;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: on ? AppColors.railActive : Colors.transparent,
        border: on ? null : Border.all(color: AppColors.voiceLine),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: AppColors.onInk),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: on ? AppColors.onInk : AppColors.voiceBright,
              ),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 6),
            Icon(trailing, size: 16, color: AppColors.voiceBright),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: chip,
    );
  }
}

const TextStyle _groupName = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 13,
  color: AppColors.voiceBright,
);

const TextStyle _groupCount = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w600,
  fontSize: 13,
  color: AppColors.voiceMuted,
);
