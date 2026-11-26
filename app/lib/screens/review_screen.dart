import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/goals.dart' show windowExpiredLabel, windowLeftLabel;
import '../domain/project_badge.dart';
import '../domain/today_view.dart'
    show
        DayTask,
        addDays,
        kWeekdaysShort,
        localDayOfInstant,
        taskDay,
        weekdayDate;
import '../domain/reminders.dart' show calendarDateForApi;
import '../models/focus_task.dart';
import '../models/goal.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../models/today_history.dart';
import '../navigation/app_routes.dart';
import '../navigation/review_routes.dart';
import '../providers/board_providers.dart';
import '../providers/focus_providers.dart';
import '../providers/goal_providers.dart';
import '../providers/today_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/dictate_into.dart';
import '../widgets/editor/editor_theme.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/ime_text_controller.dart';
import '../widgets/today/date_sheet.dart';
import '../widgets/today/next_sheet.dart';
import '../widgets/today/rhythm_sheet.dart';
import '../widgets/today/today_icons.dart';
import 'work_screen.dart' show openPickScreen;

/// Opens the weekly review (`design/today-history-spec.md` §10): a
/// full-screen dark route on a phone, a 720 px window over a dimmed screen on
/// a desktop. After «Записать» the History shows «Пересмотр записан ·
/// Недели».
Future<void> openReview(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final Review? recorded;
  if (isWideLayout(context)) {
    final height = MediaQuery.sizeOf(context).height;
    recorded = await showDialog<Review>(
      context: context,
      barrierColor: const Color(0x9914183C),
      builder: (context) => Dialog(
        backgroundColor: AppColors.voiceBackground,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: SizedBox(
          width: 720,
          height: math.min(820, height - 48),
          child: const ReviewFlow(),
        ),
      ),
    );
  } else {
    recorded = await Navigator.of(context).push<Review>(
      MaterialPageRoute<Review>(
        fullscreenDialog: true,
        builder: (_) => const ReviewFlow(),
      ),
    );
  }
  if (recorded == null || !messenger.mounted) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: const Text('Пересмотр записан'),
        persist: false,
        action: SnackBarAction(
          label: 'Недели',
          onPressed: () => container
              .read(historyTabProvider.notifier)
              .select(HistoryTab.weeks),
        ),
      ),
    );
}

const List<String> _stepNames = <String>[
  'СДЕЛАНО',
  'ЗАДУМАНО',
  'ЦЕЛИ',
  'РИТМ',
  'НЕДЕЛЯ ВПЕРЁД',
  'ИТОГ',
];

const int kReviewSteps = 6;

/// What step 2 did to a task.
enum IntendedChoice { keep, stack, drop }

/// What step 3 did to a goal.
enum GoalDecision { kept, extended, benched, achieved, slotted }

class ReviewFlow extends ConsumerStatefulWidget {
  const ReviewFlow({super.key});

  @override
  ConsumerState<ReviewFlow> createState() => _ReviewFlowState();
}

class _ReviewFlowState extends ConsumerState<ReviewFlow> {
  ReviewDraft? _draft;
  Object? _error;
  late int _step;
  late Set<int> _skipped;

  final Map<String, FollowUp> _followUps = <String, FollowUp>{};
  final Map<String, IntendedChoice> _intended = <String, IntendedChoice>{};
  final Map<String, (GoalDecision, String?)> _goals =
      <String, (GoalDecision, String?)>{};
  final Map<String, String> _rhythmTaken = <String, String>{};
  final Set<String> _expandedProjects = <String>{};
  final Set<String> _openBench = <String>{};
  bool _monthOpen = true;
  bool _saving = false;
  final TextEditingController _summary = ImeTextController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final progress = ref.read(reviewProgressProvider);
    _step = progress.step.clamp(0, kReviewSteps - 1);
    _skipped = <int>{...progress.skipped};
    _summary.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _summary.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _draft = null;
    });
    try {
      final draft = await ref.read(todayHistoryApiProvider).fetchReviewDraft();
      if (mounted) setState(() => _draft = draft);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _remember() => ref
      .read(reviewProgressProvider.notifier)
      .save(ReviewProgress(step: _step, skipped: _skipped));

  void _close() {
    _remember();
    Navigator.of(context).pop();
  }

  void _go(int step, {required bool skipped}) {
    setState(() {
      if (skipped) {
        _skipped.add(_step);
      } else {
        _skipped.remove(_step);
      }
      _step = step;
    });
    _remember();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _save({bool withSummary = true}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final review = await container
          .read(todayHistoryApiProvider)
          .saveReview(summary: withSummary ? _summary.text : null);
      container.read(reviewStatusStateProvider.notifier).recorded(review);
      container.invalidate(historyWeeksProvider);
      container.read(reviewProgressProvider.notifier).clear();
      if (navigator.mounted) navigator.pop(review);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Не удалось записать. ${describeApiError(error)}'),
            persist: false,
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => unawaited(_save(withSummary: withSummary)),
            ),
          ),
        );
    }
  }

  void _say(String text, {Future<void> Function()? undo}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          persist: false,
          action: undo == null
              ? null
              : SnackBarAction(
                  label: 'Отменить',
                  onPressed: () => unawaited(undo()),
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: editorOverlayStyle,
      child: Theme(
        data: editorTheme,
        child: Scaffold(
          backgroundColor: AppColors.voiceBackground,
          body: SafeArea(child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    final draft = _draft;
    if (draft == null) {
      return Column(
        children: <Widget>[
          _TopBar(step: _step, skipped: _skipped, onClose: _close),
          Expanded(
            child: Center(
              child: _error == null
                  ? const CircularProgressIndicator(
                      color: AppColors.voiceBright,
                    )
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.cloud_off,
                            size: 40,
                            color: AppColors.voiceMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Пересмотру нужна сеть. ${describeApiError(_error!)}',
                            textAlign: TextAlign.center,
                            style: AppText.reviewHint,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      );
    }

    final (title, hint) = _titles(draft);
    final last = _step == kReviewSteps - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TopBar(step: _step, skipped: _skipped, onClose: _close),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: <Widget>[
              Text(
                'ШАГ ${_step + 1} ИЗ $kReviewSteps · ${_stepNames[_step]}',
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.75,
                  color: AppColors.voiceMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: AppText.reviewTitle),
              const SizedBox(height: 6),
              Text(hint, style: AppText.reviewHint),
              const SizedBox(height: 16),
              ...switch (_step) {
                0 => _done(draft),
                1 => _intendedStep(draft),
                2 => _goalsStep(draft),
                3 => _rhythmStep(draft),
                4 => _weekStep(),
                _ => _summaryStep(draft),
              },
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x0014183C), AppColors.voiceBackground],
              stops: <double>[0, 0.2],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey<String>('review-skip'),
                  onPressed: _saving
                      ? null
                      : last
                      ? () => _save(withSummary: false)
                      : () => _go(_step + 1, skipped: true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.voiceBright,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  child: const Text('Пропустить'),
                ),
              ),
              SizedBox(
                height: last ? 76 : 64,
                child: FilledButton.icon(
                  key: const ValueKey<String>('review-next'),
                  onPressed: _saving
                      ? null
                      : last
                      ? () => _save()
                      : () => _go(_step + 1, skipped: false),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.voiceBackground,
                    disabledBackgroundColor: AppColors.voiceWell,
                    disabledForegroundColor: AppColors.voiceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(last ? 24 : 22),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  icon: last
                      ? const Icon(Icons.check, size: 24)
                      : const SizedBox.shrink(),
                  label: Text(last ? 'Записать пересмотр' : 'Дальше'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  (String, String) _titles(ReviewDraft draft) {
    final since = localDayOfInstant(draft.periodStart);
    return switch (_step) {
      0 => (
        'Что сделано',
        '${since == null ? 'С прошлого раза' : 'С ${weekdayDate(since)}'}. '
            'Что из этого тянет за собой продолжение?',
      ),
      1 => (
        'Задумано, но не сделано',
        'Рабочий набор, шаги целей и задачи с датой на эту неделю. '
            'Что с ними?',
      ),
      2 => (
        'Цели',
        'Окна целей. Какая остаётся, какая уступает место, какая достигнута?',
      ),
      3 => ('Ритм проектов', 'Проекты, которые затихли или разрослись.'),
      4 => ('Неделя вперёд', 'Что берёте в работу и на какие дни.'),
      _ => (
        'Итог недели',
        'Одной строкой — что это была за неделя. Можно пропустить.',
      ),
    };
  }

  // --- step 1 -------------------------------------------------------------------

  List<Widget> _done(ReviewDraft draft) {
    final weeks = ref.watch(historyWeeksProvider).value ?? const [];
    final previous = weeks
        .map((week) => week.review)
        .whereType<Review>()
        .firstOrNull;
    final groups = <String, List<DoneItem>>{};
    for (final item in draft.done) {
      groups.putIfAbsent(item.task.task.projectId, () => <DoneItem>[]).add(item);
    }

    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text('${draft.done.length}', style: AppText.reviewNumber),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'закрыто',
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.voiceBright,
                ),
              ),
              if (previous != null)
                Text(
                  'в прошлый раз ${previous.closedCount}',
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w500,
                    fontSize: 12.5,
                    color: AppColors.voiceMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (draft.month case final ReviewMonth month) ...<Widget>[
        _MonthCard(
          month: month,
          open: _monthOpen,
          onToggle: () => setState(() => _monthOpen = !_monthOpen),
        ),
        const SizedBox(height: 14),
      ],
      if (draft.done.isEmpty)
        const _Plate('С прошлого пересмотра ничего не закрыто.')
      else
        for (final entry in groups.entries) ...<Widget>[
          _projectHeader(entry.value.first.task.projectName, entry.value.length),
          _Card(
            child: Column(
              children: <Widget>[
                for (final item
                    in _expandedProjects.contains(entry.key)
                        ? entry.value
                        : entry.value.take(4))
                  _doneRow(item),
                if (!_expandedProjects.contains(entry.key) &&
                    entry.value.length > 4)
                  TextButton(
                    onPressed: () =>
                        setState(() => _expandedProjects.add(entry.key)),
                    child: Text(
                      'Ещё ${entry.value.length - 4}',
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.voiceBright,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
    ];
  }

  Widget _projectHeader(String name, int count) {
    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          _ProjectBadge(name: name, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.voiceBright,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.voiceMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneRow(DoneItem item) {
    final task = item.task.task;
    final made = _followUps[task.id];
    final day = localDayOfInstant(item.doneAt);
    final weekday = day == null
        ? ''
        : kWeekdaysShort[DateTime.parse(day).weekday - 1];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check, size: 16, color: AppColors.doneOnDark),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      height: 1.3,
                      color: AppColors.voiceInk,
                    ),
                  ),
                  if (made != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '→ ${made.title} · ${weekdayDate(made.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: AppColors.nextOnDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            weekday,
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.voiceMuted,
            ),
          ),
          const SizedBox(width: 8),
          if (made != null)
            const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.check, size: 18, color: AppColors.nextOnDark),
            )
          else
            SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final created = await showNextSheet(
                    context,
                    projectId: task.projectId,
                    projectName: item.task.projectName,
                    afterTitle: task.title,
                  );
                  if (created != null && mounted) {
                    setState(() => _followUps[task.id] = created);
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.voiceBright,
                  side: const BorderSide(color: AppColors.voiceLine),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                icon: const TodayIcon(
                  TodayGlyph.next,
                  size: 15,
                  color: AppColors.voiceBright,
                ),
                label: const Text('Следом'),
              ),
            ),
        ],
      ),
    );
  }

  // --- step 2 -------------------------------------------------------------------

  List<Widget> _intendedStep(ReviewDraft draft) {
    if (draft.intended.isEmpty) {
      return const <Widget>[
        _Plate('Задуманного без дела нет — хорошая неделя.'),
      ];
    }
    final contours = ref.watch(contourListProvider);
    final fallback = ref.watch(defaultContourIdProvider);
    final stepContour = <String, String>{
      for (final goal in draft.goals)
        if (goal.inSlot && goal.nextStep != null)
          goal.nextStep!.id: goal.contourId,
    };
    final byContour = <String?, List<IntendedTask>>{};
    final dated = <IntendedTask>[];
    for (final item in draft.intended) {
      final task = item.task.task;
      String? contour;
      if (item.reasons.contains(IntendedReason.workingSet)) {
        contour = task.focusContourId ?? fallback ?? '';
      } else if (item.reasons.contains(IntendedReason.goalStep)) {
        contour = stepContour[task.id] ?? fallback ?? '';
      }
      if (contour == null) {
        dated.add(item);
      } else {
        byContour.putIfAbsent(contour, () => <IntendedTask>[]).add(item);
      }
    }
    final ordered = <String?>[
      for (final contour in contours)
        if (byContour.containsKey(contour.id)) contour.id,
      for (final key in byContour.keys)
        if (!contours.any((c) => c.id == key)) key,
    ];
    final active = ref.watch(activeContourIdProvider);
    String nameOf(String? id) =>
        contours.where((c) => c.id == id).firstOrNull?.name ?? 'Набор';

    return <Widget>[
      for (final contour in ordered) ...<Widget>[
        _ContourLabel(nameOf(contour), active: contour == active),
        for (final item in byContour[contour]!) _intendedCard(item),
        const SizedBox(height: 8),
      ],
      if (dated.isNotEmpty) ...<Widget>[
        const _ContourLabel('С ДАТОЙ', crown: false),
        for (final item in dated) _intendedCard(item),
      ],
    ];
  }

  Widget _intendedCard(IntendedTask item) {
    final task = item.task.task;
    final choice = _intended[task.id] ?? IntendedChoice.keep;
    final day = taskDay(task.remindAt);
    final faded = choice != IntendedChoice.keep;
    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.goalRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15.5,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
                if (faded)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      choice == IntendedChoice.stack ? 'в стопке' : 'снята',
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppColors.voiceMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  item.task.projectName,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.voiceMuted,
                  ),
                ),
                for (final reason in item.reasons)
                  switch (reason) {
                    IntendedReason.workingSet => const _ReasonChip(
                      'в наборе',
                      fill: AppColors.voiceLine,
                      ink: AppColors.voiceBright,
                    ),
                    IntendedReason.goalStep => const _ReasonChip(
                      'шаг цели',
                      fill: AppColors.goalEnd,
                      ink: Color(0xFFFFFFFF),
                      crown: true,
                    ),
                    IntendedReason.dated => _ReasonChip(
                      day == null ? 'дата' : 'дата ${weekdayDate(day)}',
                      fill: AppColors.voiceWell,
                      ink: AppColors.voiceMuted,
                    ),
                  },
              ],
            ),
            const SizedBox(height: 10),
            _Segment<IntendedChoice>(
              values: IntendedChoice.values,
              labels: const <String>['Оставить', 'В стопку', 'Снять'],
              selected: choice,
              onSelect: (next) => _applyIntended(item, next),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyIntended(IntendedTask item, IntendedChoice next) async {
    final task = item.task.task;
    final previous = _intended[task.id] ?? IntendedChoice.keep;
    if (previous == next) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final wasInSet = item.reasons.contains(IntendedReason.workingSet);
    final day = taskDay(task.remindAt);

    Future<void> clear() async {
      if (wasInSet) {
        try {
          await container.read(focusSetProvider.notifier).drop(task.id);
        } catch (error) {
          debugPrint('Review: drop from set failed: $error');
        }
      }
      if (day != null) {
        await setTaskDate(container, task, date: null);
      }
    }

    Future<void> restore() async {
      if (wasInSet) {
        try {
          await container
              .read(focusSetProvider.notifier)
              .take(task, projectName: item.task.projectName);
        } catch (error) {
          debugPrint('Review: back into the set failed: $error');
        }
      }
      if (day != null) {
        await setTaskDate(container, task, date: day, time: task.remindTime);
      }
    }

    setState(() => _intended[task.id] = next);
    try {
      if (next == IntendedChoice.keep) {
        await restore();
      } else if (previous == IntendedChoice.keep) {
        await clear();
        _say(
          next == IntendedChoice.stack ? 'В стопке' : 'Снята с недели',
          undo: () async {
            if (mounted) setState(() => _intended[task.id] = IntendedChoice.keep);
            await restore();
          },
        );
      }
    } catch (error) {
      if (mounted) setState(() => _intended[task.id] = previous);
      _say('Не удалось. ${describeApiError(error)}');
    }
  }

  // --- step 3 -------------------------------------------------------------------

  List<Widget> _goalsStep(ReviewDraft draft) {
    final contours = ref.watch(contourListProvider);
    final active = ref.watch(activeContourIdProvider);
    final live = <String, GoalView>{
      for (final goal in ref.watch(goalListProvider)) goal.id: goal,
    };
    final goals = <GoalView>[
      for (final goal in draft.goals) live[goal.id] ?? goal,
    ];
    if (goals.isEmpty) {
      return const <Widget>[_Plate('Целей в окнах и на скамейке нет.')];
    }
    final ids = <String>{
      for (final contour in contours) contour.id,
      for (final goal in goals)
        if (!contours.any((c) => c.id == goal.contourId)) goal.contourId,
    }.toList();

    final out = <Widget>[];
    for (final id in ids) {
      final mine = goals.where((g) => g.contourId == id).toList();
      if (mine.isEmpty) continue;
      final contour = contours.where((c) => c.id == id).firstOrNull;
      final slotted = <GoalView>[
        for (final goal in mine)
          if (goal.inSlot || _goals[goal.id]?.$1 == GoalDecision.benched ||
              _goals[goal.id]?.$1 == GoalDecision.achieved)
            if (_goals[goal.id]?.$1 != GoalDecision.slotted) goal,
      ];
      final bench = <GoalView>[
        for (final goal in mine)
          if (!slotted.contains(goal)) goal,
      ];
      final taken = slotted
          .where(
            (g) =>
                _goals[g.id]?.$1 != GoalDecision.benched &&
                _goals[g.id]?.$1 != GoalDecision.achieved,
          )
          .length;
      final free = (contour?.slots ?? taken) - taken;
      out.add(_ContourLabel(contour?.name ?? 'Цели', active: id == active));
      for (final goal in slotted) {
        out.add(_goalCard(goal));
      }
      for (final goal in bench.where(
        (g) => _goals[g.id]?.$1 == GoalDecision.slotted,
      )) {
        out.add(_goalCard(goal));
      }
      final benchLeft = bench
          .where((g) => _goals[g.id]?.$1 != GoalDecision.slotted)
          .toList();
      if (free > 0) {
        out.add(_freeSlot(id, benchLeft));
      }
      out.add(const SizedBox(height: 8));
    }
    return out;
  }

  Widget _goalCard(GoalView goal) {
    final decision = _goals[goal.id];
    final window = goal.windowExpired
        ? windowExpiredLabel(goal.windowEndsAt)
        : windowLeftLabel(goal.windowEndsAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.goalRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const CrownIcon(size: 16, color: AppColors.crown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  goal.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              Text(
                '${goal.progress.done}/${goal.progress.total}',
                style: AppText.goalCount,
              ),
            ],
          ),
          if (window != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              window,
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: goal.windowExpired
                    ? AppColors.goalExpired
                    : AppColors.voiceMuted,
              ),
            ),
          ],
          if (goal.progress.total > 0) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                for (var i = 0; i < math.min(goal.progress.total, 12); i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i < goal.progress.done
                            ? AppColors.doneOnDark
                            : AppColors.goalWellLine,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (decision == null)
            Row(
              children: <Widget>[
                Expanded(
                  child: _DarkButton(
                    label: 'Оставить',
                    filled: true,
                    onPressed: () => _decide(goal, GoalDecision.kept),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DarkButton(
                    label: 'Уступить',
                    onPressed: () => _decide(goal, GoalDecision.benched),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DarkButton(
                    label: 'Достигнута',
                    ink: AppColors.doneOnDark,
                    onPressed: () => _decide(goal, GoalDecision.achieved),
                  ),
                ),
              ],
            )
          else
            Container(
              height: 44,
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: AppColors.goalWell,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      switch (decision.$1) {
                        GoalDecision.kept => 'Остаётся',
                        GoalDecision.extended =>
                          'Продлено до ${decision.$2 ?? ''}',
                        GoalDecision.benched => 'На скамейке',
                        GoalDecision.achieved => 'Достигнута ✓',
                        GoalDecision.slotted => 'В слоте',
                      },
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.voiceInk,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _undoGoal(goal),
                    child: const Text(
                      'Вернуть',
                      style: TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.voiceBright,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _decide(GoalView goal, GoalDecision decision) async {
    final goals = ref.read(goalsProvider.notifier);
    try {
      switch (decision) {
        case GoalDecision.kept:
          if (goal.windowExpired) {
            final extended = await goals.extend(goal.id);
            final ends = extended.windowEndsAt;
            final day = ends == null ? null : localDayOfInstant(ends);
            if (mounted) {
              setState(
                () => _goals[goal.id] = (
                  GoalDecision.extended,
                  day == null ? null : weekdayDate(day).split(' ').last,
                ),
              );
            }
            return;
          }
        case GoalDecision.benched:
          await goals.bench(goal.id);
        case GoalDecision.achieved:
          await goals.achieve(goal.id);
        case GoalDecision.slotted:
          await goals.slot(goal.id);
        case GoalDecision.extended:
          break;
      }
      if (mounted) setState(() => _goals[goal.id] = (decision, null));
    } catch (error) {
      _say('Не удалось. ${describeApiError(error)}');
    }
  }

  Future<void> _undoGoal(GoalView goal) async {
    final decision = _goals[goal.id]?.$1;
    final goals = ref.read(goalsProvider.notifier);
    try {
      switch (decision) {
        case GoalDecision.benched:
          await goals.slot(goal.id);
        case GoalDecision.achieved:
          await goals.reopen(goal.id);
        case GoalDecision.slotted:
          await goals.bench(goal.id);
        case GoalDecision.kept || GoalDecision.extended || null:
          break;
      }
      if (mounted) setState(() => _goals.remove(goal.id));
    } catch (error) {
      _say('Не удалось. ${describeApiError(error)}');
    }
  }

  Widget _freeSlot(String contourId, List<GoalView> bench) {
    final open = _openBench.contains(contourId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: bench.isEmpty
              ? null
              : () => setState(
                  () => open
                      ? _openBench.remove(contourId)
                      : _openBench.add(contourId),
                ),
          child: CustomPaint(
            painter: const _DashedBorder(color: AppColors.goalDim, radius: 20),
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Свободный слот',
                        style: TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.voiceMuted,
                        ),
                      ),
                    ),
                    if (bench.isNotEmpty)
                      Text(
                        open ? 'Со скамейки ▴' : 'Со скамейки ▾',
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.voiceBright,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open)
          for (final goal in bench)
            SizedBox(
              height: 52,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 12),
                  const CrownIcon(size: 14, color: AppColors.crownMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.voiceInk,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _decide(goal, GoalDecision.slotted),
                    child: const Text(
                      'В слот',
                      style: TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.voiceBright,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 8),
      ],
    );
  }

  // --- step 4 -------------------------------------------------------------------

  List<Widget> _rhythmStep(ReviewDraft draft) {
    if (draft.rhythm.isEmpty) {
      final view = ref.watch(boardViewProvider);
      final anyRhythm =
          view is BoardReady &&
          view.projects.any(
            (row) =>
                row.project.rhythmClosedPerWeek != null ||
                row.project.rhythmMaxOpen != null,
          );
      return <Widget>[
        _Plate(
          anyRhythm
              ? 'Все проекты в ритме.'
              : 'Ритм не задан. Его включают в меню проекта — «Ритм…».',
        ),
      ];
    }
    return <Widget>[for (final row in draft.rhythm) _rhythmCard(row)];
  }

  Widget _rhythmCard(RhythmProject row) {
    final rhythm = row.rhythm;
    final silence = rhythm.signal == RhythmSignal.silence;
    final detail = silence
        ? 'закрыто ${formatAverage(rhythm.closedAvg)} в неделю · '
              'норма ${rhythm.closedPerWeek ?? '—'}'
        : 'открыто ${rhythm.open} · потолок ${rhythm.maxOpen ?? '—'}';
    final taken = _rhythmTaken[row.project.id];
    final view = ref.watch(boardViewProvider);
    final current = view is BoardReady
        ? view.projects
              .where((p) => p.project.id == row.project.id)
              .firstOrNull
              ?.currentTask
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.goalRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _ProjectBadge(name: row.project.name, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              Text(
                rhythmSignalText(rhythm) ?? '',
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.voiceRecordingSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: AppColors.voiceMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (silence) ...<Widget>[
            if (taken != null)
              SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'В наборе: $taken',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.doneOnDark,
                    ),
                  ),
                ),
              )
            else
              _DarkButton(
                label: 'Взять задачу в набор',
                onPressed: current == null
                    ? null
                    : () => _takeCurrent(row.project, current),
              ),
            const SizedBox(height: 8),
            _DarkButton(
              label: 'Поменять норму',
              onPressed: () => _changeRhythm(row.project),
            ),
          ] else ...<Widget>[
            _DarkButton(
              label: 'Почистить',
              onPressed: () => AppRoutes.openProject(
                context,
                projectId: row.project.id,
              ),
            ),
            const SizedBox(height: 8),
            _DarkButton(
              label: 'Поменять потолок',
              onPressed: () => _changeRhythm(row.project),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _takeCurrent(Project project, Task task) async {
    try {
      await ref
          .read(focusSetProvider.notifier)
          .take(task, projectName: project.name);
      if (mounted) setState(() => _rhythmTaken[project.id] = task.title);
    } catch (error) {
      _say('Не удалось взять в набор. ${describeApiError(error)}');
    }
  }

  Future<void> _changeRhythm(Project project) async {
    final saved = await showRhythmSheet(context, project: project, dark: true);
    if (saved == null || !mounted) return;
    final draft = _draft;
    if (draft == null) return;
    setState(
      () => _draft = ReviewDraft(
        periodStart: draft.periodStart,
        periodEnd: draft.periodEnd,
        monthly: draft.monthly,
        done: draft.done,
        intended: draft.intended,
        goals: draft.goals,
        month: draft.month,
        rhythm: <RhythmProject>[
          for (final row in draft.rhythm)
            if (row.project.id == saved.id)
              if (saved.rhythm?.signal != null)
                RhythmProject(project: saved, rhythm: saved.rhythm!)
              else
                ...<RhythmProject>[]
            else
              row,
        ],
      ),
    );
  }

  // --- step 5 -------------------------------------------------------------------

  List<Widget> _weekStep() {
    final contours = ref.watch(contourListProvider);
    final fallback = ref.watch(defaultContourIdProvider);
    final active = ref.watch(activeContourIdProvider);
    final set = ref.watch(focusSetProvider).value ?? const <FocusTask>[];
    final byContour = <String?, List<FocusTask>>{};
    for (final row in set) {
      byContour
          .putIfAbsent(row.focusContourId ?? fallback, () => <FocusTask>[])
          .add(row);
    }
    final ordered = <String?>[
      for (final contour in contours) contour.id,
      for (final key in byContour.keys)
        if (!contours.any((c) => c.id == key)) key,
    ];
    final today = ref.watch(todayKeyProvider);
    final placed = ref.watch(placedBoardTasksProvider) ?? const <DayTask>[];

    final out = <Widget>[];
    for (final id in ordered) {
      final rows = byContour[id] ?? const <FocusTask>[];
      final contour = contours.where((c) => c.id == id).firstOrNull;
      if (contour == null && rows.isEmpty) continue;
      out.add(
        _ContourLabel(
          contour?.name ?? 'Набор',
          active: id == active,
          slots: contour?.slots,
          taken: rows.length,
        ),
      );
      out.add(
        _Card(
          child: Column(
            children: <Widget>[
              for (final row in rows)
                SizedBox(
                  height: 52,
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.voiceLine, width: 2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              row.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppFonts.text,
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                                color: AppColors.voiceInk,
                              ),
                            ),
                            Text(
                              row.project.name,
                              maxLines: 1,
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
                      IconButton(
                        tooltip: 'Убрать из набора',
                        onPressed: () => unawaited(
                          ref
                              .read(focusSetProvider.notifier)
                              .drop(row.id)
                              .catchError((Object error) {
                                _say('Не удалось. ${describeApiError(error)}');
                              }),
                        ),
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.voiceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => openPickScreen(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.voiceBright,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('+ Собрать'),
                ),
              ),
            ],
          ),
        ),
      );
      out.add(const SizedBox(height: 12));
    }

    // By days: tomorrow and the six after it.
    out.add(const _ContourLabel('ПО ДНЯМ', crown: false));
    final days = <String>[for (var i = 1; i <= 7; i++) addDays(today, i)];
    final byDay = <String, List<DayTask>>{
      for (final d in days) d: <DayTask>[],
    };
    for (final entry in placed) {
      final task = entry.task;
      if (task.status == TaskStatus.done) continue;
      final day = taskDay(task.remindAt);
      if (day != null && byDay.containsKey(day)) byDay[day]!.add(entry);
    }
    var i = 0;
    while (i < days.length) {
      final day = days[i];
      if (byDay[day]!.isEmpty) {
        var j = i;
        while (j + 1 < days.length && byDay[days[j + 1]]!.isEmpty) {
          j++;
        }
        String wd(String d) =>
            kWeekdaysShort[DateTime.parse(d).weekday - 1];
        final label = i == j ? wd(day) : '${wd(day)}–${wd(days[j])}';
        out.add(
          SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$label — пусто',
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.voiceMuted,
                ),
              ),
            ),
          ),
        );
        i = j + 1;
        continue;
      }
      final rows = byDay[day]!;
      out.add(
        SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${weekdayDate(day)} · ${rows.length}',
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.voiceBright,
              ),
            ),
          ),
        ),
      );
      for (final entry in rows) {
        final task = entry.task;
        out.add(
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: AppColors.voiceInk,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    entry.projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.voiceMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.voiceWell,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _moveDate(task),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      child: Text(
                        task.remindTime ??
                            kWeekdaysShort[DateTime.parse(day).weekday - 1],
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: AppColors.voiceBright,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      i++;
    }
    return out;
  }

  Future<void> _moveDate(Task task) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final choice = await showTaskDateSheet(
      context,
      current: task.remindAt,
      time: task.remindTime,
      today: ref.read(todayKeyProvider),
    );
    if (choice == null) return;
    try {
      await setTaskDate(
        container,
        task,
        date: choice.value,
        time: task.remindTime,
      );
    } catch (error) {
      _say('Не удалось. ${describeApiError(error)}');
    }
  }

  // --- step 6 -------------------------------------------------------------------

  List<Widget> _summaryStep(ReviewDraft draft) {
    final length = _summary.text.length;
    final achieved = _goals.values
        .where((d) => d.$1 == GoalDecision.achieved)
        .length;
    final stacked = _intended.values
        .where((c) => c != IntendedChoice.keep)
        .length;
    return <Widget>[
      Container(
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.voiceWell,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('review-summary'),
              controller: _summary,
              maxLength: 300,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppColors.voiceBright,
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w500,
                fontSize: 20,
                color: Color(0xFFFFFFFF),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: false,
                counterText: '',
                hintText: 'Например: дожал стенды, дом стоял',
                hintStyle: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  color: AppColors.reviewSkipped,
                ),
              ),
            ),
            Row(
              children: <Widget>[
                if (length > 250)
                  Text(
                    '$length из 300',
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.voiceMuted,
                    ),
                  ),
                const Spacer(),
                DictateInto(controller: _summary, label: 'Итог недели'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _NumberChip(text: '${draft.done.length} закрыто'),
          if (achieved > 0)
            _NumberChip(
              text: achieved == 1 ? '1 цель' : '$achieved цели',
              crown: true,
            ),
          if (_followUps.isNotEmpty)
            _NumberChip(text: 'следом ${_followUps.length}'),
          if (stacked > 0) _NumberChip(text: 'в стопку $stacked'),
        ],
      ),
    ];
  }
}

// --- parts -----------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.step,
    required this.skipped,
    required this.onClose,
  });

  final int step;
  final Set<int> skipped;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < kReviewSteps; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                key: ValueKey<String>('review-progress-$i'),
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i < step
                      ? (skipped.contains(i)
                            ? AppColors.reviewSkipped
                            : AppColors.reviewStepDone)
                      : i == step
                      ? const Color(0x99FFFFFF)
                      : AppColors.reviewStepTrack,
                ),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Закрыть',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppColors.voiceMuted),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
    decoration: BoxDecoration(
      color: AppColors.goalRaised,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

/// A step with nothing to show still shows that it was there.
class _Plate extends StatelessWidget {
  const _Plate(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: AppColors.goalRaised,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.text,
        fontWeight: FontWeight.w500,
        fontSize: 15,
        height: 1.35,
        color: AppColors.voiceInk,
      ),
    ),
  );
}

class _ContourLabel extends StatelessWidget {
  const _ContourLabel(
    this.name, {
    this.active = false,
    this.crown = true,
    this.slots,
    this.taken = 0,
  });

  final String name;
  final bool active;
  final bool crown;
  final int? slots;
  final int taken;

  @override
  Widget build(BuildContext context) {
    final slots = this.slots;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: <Widget>[
          if (crown) ...<Widget>[
            CrownIcon(
              size: 12,
              color: active ? AppColors.crown : AppColors.crownMuted,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            name.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.6,
              color: AppColors.voiceMuted,
            ),
          ),
          if (slots != null) ...<Widget>[
            const SizedBox(width: 8),
            for (var i = 0; i < math.max(slots, taken); i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < taken ? AppColors.crown : Colors.transparent,
                  border: i < taken
                      ? null
                      : Border.all(color: AppColors.goalDim),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip(
    this.label, {
    required this.fill,
    required this.ink,
    this.crown = false,
  });

  final String label;
  final Color fill;
  final Color ink;
  final bool crown;

  @override
  Widget build(BuildContext context) => Container(
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (crown) ...<Widget>[
          const CrownIcon(size: 11, color: AppColors.crown),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.text,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.voiceWell,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Material(
                color: values[i] == selected
                    ? AppColors.card
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelect(values[i]),
                  child: Center(
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: values[i] == selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontSize: 13.5,
                        color: values[i] == selected
                            ? AppColors.voiceBackground
                            : AppColors.voiceBright,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DarkButton extends StatelessWidget {
  const _DarkButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.ink = AppColors.voiceBright,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const text = TextStyle(
      fontFamily: AppFonts.text,
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );
    return SizedBox(
      height: 44,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.voiceBackground,
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: text.copyWith(fontWeight: FontWeight.w700),
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                side: BorderSide(
                  color: ink == AppColors.voiceBright
                      ? AppColors.voiceLine
                      : ink,
                ),
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: text,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
    );
  }
}

class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.text, this.crown = false});

  final String text;
  final bool crown;

  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.goalRaised,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (crown) ...<Widget>[
          const CrownIcon(size: 13, color: AppColors.crown),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: const TextStyle(
            fontFamily: AppFonts.text,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.voiceInk,
          ),
        ),
      ],
    ),
  );
}

class _ProjectBadge extends StatelessWidget {
  const _ProjectBadge({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: projectBadgeColor(name),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Text(
      projectBadgeLetter(name),
      style: TextStyle(
        fontFamily: AppFonts.text,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.5,
        color: AppColors.onInk,
      ),
    ),
  );
}

/// The month section of step 1 (`monthly` reviews).
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.open,
    required this.onToggle,
  });

  final ReviewMonth month;
  final bool open;
  final VoidCallback onToggle;

  static const List<String> _genitive = <String>[
    'ЯНВАРЯ',
    'ФЕВРАЛЯ',
    'МАРТА',
    'АПРЕЛЯ',
    'МАЯ',
    'ИЮНЯ',
    'ИЮЛЯ',
    'АВГУСТА',
    'СЕНТЯБРЯ',
    'ОКТЯБРЯ',
    'НОЯБРЯ',
    'ДЕКАБРЯ',
  ];

  @override
  Widget build(BuildContext context) {
    final m = int.tryParse(month.month.split('-').last) ?? 1;
    final top = month.byProject.fold<int>(0, (a, p) => math.max(a, p.closed));
    return Container(
      key: const ValueKey<String>('review-month'),
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.goalRaised, AppColors.goalEnd],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'ИТОГИ ${_genitive[(m - 1).clamp(0, 11)]}',
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.7,
                    color: AppColors.voiceMuted,
                  ),
                ),
              ),
              IconButton(
                tooltip: open ? 'Свернуть' : 'Развернуть',
                onPressed: onToggle,
                icon: Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.voiceMuted,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${month.closed}',
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  color: AppColors.doneOnDark,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text(
                  'закрыто за месяц',
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.voiceBright,
                  ),
                ),
              ),
            ],
          ),
          if (open) ...<Widget>[
            const SizedBox(height: 8),
            for (final project in month.byProject.take(5))
              SizedBox(
                height: 26,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.voiceInk,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: top == 0
                              ? 0
                              : math.max(0.04, project.closed / top),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.doneOnDark,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${project.closed}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.voiceInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            if (month.byProject.length > 5)
              Text(
                'и ещё ${month.byProject.length - 5}',
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.voiceBright,
                ),
              ),
            for (final goal in month.achievedGoals) ...<Widget>[
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  const CrownIcon(size: 14, color: AppColors.crown),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// The day of [instant] as `YYYY-MM-DD` local -- for tests.
@visibleForTesting
String reviewDayOf(DateTime instant) => calendarDateForApi(instant.toLocal());
