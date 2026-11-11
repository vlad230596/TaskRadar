// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_location.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TaskLocation _$TaskLocationFromJson(Map<String, dynamic> json) =>
    _TaskLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      radius: (json['radius'] as num?)?.toInt() ?? TaskLocation.defaultRadius,
      label: json['label'] as String?,
    );

Map<String, dynamic> _$TaskLocationToJson(_TaskLocation instance) =>
    <String, dynamic>{
      'lat': instance.lat,
      'lng': instance.lng,
      'radius': instance.radius,
      'label': ?instance.label,
    };
