// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ContourSchedule _$ContourScheduleFromJson(Map<String, dynamic> json) =>
    _ContourSchedule(
      days: (json['days'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(),
      from: json['from'] as String,
      to: json['to'] as String,
    );

Map<String, dynamic> _$ContourScheduleToJson(_ContourSchedule instance) =>
    <String, dynamic>{
      'days': instance.days,
      'from': instance.from,
      'to': instance.to,
    };

_Contour _$ContourFromJson(Map<String, dynamic> json) => _Contour(
  id: json['id'] as String,
  name: json['name'] as String,
  slots: (json['slots'] as num?)?.toInt() ?? 2,
  windowDays: (json['windowDays'] as num?)?.toInt() ?? 7,
  schedule: json['schedule'] == null
      ? null
      : ContourSchedule.fromJson(json['schedule'] as Map<String, dynamic>),
  position: (json['position'] as num).toDouble(),
  createdAt: json['createdAt'] as String?,
  updatedAt: json['updatedAt'] as String?,
);

Map<String, dynamic> _$ContourToJson(_Contour instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'slots': instance.slots,
  'windowDays': instance.windowDays,
  'schedule': instance.schedule?.toJson(),
  'position': instance.position,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
};

_ActiveContourChoice _$ActiveContourChoiceFromJson(Map<String, dynamic> json) =>
    _ActiveContourChoice(
      contourId: json['contourId'] as String?,
      until: json['until'] as String?,
    );

Map<String, dynamic> _$ActiveContourChoiceToJson(
  _ActiveContourChoice instance,
) => <String, dynamic>{
  'contourId': instance.contourId,
  'until': instance.until,
};

_ContourList _$ContourListFromJson(Map<String, dynamic> json) => _ContourList(
  contours: (json['contours'] as List<dynamic>)
      .map((e) => Contour.fromJson(e as Map<String, dynamic>))
      .toList(),
  active: json['active'] == null
      ? const ActiveContourChoice()
      : ActiveContourChoice.fromJson(json['active'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ContourListToJson(_ContourList instance) =>
    <String, dynamic>{
      'contours': instance.contours.map((e) => e.toJson()).toList(),
      'active': instance.active.toJson(),
    };

_TaskGoalRef _$TaskGoalRefFromJson(Map<String, dynamic> json) => _TaskGoalRef(
  id: json['id'] as String,
  title: json['title'] as String,
  contourId: json['contourId'] as String,
);

Map<String, dynamic> _$TaskGoalRefToJson(_TaskGoalRef instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'contourId': instance.contourId,
    };

_GoalTask _$GoalTaskFromJson(Map<String, dynamic> json) => _GoalTask(
  id: json['id'] as String,
  title: json['title'] as String,
  status: $enumDecode(_$TaskStatusEnumMap, json['status']),
  projectId: json['projectId'] as String,
  projectName: json['projectName'] as String,
  focusedAt: json['focusedAt'] as String?,
  focusContourId: json['focusContourId'] as String?,
);

Map<String, dynamic> _$GoalTaskToJson(_GoalTask instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'status': _$TaskStatusEnumMap[instance.status]!,
  'projectId': instance.projectId,
  'projectName': instance.projectName,
  'focusedAt': instance.focusedAt,
  'focusContourId': instance.focusContourId,
};

const _$TaskStatusEnumMap = {
  TaskStatus.pending: 'pending',
  TaskStatus.done: 'done',
  TaskStatus.blocked: 'blocked',
};

_GoalIdea _$GoalIdeaFromJson(Map<String, dynamic> json) => _GoalIdea(
  id: json['id'] as String,
  title: json['title'] as String,
  projectId: json['projectId'] as String,
  projectName: json['projectName'] as String,
);

Map<String, dynamic> _$GoalIdeaToJson(_GoalIdea instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'projectId': instance.projectId,
  'projectName': instance.projectName,
};

_GoalProgress _$GoalProgressFromJson(Map<String, dynamic> json) =>
    _GoalProgress(
      done: (json['done'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$GoalProgressToJson(_GoalProgress instance) =>
    <String, dynamic>{'done': instance.done, 'total': instance.total};

_GoalView _$GoalViewFromJson(Map<String, dynamic> json) => _GoalView(
  id: json['id'] as String,
  contourId: json['contourId'] as String,
  title: json['title'] as String,
  why: json['why'] as String?,
  state: $enumDecode(
    _$GoalStateEnumMap,
    json['state'],
    unknownValue: GoalState.bench,
  ),
  slottedAt: json['slottedAt'] as String?,
  windowDays: (json['windowDays'] as num?)?.toInt() ?? 7,
  ownWindowDays: (json['ownWindowDays'] as num?)?.toInt(),
  windowEndsAt: json['windowEndsAt'] as String?,
  windowExpired: json['windowExpired'] as bool? ?? false,
  achievedAt: json['achievedAt'] as String?,
  position: (json['position'] as num).toDouble(),
  createdAt: json['createdAt'] as String,
  tasks:
      (json['tasks'] as List<dynamic>?)
          ?.map((e) => GoalTask.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <GoalTask>[],
  nextStep: json['nextStep'] == null
      ? null
      : GoalTask.fromJson(json['nextStep'] as Map<String, dynamic>),
  ideas:
      (json['ideas'] as List<dynamic>?)
          ?.map((e) => GoalIdea.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <GoalIdea>[],
  progress: json['progress'] == null
      ? const GoalProgress()
      : GoalProgress.fromJson(json['progress'] as Map<String, dynamic>),
);

Map<String, dynamic> _$GoalViewToJson(_GoalView instance) => <String, dynamic>{
  'id': instance.id,
  'contourId': instance.contourId,
  'title': instance.title,
  'why': instance.why,
  'state': _$GoalStateEnumMap[instance.state]!,
  'slottedAt': instance.slottedAt,
  'windowDays': instance.windowDays,
  'ownWindowDays': instance.ownWindowDays,
  'windowEndsAt': instance.windowEndsAt,
  'windowExpired': instance.windowExpired,
  'achievedAt': instance.achievedAt,
  'position': instance.position,
  'createdAt': instance.createdAt,
  'tasks': instance.tasks.map((e) => e.toJson()).toList(),
  'nextStep': instance.nextStep?.toJson(),
  'ideas': instance.ideas.map((e) => e.toJson()).toList(),
  'progress': instance.progress.toJson(),
};

const _$GoalStateEnumMap = {
  GoalState.slot: 'slot',
  GoalState.bench: 'bench',
  GoalState.achieved: 'achieved',
};
