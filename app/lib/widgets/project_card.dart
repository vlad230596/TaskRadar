import 'package:flutter/material.dart';

import '../domain/project_summary.dart';
import '../domain/reminders.dart';
import '../models/board_project.dart';

/// One project on the board, on a narrow window.
///
/// The wide window draws the same project as a column with its whole task line
/// instead (`project_column.dart`, F6). They share the header and the summary
/// logic and differ in exactly one decision -- how much of the task list is
/// worth printing when there is room for it.
///
/// ## What this card is for
///
/// `../../README.md` states the product problem: the expensive thing is not
/// writing tasks down, it is **restoring context** on a project that has been
/// in the background for two weeks. The morning use of this screen is to scroll
/// it once and know, per project, "what is happening here" without opening
/// anything.
///
/// So the layout is ordered by how much each element answers that question:
///
/// 1. the project name -- which project this is;
/// 2. the **current task** -- the single sentence that restores the context;
/// 3. done/total -- whether this project is moving at all;
/// 4. badges -- whether it is *stuck*, and whether it is stuck on something
///    that is worth acting on today.
///
/// The due-reminder badge is separated from the plain blocker badge on purpose.
/// "This project is waiting on something" is background information; "the day
/// you said to come back has arrived" is the one thing on this screen that asks
/// for action right now, and it is the reason the whole native client exists
/// (see `../../../flutter-migration-plan.md`). Rendering them as one badge would
/// bury it.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    required this.entry,
    required this.onTap,
    this.now,
    super.key,
  });

  final BoardProject entry;
  final VoidCallback onTap;

  /// Fixes "today" for tests. Production passes nothing; see [isReminderDue].
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = ProjectSummary.of(entry, now: now);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.project.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _DoneCounter(summary: summary),
                ],
              ),
              const SizedBox(height: 10),
              _Progress(summary: summary),
              const SizedBox(height: 12),
              _CurrentTask(summary: summary),
              ..._badges(context, summary),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _badges(BuildContext context, ProjectSummary summary) {
    final theme = Theme.of(context);
    final badges = <Widget>[];

    if (summary.hasDueReminder) {
      // `nextReminderAt` is the earliest reminder date in the project, and a
      // due date is by definition earlier than a not-yet-due one -- so when
      // anything is due, the earliest date *is* the earliest due date. No
      // second traversal needed.
      badges.add(
        _Badge(
          icon: Icons.notifications_active,
          label: 'Напоминание · ${formatReminderDate(summary.nextReminderAt!)}',
          background: theme.colorScheme.errorContainer,
          foreground: theme.colorScheme.onErrorContainer,
        ),
      );
    }

    if (summary.hasBlocker) {
      final base = summary.blockedCount > 1
          ? 'Блокеров: ${summary.blockedCount}'
          : 'Блокер';

      // The date is appended only when nothing is due yet: when it is, the red
      // badge above already carries it, and printing the same date twice makes
      // the card harder to scan rather than clearer.
      final label = (!summary.hasDueReminder && summary.nextReminderAt != null)
          ? '$base · ${formatReminderDate(summary.nextReminderAt!)}'
          : base;

      badges.add(
        _Badge(
          icon: Icons.pause_circle_outline,
          label: label,
          background: theme.colorScheme.secondaryContainer,
          foreground: theme.colorScheme.onSecondaryContainer,
        ),
      );
    }

    if (badges.isEmpty) return const <Widget>[];

    return <Widget>[
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: badges),
    ];
  }
}

/// "3 / 7". Plain digits rather than a percentage: at 5-10 tasks a percentage
/// is false precision, and the raw counts also say how big the project is.
class _DoneCounter extends StatelessWidget {
  const _DoneCounter({required this.summary});

  final ProjectSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Сделано ${summary.doneCount} из ${summary.totalCount}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '${summary.doneCount} / ${summary.totalCount}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.summary});

  final ProjectSummary summary;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: summary.progress,
        minHeight: 5,
        // The indeterminate animation is what a null value means, and an
        // endlessly animating bar on every card would turn the board into a
        // disco. A finished-ness of zero is a real, static answer.
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

/// The line that actually restores the context.
class _CurrentTask extends StatelessWidget {
  const _CurrentTask({required this.summary});

  final ProjectSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (IconData icon, String text, Color color, bool muted) =
        switch (summary.emptiness) {
          ProjectEmptiness.hasCurrentTask => (
            Icons.play_arrow_rounded,
            summary.currentTask!.title,
            scheme.primary,
            false,
          ),
          ProjectEmptiness.noTasks => (
            Icons.more_horiz,
            'Задач пока нет',
            scheme.onSurfaceVariant,
            true,
          ),
          ProjectEmptiness.allDone => (
            Icons.check_circle,
            'Все задачи сделаны',
            scheme.onSurfaceVariant,
            true,
          ),
          // Distinguished from "all done" deliberately: an all-blocked project
          // looks finished by the counter alone, and it is the opposite --
          // it is the one that needs a nudge.
          ProjectEmptiness.allBlocked => (
            Icons.pause_circle_filled,
            'Нет текущей задачи — всё в блокерах',
            scheme.onSurfaceVariant,
            true,
          ),
        };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
              fontStyle: muted ? FontStyle.italic : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
