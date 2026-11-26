import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/project_badge.dart';
import '../domain/today_view.dart';
import '../models/focus_task.dart';
import '../models/goal.dart';
import '../models/task_status.dart';

/// What the Android home-screen widget draws: the set «в работе», grouped by
/// project, frozen at one moment.
///
/// ## Why a snapshot and not the API
///
/// The widget lives in the launcher's process and has no session, no token
/// and no network code -- and must keep showing something on a phone in a
/// tunnel. So the app pushes this snapshot every time the set changes, and the
/// widget draws the last one it was given (see `HomeWidgetScope`). Offline the
/// widget simply keeps the last snapshot, with its time on it.
///
/// ## Which tasks
///
/// Exactly the rows of `activeFocusSetProvider` -- the set the work mode shows
/// (the active contour's), in
/// the server's order (`focusedAt` ascending). Nothing is re-sorted here, for
/// the same reason the work screen does not: a client that reorders the set
/// itself drifts from the server silently.
///
/// - **Projects** come in the order of their first task in the set: the
///   project whose task was taken first is on top.
/// - **Tasks** inside a project keep their order from the set.
///
/// ## The wire format
///
/// Plain JSON with a schema number ([schemaVersion]). The reader is Kotlin
/// (`HomeWidgetStore.kt`), which treats a snapshot with a newer schema the same
/// way as no snapshot: "open the app". Keep both sides in step.
@immutable
class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    required this.updatedAt,
    required this.fromCache,
    required this.signedIn,
    required this.projects,
    this.goals = const <HomeWidgetGoal>[],
    this.today,
  });

  /// The snapshot the widget gets when the user signs out: no tasks, and a
  /// reason to open the app rather than "nothing in work".
  factory HomeWidgetSnapshot.signedOut({required DateTime at}) =>
      HomeWidgetSnapshot(
        updatedAt: at,
        fromCache: false,
        signedIn: false,
        projects: const <HomeWidgetProject>[],
      );

  /// Bump together with `HomeWidgetStore.SCHEMA_VERSION` in Kotlin.
  static const int schemaVersion = 1;

  /// When the data was true: the moment of the server answer, or -- when the
  /// set on screen is the local copy -- the moment that copy was saved. Never
  /// "when the widget was redrawn": the widget prints it as «обновлено», and an
  /// offline copy stamped with the current time would be a lie.
  final DateTime updatedAt;

  /// True when the set came from the local copy because the server did not
  /// answer. The widget says «копия» next to the time.
  final bool fromCache;

  /// False only for [HomeWidgetSnapshot.signedOut].
  final bool signedIn;

  final List<HomeWidgetProject> projects;

  /// The active contour's goals in slots, drawn above the projects
  /// (`design/goals-ideas-spec.md`, п. 10). Optional on the wire: a snapshot
  /// without the key -- an older app -- has none, and the schema number stays
  /// 1 so an older widget simply ignores them.
  final List<HomeWidgetGoal> goals;

  /// The «Сегодня 3 из 7» row (`design/today-history-spec.md` §12), or null
  /// when there is nothing to say (no day block known yet).
  final HomeWidgetToday? today;

  /// All tasks in the snapshot, across projects.
  int get total => projects.fold(0, (sum, project) => sum + project.count);

  Map<String, Object?> toJson() => <String, Object?>{
    'v': schemaVersion,
    'updatedAt': updatedAt.toUtc().millisecondsSinceEpoch,
    'fromCache': fromCache,
    'signedIn': signedIn,
    'total': total,
    'projects': <Object?>[for (final project in projects) project.toJson()],
    'goals': <Object?>[for (final goal in goals) goal.toJson()],
    'today': ?today?.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory HomeWidgetSnapshot.fromJson(Map<String, Object?> json) {
    final version = json['v'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported home widget schema: $version');
    }
    return HomeWidgetSnapshot(
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt']! as int,
        isUtc: true,
      ),
      fromCache: json['fromCache']! as bool,
      signedIn: json['signedIn']! as bool,
      projects: List<HomeWidgetProject>.unmodifiable(
        (json['projects']! as List<Object?>).map(
          (row) => HomeWidgetProject.fromJson(
            (row! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        ),
      ),
      goals: List<HomeWidgetGoal>.unmodifiable(
        ((json['goals'] as List<Object?>?) ?? const <Object?>[]).map(
          (row) => HomeWidgetGoal.fromJson(
            (row! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        ),
      ),
      today: json['today'] is Map
          ? HomeWidgetToday.fromJson(
              (json['today']! as Map<Object?, Object?>).cast<String, Object?>(),
            )
          : null,
    );
  }

  factory HomeWidgetSnapshot.decode(String source) =>
      HomeWidgetSnapshot.fromJson(
        (jsonDecode(source) as Map<Object?, Object?>).cast<String, Object?>(),
      );
}

/// One project header in the widget, with its tasks.
@immutable
class HomeWidgetProject {
  const HomeWidgetProject({
    required this.id,
    required this.name,
    required this.badgeColor,
    required this.badgeLetter,
    required this.tasks,
  });

  final String id;
  final String name;

  /// ARGB, from [assignProjectBadgeColors] over the projects *in the widget*,
  /// so two headers next to each other never share a colour.
  final int badgeColor;
  final String badgeLetter;
  final List<HomeWidgetTask> tasks;

  /// The number on the header: this project's tasks in work.
  int get count => tasks.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'count': count,
    'badge': badgeColor,
    'letter': badgeLetter,
    'tasks': <Object?>[for (final task in tasks) task.toJson()],
  };

  factory HomeWidgetProject.fromJson(Map<String, Object?> json) =>
      HomeWidgetProject(
        id: json['id']! as String,
        name: json['name']! as String,
        badgeColor: json['badge']! as int,
        badgeLetter: json['letter']! as String,
        tasks: List<HomeWidgetTask>.unmodifiable(
          (json['tasks']! as List<Object?>).map(
            (row) => HomeWidgetTask.fromJson(
              (row! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          ),
        ),
      );
}

/// One task row in the widget.
@immutable
class HomeWidgetTask {
  const HomeWidgetTask({
    required this.id,
    required this.projectId,
    required this.title,
    required this.blocked,
  });

  final String id;

  /// Carried so the tap can open the project without a board lookup if it has
  /// to; the app still resolves through `NotificationLink`.
  final String projectId;
  final String title;

  /// «Ждёт»: a blocked task stays in the set (waiting is still work), and the
  /// widget marks it with the amber dot the app uses.
  final bool blocked;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'projectId': projectId,
    'title': title,
    'blocked': blocked,
  };

  factory HomeWidgetTask.fromJson(Map<String, Object?> json) => HomeWidgetTask(
    id: json['id']! as String,
    projectId: json['projectId']! as String,
    title: json['title']! as String,
    blocked: json['blocked']! as bool,
  );
}

/// One goal step row in the widget: the goal's next step (or «Обсудить» when
/// it has none), its progress and whether its window ran out.
@immutable
class HomeWidgetGoal {
  const HomeWidgetGoal({
    required this.goalId,
    required this.title,
    required this.done,
    required this.total,
    this.stepId,
    this.stepTitle,
    this.stepProjectId,
    this.expired = false,
    this.inWork = false,
  });

  final String goalId;

  /// The goal's title.
  final String title;
  final int done;
  final int total;

  /// The next step, or null: the widget then says «Обсудить: <title>» and
  /// has no take button.
  final String? stepId;
  final String? stepTitle;
  final String? stepProjectId;

  /// The goal's window ran out (`windowExpired`).
  final bool expired;

  /// The step is already in the active contour's set: «в работе» instead of
  /// the take button.
  final bool inWork;

  Map<String, Object?> toJson() => <String, Object?>{
    'goalId': goalId,
    'title': title,
    'done': done,
    'total': total,
    'stepId': stepId,
    'stepTitle': stepTitle,
    'stepProjectId': stepProjectId,
    'expired': expired,
    'inWork': inWork,
  };

  factory HomeWidgetGoal.fromJson(Map<String, Object?> json) => HomeWidgetGoal(
    goalId: json['goalId']! as String,
    title: json['title']! as String,
    done: json['done']! as int,
    total: json['total']! as int,
    stepId: json['stepId'] as String?,
    stepTitle: json['stepTitle'] as String?,
    stepProjectId: json['stepProjectId'] as String?,
    expired: json['expired'] as bool? ?? false,
    inWork: json['inWork'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetGoal &&
      other.goalId == goalId &&
      other.title == title &&
      other.done == done &&
      other.total == total &&
      other.stepId == stepId &&
      other.stepTitle == stepTitle &&
      other.stepProjectId == stepProjectId &&
      other.expired == expired &&
      other.inWork == inWork;

  @override
  int get hashCode => Object.hash(
    goalId,
    title,
    done,
    total,
    stepId,
    stepTitle,
    stepProjectId,
    expired,
    inWork,
  );
}

/// The widget's goal rows: the goals of [activeContourId] in slots, in the
/// order [goals] has them (contour, then position -- the server's order).
/// [setIds] is the active contour's working set, for «в работе». No active
/// contour known (contours not loaded) -- no rows: the widget then shows the
/// set alone, as before goals.
List<HomeWidgetGoal> buildHomeWidgetGoals(
  List<GoalView> goals, {
  required String? activeContourId,
  required Set<String> setIds,
}) {
  if (activeContourId == null) return const <HomeWidgetGoal>[];
  return List<HomeWidgetGoal>.unmodifiable(<HomeWidgetGoal>[
    for (final goal in goals)
      if (goal.contourId == activeContourId && goal.inSlot)
        HomeWidgetGoal(
          goalId: goal.id,
          title: goal.title.trim().isEmpty ? 'Без названия' : goal.title,
          done: goal.progress.done,
          total: goal.progress.total,
          stepId: goal.nextStep?.id,
          stepTitle: goal.nextStep?.title,
          stepProjectId: goal.nextStep?.projectId,
          expired: goal.windowExpired,
          inWork: goal.nextStep != null && setIds.contains(goal.nextStep!.id),
        ),
  ]);
}

/// Builds the snapshot from the set as the work mode has it.
///
/// [rows] is taken in its own order; see [HomeWidgetSnapshot] for why nothing
/// is sorted. A task title that is blank (the API forbids it, an old cached
/// row might not) is shown as «Без названия» rather than as an empty row.
HomeWidgetSnapshot buildHomeWidgetSnapshot(
  List<FocusTask> rows, {
  required DateTime updatedAt,
  bool fromCache = false,
  List<HomeWidgetGoal> goals = const <HomeWidgetGoal>[],
  HomeWidgetToday? today,
}) {
  final order = <String>[];
  final names = <String, String>{};
  final tasks = <String, List<HomeWidgetTask>>{};

  for (final row in rows) {
    final projectId = row.project.id.isNotEmpty
        ? row.project.id
        : row.projectId;
    if (!tasks.containsKey(projectId)) {
      order.add(projectId);
      names[projectId] = row.project.name;
      tasks[projectId] = <HomeWidgetTask>[];
    }
    final title = row.title.trim();
    tasks[projectId]!.add(
      HomeWidgetTask(
        id: row.id,
        projectId: projectId,
        title: title.isEmpty ? 'Без названия' : title,
        blocked: row.status == TaskStatus.blocked,
      ),
    );
  }

  final colours = assignProjectBadgeColors(names.values);

  return HomeWidgetSnapshot(
    updatedAt: updatedAt,
    fromCache: fromCache,
    signedIn: true,
    goals: goals,
    today: today,
    projects: List<HomeWidgetProject>.unmodifiable(<HomeWidgetProject>[
      for (final id in order)
        HomeWidgetProject(
          id: id,
          name: names[id]!,
          badgeColor: colours[names[id]!]!.toARGB32(),
          badgeLetter: projectBadgeLetter(names[id]!),
          tasks: List<HomeWidgetTask>.unmodifiable(tasks[id]!),
        ),
    ]),
  );
}

/// The widget's «Сегодня» row: «Сегодня 3 из 7» and the nearest timed task
/// («15:00 Встретить курьера»). Computed in the app from the day block, so it
/// works offline; the widget only draws it.
@immutable
class HomeWidgetToday {
  const HomeWidgetToday({
    required this.done,
    required this.total,
    this.tail = 0,
    this.time,
    this.title,
  });

  /// «N из M»: N closed today, M = today + closed today.
  final int done;
  final int total;

  /// «С прошлых дней»: shown instead when M = 0 (coordinator, answer 7).
  final int tail;

  /// The nearest open task today with a time: `9:30` and its title.
  final String? time;
  final String? title;

  /// Whether the row is drawn at all: M = 0 with no tail hides it.
  bool get visible => total > 0 || tail > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'done': done,
    'total': total,
    'tail': tail,
    'time': time,
    'title': title,
  };

  factory HomeWidgetToday.fromJson(Map<String, Object?> json) =>
      HomeWidgetToday(
        done: json['done'] as int? ?? 0,
        total: json['total'] as int? ?? 0,
        tail: json['tail'] as int? ?? 0,
        time: json['time'] as String?,
        title: json['title'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetToday &&
      other.done == done &&
      other.total == total &&
      other.tail == tail &&
      other.time == time &&
      other.title == title;

  @override
  int get hashCode => Object.hash(done, total, tail, time, title);
}

/// The «Сегодня» row from [view] at [now]: the nearest timed open task that
/// has not passed, else the nearest one that has; no timed task, no line.
HomeWidgetToday buildHomeWidgetToday(DayView view, {required DateTime now}) {
  final minute = now.hour * 60 + now.minute;
  DayTask? ahead;
  int? aheadAt;
  DayTask? passed;
  int? passedAt;
  for (final entry in view.today) {
    final time = entry.time;
    if (time == null) continue;
    final parts = time.split(':');
    final at = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    if (at >= minute) {
      if (aheadAt == null || at < aheadAt) {
        ahead = entry;
        aheadAt = at;
      }
    } else if (passedAt == null || at > passedAt) {
      passed = entry;
      passedAt = at;
    }
  }
  final shown = ahead ?? passed;
  final title = shown?.task.title.trim();
  return HomeWidgetToday(
    done: view.doneCount,
    total: view.total,
    tail: view.tail.length,
    time: shown == null ? null : formatClock(shown.time!),
    title: shown == null
        ? null
        : (title == null || title.isEmpty ? 'Без названия' : title),
  );
}
