// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Note _$NoteFromJson(Map<String, dynamic> json) => _Note(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  title: json['title'] as String,
  content: json['content'] as String,
  aiSource: json['aiSource'] as String?,
  aiKind: json['aiKind'] as String?,
  aiResult: json['aiResult'] as Map<String, dynamic>?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, dynamic> _$NoteToJson(_Note instance) => <String, dynamic>{
  'id': instance.id,
  'projectId': instance.projectId,
  'title': instance.title,
  'content': instance.content,
  'aiSource': instance.aiSource,
  'aiKind': instance.aiKind,
  'aiResult': instance.aiResult,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
};
