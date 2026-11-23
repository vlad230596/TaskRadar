import '../models/goal.dart';

/// The rules of goals and contours that need no network and no widget
/// (`design/goals-ideas-contract.md`): which contour is active, when that
/// answer changes, the crown, the warm age, and when taking a task into work
/// becomes a duel. Pure functions over plain values, so each rule is one test.

// -- Contour schedule ---------------------------------------------------------

/// Minutes since midnight for `HH:MM`, or null for anything else.
int? minutesOf(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 24 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}

/// Whether [schedule] covers the local moment [now]: its weekday is one of
/// the days, and `from <= time < to`.
bool scheduleCovers(ContourSchedule schedule, DateTime now) {
  final local = now.toLocal();
  if (!schedule.days.contains(local.weekday)) return false;
  final from = minutesOf(schedule.from);
  final to = minutesOf(schedule.to);
  if (from == null || to == null) return false;
  final minute = local.hour * 60 + local.minute;
  return minute >= from && minute < to;
}

/// Point 2 of the contract's resolution: the first contour by position whose
/// schedule covers [now], or null.
Contour? scheduledContour(List<Contour> contours, DateTime now) {
  for (final contour in _byPosition(contours)) {
    final schedule = contour.schedule;
    if (schedule != null && scheduleCovers(schedule, now)) return contour;
  }
  return null;
}

/// `resolveActiveContour(contours, override, now)` from the contract:
///
/// 1. the manual choice, while its `until` is null or in the future;
/// 2. else the first contour by position whose schedule covers [now];
/// 3. else the first by position.
///
/// Null only for an empty list (which the server never sends).
Contour? resolveActiveContour(
  List<Contour> contours,
  ActiveContourChoice choice,
  DateTime now,
) {
  if (contours.isEmpty) return null;
  final chosenId = choice.contourId;
  if (chosenId != null) {
    final until = choice.until == null ? null : DateTime.tryParse(choice.until!);
    if (until == null || until.isAfter(now)) {
      for (final contour in contours) {
        if (contour.id == chosenId) return contour;
      }
    }
  }
  return scheduledContour(contours, now) ?? _byPosition(contours).first;
}

/// Whether the active contour is a manual choice still in force -- the dot
/// «выбрано вручную» on the switcher.
bool isManualChoice(
  List<Contour> contours,
  ActiveContourChoice choice,
  DateTime now,
) {
  final chosenId = choice.contourId;
  if (chosenId == null) return false;
  if (!contours.any((contour) => contour.id == chosenId)) return false;
  final until = choice.until == null ? null : DateTime.tryParse(choice.until!);
  return until == null || until.isAfter(now);
}

/// The nearest moment after [now] at which point 2 of the resolution gives a
/// different answer -- the `until` of a manual switch. Null when no contour
/// has a schedule (the choice then lasts until the next manual switch), or
/// when nothing changes within the next eight days.
DateTime? nextScheduleChange(List<Contour> contours, DateTime now) {
  final scheduled = <ContourSchedule>[
    for (final contour in contours)
      if (contour.schedule != null) contour.schedule!,
  ];
  if (scheduled.isEmpty) return null;

  final local = now.toLocal();
  final candidates = <DateTime>{};
  for (var offset = 0; offset <= 8; offset++) {
    final day = DateTime(local.year, local.month, local.day + offset);
    for (final schedule in scheduled) {
      if (!schedule.days.contains(day.weekday)) continue;
      for (final edge in <String>[schedule.from, schedule.to]) {
        final minutes = minutesOf(edge);
        if (minutes == null) continue;
        final at = DateTime(
          day.year,
          day.month,
          day.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (at.isAfter(local)) candidates.add(at);
      }
    }
  }
  final sorted = candidates.toList()..sort();
  final current = scheduledContour(contours, local)?.id;
  for (final at in sorted) {
    if (scheduledContour(contours, at)?.id != current) return at;
  }
  return null;
}

/// «пн–пт · 9:00–19:00», or «без расписания».
String describeSchedule(ContourSchedule? schedule) {
  if (schedule == null) return 'без расписания';
  return '${describeDays(schedule.days)} · '
      '${formatClock(schedule.from)}–${formatClock(schedule.to)}';
}

const List<String> weekdayShort = <String>[
  'пн',
  'вт',
  'ср',
  'чт',
  'пт',
  'сб',
  'вс',
];

/// «пн–пт», «сб, вс», «пн, ср–пт», «каждый день».
String describeDays(List<int> days) {
  final sorted = days.toSet().where((d) => d >= 1 && d <= 7).toList()..sort();
  if (sorted.length == 7) return 'каждый день';
  if (sorted.isEmpty) return 'без дней';
  final runs = <String>[];
  var start = sorted.first;
  var prev = start;
  void flush() {
    if (prev - start >= 2) {
      runs.add('${weekdayShort[start - 1]}–${weekdayShort[prev - 1]}');
    } else {
      for (var d = start; d <= prev; d++) {
        runs.add(weekdayShort[d - 1]);
      }
    }
  }

  for (final day in sorted.skip(1)) {
    if (day == prev + 1) {
      prev = day;
      continue;
    }
    flush();
    start = day;
    prev = day;
  }
  flush();
  return runs.join(', ');
}

/// `09:00` -> «9:00».
String formatClock(String hhmm) {
  final minutes = minutesOf(hhmm);
  if (minutes == null) return hhmm;
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// The toast after a manual switch: «Личное — до пн 9:00» or «Личное — пока
/// не переключите».
String manualSwitchToast(String name, DateTime? until, {DateTime? now}) {
  if (until == null) return '$name — пока не переключите';
  final local = until.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final clock = '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  if (sameDay) return '$name — до $clock';
  return '$name — до ${weekdayShort[local.weekday - 1]} $clock';
}

List<Contour> _byPosition(List<Contour> contours) =>
    <Contour>[...contours]..sort((a, b) => a.position.compareTo(b.position));

// -- Crown and age ------------------------------------------------------------

/// How a task's crown is drawn.
enum CrownLevel {
  /// No goals: no crown.
  none,

  /// Goals, none of the active contour: the muted crown.
  muted,

  /// At least one goal of the active contour: the bright crown.
  bright,
}

/// The crown of a task with [goals], given the active contour. With no
/// active contour known (contours not loaded), any goal is bright.
CrownLevel crownLevel(List<TaskGoalRef> goals, String? activeContourId) {
  if (goals.isEmpty) return CrownLevel.none;
  if (activeContourId == null) return CrownLevel.bright;
  return goals.any((goal) => goal.contourId == activeContourId)
      ? CrownLevel.bright
      : CrownLevel.muted;
}

/// Whether an age may go warm (`isStaleAge`): only for a task in a working
/// set or with a crown. Every other age stays grey, however old.
bool mayWarmAge({required bool inWorkingSet, required bool crowned}) =>
    inWorkingSet || crowned;

// -- Duel -----------------------------------------------------------------------

/// The goals whose next step should be offered against a task being taken
/// into work (contract, «Дуэль»), in the contour's order. Empty means no duel:
///
/// - the task has a goal of the active contour (a bright crown);
/// - the set is already full ([setSize] >= [setLimit]) -- the set's own rule
///   comes first;
/// - no goal of the active contour is in a slot with a next step that is not
///   yet in the active set (and is not the task itself).
///
/// A goal whose window has run out is left out: its step is not shown until
/// the owner decides what to do with the goal.
List<GoalView> duelGoals({
  required String taskId,
  required List<TaskGoalRef> taskGoals,
  required String? activeContourId,
  required List<GoalView> goals,
  required Set<String> activeSetIds,
  required int setSize,
  required int setLimit,
}) {
  if (activeContourId == null) return const <GoalView>[];
  if (taskGoals.any((goal) => goal.contourId == activeContourId)) {
    return const <GoalView>[];
  }
  if (setSize >= setLimit) return const <GoalView>[];
  return <GoalView>[
    for (final goal in goals)
      if (goal.contourId == activeContourId &&
          goal.inSlot &&
          !goal.windowExpired &&
          goal.nextStep != null &&
          goal.nextStep!.id != taskId &&
          !activeSetIds.contains(goal.nextStep!.id))
        goal,
  ];
}

// -- Window -------------------------------------------------------------------

/// The end of a running window: «ещё 3 д», «ещё 1 д», and in the last day
/// «до 18:30». Null without an end.
String? windowLeftLabel(String? windowEndsAt, {DateTime? now}) {
  if (windowEndsAt == null) return null;
  final end = DateTime.tryParse(windowEndsAt)?.toLocal();
  if (end == null) return null;
  final at = (now ?? DateTime.now()).toLocal();
  final left = end.difference(at);
  if (left <= Duration.zero) return null;
  if (left < const Duration(days: 1)) {
    return 'до ${end.hour}:${end.minute.toString().padLeft(2, '0')}';
  }
  return 'ещё ${left.inDays} д';
}

/// An expired window: «Окно вышло сегодня» / «вчера» / «3 д назад».
String windowExpiredLabel(String? windowEndsAt, {DateTime? now}) {
  final end = windowEndsAt == null
      ? null
      : DateTime.tryParse(windowEndsAt)?.toLocal();
  if (end == null) return 'Окно вышло';
  final at = (now ?? DateTime.now()).toLocal();
  final days = DateTime(
    at.year,
    at.month,
    at.day,
  ).difference(DateTime(end.year, end.month, end.day)).inDays;
  if (days <= 0) return 'Окно вышло сегодня';
  if (days == 1) return 'Окно вышло вчера';
  return 'Окно вышло $days д назад';
}

/// `1.12` -- a date the way snackbars say it.
String shortDate(String? iso) {
  final at = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  return '${at.day}.${at.month.toString().padLeft(2, '0')}';
}

/// Whole days from [fromIso] to [toIso], at least 1.
int daysBetween(String fromIso, String? toIso) {
  final from = DateTime.tryParse(fromIso)?.toLocal();
  final to = toIso == null ? null : DateTime.tryParse(toIso)?.toLocal();
  if (from == null || to == null) return 1;
  final days = DateTime(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime(from.year, from.month, from.day)).inDays;
  return days < 1 ? 1 : days;
}

/// «задача / задачи / задач» for [n].
String tasksWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'задача';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'задачи';
  }
  return 'задач';
}

/// «цель / цели / целей» for [n].
String goalsWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'цель';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'цели';
  return 'целей';
}

/// «слот / слота / слотов» for [n].
String slotsWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'слот';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'слота';
  return 'слотов';
}
