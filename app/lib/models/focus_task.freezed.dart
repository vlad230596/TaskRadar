// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'focus_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FocusTask {

 String get id; String get projectId; String get title; String? get description; TaskStatus get status; double get position; String? get remindAt; String get createdAt; String get updatedAt;/// Когда задачу взяли в работу. Порядок набора — по нему, по возрастанию.
 String get focusedAt;/// Проект задачи: только id и имя — больше сервер здесь и не присылает.
 FocusProject get project;
/// Create a copy of FocusTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FocusTaskCopyWith<FocusTask> get copyWith => _$FocusTaskCopyWithImpl<FocusTask>(this as FocusTask, _$identity);

  /// Serializes this FocusTask to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FocusTask&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.remindAt, remindAt) || other.remindAt == remindAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.focusedAt, focusedAt) || other.focusedAt == focusedAt)&&(identical(other.project, project) || other.project == project));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,title,description,status,position,remindAt,createdAt,updatedAt,focusedAt,project);

@override
String toString() {
  return 'FocusTask(id: $id, projectId: $projectId, title: $title, description: $description, status: $status, position: $position, remindAt: $remindAt, createdAt: $createdAt, updatedAt: $updatedAt, focusedAt: $focusedAt, project: $project)';
}


}

/// @nodoc
abstract mixin class $FocusTaskCopyWith<$Res>  {
  factory $FocusTaskCopyWith(FocusTask value, $Res Function(FocusTask) _then) = _$FocusTaskCopyWithImpl;
@useResult
$Res call({
 String id, String projectId, String title, String? description, TaskStatus status, double position, String? remindAt, String createdAt, String updatedAt, String focusedAt, FocusProject project
});


$FocusProjectCopyWith<$Res> get project;

}
/// @nodoc
class _$FocusTaskCopyWithImpl<$Res>
    implements $FocusTaskCopyWith<$Res> {
  _$FocusTaskCopyWithImpl(this._self, this._then);

  final FocusTask _self;
  final $Res Function(FocusTask) _then;

/// Create a copy of FocusTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? description = freezed,Object? status = null,Object? position = null,Object? remindAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? focusedAt = null,Object? project = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,remindAt: freezed == remindAt ? _self.remindAt : remindAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,focusedAt: null == focusedAt ? _self.focusedAt : focusedAt // ignore: cast_nullable_to_non_nullable
as String,project: null == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as FocusProject,
  ));
}
/// Create a copy of FocusTask
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FocusProjectCopyWith<$Res> get project {
  
  return $FocusProjectCopyWith<$Res>(_self.project, (value) {
    return _then(_self.copyWith(project: value));
  });
}
}


/// Adds pattern-matching-related methods to [FocusTask].
extension FocusTaskPatterns on FocusTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FocusTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FocusTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FocusTask value)  $default,){
final _that = this;
switch (_that) {
case _FocusTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FocusTask value)?  $default,){
final _that = this;
switch (_that) {
case _FocusTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  String? description,  TaskStatus status,  double position,  String? remindAt,  String createdAt,  String updatedAt,  String focusedAt,  FocusProject project)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FocusTask() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.description,_that.status,_that.position,_that.remindAt,_that.createdAt,_that.updatedAt,_that.focusedAt,_that.project);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  String? description,  TaskStatus status,  double position,  String? remindAt,  String createdAt,  String updatedAt,  String focusedAt,  FocusProject project)  $default,) {final _that = this;
switch (_that) {
case _FocusTask():
return $default(_that.id,_that.projectId,_that.title,_that.description,_that.status,_that.position,_that.remindAt,_that.createdAt,_that.updatedAt,_that.focusedAt,_that.project);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String projectId,  String title,  String? description,  TaskStatus status,  double position,  String? remindAt,  String createdAt,  String updatedAt,  String focusedAt,  FocusProject project)?  $default,) {final _that = this;
switch (_that) {
case _FocusTask() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.description,_that.status,_that.position,_that.remindAt,_that.createdAt,_that.updatedAt,_that.focusedAt,_that.project);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FocusTask implements FocusTask {
  const _FocusTask({required this.id, required this.projectId, required this.title, required this.description, required this.status, required this.position, required this.remindAt, required this.createdAt, required this.updatedAt, required this.focusedAt, required this.project});
  factory _FocusTask.fromJson(Map<String, dynamic> json) => _$FocusTaskFromJson(json);

@override final  String id;
@override final  String projectId;
@override final  String title;
@override final  String? description;
@override final  TaskStatus status;
@override final  double position;
@override final  String? remindAt;
@override final  String createdAt;
@override final  String updatedAt;
/// Когда задачу взяли в работу. Порядок набора — по нему, по возрастанию.
@override final  String focusedAt;
/// Проект задачи: только id и имя — больше сервер здесь и не присылает.
@override final  FocusProject project;

/// Create a copy of FocusTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FocusTaskCopyWith<_FocusTask> get copyWith => __$FocusTaskCopyWithImpl<_FocusTask>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FocusTaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FocusTask&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.remindAt, remindAt) || other.remindAt == remindAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.focusedAt, focusedAt) || other.focusedAt == focusedAt)&&(identical(other.project, project) || other.project == project));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,title,description,status,position,remindAt,createdAt,updatedAt,focusedAt,project);

@override
String toString() {
  return 'FocusTask(id: $id, projectId: $projectId, title: $title, description: $description, status: $status, position: $position, remindAt: $remindAt, createdAt: $createdAt, updatedAt: $updatedAt, focusedAt: $focusedAt, project: $project)';
}


}

/// @nodoc
abstract mixin class _$FocusTaskCopyWith<$Res> implements $FocusTaskCopyWith<$Res> {
  factory _$FocusTaskCopyWith(_FocusTask value, $Res Function(_FocusTask) _then) = __$FocusTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String projectId, String title, String? description, TaskStatus status, double position, String? remindAt, String createdAt, String updatedAt, String focusedAt, FocusProject project
});


@override $FocusProjectCopyWith<$Res> get project;

}
/// @nodoc
class __$FocusTaskCopyWithImpl<$Res>
    implements _$FocusTaskCopyWith<$Res> {
  __$FocusTaskCopyWithImpl(this._self, this._then);

  final _FocusTask _self;
  final $Res Function(_FocusTask) _then;

/// Create a copy of FocusTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? description = freezed,Object? status = null,Object? position = null,Object? remindAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? focusedAt = null,Object? project = null,}) {
  return _then(_FocusTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,remindAt: freezed == remindAt ? _self.remindAt : remindAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,focusedAt: null == focusedAt ? _self.focusedAt : focusedAt // ignore: cast_nullable_to_non_nullable
as String,project: null == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as FocusProject,
  ));
}

/// Create a copy of FocusTask
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FocusProjectCopyWith<$Res> get project {
  
  return $FocusProjectCopyWith<$Res>(_self.project, (value) {
    return _then(_self.copyWith(project: value));
  });
}
}


/// @nodoc
mixin _$FocusProject {

 String get id; String get name;
/// Create a copy of FocusProject
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FocusProjectCopyWith<FocusProject> get copyWith => _$FocusProjectCopyWithImpl<FocusProject>(this as FocusProject, _$identity);

  /// Serializes this FocusProject to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FocusProject&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name);

@override
String toString() {
  return 'FocusProject(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class $FocusProjectCopyWith<$Res>  {
  factory $FocusProjectCopyWith(FocusProject value, $Res Function(FocusProject) _then) = _$FocusProjectCopyWithImpl;
@useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class _$FocusProjectCopyWithImpl<$Res>
    implements $FocusProjectCopyWith<$Res> {
  _$FocusProjectCopyWithImpl(this._self, this._then);

  final FocusProject _self;
  final $Res Function(FocusProject) _then;

/// Create a copy of FocusProject
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FocusProject].
extension FocusProjectPatterns on FocusProject {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FocusProject value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FocusProject() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FocusProject value)  $default,){
final _that = this;
switch (_that) {
case _FocusProject():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FocusProject value)?  $default,){
final _that = this;
switch (_that) {
case _FocusProject() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FocusProject() when $default != null:
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name)  $default,) {final _that = this;
switch (_that) {
case _FocusProject():
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name)?  $default,) {final _that = this;
switch (_that) {
case _FocusProject() when $default != null:
return $default(_that.id,_that.name);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FocusProject implements FocusProject {
  const _FocusProject({required this.id, required this.name});
  factory _FocusProject.fromJson(Map<String, dynamic> json) => _$FocusProjectFromJson(json);

@override final  String id;
@override final  String name;

/// Create a copy of FocusProject
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FocusProjectCopyWith<_FocusProject> get copyWith => __$FocusProjectCopyWithImpl<_FocusProject>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FocusProjectToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FocusProject&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name);

@override
String toString() {
  return 'FocusProject(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class _$FocusProjectCopyWith<$Res> implements $FocusProjectCopyWith<$Res> {
  factory _$FocusProjectCopyWith(_FocusProject value, $Res Function(_FocusProject) _then) = __$FocusProjectCopyWithImpl;
@override @useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class __$FocusProjectCopyWithImpl<$Res>
    implements _$FocusProjectCopyWith<$Res> {
  __$FocusProjectCopyWithImpl(this._self, this._then);

  final _FocusProject _self;
  final $Res Function(_FocusProject) _then;

/// Create a copy of FocusProject
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,}) {
  return _then(_FocusProject(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
