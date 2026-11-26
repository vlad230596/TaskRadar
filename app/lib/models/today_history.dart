import 'package:flutter/foundation.dart';

import 'goal.dart';
import 'project.dart';
import 'task.dart';

/// The shapes of «Сегодня», «Сделано», «Недели», the review and the owner's
/// server settings (`design/today-history-contract.md`).
///
/// Hand-written rather than generated: every one of them is read-only on the
/// client (the app never sends them back), several wrap a [Task] that arrives
/// without `isCurrent`, and the lists are read leniently -- one odd row is not
/// worth an empty history.

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

List<Map<String, dynamic>> _maps(Object? value) => <Map<String, dynamic>>[
  if (value is List)
    for (final row in value)
      if (row is Map) row.cast<String, dynamic>(),
];

/// A task with where it lives: `taskView` + `projectName`, `scopeId`,
/// `scopeName` (`/today`, `/history/done`, `/reviews/draft`).
@immutable
class PlacedTask {
  const PlacedTask({
    required this.task,
    required this.projectName,
    this.scopeId,
    this.scopeName,
  });

  /// `isCurrent` is not on the wire for these lists; it reads as false, which
  /// is all a list across projects can honestly say.
  factory PlacedTask.fromJson(Map<String, dynamic> json) => PlacedTask(
    task: Task.fromJson(<String, dynamic>{'isCurrent': false, ...json}),
    projectName: json['projectName'] as String? ?? '',
    scopeId: json['scopeId'] as String?,
    scopeName: json['scopeName'] as String?,
  );

  final Task task;
  final String projectName;
  final String? scopeId;
  final String? scopeName;

  String get id => task.id;

  Map<String, dynamic> toJson() => <String, dynamic>{
    ...task.toJson(),
    'projectName': projectName,
    'scopeId': scopeId,
    'scopeName': scopeName,
  };
}

/// One closing in «Сделано».
@immutable
class DoneItem {
  const DoneItem({required this.task, required this.doneAt});

  factory DoneItem.fromJson(Map<String, dynamic> json) => DoneItem(
    task: PlacedTask.fromJson(
      (json['task'] as Map).cast<String, dynamic>(),
    ),
    doneAt: json['doneAt'] as String? ?? '',
  );

  final PlacedTask task;

  /// ISO instant.
  final String doneAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'task': task.toJson(),
    'doneAt': doneAt,
  };
}

/// A page of `GET /history/done`.
@immutable
class DonePage {
  const DonePage({required this.items, this.nextBefore});

  factory DonePage.fromJson(Map<String, dynamic> json) => DonePage(
    items: List<DoneItem>.unmodifiable(
      _maps(json['items']).map(DoneItem.fromJson),
    ),
    nextBefore: json['nextBefore'] as String?,
  );

  final List<DoneItem> items;

  /// Where the next page starts, or null at the end.
  final String? nextBefore;
}

/// «закрыто N» of one project.
@immutable
class ProjectClosed {
  const ProjectClosed({
    required this.projectId,
    required this.name,
    required this.closed,
  });

  factory ProjectClosed.fromJson(Map<String, dynamic> json) => ProjectClosed(
    projectId: json['projectId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    closed: _int(json['closed']),
  );

  final String projectId;
  final String name;
  final int closed;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'projectId': projectId,
    'name': name,
    'closed': closed,
  };
}

/// A goal achieved within a review's period, as the review stored it.
@immutable
class AchievedRef {
  const AchievedRef({required this.goalId, required this.title});

  factory AchievedRef.fromJson(Map<String, dynamic> json) => AchievedRef(
    goalId: json['goalId'] as String? ?? '',
    title: json['title'] as String? ?? '',
  );

  final String goalId;
  final String title;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'goalId': goalId,
    'title': title,
  };
}

/// A review's record.
@immutable
class Review {
  const Review({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    this.monthly = false,
    this.closedCount = 0,
    this.byProject = const <ProjectClosed>[],
    this.achievedGoals = const <AchievedRef>[],
    this.summary,
    this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
    id: json['id'] as String? ?? '',
    periodStart: json['periodStart'] as String? ?? '',
    periodEnd: json['periodEnd'] as String? ?? '',
    monthly: json['monthly'] == true,
    closedCount: _int(json['closedCount']),
    byProject: List<ProjectClosed>.unmodifiable(
      _maps(json['byProject']).map(ProjectClosed.fromJson),
    ),
    achievedGoals: List<AchievedRef>.unmodifiable(
      _maps(json['achievedGoals']).map(AchievedRef.fromJson),
    ),
    summary: json['summary'] as String?,
    createdAt: json['createdAt'] as String?,
  );

  final String id;
  final String periodStart;
  final String periodEnd;
  final bool monthly;
  final int closedCount;
  final List<ProjectClosed> byProject;
  final List<AchievedRef> achievedGoals;
  final String? summary;
  final String? createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'periodStart': periodStart,
    'periodEnd': periodEnd,
    'monthly': monthly,
    'closedCount': closedCount,
    'byProject': <Object>[for (final p in byProject) p.toJson()],
    'achievedGoals': <Object>[for (final g in achievedGoals) g.toJson()],
    'summary': summary,
    'createdAt': createdAt,
  };
}

/// One week of `GET /history/weeks`.
@immutable
class HistoryWeek {
  const HistoryWeek({
    required this.start,
    required this.closed,
    this.byProject = const <ProjectClosed>[],
    this.review,
  });

  factory HistoryWeek.fromJson(Map<String, dynamic> json) => HistoryWeek(
    start: json['start'] as String? ?? '',
    closed: _int(json['closed']),
    byProject: List<ProjectClosed>.unmodifiable(
      _maps(json['byProject']).map(ProjectClosed.fromJson),
    ),
    review: json['review'] is Map
        ? Review.fromJson((json['review'] as Map).cast<String, dynamic>())
        : null,
  );

  /// The week's Monday, `YYYY-MM-DD`.
  final String start;
  final int closed;
  final List<ProjectClosed> byProject;
  final Review? review;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'start': start,
    'closed': closed,
    'byProject': <Object>[for (final p in byProject) p.toJson()],
    'review': review?.toJson(),
  };

  static List<HistoryWeek> listFromJson(Object? json) {
    final weeks = json is Map ? json['weeks'] : json;
    return List<HistoryWeek>.unmodifiable(
      _maps(weeks).map(HistoryWeek.fromJson),
    );
  }
}

/// `GET /reviews/status`.
@immutable
class ReviewStatus {
  const ReviewStatus({required this.due, this.nextAt, this.lastAt});

  factory ReviewStatus.fromJson(Map<String, dynamic> json) => ReviewStatus(
    due: json['due'] == true,
    nextAt: json['nextAt'] as String?,
    lastAt: json['lastAt'] as String?,
  );

  final bool due;

  /// When the review became (or becomes) due; in the past when [due].
  final String? nextAt;
  final String? lastAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'due': due,
    'nextAt': nextAt,
    'lastAt': lastAt,
  };
}

/// Why a task is in «Задумано».
enum IntendedReason { workingSet, goalStep, dated }

@immutable
class IntendedTask {
  const IntendedTask({required this.task, required this.reasons});

  factory IntendedTask.fromJson(Map<String, dynamic> json) => IntendedTask(
    task: PlacedTask.fromJson((json['task'] as Map).cast<String, dynamic>()),
    reasons: <IntendedReason>[
      if (json['reasons'] is List)
        for (final reason in json['reasons'] as List)
          ...IntendedReason.values.where((r) => r.name == reason),
    ],
  );

  final PlacedTask task;
  final List<IntendedReason> reasons;
}

/// A project off its rhythm, in the draft.
@immutable
class RhythmProject {
  const RhythmProject({required this.project, required this.rhythm});

  factory RhythmProject.fromJson(Map<String, dynamic> json) {
    final project = Project.fromJson(
      (json['project'] as Map).cast<String, dynamic>(),
    );
    final rhythm =
        ProjectRhythm.maybeFromJson(json['rhythm']) ?? const ProjectRhythm();
    return RhythmProject(
      project: project.copyWith(rhythm: rhythm),
      rhythm: rhythm,
    );
  }

  final Project project;
  final ProjectRhythm rhythm;
}

/// The monthly section of a draft: the calendar month before the review's.
@immutable
class ReviewMonth {
  const ReviewMonth({
    required this.month,
    this.byProject = const <ProjectClosed>[],
    this.achievedGoals = const <GoalView>[],
  });

  factory ReviewMonth.fromJson(Map<String, dynamic> json) => ReviewMonth(
    month: json['month'] as String? ?? '',
    byProject: List<ProjectClosed>.unmodifiable(
      _maps(json['byProject']).map(ProjectClosed.fromJson),
    ),
    achievedGoals: List<GoalView>.unmodifiable(
      _maps(json['achievedGoals']).map(GoalView.fromJson),
    ),
  );

  /// `YYYY-MM`.
  final String month;
  final List<ProjectClosed> byProject;
  final List<GoalView> achievedGoals;

  int get closed => byProject.fold(0, (sum, p) => sum + p.closed);
}

/// `GET /reviews/draft`: what the six steps look at.
@immutable
class ReviewDraft {
  const ReviewDraft({
    required this.periodStart,
    required this.periodEnd,
    this.monthly = false,
    this.done = const <DoneItem>[],
    this.intended = const <IntendedTask>[],
    this.goals = const <GoalView>[],
    this.rhythm = const <RhythmProject>[],
    this.month,
  });

  factory ReviewDraft.fromJson(Map<String, dynamic> json) => ReviewDraft(
    periodStart: json['periodStart'] as String? ?? '',
    periodEnd: json['periodEnd'] as String? ?? '',
    monthly: json['monthly'] == true,
    done: List<DoneItem>.unmodifiable(_maps(json['done']).map(DoneItem.fromJson)),
    intended: List<IntendedTask>.unmodifiable(
      _maps(json['intended']).map(IntendedTask.fromJson),
    ),
    goals: List<GoalView>.unmodifiable(
      _maps(json['goals']).map(GoalView.fromJson),
    ),
    rhythm: List<RhythmProject>.unmodifiable(
      _maps(json['rhythm']).map(RhythmProject.fromJson),
    ),
    month: json['month'] is Map
        ? ReviewMonth.fromJson((json['month'] as Map).cast<String, dynamic>())
        : null,
  );

  final String periodStart;
  final String periodEnd;
  final bool monthly;
  final List<DoneItem> done;
  final List<IntendedTask> intended;
  final List<GoalView> goals;
  final List<RhythmProject> rhythm;
  final ReviewMonth? month;
}

/// The owner's settings kept on the server (`GET/PATCH /settings`).
@immutable
class OwnerSettings {
  const OwnerSettings({
    this.laterHorizonDays = kDefaultLaterHorizonDays,
    this.reviewWeekday = 1,
    this.reviewTime = '09:00',
  });

  factory OwnerSettings.fromJson(Map<String, dynamic> json) => OwnerSettings(
    laterHorizonDays: _int(json['laterHorizonDays'], kDefaultLaterHorizonDays),
    reviewWeekday: _int(json['reviewWeekday'], 1),
    reviewTime: json['reviewTime'] as String? ?? '09:00',
  );

  /// «Позже» starts after today + this many days. 1..90.
  final int laterHorizonDays;

  /// 1 = Monday .. 7 = Sunday, like `DateTime.weekday`.
  final int reviewWeekday;

  /// `HH:MM`, local.
  final String reviewTime;

  OwnerSettings copyWith({
    int? laterHorizonDays,
    int? reviewWeekday,
    String? reviewTime,
  }) => OwnerSettings(
    laterHorizonDays: laterHorizonDays ?? this.laterHorizonDays,
    reviewWeekday: reviewWeekday ?? this.reviewWeekday,
    reviewTime: reviewTime ?? this.reviewTime,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'laterHorizonDays': laterHorizonDays,
    'reviewWeekday': reviewWeekday,
    'reviewTime': reviewTime,
  };

  @override
  bool operator ==(Object other) =>
      other is OwnerSettings &&
      other.laterHorizonDays == laterHorizonDays &&
      other.reviewWeekday == reviewWeekday &&
      other.reviewTime == reviewTime;

  @override
  int get hashCode => Object.hash(laterHorizonDays, reviewWeekday, reviewTime);
}

/// The horizon a user who never set one has (the server's default too).
const int kDefaultLaterHorizonDays = 10;
