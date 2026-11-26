import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../domain/goals.dart';
import '../../domain/reminders.dart';
import '../../domain/today_view.dart';
import '../../models/task.dart';
import '../../models/task_status.dart';
import '../../navigation/app_routes.dart';
import '../../providers/focus_providers.dart';
import '../../providers/outbox_providers.dart';
import '../../providers/today_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../goals/crown.dart';
import '../task_list.dart' show chooseRowAction;
import 'date_sheet.dart';
import 'next_sheet.dart';
import 'row_date_actions.dart';
import 'today_icons.dart';

/// The day block of «Работа» (`design/today-history-spec.md` §4): «С прошлых
/// дней» and «Сегодня», under the goal block and over the working set.
///
/// Computed on the client from the board ([dayViewProvider]), so it works
/// offline; it takes no slot of the set, hides nothing and calls no duel.
class DayBlock extends ConsumerWidget {
  const DayBlock({this.wide = false, super.key});

  /// The desktop's day column: rows 44, titles up to two lines.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A day block opened after midnight moves to the new day -- after this
    // frame, as a build must not change a provider.
    final shownDay = ref.watch(todayKeyProvider);
    if (calendarDateForApi(ref.read(appClockProvider)()) != shownDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(todayKeyProvider.notifier).check();
      });
    }
    final view = ref.watch(dayViewProvider);
    final pad = wide
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 0);
    if (view == null) {
      return Padding(padding: pad, child: const _Skeleton());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (view.tail.isNotEmpty)
          Padding(
            padding: pad,
            child: TailCard(tail: view.tail, today: view.date, wide: wide),
          ),
        if (view.total > 0)
          Padding(
            padding: wide && view.tail.isNotEmpty
                ? const EdgeInsets.only(top: 12)
                : pad,
            child: TodayCard(view: view, wide: wide),
          )
        else if (view.tail.isEmpty)
          Padding(padding: pad, child: const _EmptyToday()),
      ],
    );
  }
}

// --- «С прошлых дней» ---------------------------------------------------------

class TailCard extends ConsumerStatefulWidget {
  const TailCard({
    required this.tail,
    required this.today,
    this.wide = false,
    super.key,
  });

  final List<DayTask> tail;
  final String today;
  final bool wide;

  @override
  ConsumerState<TailCard> createState() => _TailCardState();
}

class _TailCardState extends ConsumerState<TailCard> {
  /// Not remembered: each opening of «Работа» shows three again (§4.1).
  bool _expanded = false;

  static const int _folded = 3;

  Future<void> _allToday() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final moved = <(Task, String?, String?)>[
      for (final entry in widget.tail)
        (entry.task, taskDay(entry.task.remindAt), entry.task.remindTime),
    ];
    try {
      for (final (task, _, _) in moved) {
        await setTaskDate(container, task, date: widget.today);
      }
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Не удалось перенести. ${describeApiError(error)}'),
          ),
        );
      return;
    }
    if (!messenger.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${_tasks(moved.length)} на сегодня'),
          persist: false,
          action: SnackBarAction(
            label: 'Отменить',
            // Each one gets its own date back.
            onPressed: () => unawaited(() async {
              for (final (task, date, time) in moved) {
                try {
                  await setTaskDate(
                    container,
                    freshTask(container, task),
                    date: date,
                    time: time,
                  );
                } catch (error) {
                  debugPrint('Undo of «Все в сегодня» failed: $error');
                }
              }
            }()),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final tail = widget.tail;
    final shown = _expanded || tail.length <= _folded + 1
        ? tail
        : tail.take(_folded).toList();
    final rest = tail.length - shown.length;

    return Container(
      key: const ValueKey<String>('day-tail'),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      decoration: BoxDecoration(
        color: AppColors.tailFill,
        border: Border.all(color: AppColors.tailLine),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: <Widget>[
                  const TodayIcon(
                    TodayGlyph.calendar,
                    size: 16,
                    color: AppColors.waitingInk,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'С прошлых дней',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _headStyle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${tail.length}',
                    style: _headStyle.copyWith(color: AppColors.waitingInk),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: () => unawaited(_allToday()),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.card,
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.tailLine),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: _buttonText,
                      ),
                      child: const Text('Все в сегодня'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < shown.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                  height: 1,
                  color: AppColors.tailLine.withValues(alpha: 0.6),
                ),
              ),
            _TailRow(entry: shown[i], today: widget.today, wide: widget.wide),
          ],
          if (rest > 0)
            InkWell(
              onTap: () => setState(() => _expanded = true),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'Ещё $rest',
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.waitingInk,
                      ),
                    ),
                    const Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppColors.waitingInk,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «14 задач» with the right ending.
String _tasks(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'задача'
      : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
      ? 'задачи'
      : 'задач';
  return '$n $word';
}

enum _TailMenu { pick, stack }

class _TailRow extends ConsumerWidget {
  const _TailRow({required this.entry, required this.today, this.wide = false});

  final DayTask entry;
  final String today;
  final bool wide;

  Task get task => entry.task;

  Future<void> _menu(BuildContext context) async {
    final chosen = await showModalBottomSheet<_TailMenu>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              minTileHeight: 48,
              leading: const TodayIcon(
                TodayGlyph.calendar,
                size: 22,
                color: AppColors.inkSoft,
              ),
              title: const Text('Дата…'),
              onTap: () => Navigator.of(context).pop(_TailMenu.pick),
            ),
            ListTile(
              minTileHeight: 48,
              leading: const TodayIcon(
                TodayGlyph.stack,
                size: 22,
                color: AppColors.inkSoft,
              ),
              title: const Text('В стопку'),
              subtitle: const Text('снять дату, останется в проекте'),
              onTap: () => Navigator.of(context).pop(_TailMenu.stack),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    switch (chosen) {
      case _TailMenu.pick:
        await runRowDateAction(context, task, RowDateAction.pick);
      case _TailMenu.stack:
        await moveTaskDate(context, task, date: null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = formatTaskDate(task.remindAt, task.remindTime, today);
    final crown = watchCrown(ref, task.id, task.goals);
    final blocked = task.status == TaskStatus.blocked;

    final text = InkWell(
      onTap: () => unawaited(
        AppRoutes.openTask(context, projectId: task.projectId, taskId: task.id),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.todayRow,
            ),
            const SizedBox(height: 3),
            Row(
              children: <Widget>[
                if (blocked) ...<Widget>[
                  const TodayIcon(
                    TodayGlyph.lock,
                    size: 12,
                    color: AppColors.waitingInk,
                  ),
                  const SizedBox(width: 4),
                ],
                if (crown != CrownLevel.none) ...<Widget>[
                  CrownChip(
                    bright: crown == CrownLevel.bright,
                    size: 18,
                    iconSize: 11,
                    radius: 6,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: entry.projectName),
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: label?.text ?? '',
                          style: const TextStyle(color: AppColors.dateOverdue),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final todayButton = SizedBox(
      height: wide ? 32 : 36,
      child: FilledButton(
        key: ValueKey<String>('tail-today-${task.id}'),
        onPressed: () =>
            unawaited(moveTaskDate(context, task, date: today)),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.onInk,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size(0, wide ? 32 : 36),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(wide ? 10 : 12),
          ),
          textStyle: _buttonText,
        ),
        child: const Text('Сегодня'),
      ),
    );

    final more = SizedBox(
      width: Targets.minimum,
      height: Targets.minimum,
      child: IconButton(
        tooltip: 'Ещё',
        onPressed: () => unawaited(_menu(context)),
        icon: const Icon(Icons.more_horiz, color: AppColors.muted),
      ),
    );

    if (wide) {
      return HoverBuilder(
        builder: (context, hovered) => Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
          child: hovered
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    text,
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        todayButton,
                        const SizedBox(width: 6),
                        _TextAction(
                          label: 'Дата…',
                          onTap: () => unawaited(
                            runRowDateAction(context, task, RowDateAction.pick),
                          ),
                        ),
                        _TextAction(
                          label: 'В стопку',
                          onTap: () => unawaited(
                            moveTaskDate(context, task, date: null),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    Expanded(child: text),
                    const SizedBox(width: 8),
                    todayButton,
                  ],
                ),
        ),
      );
    }

    return Container(
      key: ValueKey<String>('tail-row-${task.id}'),
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 8),
      child: Row(
        children: <Widget>[
          Expanded(child: text),
          const SizedBox(width: 8),
          todayButton,
          more,
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 32),
        textStyle: _buttonText.copyWith(fontSize: 13),
      ),
      child: Text(label),
    ),
  );
}

// --- «Сегодня» ------------------------------------------------------------------

class TodayCard extends ConsumerStatefulWidget {
  const TodayCard({required this.view, this.wide = false, super.key});

  final DayView view;
  final bool wide;

  @override
  ConsumerState<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends ConsumerState<TodayCard> {
  bool _doneOpen = false;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final folded =
        ref.watch(uiNoteProvider(UiNotes.todayFolded)).value == view.date;
    final offline = ref.watch(appOfflineProvider);
    final allDone = view.today.isEmpty && view.doneCount > 0;
    final groups = view.groups;
    final headings = groups.length > 1;
    final done = view.doneToday;
    final doneShown = _doneOpen || done.length <= 3
        ? done
        : done.sublist(done.length - 3);

    return Container(
      key: const ValueKey<String>('day-today'),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: <Widget>[
                  const Flexible(
                    child: Text(
                      'Сегодня',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.todayTitle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${view.doneCount} из ${view.total}',
                    maxLines: 1,
                    style: AppText.todayCount,
                  ),
                  if (allDone) ...<Widget>[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.todayProgress,
                    ),
                  ],
                  const Spacer(),
                  if (offline) ...<Widget>[
                    const Tooltip(
                      message: 'Без сети — считаем по сохранённому',
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 16,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    weekdayDate(view.date),
                    style: AppText.caption.copyWith(fontSize: 12.5),
                  ),
                  IconButton(
                    tooltip: folded ? 'Развернуть' : 'Свернуть',
                    onPressed: () => unawaited(
                      ref
                          .read(uiNoteProvider(UiNotes.todayFolded).notifier)
                          .write(folded ? '' : view.date),
                    ),
                    icon: Icon(
                      folded ? Icons.expand_more : Icons.expand_less,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: _Progress(done: view.doneCount, total: view.total),
          ),
          if (!folded) ...<Widget>[
            for (final group in groups) ...<Widget>[
              if (headings) _ScopeHeading(name: group.scopeName ?? ''),
              for (final entry in group.tasks)
                entry.task.status == TaskStatus.blocked
                    ? _BlockedRow(entry: entry, wide: widget.wide)
                    : _TodayRow(entry: entry, today: view.date, wide: widget.wide),
            ],
            if (done.isNotEmpty) ...<Widget>[
              if (view.today.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Divider(height: 1, color: AppColors.lineFaint),
                ),
              if (allDone && !_doneOpen)
                _FoldRow(
                  label: 'Всё сделано · ${done.length}',
                  colour: AppColors.done,
                  onTap: () => setState(() => _doneOpen = true),
                )
              else ...<Widget>[
                if (doneShown.length < done.length)
                  _FoldRow(
                    label: 'Ещё ${done.length - doneShown.length} сделано',
                    colour: AppColors.muted,
                    onTap: () => setState(() => _doneOpen = true),
                  ),
                for (final entry in doneShown) _DoneRow(entry: entry),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total > 12) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: total == 0 ? 0 : done / total),
          duration: const Duration(milliseconds: 200),
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: AppColors.todayTrack,
            color: AppColors.todayProgress,
          ),
        ),
      );
    }
    return Row(
      children: <Widget>[
        for (var i = 0; i < total; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i < done ? AppColors.todayProgress : AppColors.todayTrack,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScopeHeading extends StatelessWidget {
  const _ScopeHeading({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            Text(name.toUpperCase(), style: AppText.scopeLabel),
            const SizedBox(width: 8),
            const Expanded(child: Divider(height: 1, color: AppColors.lineFaint)),
          ],
        ),
      ),
    );
  }
}

class _FoldRow extends StatelessWidget {
  const _FoldRow({
    required this.label,
    required this.colour,
    required this.onTap,
  });

  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: colour,
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: colour),
          ],
        ),
      ),
    ),
  );
}

/// «Сделано: …» with «Следом…», and its undo: the status back, and the place
/// in the set the closing cost.
Future<void> completeDayTask(BuildContext context, DayTask entry) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final task = freshTask(container, entry.task);
  final wasInFocus = container.read(focusedTaskIdsProvider).contains(task.id);
  try {
    await setDayTaskStatus(container, task, TaskStatus.done);
  } catch (error) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось отметить задачу сделанной. ${describeApiError(error)}',
          ),
        ),
      );
    return;
  }
  if (!messenger.mounted) return;
  showDoneSnackBar(
    messenger,
    title: task.title,
    projectId: task.projectId,
    projectName: entry.projectName,
    undo: () async {
      await setDayTaskStatus(
        container,
        freshTask(container, task),
        task.status,
      );
      if (wasInFocus) {
        await container
            .read(focusSetProvider.notifier)
            .take(freshTask(container, task), projectName: entry.projectName);
      }
    },
  );
}

class _TodayRow extends ConsumerStatefulWidget {
  const _TodayRow({required this.entry, required this.today, this.wide = false});

  final DayTask entry;
  final String today;
  final bool wide;

  @override
  ConsumerState<_TodayRow> createState() => _TodayRowState();
}

class _TodayRowState extends ConsumerState<_TodayRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  bool _completing = false;

  Task get task => widget.entry.task;

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    setState(() => _completing = true);
    await _pop.forward(from: 0);
    if (!mounted) return;
    await completeDayTask(context, widget.entry);
    if (mounted) setState(() => _completing = false);
  }

  Future<void> _choose() async {
    final chosen = await chooseRowAction(context, ref, task);
    if (chosen == null || !mounted) return;
    switch (chosen) {
      case TaskStatus.done:
        await _done();
      case final TaskStatus status:
        if (status == task.status) return;
        await setDayTaskStatus(
          ProviderScope.containerOf(context, listen: false),
          task,
          status,
        );
      case final RowDateAction action:
        await runRowDateAction(context, task, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = widget.entry.time;
    final now = ref.watch(appClockProvider)();
    final passed =
        time != null &&
        now.hour * 60 + now.minute >
            int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3));
    final inWork = ref.watch(focusedTaskIdsProvider).contains(task.id);
    final waiting =
        ref.watch(outboxMarksProvider(task.projectId))[task.id] ==
        OutboxMark.waiting;
    final crown = watchCrown(ref, task.id, task.goals);

    return ConstrainedBox(
      key: ValueKey<String>('today-row-${task.id}'),
      constraints: BoxConstraints(minHeight: widget.wide ? 44 : 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
        child: Row(
          children: <Widget>[
            Tooltip(
              message: 'Отметить сделанной',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _completing ? null : () => unawaited(_done()),
                onLongPress: () => unawaited(_choose()),
                child: SizedBox(
                  width: 44,
                  height: 48,
                  child: Center(
                    child: ScaleTransition(
                      scale: TweenSequence<double>(<TweenSequenceItem<double>>[
                        TweenSequenceItem<double>(
                          tween: Tween(begin: 1, end: 0.8),
                          weight: 30,
                        ),
                        TweenSequenceItem<double>(
                          tween: Tween(begin: 0.8, end: 1.15),
                          weight: 40,
                        ),
                        TweenSequenceItem<double>(
                          tween: Tween(begin: 1.15, end: 1),
                          weight: 30,
                        ),
                      ]).animate(_pop),
                      child: _completing
                          ? const _DoneCheck()
                          : Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.lineStrong,
                                  width: 2,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            if (time != null) ...<Widget>[
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: passed ? Colors.transparent : AppColors.timeChip,
                  border: passed
                      ? Border.all(color: AppColors.lineStrong)
                      : null,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(formatClock(time), style: AppText.timeLabel),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: InkWell(
                onTap: () => unawaited(
                  AppRoutes.openTask(
                    context,
                    projectId: task.projectId,
                    taskId: task.id,
                  ),
                ),
                onLongPress: () => unawaited(_choose()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    task.title,
                    maxLines: widget.wide ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.todayRow,
                  ),
                ),
              ),
            ),
            if (crown != CrownLevel.none)
              TaskCrown(
                taskId: task.id,
                goals: task.goals,
                size: 20,
                iconSize: 12,
                target: 32,
              ),
            const SizedBox(width: 8),
            if (waiting)
              const Icon(
                Icons.cloud_upload_outlined,
                size: 14,
                color: AppColors.muted,
                semanticLabel: 'не отправлено',
              )
            else if (inWork)
              Container(
                key: const ValueKey<String>('today-in-work'),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.indigo,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                widget.entry.projectName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneCheck extends StatelessWidget {
  const _DoneCheck();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: const BoxDecoration(
      color: AppColors.doneChip,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.check, size: 16, color: AppColors.todayProgress),
  );
}

class _BlockedRow extends ConsumerWidget {
  const _BlockedRow({required this.entry, this.wide = false});

  final DayTask entry;
  final bool wide;

  Task get task => entry.task;

  Future<void> _unblock(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setDayTaskStatus(container, task, TaskStatus.pending);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось разблокировать. ${describeApiError(error)}'),
        ),
      );
      return;
    }
    if (!messenger.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Разблокирована'),
          persist: false,
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () => unawaited(
              setDayTaskStatus(
                container,
                freshTask(container, task),
                TaskStatus.blocked,
              ).then<void>((_) {}, onError: (Object _) {}),
            ),
          ),
        ),
      );
  }

  Future<void> _wait(BuildContext context, String today) async {
    final choice = await showTaskDateSheet(
      context,
      current: task.remindAt,
      time: task.remindTime,
      today: today,
      subtitle: 'Когда проверить снова',
    );
    final date = choice?.value;
    if (choice == null || !context.mounted) return;
    await moveTaskDate(
      context,
      task,
      date: date,
      keepTime: true,
      message: date == null ? 'Дата снята' : 'Проверить ${weekdayDate(date)}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayKeyProvider);
    return Container(
      key: ValueKey<String>('today-blocked-${task.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.waitingFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              InkWell(
                customBorder: const CircleBorder(),
                // A tap does not close a waiting task; a long press does.
                onLongPress: () async {
                  final chosen = await chooseRowAction(context, ref, task);
                  if (chosen == null || !context.mounted) return;
                  switch (chosen) {
                    case TaskStatus.done:
                      await completeDayTask(context, entry);
                    case final TaskStatus status:
                      await setDayTaskStatus(
                        ProviderScope.containerOf(context, listen: false),
                        task,
                        status,
                      );
                    case final RowDateAction action:
                      await runRowDateAction(context, task, action);
                  }
                },
                child: SizedBox(
                  width: 38,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.waitingChip,
                        shape: BoxShape.circle,
                      ),
                      child: const TodayIcon(
                        TodayGlyph.lock,
                        size: 13,
                        color: AppColors.waitingInk,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => unawaited(
                    AppRoutes.openTask(
                      context,
                      projectId: task.projectId,
                      taskId: task.id,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      task.title,
                      maxLines: wide ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.todayRow.copyWith(color: AppColors.inkSoft),
                    ),
                  ),
                ),
              ),
              Container(
                height: 20,
                margin: const EdgeInsets.only(left: 8, right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.waitingChip,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'проверить',
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    color: AppColors.waitingInk,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(42, 0, 10, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_unblock(context)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: AppColors.lineStrong),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: _buttonText,
                    ),
                    icon: const TodayIcon(
                      TodayGlyph.unlock,
                      size: 15,
                      color: AppColors.ink,
                    ),
                    label: const Text('Разблокировать'),
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_wait(context, today)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.waitingInk,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      textStyle: _buttonText,
                    ),
                    icon: const TodayIcon(
                      TodayGlyph.calendar,
                      size: 15,
                      color: AppColors.waitingInk,
                    ),
                    label: const Text('Ещё ждём…'),
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

class _DoneRow extends ConsumerWidget {
  const _DoneRow({required this.entry});

  final DayTask entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = entry.task;
    final at = DateTime.tryParse(task.doneAt ?? '')?.toLocal();
    return SizedBox(
      key: ValueKey<String>('today-done-${task.id}'),
      height: 40,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
        child: Row(
          children: <Widget>[
            Tooltip(
              message: 'Вернуть в открытые',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => unawaited(
                  setDayTaskStatus(
                    ProviderScope.containerOf(context, listen: false),
                    task,
                    TaskStatus.pending,
                  ).then<void>((_) {}, onError: (Object error) {
                    debugPrint('Reopening from «Сегодня» failed: $error');
                  }),
                ),
                child: const SizedBox(
                  width: 44,
                  height: 40,
                  child: Center(child: _DoneCheck()),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => unawaited(
                  AppRoutes.openTask(
                    context,
                    projectId: task.projectId,
                    taskId: task.id,
                  ),
                ),
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.todayRowDone,
                ),
              ),
            ),
            if (at != null)
              Text(
                '${at.hour}:${at.minute.toString().padLeft(2, '0')}',
                style: AppText.caption,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyToday extends StatelessWidget {
  const _EmptyToday();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey<String>('day-empty'),
      painter: _Dashed(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              const TodayIcon(
                TodayGlyph.calendar,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: 10),
              Flexible(
                flex: 2,
                child: Text(
                  'На сегодня ничего',
                  style: AppText.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'дата → «Сегодня» в проекте',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.hint.copyWith(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed oldDelegate) => false;
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
      height: 14,
      width: width,
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AppColors.lineFaint,
        borderRadius: BorderRadius.circular(7),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Сегодня', style: AppText.todayTitle),
          bar(220),
          bar(180),
          bar(240),
        ],
      ),
    );
  }
}

const TextStyle _headStyle = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 15,
  color: AppColors.ink,
);

const TextStyle _buttonText = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 13.5,
);
