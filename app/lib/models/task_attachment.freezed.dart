// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_attachment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TaskAttachment {

 String get id;/// `image/png`, `image/jpeg` or `image/webp`.
 String get mime; int get width; int get height; int get sizeBytes; String get createdAt;
/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskAttachmentCopyWith<TaskAttachment> get copyWith => _$TaskAttachmentCopyWithImpl<TaskAttachment>(this as TaskAttachment, _$identity);

  /// Serializes this TaskAttachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.mime, mime) || other.mime == mime)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,mime,width,height,sizeBytes,createdAt);

@override
String toString() {
  return 'TaskAttachment(id: $id, mime: $mime, width: $width, height: $height, sizeBytes: $sizeBytes, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $TaskAttachmentCopyWith<$Res>  {
  factory $TaskAttachmentCopyWith(TaskAttachment value, $Res Function(TaskAttachment) _then) = _$TaskAttachmentCopyWithImpl;
@useResult
$Res call({
 String id, String mime, int width, int height, int sizeBytes, String createdAt
});




}
/// @nodoc
class _$TaskAttachmentCopyWithImpl<$Res>
    implements $TaskAttachmentCopyWith<$Res> {
  _$TaskAttachmentCopyWithImpl(this._self, this._then);

  final TaskAttachment _self;
  final $Res Function(TaskAttachment) _then;

/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? mime = null,Object? width = null,Object? height = null,Object? sizeBytes = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,mime: null == mime ? _self.mime : mime // ignore: cast_nullable_to_non_nullable
as String,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskAttachment].
extension TaskAttachmentPatterns on TaskAttachment {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskAttachment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskAttachment value)  $default,){
final _that = this;
switch (_that) {
case _TaskAttachment():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskAttachment value)?  $default,){
final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String mime,  int width,  int height,  int sizeBytes,  String createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that.id,_that.mime,_that.width,_that.height,_that.sizeBytes,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String mime,  int width,  int height,  int sizeBytes,  String createdAt)  $default,) {final _that = this;
switch (_that) {
case _TaskAttachment():
return $default(_that.id,_that.mime,_that.width,_that.height,_that.sizeBytes,_that.createdAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String mime,  int width,  int height,  int sizeBytes,  String createdAt)?  $default,) {final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that.id,_that.mime,_that.width,_that.height,_that.sizeBytes,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskAttachment implements TaskAttachment {
  const _TaskAttachment({required this.id, required this.mime, this.width = 0, this.height = 0, this.sizeBytes = 0, required this.createdAt});
  factory _TaskAttachment.fromJson(Map<String, dynamic> json) => _$TaskAttachmentFromJson(json);

@override final  String id;
/// `image/png`, `image/jpeg` or `image/webp`.
@override final  String mime;
@override@JsonKey() final  int width;
@override@JsonKey() final  int height;
@override@JsonKey() final  int sizeBytes;
@override final  String createdAt;

/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskAttachmentCopyWith<_TaskAttachment> get copyWith => __$TaskAttachmentCopyWithImpl<_TaskAttachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskAttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.mime, mime) || other.mime == mime)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,mime,width,height,sizeBytes,createdAt);

@override
String toString() {
  return 'TaskAttachment(id: $id, mime: $mime, width: $width, height: $height, sizeBytes: $sizeBytes, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$TaskAttachmentCopyWith<$Res> implements $TaskAttachmentCopyWith<$Res> {
  factory _$TaskAttachmentCopyWith(_TaskAttachment value, $Res Function(_TaskAttachment) _then) = __$TaskAttachmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String mime, int width, int height, int sizeBytes, String createdAt
});




}
/// @nodoc
class __$TaskAttachmentCopyWithImpl<$Res>
    implements _$TaskAttachmentCopyWith<$Res> {
  __$TaskAttachmentCopyWithImpl(this._self, this._then);

  final _TaskAttachment _self;
  final $Res Function(_TaskAttachment) _then;

/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? mime = null,Object? width = null,Object? height = null,Object? sizeBytes = null,Object? createdAt = null,}) {
  return _then(_TaskAttachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,mime: null == mime ? _self.mime : mime // ignore: cast_nullable_to_non_nullable
as String,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
