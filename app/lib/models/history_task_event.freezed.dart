// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'history_task_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TaskEvent implements DiagnosticableTreeMixin {

 String get id; String get taskId; TaskEventKind get kind; TaskStatus? get fromStatus; TaskStatus? get toStatus; String get at;
/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskEventCopyWith<TaskEvent> get copyWith => _$TaskEventCopyWithImpl<TaskEvent>(this as TaskEvent, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'TaskEvent'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('taskId', taskId))..add(DiagnosticsProperty('kind', kind))..add(DiagnosticsProperty('fromStatus', fromStatus))..add(DiagnosticsProperty('toStatus', toStatus))..add(DiagnosticsProperty('at', at));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.fromStatus, fromStatus) || other.fromStatus == fromStatus)&&(identical(other.toStatus, toStatus) || other.toStatus == toStatus)&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode => Object.hash(runtimeType,id,taskId,kind,fromStatus,toStatus,at);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'TaskEvent(id: $id, taskId: $taskId, kind: $kind, fromStatus: $fromStatus, toStatus: $toStatus, at: $at)';
}


}

/// @nodoc
abstract mixin class $TaskEventCopyWith<$Res>  {
  factory $TaskEventCopyWith(TaskEvent value, $Res Function(TaskEvent) _then) = _$TaskEventCopyWithImpl;
@useResult
$Res call({
 String id, String taskId, TaskEventKind kind, TaskStatus? fromStatus, TaskStatus? toStatus, String at
});




}
/// @nodoc
class _$TaskEventCopyWithImpl<$Res>
    implements $TaskEventCopyWith<$Res> {
  _$TaskEventCopyWithImpl(this._self, this._then);

  final TaskEvent _self;
  final $Res Function(TaskEvent) _then;

/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? taskId = null,Object? kind = null,Object? fromStatus = freezed,Object? toStatus = freezed,Object? at = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as TaskEventKind,fromStatus: freezed == fromStatus ? _self.fromStatus : fromStatus // ignore: cast_nullable_to_non_nullable
as TaskStatus?,toStatus: freezed == toStatus ? _self.toStatus : toStatus // ignore: cast_nullable_to_non_nullable
as TaskStatus?,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskEvent].
extension TaskEventPatterns on TaskEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskEvent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskEvent value)  $default,){
final _that = this;
switch (_that) {
case _TaskEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskEvent value)?  $default,){
final _that = this;
switch (_that) {
case _TaskEvent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String taskId,  TaskEventKind kind,  TaskStatus? fromStatus,  TaskStatus? toStatus,  String at)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskEvent() when $default != null:
return $default(_that.id,_that.taskId,_that.kind,_that.fromStatus,_that.toStatus,_that.at);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String taskId,  TaskEventKind kind,  TaskStatus? fromStatus,  TaskStatus? toStatus,  String at)  $default,) {final _that = this;
switch (_that) {
case _TaskEvent():
return $default(_that.id,_that.taskId,_that.kind,_that.fromStatus,_that.toStatus,_that.at);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String taskId,  TaskEventKind kind,  TaskStatus? fromStatus,  TaskStatus? toStatus,  String at)?  $default,) {final _that = this;
switch (_that) {
case _TaskEvent() when $default != null:
return $default(_that.id,_that.taskId,_that.kind,_that.fromStatus,_that.toStatus,_that.at);case _:
  return null;

}
}

}

/// @nodoc


class _TaskEvent extends TaskEvent with DiagnosticableTreeMixin {
  const _TaskEvent({required this.id, required this.taskId, required this.kind, required this.fromStatus, required this.toStatus, required this.at}): super._();
  

@override final  String id;
@override final  String taskId;
@override final  TaskEventKind kind;
@override final  TaskStatus? fromStatus;
@override final  TaskStatus? toStatus;
@override final  String at;

/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskEventCopyWith<_TaskEvent> get copyWith => __$TaskEventCopyWithImpl<_TaskEvent>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'TaskEvent'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('taskId', taskId))..add(DiagnosticsProperty('kind', kind))..add(DiagnosticsProperty('fromStatus', fromStatus))..add(DiagnosticsProperty('toStatus', toStatus))..add(DiagnosticsProperty('at', at));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.fromStatus, fromStatus) || other.fromStatus == fromStatus)&&(identical(other.toStatus, toStatus) || other.toStatus == toStatus)&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode => Object.hash(runtimeType,id,taskId,kind,fromStatus,toStatus,at);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'TaskEvent(id: $id, taskId: $taskId, kind: $kind, fromStatus: $fromStatus, toStatus: $toStatus, at: $at)';
}


}

/// @nodoc
abstract mixin class _$TaskEventCopyWith<$Res> implements $TaskEventCopyWith<$Res> {
  factory _$TaskEventCopyWith(_TaskEvent value, $Res Function(_TaskEvent) _then) = __$TaskEventCopyWithImpl;
@override @useResult
$Res call({
 String id, String taskId, TaskEventKind kind, TaskStatus? fromStatus, TaskStatus? toStatus, String at
});




}
/// @nodoc
class __$TaskEventCopyWithImpl<$Res>
    implements _$TaskEventCopyWith<$Res> {
  __$TaskEventCopyWithImpl(this._self, this._then);

  final _TaskEvent _self;
  final $Res Function(_TaskEvent) _then;

/// Create a copy of TaskEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? taskId = null,Object? kind = null,Object? fromStatus = freezed,Object? toStatus = freezed,Object? at = null,}) {
  return _then(_TaskEvent(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as TaskEventKind,fromStatus: freezed == fromStatus ? _self.fromStatus : fromStatus // ignore: cast_nullable_to_non_nullable
as TaskStatus?,toStatus: freezed == toStatus ? _self.toStatus : toStatus // ignore: cast_nullable_to_non_nullable
as TaskStatus?,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
