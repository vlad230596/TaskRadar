// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LoginResult _$LoginResultFromJson(Map<String, dynamic> json) => _LoginResult(
  ok: json['ok'] as bool,
  token: json['token'] as String,
  expiresIn: (json['expiresIn'] as num).toInt(),
);

Map<String, dynamic> _$LoginResultToJson(_LoginResult instance) =>
    <String, dynamic>{
      'ok': instance.ok,
      'token': instance.token,
      'expiresIn': instance.expiresIn,
    };
