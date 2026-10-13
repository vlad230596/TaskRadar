// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_InboxItem _$InboxItemFromJson(Map<String, dynamic> json) => _InboxItem(
  id: json['id'] as String,
  text: json['text'] as String,
  aiSource: json['aiSource'] as String?,
  aiKind: json['aiKind'] as String?,
  aiResult: json['aiResult'] as Map<String, dynamic>?,
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, dynamic> _$InboxItemToJson(_InboxItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'aiSource': instance.aiSource,
      'aiKind': instance.aiKind,
      'aiResult': instance.aiResult,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };
