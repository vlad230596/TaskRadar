// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_attachment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TaskAttachment _$TaskAttachmentFromJson(Map<String, dynamic> json) =>
    _TaskAttachment(
      id: json['id'] as String,
      mime: json['mime'] as String,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String,
    );

Map<String, dynamic> _$TaskAttachmentToJson(_TaskAttachment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'mime': instance.mime,
      'width': instance.width,
      'height': instance.height,
      'sizeBytes': instance.sizeBytes,
      'createdAt': instance.createdAt,
    };
