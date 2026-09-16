import 'package:flutter/material.dart';

import '../domain/project_summary.dart';
import '../domain/reminders.dart';
import '../models/board_project.dart';
import '../models/task.dart';
import '../models/task_status.dart';

/// One project as a column on the wide board (F6).
///
/// ## Why this is not [ProjectCard] in a grid
///
/// The card answers "what is happening in this project" in four lines, because
/// on a phone four lines is what a project gets before the next one has to be
/// on screen. `../../../README.md` describes something else for the desktop:
/// 10-15 projects visible at once, each a column with its **task line running
/// top to bottom** -- so the extra width does not buy bigger text, it buys the
/// shape of the project itself. A long column with two filled dots at the top
/// says "this has barely moved" without a counter being read at all.
///
/// The header is deliberately the card's header (name, done counter, progress),
/// so switching layouts does not feel like switching applications. What is new
/// below it is the line.
///
/// ## What each row shows, and why not all of them show a title
///
/// The line is ordered by how much each row is worth reading, which is the same
/// hierarchy the React client used (`frontend/src/components/TaskRow.tsx`) and
/// the same one the card's badges follow:
///
/// 1. **the current task** -- title, highlighted. The one sentence that
///    restores the context, and the reason to look at this column at all;
/// 2. **blocked tasks** -- title plus the date they are waiting for, because a
///    blocker is unfinished work that will never speak up on its own, and a
///    blocker whose day has come is the single thing on this screen that asks
///    for action today;
/// 3. **everything else** -- a dot, with the title in a tooltip.
///
/// That third rule is the one worth defending. Printing every done and pending
/// title turns a 12-task project into a wall of text and a 15-project board
/// into something you scroll instead of glance at, which is precisely the
/// property the product is built around. A dot still carries the two facts that
/// matter in aggregate -- how much there is, and how much of it is behind you --
/// and the title is one hover away, because this layout only ever renders where
/// there is a mouse.
class ProjectColumn extends StatelessWidget {
  const ProjectColumn({
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
      // The grid outside owns the spacing between columns, so the column owns
      // none of it -- otherwise the gap between two columns is the sum of two
      // numbers maintained in two files.
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // The whole column, not just its title as in the React version: there
        // is nothing else to click in here, and a 260px-wide target beats a
        // text link for a mouse crossing the screen.
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Tooltip(
                      // A long name is ellipsed at two lines; on the desktop
                      // the whole of it is a hover away.
                      message: entry.project.name,
                      child: Text(
                        entry.project.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${summary.doneCount} / ${summary.totalCount}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: summary.progress,
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 10),
              if (entry.tasks.isEmpty)
                Text(
                  'Задач пока нет',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                // Server order, never re-sorted here -- see the note on
                // `Task.position`. The line *is* that order; grouping it by
                // status would destroy the one thing it draws.
                for (final task in entry.tasks)
                  _TaskLine(
                    key: ValueKey<String>(task.id),
                    task: task,
                    now: now,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One task in the line. See the hierarchy in [ProjectColumn].
class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.task, required this.now, super.key});

  final Task task;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    // `isCurrent` is checked before the status, because it is the stronger
    // fact: the server computes it (`backend/src/domain/isCurrent.ts`) and a
    // current task is by construction neither done nor blocked.
    if (task.isCurrent) return _CurrentLine(task: task);
    if (task.status == TaskStatus.blocked) {
      return _BlockedLine(task: task, now: now);
    }
    return _DotLine(task: task);
  }
}

/// The current task: the only row here meant to be read at a distance.
class _CurrentLine extends StatelessWidget {
  const _CurrentLine({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.play_arrow_rounded, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              task.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A blocked task: its title, and the date it is waiting for.
///
/// The date is a chip in the error colours once it has arrived and quiet text
/// until then -- the same split the card's two badges make, for the same
/// reason. "Waiting on something" is background; "the day you named is today"
/// is the whole product.
class _BlockedLine extends StatelessWidget {
  const _BlockedLine({required this.task, required this.now});

  final Task task;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final remindAt = task.remindAt;
    final due = remindAt != null && isReminderDue(remindAt, now: now);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              Icons.pause_circle_outline,
              size: 14,
              color: due ? scheme.error : scheme.secondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
                if (remindAt == null)
                  // A dateless blocker is the failure this product exists to
                  // prevent (see `task_list.dart`), so the column says so out
                  // loud rather than leaving the row merely quiet.
                  Text(
                    'без даты',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (due)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'проверить · ${formatReminderDate(remindAt)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Text(
                    'напомнить ${formatReminderDate(remindAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.secondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Done, or pending but not current: a dot, and the title on hover.
class _DotLine extends StatelessWidget {
  const _DotLine({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = task.status == TaskStatus.done;

    return Tooltip(
      message: task.title,
      child: Semantics(
        label: done ? 'Сделано: ${task.title}' : 'Ожидает: ${task.title}',
        // Full width rather than the dot's own nine pixels: the tooltip is the
        // only way to read this title, and a nine-pixel hover target is a way
        // of not offering it.
        child: SizedBox(
          height: 15,
          width: double.infinity,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 9,
              height: 9,
              // Filled means behind you, hollow means ahead of you -- the same
              // vocabulary as the React line, worth keeping for eyes that have
              // read it for months.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? scheme.onSurfaceVariant : null,
                border: done
                    ? null
                    : Border.all(color: scheme.outlineVariant, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
