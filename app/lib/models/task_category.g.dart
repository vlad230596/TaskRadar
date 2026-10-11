// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TaskCategory _$TaskCategoryFromJson(Map<String, dynamic> json) =>
    _TaskCategory(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      position: (json['position'] as num).toDouble(),
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );

Map<String, dynamic> _$TaskCategoryToJson(_TaskCategory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'projectId': instance.projectId,
      'name': instance.name,
      'position': instance.position,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };
