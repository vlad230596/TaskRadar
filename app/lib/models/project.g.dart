// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Project _$ProjectFromJson(Map<String, dynamic> json) => _Project(
  id: json['id'] as String,
  name: json['name'] as String,
  scopeId: json['scopeId'] as String,
  archivedAt: json['archivedAt'] as String?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
  noteCount: _countFromJson(json['noteCount']),
);

Map<String, dynamic> _$ProjectToJson(_Project instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'scopeId': instance.scopeId,
  'archivedAt': instance.archivedAt,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
  'noteCount': ?instance.noteCount,
};
