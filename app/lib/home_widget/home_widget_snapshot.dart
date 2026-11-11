import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/project_badge.dart';
import '../models/focus_task.dart';
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
/// Exactly the rows of `focusSetProvider` -- the set the work mode shows, in
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

  /// All tasks in the snapshot, across projects.
  int get total => projects.fold(0, (sum, project) => sum + project.count);

  Map<String, Object?> toJson() => <String, Object?>{
    'v': schemaVersion,
    'updatedAt': updatedAt.toUtc().millisecondsSinceEpoch,
    'fromCache': fromCache,
    'signedIn': signedIn,
    'total': total,
    'projects': <Object?>[for (final project in projects) project.toJson()],
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

/// Builds the snapshot from the set as the work mode has it.
///
/// [rows] is taken in its own order; see [HomeWidgetSnapshot] for why nothing
/// is sorted. A task title that is blank (the API forbids it, an old cached
/// row might not) is shown as «Без названия» rather than as an empty row.
HomeWidgetSnapshot buildHomeWidgetSnapshot(
  List<FocusTask> rows, {
  required DateTime updatedAt,
  bool fromCache = false,
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
