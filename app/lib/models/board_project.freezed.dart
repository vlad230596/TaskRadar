// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'board_project.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BoardProject {

 Project get project; List<Task> get tasks;
/// Create a copy of BoardProject
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BoardProjectCopyWith<BoardProject> get copyWith => _$BoardProjectCopyWithImpl<BoardProject>(this as BoardProject, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BoardProject&&(identical(other.project, project) || other.project == project)&&const DeepCollectionEquality().equals(other.tasks, tasks));
}


@override
int get hashCode => Object.hash(runtimeType,project,const DeepCollectionEquality().hash(tasks));

@override
String toString() {
  return 'BoardProject(project: $project, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class $BoardProjectCopyWith<$Res>  {
  factory $BoardProjectCopyWith(BoardProject value, $Res Function(BoardProject) _then) = _$BoardProjectCopyWithImpl;
@useResult
$Res call({
 Project project, List<Task> tasks
});


$ProjectCopyWith<$Res> get project;

}
/// @nodoc
class _$BoardProjectCopyWithImpl<$Res>
    implements $BoardProjectCopyWith<$Res> {
  _$BoardProjectCopyWithImpl(this._self, this._then);

  final BoardProject _self;
  final $Res Function(BoardProject) _then;

/// Create a copy of BoardProject
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? project = null,Object? tasks = null,}) {
  return _then(_self.copyWith(
project: null == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as Project,tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<Task>,
  ));
}
/// Create a copy of BoardProject
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectCopyWith<$Res> get project {
  
  return $ProjectCopyWith<$Res>(_self.project, (value) {
    return _then(_self.copyWith(project: value));
  });
}
}


/// Adds pattern-matching-related methods to [BoardProject].
extension BoardProjectPatterns on BoardProject {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BoardProject value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BoardProject() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BoardProject value)  $default,){
final _that = this;
switch (_that) {
case _BoardProject():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BoardProject value)?  $default,){
final _that = this;
switch (_that) {
case _BoardProject() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Project project,  List<Task> tasks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BoardProject() when $default != null:
return $default(_that.project,_that.tasks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Project project,  List<Task> tasks)  $default,) {final _that = this;
switch (_that) {
case _BoardProject():
return $default(_that.project,_that.tasks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Project project,  List<Task> tasks)?  $default,) {final _that = this;
switch (_that) {
case _BoardProject() when $default != null:
return $default(_that.project,_that.tasks);case _:
  return null;

}
}

}

/// @nodoc


class _BoardProject extends BoardProject {
  const _BoardProject({required this.project, required final  List<Task> tasks}): _tasks = tasks,super._();
  

@override final  Project project;
 final  List<Task> _tasks;
@override List<Task> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}


/// Create a copy of BoardProject
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BoardProjectCopyWith<_BoardProject> get copyWith => __$BoardProjectCopyWithImpl<_BoardProject>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BoardProject&&(identical(other.project, project) || other.project == project)&&const DeepCollectionEquality().equals(other._tasks, _tasks));
}


@override
int get hashCode => Object.hash(runtimeType,project,const DeepCollectionEquality().hash(_tasks));

@override
String toString() {
  return 'BoardProject(project: $project, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class _$BoardProjectCopyWith<$Res> implements $BoardProjectCopyWith<$Res> {
  factory _$BoardProjectCopyWith(_BoardProject value, $Res Function(_BoardProject) _then) = __$BoardProjectCopyWithImpl;
@override @useResult
$Res call({
 Project project, List<Task> tasks
});


@override $ProjectCopyWith<$Res> get project;

}
/// @nodoc
class __$BoardProjectCopyWithImpl<$Res>
    implements _$BoardProjectCopyWith<$Res> {
  __$BoardProjectCopyWithImpl(this._self, this._then);

  final _BoardProject _self;
  final $Res Function(_BoardProject) _then;

/// Create a copy of BoardProject
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? project = null,Object? tasks = null,}) {
  return _then(_BoardProject(
project: null == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as Project,tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<Task>,
  ));
}

/// Create a copy of BoardProject
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectCopyWith<$Res> get project {
  
  return $ProjectCopyWith<$Res>(_self.project, (value) {
    return _then(_self.copyWith(project: value));
  });
}
}

// dart format on
