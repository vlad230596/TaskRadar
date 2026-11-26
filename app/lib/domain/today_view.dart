/// «Сегодня», «С прошлых дней» and «Позже» on the client
/// (`design/today-history-contract.md`).
///
/// The server computes the same lists (`backend/src/domain/today.ts`, `GET
/// /today`) for MCP and as a reference; the app computes them **here**, from
/// the board it already holds (with the outbox's waiting edits applied), so
/// the day block works offline and moves the moment a date is changed. The
/// rules must stay those of the server -- the tests in
/// `test/today_view_test.dart` are its cases.
///
/// One difference, decided by the coordinator (answer 1): the client groups
/// «Сегодня» by scope, and inside a scope puts the timed tasks first (by
/// time), then the rest in board order. The server's flat order -- timed
/// first across all scopes -- stays for MCP.
///
/// Days are `YYYY-MM-DD` strings compared as strings: zero-padded and
/// big-endian, so string order is date order. A task's date is the prefix of
/// its `remindAt` (see `reminders.dart` for why never a parsed instant).
library;

import 'package:flutter/foundation.dart';

import 'goals.dart' show formatClock;

import '../models/board_project.dart';
import '../models/scope.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import 'reminder_schedule.dart';
import 'reminders.dart';

export 'goals.dart' show formatClock;

/// A stored date's calendar day, or null for none or garbage.
String? taskDay(String? remindAt) =>
    remindAt == null ? null : reminderCalendarDate(remindAt);

/// [day] plus [days] calendar days.
String addDays(String day, int days) {
  final parts = day.split('-');
  final date = DateTime.utc(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]) + days,
  );
  return calendarDateForApi(date);
}

/// Whole days from [from] to [to] (positive when [to] is later).
int daysBetween(String from, String to) {
  DateTime parse(String day) {
    final p = day.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  return parse(to).difference(parse(from)).inDays;
}

/// The local calendar day of an ISO instant, or null.
String? localDayOfInstant(String? iso) {
  if (iso == null) return null;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return null;
  return calendarDateForApi(parsed.toLocal());
}

bool _open(Task task) => task.status != TaskStatus.done;

/// «Позже»: open, and dated after [today] + [horizonDays].
bool isLater(Task task, String today, int horizonDays) {
  final day = taskDay(task.remindAt);
  return _open(task) &&
      day != null &&
      day.compareTo(addDays(today, horizonDays)) > 0;
}

/// A task of the day block, with where it lives.
@immutable
class DayTask {
  const DayTask({
    required this.task,
    required this.projectName,
    this.scopeId,
    this.scopeName,
    this.scopeOrder = 0,
    this.projectOrder = 0,
  });

  final Task task;
  final String projectName;
  final String? scopeId;
  final String? scopeName;

  /// Board order: the scope's place, the project's place on the board.
  final int scopeOrder;
  final int projectOrder;

  String get id => task.id;
  String get projectId => task.projectId;

  /// `HH:MM` when the task has a readable time, else null.
  String? get time => reminderTimeFromString(task.remindTime)?.format();

  @override
  bool operator ==(Object other) =>
      other is DayTask &&
      other.task == task &&
      other.projectName == projectName &&
      other.scopeId == scopeId;

  @override
  int get hashCode => Object.hash(task, projectName, scopeId);
}

/// One scope's part of «Сегодня».
@immutable
class TodayScopeGroup {
  const TodayScopeGroup({
    required this.scopeId,
    required this.scopeName,
    required this.tasks,
  });

  final String? scopeId;
  final String? scopeName;
  final List<DayTask> tasks;
}

/// The day block of «Работа».
@immutable
class DayView {
  const DayView({
    required this.date,
    required this.today,
    required this.doneToday,
    required this.tail,
  });

  static const DayView empty = DayView(
    date: '',
    today: <DayTask>[],
    doneToday: <DayTask>[],
    tail: <DayTask>[],
  );

  /// The owner's today.
  final String date;

  /// Open, dated today -- grouped by scope (scope order), inside a scope the
  /// timed ones by time, then the rest in board order.
  final List<DayTask> today;

  /// Closed today and dated today or earlier; by `doneAt`.
  final List<DayTask> doneToday;

  /// Open, dated before today; oldest date first, then board order.
  final List<DayTask> tail;

  /// «N из M»: M = today + doneToday, N = doneToday.
  int get total => today.length + doneToday.length;
  int get doneCount => doneToday.length;

  /// [today] split by scope, in order. One group (with its scope) when all of
  /// it is one scope -- the caller draws no headings then.
  List<TodayScopeGroup> get groups {
    final groups = <TodayScopeGroup>[];
    for (final task in today) {
      if (groups.isEmpty || groups.last.scopeId != task.scopeId) {
        groups.add(
          TodayScopeGroup(
            scopeId: task.scopeId,
            scopeName: task.scopeName,
            tasks: <DayTask>[task],
          ),
        );
      } else {
        groups.last.tasks.add(task);
      }
    }
    return groups;
  }
}

int _boardOrder(DayTask a, DayTask b) {
  final scope = a.scopeOrder.compareTo(b.scopeOrder);
  if (scope != 0) return scope;
  final project = a.projectOrder.compareTo(b.projectOrder);
  if (project != 0) return project;
  return a.task.position.compareTo(b.task.position);
}

/// The day block from tasks already placed ([DayTask]s). Pure; see the file
/// comment for the rules.
DayView dayViewOf(Iterable<DayTask> tasks, String today) {
  final dueToday = <DayTask>[];
  final doneToday = <DayTask>[];
  final tail = <DayTask>[];

  for (final entry in tasks) {
    final task = entry.task;
    final day = taskDay(task.remindAt);
    if (day == null) continue;
    if (task.status == TaskStatus.done) {
      if (day.compareTo(today) <= 0 &&
          localDayOfInstant(task.doneAt) == today) {
        doneToday.add(entry);
      }
    } else if (day == today) {
      dueToday.add(entry);
    } else if (day.compareTo(today) < 0) {
      tail.add(entry);
    }
  }

  dueToday.sort((a, b) {
    final scope = a.scopeOrder.compareTo(b.scopeOrder);
    if (scope != 0) return scope;
    final at = a.time;
    final bt = b.time;
    if (at != null && bt != null) {
      final byTime = at.compareTo(bt);
      return byTime != 0 ? byTime : _boardOrder(a, b);
    }
    if (at != null) return -1;
    if (bt != null) return 1;
    return _boardOrder(a, b);
  });
  doneToday.sort(
    (a, b) => (a.task.doneAt ?? '').compareTo(b.task.doneAt ?? ''),
  );
  tail.sort((a, b) {
    final byDay = taskDay(
      a.task.remindAt,
    )!.compareTo(taskDay(b.task.remindAt)!);
    return byDay != 0 ? byDay : _boardOrder(a, b);
  });

  return DayView(
    date: today,
    today: List<DayTask>.unmodifiable(dueToday),
    doneToday: List<DayTask>.unmodifiable(doneToday),
    tail: List<DayTask>.unmodifiable(tail),
  );
}

/// Every task of the board, placed: its project's name, its scope and the
/// board order. Archived projects are not on the board, which is the rule of
/// `/today` too.
List<DayTask> placeBoardTasks(
  List<BoardProject> board, {
  List<Scope> scopes = const <Scope>[],
}) {
  final scopeIndex = <String, int>{
    for (var i = 0; i < scopes.length; i++) scopes[i].id: i,
  };
  final scopeNames = <String, String>{
    for (final scope in scopes) scope.id: scope.name,
  };
  return <DayTask>[
    for (var p = 0; p < board.length; p++)
      for (final task in board[p].tasks)
        DayTask(
          task: task,
          projectName: board[p].project.name,
          scopeId: board[p].project.scopeId,
          scopeName: scopeNames[board[p].project.scopeId],
          scopeOrder: scopeIndex[board[p].project.scopeId] ?? scopes.length,
          projectOrder: p,
        ),
  ];
}

// --- the date label (today-history-spec.md §3) --------------------------------

/// How a date label is coloured.
enum DateTone { overdue, today, soon }

@immutable
class TaskDateLabel {
  const TaskDateLabel(this.text, this.tone);

  final String text;
  final DateTone tone;

  /// The same label with a capital first letter (the editor's chip).
  String get capitalized =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  @override
  bool operator ==(Object other) =>
      other is TaskDateLabel && other.text == text && other.tone == tone;

  @override
  int get hashCode => Object.hash(text, tone);

  @override
  String toString() => 'TaskDateLabel($text, $tone)';
}

const List<String> kWeekdaysShort = <String>[
  'пн',
  'вт',
  'ср',
  'чт',
  'пт',
  'сб',
  'вс',
];

const List<String> kMonthsShort = <String>[
  'янв',
  'фев',
  'мар',
  'апр',
  'мая',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
];

DateTime _utcDay(String day) {
  final p = day.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// «пт 27.11» -- a weekday and a short date.
String weekdayDate(String day) {
  final date = _utcDay(day);
  return '${kWeekdaysShort[date.weekday - 1]} '
      '${date.day}.${date.month.toString().padLeft(2, '0')}';
}

/// «27.11».
String shortDate(String day) {
  final date = _utcDay(day);
  return '${date.day}.${date.month.toString().padLeft(2, '0')}';
}

/// A task's date as rows show it: «вчера», «3 дн. назад», «сегодня · 15:00»,
/// «завтра», «сб 28.11», «25 фев», «3 янв 2027». Null for no date; the raw
/// value for an unreadable one.
TaskDateLabel? formatTaskDate(
  String? remindAt,
  String? remindTime,
  String today,
) {
  if (remindAt == null) return null;
  final day = taskDay(remindAt);
  if (day == null) return TaskDateLabel(remindAt, DateTone.soon);
  final diff = daysBetween(today, day);
  final time = reminderTimeFromString(remindTime);
  String withTime(String text) =>
      time == null ? text : '$text · ${formatClock(time.format())}';

  if (diff == -1) return const TaskDateLabel('вчера', DateTone.overdue);
  if (diff < -1) return TaskDateLabel('${-diff} дн. назад', DateTone.overdue);
  if (diff == 0) return TaskDateLabel(withTime('сегодня'), DateTone.today);
  if (diff == 1) return TaskDateLabel(withTime('завтра'), DateTone.soon);
  if (diff <= 6) {
    return TaskDateLabel(withTime(weekdayDate(day)), DateTone.soon);
  }
  final date = _utcDay(day);
  final todayYear = _utcDay(today).year;
  final base = '${date.day} ${kMonthsShort[date.month - 1]}';
  return TaskDateLabel(
    withTime(date.year == todayYear ? base : '$base ${date.year}'),
    DateTone.soon,
  );
}

/// «Пн» in the date sheet: the nearest **next** Monday (on a Monday, a week
/// on).
String nextMonday(String today) {
  final weekday = _utcDay(today).weekday;
  return addDays(today, 8 - weekday);
}

/// The `YYYY-MM-DD` of [day] as a local-midnight [DateTime].
DateTime localDateOf(String day) {
  final p = day.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}
