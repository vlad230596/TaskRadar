// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Task _$TaskFromJson(Map<String, dynamic> json) => _Task(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  status: $enumDecode(_$TaskStatusEnumMap, json['status']),
  position: (json['position'] as num).toDouble(),
  remindAt: json['remindAt'] as String?,
  remindTime: json['remindTime'] as String?,
  categoryId: json['categoryId'] as String?,
  aiSource: json['aiSource'] as String?,
  aiKind: json['aiKind'] as String?,
  aiResult: json['aiResult'] as Map<String, dynamic>?,
  checklist: (json['checklist'] as List<dynamic>?)
      ?.map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  location: json['location'] == null
      ? null
      : TaskLocation.fromJson(json['location'] as Map<String, dynamic>),
  attachments:
      (json['attachments'] as List<dynamic>?)
          ?.map((e) => TaskAttachment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <TaskAttachment>[],
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
  isCurrent: json['isCurrent'] as bool,
);

Map<String, dynamic> _$TaskToJson(_Task instance) => <String, dynamic>{
  'id': instance.id,
  'projectId': instance.projectId,
  'title': instance.title,
  'description': instance.description,
  'status': _$TaskStatusEnumMap[instance.status]!,
  'position': instance.position,
  'remindAt': instance.remindAt,
  'remindTime': instance.remindTime,
  'categoryId': instance.categoryId,
  'aiSource': instance.aiSource,
  'aiKind': instance.aiKind,
  'aiResult': instance.aiResult,
  'checklist': instance.checklist?.map((e) => e.toJson()).toList(),
  'location': instance.location?.toJson(),
  'attachments': instance.attachments.map((e) => e.toJson()).toList(),
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
  'isCurrent': instance.isCurrent,
};

const _$TaskStatusEnumMap = {
  TaskStatus.pending: 'pending',
  TaskStatus.done: 'done',
  TaskStatus.blocked: 'blocked',
};
