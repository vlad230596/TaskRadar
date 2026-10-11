// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_category.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TaskCategory {

 String get id; String get projectId; String get name;/// Order of the groups. Read for diagnostics only, as with
/// [Task.position]: the list comes back sorted.
 double get position; String get createdAt; String get updatedAt;
/// Create a copy of TaskCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskCategoryCopyWith<TaskCategory> get copyWith => _$TaskCategoryCopyWithImpl<TaskCategory>(this as TaskCategory, _$identity);

  /// Serializes this TaskCategory to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.name, name) || other.name == name)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,name,position,createdAt,updatedAt);

@override
String toString() {
  return 'TaskCategory(id: $id, projectId: $projectId, name: $name, position: $position, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $TaskCategoryCopyWith<$Res>  {
  factory $TaskCategoryCopyWith(TaskCategory value, $Res Function(TaskCategory) _then) = _$TaskCategoryCopyWithImpl;
@useResult
$Res call({
 String id, String projectId, String name, double position, String createdAt, String updatedAt
});




}
/// @nodoc
class _$TaskCategoryCopyWithImpl<$Res>
    implements $TaskCategoryCopyWith<$Res> {
  _$TaskCategoryCopyWithImpl(this._self, this._then);

  final TaskCategory _self;
  final $Res Function(TaskCategory) _then;

/// Create a copy of TaskCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? projectId = null,Object? name = null,Object? position = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskCategory].
extension TaskCategoryPatterns on TaskCategory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskCategory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskCategory() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskCategory value)  $default,){
final _that = this;
switch (_that) {
case _TaskCategory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskCategory value)?  $default,){
final _that = this;
switch (_that) {
case _TaskCategory() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String projectId,  String name,  double position,  String createdAt,  String updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskCategory() when $default != null:
return $default(_that.id,_that.projectId,_that.name,_that.position,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String projectId,  String name,  double position,  String createdAt,  String updatedAt)  $default,) {final _that = this;
switch (_that) {
case _TaskCategory():
return $default(_that.id,_that.projectId,_that.name,_that.position,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String projectId,  String name,  double position,  String createdAt,  String updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _TaskCategory() when $default != null:
return $default(_that.id,_that.projectId,_that.name,_that.position,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskCategory implements TaskCategory {
  const _TaskCategory({required this.id, required this.projectId, required this.name, required this.position, required this.createdAt, required this.updatedAt});
  factory _TaskCategory.fromJson(Map<String, dynamic> json) => _$TaskCategoryFromJson(json);

@override final  String id;
@override final  String projectId;
@override final  String name;
/// Order of the groups. Read for diagnostics only, as with
/// [Task.position]: the list comes back sorted.
@override final  double position;
@override final  String createdAt;
@override final  String updatedAt;

/// Create a copy of TaskCategory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskCategoryCopyWith<_TaskCategory> get copyWith => __$TaskCategoryCopyWithImpl<_TaskCategory>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskCategoryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.name, name) || other.name == name)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,name,position,createdAt,updatedAt);

@override
String toString() {
  return 'TaskCategory(id: $id, projectId: $projectId, name: $name, position: $position, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$TaskCategoryCopyWith<$Res> implements $TaskCategoryCopyWith<$Res> {
  factory _$TaskCategoryCopyWith(_TaskCategory value, $Res Function(_TaskCategory) _then) = __$TaskCategoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String projectId, String name, double position, String createdAt, String updatedAt
});




}
/// @nodoc
class __$TaskCategoryCopyWithImpl<$Res>
    implements _$TaskCategoryCopyWith<$Res> {
  __$TaskCategoryCopyWithImpl(this._self, this._then);

  final _TaskCategory _self;
  final $Res Function(_TaskCategory) _then;

/// Create a copy of TaskCategory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? projectId = null,Object? name = null,Object? position = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_TaskCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
