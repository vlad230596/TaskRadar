// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'focus_task.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FocusTask _$FocusTaskFromJson(Map<String, dynamic> json) => _FocusTask(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  status: $enumDecode(_$TaskStatusEnumMap, json['status']),
  position: (json['position'] as num).toDouble(),
  remindAt: json['remindAt'] as String?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
  focusedAt: json['focusedAt'] as String,
  project: FocusProject.fromJson(json['project'] as Map<String, dynamic>),
);

Map<String, dynamic> _$FocusTaskToJson(_FocusTask instance) =>
    <String, dynamic>{
      'id': instance.id,
      'projectId': instance.projectId,
      'title': instance.title,
      'description': instance.description,
      'status': _$TaskStatusEnumMap[instance.status]!,
      'position': instance.position,
      'remindAt': instance.remindAt,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
      'focusedAt': instance.focusedAt,
      'project': instance.project,
    };

const _$TaskStatusEnumMap = {
  TaskStatus.pending: 'pending',
  TaskStatus.done: 'done',
  TaskStatus.blocked: 'blocked',
};

_FocusProject _$FocusProjectFromJson(Map<String, dynamic> json) =>
    _FocusProject(id: json['id'] as String, name: json['name'] as String);

Map<String, dynamic> _$FocusProjectToJson(_FocusProject instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};
