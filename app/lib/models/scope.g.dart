// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scope.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Scope _$ScopeFromJson(Map<String, dynamic> json) => _Scope(
  id: json['id'] as String,
  name: json['name'] as String,
  position: (json['position'] as num).toDouble(),
  createdAt: json['createdAt'] as String,
  updatedAt: json['updatedAt'] as String,
);

Map<String, dynamic> _$ScopeToJson(_Scope instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'position': instance.position,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
};
