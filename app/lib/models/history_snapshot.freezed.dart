// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'history_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HistoryDay implements DiagnosticableTreeMixin {

 String get date; int get count;
/// Create a copy of HistoryDay
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistoryDayCopyWith<HistoryDay> get copyWith => _$HistoryDayCopyWithImpl<HistoryDay>(this as HistoryDay, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'HistoryDay'))
    ..add(DiagnosticsProperty('date', date))..add(DiagnosticsProperty('count', count));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HistoryDay&&(identical(other.date, date) || other.date == date)&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode => Object.hash(runtimeType,date,count);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'HistoryDay(date: $date, count: $count)';
}


}

/// @nodoc
abstract mixin class $HistoryDayCopyWith<$Res>  {
  factory $HistoryDayCopyWith(HistoryDay value, $Res Function(HistoryDay) _then) = _$HistoryDayCopyWithImpl;
@useResult
$Res call({
 String date, int count
});




}
/// @nodoc
class _$HistoryDayCopyWithImpl<$Res>
    implements $HistoryDayCopyWith<$Res> {
  _$HistoryDayCopyWithImpl(this._self, this._then);

  final HistoryDay _self;
  final $Res Function(HistoryDay) _then;

/// Create a copy of HistoryDay
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? date = null,Object? count = null,}) {
  return _then(_self.copyWith(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [HistoryDay].
extension HistoryDayPatterns on HistoryDay {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HistoryDay value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HistoryDay() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HistoryDay value)  $default,){
final _that = this;
switch (_that) {
case _HistoryDay():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HistoryDay value)?  $default,){
final _that = this;
switch (_that) {
case _HistoryDay() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String date,  int count)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HistoryDay() when $default != null:
return $default(_that.date,_that.count);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String date,  int count)  $default,) {final _that = this;
switch (_that) {
case _HistoryDay():
return $default(_that.date,_that.count);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String date,  int count)?  $default,) {final _that = this;
switch (_that) {
case _HistoryDay() when $default != null:
return $default(_that.date,_that.count);case _:
  return null;

}
}

}

/// @nodoc


class _HistoryDay extends HistoryDay with DiagnosticableTreeMixin {
  const _HistoryDay({required this.date, required this.count}): super._();
  

@override final  String date;
@override final  int count;

/// Create a copy of HistoryDay
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistoryDayCopyWith<_HistoryDay> get copyWith => __$HistoryDayCopyWithImpl<_HistoryDay>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'HistoryDay'))
    ..add(DiagnosticsProperty('date', date))..add(DiagnosticsProperty('count', count));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HistoryDay&&(identical(other.date, date) || other.date == date)&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode => Object.hash(runtimeType,date,count);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'HistoryDay(date: $date, count: $count)';
}


}

/// @nodoc
abstract mixin class _$HistoryDayCopyWith<$Res> implements $HistoryDayCopyWith<$Res> {
  factory _$HistoryDayCopyWith(_HistoryDay value, $Res Function(_HistoryDay) _then) = __$HistoryDayCopyWithImpl;
@override @useResult
$Res call({
 String date, int count
});




}
/// @nodoc
class __$HistoryDayCopyWithImpl<$Res>
    implements _$HistoryDayCopyWith<$Res> {
  __$HistoryDayCopyWithImpl(this._self, this._then);

  final _HistoryDay _self;
  final $Res Function(_HistoryDay) _then;

/// Create a copy of HistoryDay
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? date = null,Object? count = null,}) {
  return _then(_HistoryDay(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$StatusSpans implements DiagnosticableTreeMixin {

 int get pendingMs; int get doneMs; int get blockedMs;
/// Create a copy of StatusSpans
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatusSpansCopyWith<StatusSpans> get copyWith => _$StatusSpansCopyWithImpl<StatusSpans>(this as StatusSpans, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'StatusSpans'))
    ..add(DiagnosticsProperty('pendingMs', pendingMs))..add(DiagnosticsProperty('doneMs', doneMs))..add(DiagnosticsProperty('blockedMs', blockedMs));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatusSpans&&(identical(other.pendingMs, pendingMs) || other.pendingMs == pendingMs)&&(identical(other.doneMs, doneMs) || other.doneMs == doneMs)&&(identical(other.blockedMs, blockedMs) || other.blockedMs == blockedMs));
}


@override
int get hashCode => Object.hash(runtimeType,pendingMs,doneMs,blockedMs);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'StatusSpans(pendingMs: $pendingMs, doneMs: $doneMs, blockedMs: $blockedMs)';
}


}

/// @nodoc
abstract mixin class $StatusSpansCopyWith<$Res>  {
  factory $StatusSpansCopyWith(StatusSpans value, $Res Function(StatusSpans) _then) = _$StatusSpansCopyWithImpl;
@useResult
$Res call({
 int pendingMs, int doneMs, int blockedMs
});




}
/// @nodoc
class _$StatusSpansCopyWithImpl<$Res>
    implements $StatusSpansCopyWith<$Res> {
  _$StatusSpansCopyWithImpl(this._self, this._then);

  final StatusSpans _self;
  final $Res Function(StatusSpans) _then;

/// Create a copy of StatusSpans
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pendingMs = null,Object? doneMs = null,Object? blockedMs = null,}) {
  return _then(_self.copyWith(
pendingMs: null == pendingMs ? _self.pendingMs : pendingMs // ignore: cast_nullable_to_non_nullable
as int,doneMs: null == doneMs ? _self.doneMs : doneMs // ignore: cast_nullable_to_non_nullable
as int,blockedMs: null == blockedMs ? _self.blockedMs : blockedMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [StatusSpans].
extension StatusSpansPatterns on StatusSpans {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatusSpans value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatusSpans() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatusSpans value)  $default,){
final _that = this;
switch (_that) {
case _StatusSpans():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatusSpans value)?  $default,){
final _that = this;
switch (_that) {
case _StatusSpans() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int pendingMs,  int doneMs,  int blockedMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatusSpans() when $default != null:
return $default(_that.pendingMs,_that.doneMs,_that.blockedMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int pendingMs,  int doneMs,  int blockedMs)  $default,) {final _that = this;
switch (_that) {
case _StatusSpans():
return $default(_that.pendingMs,_that.doneMs,_that.blockedMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int pendingMs,  int doneMs,  int blockedMs)?  $default,) {final _that = this;
switch (_that) {
case _StatusSpans() when $default != null:
return $default(_that.pendingMs,_that.doneMs,_that.blockedMs);case _:
  return null;

}
}

}

/// @nodoc


class _StatusSpans extends StatusSpans with DiagnosticableTreeMixin {
  const _StatusSpans({required this.pendingMs, required this.doneMs, required this.blockedMs}): super._();
  

@override final  int pendingMs;
@override final  int doneMs;
@override final  int blockedMs;

/// Create a copy of StatusSpans
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatusSpansCopyWith<_StatusSpans> get copyWith => __$StatusSpansCopyWithImpl<_StatusSpans>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'StatusSpans'))
    ..add(DiagnosticsProperty('pendingMs', pendingMs))..add(DiagnosticsProperty('doneMs', doneMs))..add(DiagnosticsProperty('blockedMs', blockedMs));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatusSpans&&(identical(other.pendingMs, pendingMs) || other.pendingMs == pendingMs)&&(identical(other.doneMs, doneMs) || other.doneMs == doneMs)&&(identical(other.blockedMs, blockedMs) || other.blockedMs == blockedMs));
}


@override
int get hashCode => Object.hash(runtimeType,pendingMs,doneMs,blockedMs);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'StatusSpans(pendingMs: $pendingMs, doneMs: $doneMs, blockedMs: $blockedMs)';
}


}

/// @nodoc
abstract mixin class _$StatusSpansCopyWith<$Res> implements $StatusSpansCopyWith<$Res> {
  factory _$StatusSpansCopyWith(_StatusSpans value, $Res Function(_StatusSpans) _then) = __$StatusSpansCopyWithImpl;
@override @useResult
$Res call({
 int pendingMs, int doneMs, int blockedMs
});




}
/// @nodoc
class __$StatusSpansCopyWithImpl<$Res>
    implements _$StatusSpansCopyWith<$Res> {
  __$StatusSpansCopyWithImpl(this._self, this._then);

  final _StatusSpans _self;
  final $Res Function(_StatusSpans) _then;

/// Create a copy of StatusSpans
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingMs = null,Object? doneMs = null,Object? blockedMs = null,}) {
  return _then(_StatusSpans(
pendingMs: null == pendingMs ? _self.pendingMs : pendingMs // ignore: cast_nullable_to_non_nullable
as int,doneMs: null == doneMs ? _self.doneMs : doneMs // ignore: cast_nullable_to_non_nullable
as int,blockedMs: null == blockedMs ? _self.blockedMs : blockedMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$StaleTask implements DiagnosticableTreeMixin {

 String get id; String get title; TaskStatus get status; String get projectId; String get projectName; String get createdAt;/// Когда задачу взяли в набор, или null. См. [inWorkMs].
 String? get focusedAt;/// Сколько задача живёт незакрытой. По нему сервер и сортирует.
 int get ageMs;/// Когда начался текущий статус.
 String get currentSince;/// Сколько текущий статус держится.
 int get currentForMs;/// Куда ушёл возраст. Полоска под строкой — это он.
 StatusSpans get byStatus;
/// Create a copy of StaleTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaleTaskCopyWith<StaleTask> get copyWith => _$StaleTaskCopyWithImpl<StaleTask>(this as StaleTask, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'StaleTask'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('projectId', projectId))..add(DiagnosticsProperty('projectName', projectName))..add(DiagnosticsProperty('createdAt', createdAt))..add(DiagnosticsProperty('focusedAt', focusedAt))..add(DiagnosticsProperty('ageMs', ageMs))..add(DiagnosticsProperty('currentSince', currentSince))..add(DiagnosticsProperty('currentForMs', currentForMs))..add(DiagnosticsProperty('byStatus', byStatus));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StaleTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.projectName, projectName) || other.projectName == projectName)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.focusedAt, focusedAt) || other.focusedAt == focusedAt)&&(identical(other.ageMs, ageMs) || other.ageMs == ageMs)&&(identical(other.currentSince, currentSince) || other.currentSince == currentSince)&&(identical(other.currentForMs, currentForMs) || other.currentForMs == currentForMs)&&(identical(other.byStatus, byStatus) || other.byStatus == byStatus));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,status,projectId,projectName,createdAt,focusedAt,ageMs,currentSince,currentForMs,byStatus);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'StaleTask(id: $id, title: $title, status: $status, projectId: $projectId, projectName: $projectName, createdAt: $createdAt, focusedAt: $focusedAt, ageMs: $ageMs, currentSince: $currentSince, currentForMs: $currentForMs, byStatus: $byStatus)';
}


}

/// @nodoc
abstract mixin class $StaleTaskCopyWith<$Res>  {
  factory $StaleTaskCopyWith(StaleTask value, $Res Function(StaleTask) _then) = _$StaleTaskCopyWithImpl;
@useResult
$Res call({
 String id, String title, TaskStatus status, String projectId, String projectName, String createdAt, String? focusedAt, int ageMs, String currentSince, int currentForMs, StatusSpans byStatus
});


$StatusSpansCopyWith<$Res> get byStatus;

}
/// @nodoc
class _$StaleTaskCopyWithImpl<$Res>
    implements $StaleTaskCopyWith<$Res> {
  _$StaleTaskCopyWithImpl(this._self, this._then);

  final StaleTask _self;
  final $Res Function(StaleTask) _then;

/// Create a copy of StaleTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? status = null,Object? projectId = null,Object? projectName = null,Object? createdAt = null,Object? focusedAt = freezed,Object? ageMs = null,Object? currentSince = null,Object? currentForMs = null,Object? byStatus = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,projectName: null == projectName ? _self.projectName : projectName // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,focusedAt: freezed == focusedAt ? _self.focusedAt : focusedAt // ignore: cast_nullable_to_non_nullable
as String?,ageMs: null == ageMs ? _self.ageMs : ageMs // ignore: cast_nullable_to_non_nullable
as int,currentSince: null == currentSince ? _self.currentSince : currentSince // ignore: cast_nullable_to_non_nullable
as String,currentForMs: null == currentForMs ? _self.currentForMs : currentForMs // ignore: cast_nullable_to_non_nullable
as int,byStatus: null == byStatus ? _self.byStatus : byStatus // ignore: cast_nullable_to_non_nullable
as StatusSpans,
  ));
}
/// Create a copy of StaleTask
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatusSpansCopyWith<$Res> get byStatus {
  
  return $StatusSpansCopyWith<$Res>(_self.byStatus, (value) {
    return _then(_self.copyWith(byStatus: value));
  });
}
}


/// Adds pattern-matching-related methods to [StaleTask].
extension StaleTaskPatterns on StaleTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StaleTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StaleTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StaleTask value)  $default,){
final _that = this;
switch (_that) {
case _StaleTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StaleTask value)?  $default,){
final _that = this;
switch (_that) {
case _StaleTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  TaskStatus status,  String projectId,  String projectName,  String createdAt,  String? focusedAt,  int ageMs,  String currentSince,  int currentForMs,  StatusSpans byStatus)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StaleTask() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.projectId,_that.projectName,_that.createdAt,_that.focusedAt,_that.ageMs,_that.currentSince,_that.currentForMs,_that.byStatus);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  TaskStatus status,  String projectId,  String projectName,  String createdAt,  String? focusedAt,  int ageMs,  String currentSince,  int currentForMs,  StatusSpans byStatus)  $default,) {final _that = this;
switch (_that) {
case _StaleTask():
return $default(_that.id,_that.title,_that.status,_that.projectId,_that.projectName,_that.createdAt,_that.focusedAt,_that.ageMs,_that.currentSince,_that.currentForMs,_that.byStatus);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  TaskStatus status,  String projectId,  String projectName,  String createdAt,  String? focusedAt,  int ageMs,  String currentSince,  int currentForMs,  StatusSpans byStatus)?  $default,) {final _that = this;
switch (_that) {
case _StaleTask() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.projectId,_that.projectName,_that.createdAt,_that.focusedAt,_that.ageMs,_that.currentSince,_that.currentForMs,_that.byStatus);case _:
  return null;

}
}

}

/// @nodoc


class _StaleTask extends StaleTask with DiagnosticableTreeMixin {
  const _StaleTask({required this.id, required this.title, required this.status, required this.projectId, required this.projectName, required this.createdAt, required this.focusedAt, required this.ageMs, required this.currentSince, required this.currentForMs, required this.byStatus}): super._();
  

@override final  String id;
@override final  String title;
@override final  TaskStatus status;
@override final  String projectId;
@override final  String projectName;
@override final  String createdAt;
/// Когда задачу взяли в набор, или null. См. [inWorkMs].
@override final  String? focusedAt;
/// Сколько задача живёт незакрытой. По нему сервер и сортирует.
@override final  int ageMs;
/// Когда начался текущий статус.
@override final  String currentSince;
/// Сколько текущий статус держится.
@override final  int currentForMs;
/// Куда ушёл возраст. Полоска под строкой — это он.
@override final  StatusSpans byStatus;

/// Create a copy of StaleTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StaleTaskCopyWith<_StaleTask> get copyWith => __$StaleTaskCopyWithImpl<_StaleTask>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'StaleTask'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('projectId', projectId))..add(DiagnosticsProperty('projectName', projectName))..add(DiagnosticsProperty('createdAt', createdAt))..add(DiagnosticsProperty('focusedAt', focusedAt))..add(DiagnosticsProperty('ageMs', ageMs))..add(DiagnosticsProperty('currentSince', currentSince))..add(DiagnosticsProperty('currentForMs', currentForMs))..add(DiagnosticsProperty('byStatus', byStatus));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StaleTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.projectName, projectName) || other.projectName == projectName)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.focusedAt, focusedAt) || other.focusedAt == focusedAt)&&(identical(other.ageMs, ageMs) || other.ageMs == ageMs)&&(identical(other.currentSince, currentSince) || other.currentSince == currentSince)&&(identical(other.currentForMs, currentForMs) || other.currentForMs == currentForMs)&&(identical(other.byStatus, byStatus) || other.byStatus == byStatus));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,status,projectId,projectName,createdAt,focusedAt,ageMs,currentSince,currentForMs,byStatus);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'StaleTask(id: $id, title: $title, status: $status, projectId: $projectId, projectName: $projectName, createdAt: $createdAt, focusedAt: $focusedAt, ageMs: $ageMs, currentSince: $currentSince, currentForMs: $currentForMs, byStatus: $byStatus)';
}


}

/// @nodoc
abstract mixin class _$StaleTaskCopyWith<$Res> implements $StaleTaskCopyWith<$Res> {
  factory _$StaleTaskCopyWith(_StaleTask value, $Res Function(_StaleTask) _then) = __$StaleTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, TaskStatus status, String projectId, String projectName, String createdAt, String? focusedAt, int ageMs, String currentSince, int currentForMs, StatusSpans byStatus
});


@override $StatusSpansCopyWith<$Res> get byStatus;

}
/// @nodoc
class __$StaleTaskCopyWithImpl<$Res>
    implements _$StaleTaskCopyWith<$Res> {
  __$StaleTaskCopyWithImpl(this._self, this._then);

  final _StaleTask _self;
  final $Res Function(_StaleTask) _then;

/// Create a copy of StaleTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? status = null,Object? projectId = null,Object? projectName = null,Object? createdAt = null,Object? focusedAt = freezed,Object? ageMs = null,Object? currentSince = null,Object? currentForMs = null,Object? byStatus = null,}) {
  return _then(_StaleTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,projectName: null == projectName ? _self.projectName : projectName // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,focusedAt: freezed == focusedAt ? _self.focusedAt : focusedAt // ignore: cast_nullable_to_non_nullable
as String?,ageMs: null == ageMs ? _self.ageMs : ageMs // ignore: cast_nullable_to_non_nullable
as int,currentSince: null == currentSince ? _self.currentSince : currentSince // ignore: cast_nullable_to_non_nullable
as String,currentForMs: null == currentForMs ? _self.currentForMs : currentForMs // ignore: cast_nullable_to_non_nullable
as int,byStatus: null == byStatus ? _self.byStatus : byStatus // ignore: cast_nullable_to_non_nullable
as StatusSpans,
  ));
}

/// Create a copy of StaleTask
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StatusSpansCopyWith<$Res> get byStatus {
  
  return $StatusSpansCopyWith<$Res>(_self.byStatus, (value) {
    return _then(_self.copyWith(byStatus: value));
  });
}
}

/// @nodoc
mixin _$ProjectMovement implements DiagnosticableTreeMixin {

 String get projectId; String get name; int get opened; int get closed;
/// Create a copy of ProjectMovement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectMovementCopyWith<ProjectMovement> get copyWith => _$ProjectMovementCopyWithImpl<ProjectMovement>(this as ProjectMovement, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ProjectMovement'))
    ..add(DiagnosticsProperty('projectId', projectId))..add(DiagnosticsProperty('name', name))..add(DiagnosticsProperty('opened', opened))..add(DiagnosticsProperty('closed', closed));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectMovement&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.name, name) || other.name == name)&&(identical(other.opened, opened) || other.opened == opened)&&(identical(other.closed, closed) || other.closed == closed));
}


@override
int get hashCode => Object.hash(runtimeType,projectId,name,opened,closed);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ProjectMovement(projectId: $projectId, name: $name, opened: $opened, closed: $closed)';
}


}

/// @nodoc
abstract mixin class $ProjectMovementCopyWith<$Res>  {
  factory $ProjectMovementCopyWith(ProjectMovement value, $Res Function(ProjectMovement) _then) = _$ProjectMovementCopyWithImpl;
@useResult
$Res call({
 String projectId, String name, int opened, int closed
});




}
/// @nodoc
class _$ProjectMovementCopyWithImpl<$Res>
    implements $ProjectMovementCopyWith<$Res> {
  _$ProjectMovementCopyWithImpl(this._self, this._then);

  final ProjectMovement _self;
  final $Res Function(ProjectMovement) _then;

/// Create a copy of ProjectMovement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? name = null,Object? opened = null,Object? closed = null,}) {
  return _then(_self.copyWith(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,opened: null == opened ? _self.opened : opened // ignore: cast_nullable_to_non_nullable
as int,closed: null == closed ? _self.closed : closed // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProjectMovement].
extension ProjectMovementPatterns on ProjectMovement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectMovement value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectMovement() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectMovement value)  $default,){
final _that = this;
switch (_that) {
case _ProjectMovement():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectMovement value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectMovement() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  String name,  int opened,  int closed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectMovement() when $default != null:
return $default(_that.projectId,_that.name,_that.opened,_that.closed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  String name,  int opened,  int closed)  $default,) {final _that = this;
switch (_that) {
case _ProjectMovement():
return $default(_that.projectId,_that.name,_that.opened,_that.closed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  String name,  int opened,  int closed)?  $default,) {final _that = this;
switch (_that) {
case _ProjectMovement() when $default != null:
return $default(_that.projectId,_that.name,_that.opened,_that.closed);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectMovement extends ProjectMovement with DiagnosticableTreeMixin {
  const _ProjectMovement({required this.projectId, required this.name, required this.opened, required this.closed}): super._();
  

@override final  String projectId;
@override final  String name;
@override final  int opened;
@override final  int closed;

/// Create a copy of ProjectMovement
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectMovementCopyWith<_ProjectMovement> get copyWith => __$ProjectMovementCopyWithImpl<_ProjectMovement>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ProjectMovement'))
    ..add(DiagnosticsProperty('projectId', projectId))..add(DiagnosticsProperty('name', name))..add(DiagnosticsProperty('opened', opened))..add(DiagnosticsProperty('closed', closed));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectMovement&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.name, name) || other.name == name)&&(identical(other.opened, opened) || other.opened == opened)&&(identical(other.closed, closed) || other.closed == closed));
}


@override
int get hashCode => Object.hash(runtimeType,projectId,name,opened,closed);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ProjectMovement(projectId: $projectId, name: $name, opened: $opened, closed: $closed)';
}


}

/// @nodoc
abstract mixin class _$ProjectMovementCopyWith<$Res> implements $ProjectMovementCopyWith<$Res> {
  factory _$ProjectMovementCopyWith(_ProjectMovement value, $Res Function(_ProjectMovement) _then) = __$ProjectMovementCopyWithImpl;
@override @useResult
$Res call({
 String projectId, String name, int opened, int closed
});




}
/// @nodoc
class __$ProjectMovementCopyWithImpl<$Res>
    implements _$ProjectMovementCopyWith<$Res> {
  __$ProjectMovementCopyWithImpl(this._self, this._then);

  final _ProjectMovement _self;
  final $Res Function(_ProjectMovement) _then;

/// Create a copy of ProjectMovement
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? name = null,Object? opened = null,Object? closed = null,}) {
  return _then(_ProjectMovement(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,opened: null == opened ? _self.opened : opened // ignore: cast_nullable_to_non_nullable
as int,closed: null == closed ? _self.closed : closed // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$HistorySnapshot implements DiagnosticableTreeMixin {

 HistoryRange get range;/// Начало окна, или null для «всё время» — которое не дата, и сервер
/// специально не делает вид, что дата.
 String? get from; String get to;/// По записи на день, с нулями, — для 7d/30d. Для «всё время» только те
/// дни, в которые что-то закрылось.
 List<HistoryDay> get closedByDay; int get closedTotal; List<ProjectMovement> get projects; List<StaleTask> get stale;
/// Create a copy of HistorySnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistorySnapshotCopyWith<HistorySnapshot> get copyWith => _$HistorySnapshotCopyWithImpl<HistorySnapshot>(this as HistorySnapshot, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'HistorySnapshot'))
    ..add(DiagnosticsProperty('range', range))..add(DiagnosticsProperty('from', from))..add(DiagnosticsProperty('to', to))..add(DiagnosticsProperty('closedByDay', closedByDay))..add(DiagnosticsProperty('closedTotal', closedTotal))..add(DiagnosticsProperty('projects', projects))..add(DiagnosticsProperty('stale', stale));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HistorySnapshot&&(identical(other.range, range) || other.range == range)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&const DeepCollectionEquality().equals(other.closedByDay, closedByDay)&&(identical(other.closedTotal, closedTotal) || other.closedTotal == closedTotal)&&const DeepCollectionEquality().equals(other.projects, projects)&&const DeepCollectionEquality().equals(other.stale, stale));
}


@override
int get hashCode => Object.hash(runtimeType,range,from,to,const DeepCollectionEquality().hash(closedByDay),closedTotal,const DeepCollectionEquality().hash(projects),const DeepCollectionEquality().hash(stale));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'HistorySnapshot(range: $range, from: $from, to: $to, closedByDay: $closedByDay, closedTotal: $closedTotal, projects: $projects, stale: $stale)';
}


}

/// @nodoc
abstract mixin class $HistorySnapshotCopyWith<$Res>  {
  factory $HistorySnapshotCopyWith(HistorySnapshot value, $Res Function(HistorySnapshot) _then) = _$HistorySnapshotCopyWithImpl;
@useResult
$Res call({
 HistoryRange range, String? from, String to, List<HistoryDay> closedByDay, int closedTotal, List<ProjectMovement> projects, List<StaleTask> stale
});




}
/// @nodoc
class _$HistorySnapshotCopyWithImpl<$Res>
    implements $HistorySnapshotCopyWith<$Res> {
  _$HistorySnapshotCopyWithImpl(this._self, this._then);

  final HistorySnapshot _self;
  final $Res Function(HistorySnapshot) _then;

/// Create a copy of HistorySnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? range = null,Object? from = freezed,Object? to = null,Object? closedByDay = null,Object? closedTotal = null,Object? projects = null,Object? stale = null,}) {
  return _then(_self.copyWith(
range: null == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as HistoryRange,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,closedByDay: null == closedByDay ? _self.closedByDay : closedByDay // ignore: cast_nullable_to_non_nullable
as List<HistoryDay>,closedTotal: null == closedTotal ? _self.closedTotal : closedTotal // ignore: cast_nullable_to_non_nullable
as int,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as List<ProjectMovement>,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as List<StaleTask>,
  ));
}

}


/// Adds pattern-matching-related methods to [HistorySnapshot].
extension HistorySnapshotPatterns on HistorySnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HistorySnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HistorySnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HistorySnapshot value)  $default,){
final _that = this;
switch (_that) {
case _HistorySnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HistorySnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _HistorySnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( HistoryRange range,  String? from,  String to,  List<HistoryDay> closedByDay,  int closedTotal,  List<ProjectMovement> projects,  List<StaleTask> stale)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HistorySnapshot() when $default != null:
return $default(_that.range,_that.from,_that.to,_that.closedByDay,_that.closedTotal,_that.projects,_that.stale);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( HistoryRange range,  String? from,  String to,  List<HistoryDay> closedByDay,  int closedTotal,  List<ProjectMovement> projects,  List<StaleTask> stale)  $default,) {final _that = this;
switch (_that) {
case _HistorySnapshot():
return $default(_that.range,_that.from,_that.to,_that.closedByDay,_that.closedTotal,_that.projects,_that.stale);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( HistoryRange range,  String? from,  String to,  List<HistoryDay> closedByDay,  int closedTotal,  List<ProjectMovement> projects,  List<StaleTask> stale)?  $default,) {final _that = this;
switch (_that) {
case _HistorySnapshot() when $default != null:
return $default(_that.range,_that.from,_that.to,_that.closedByDay,_that.closedTotal,_that.projects,_that.stale);case _:
  return null;

}
}

}

/// @nodoc


class _HistorySnapshot extends HistorySnapshot with DiagnosticableTreeMixin {
  const _HistorySnapshot({required this.range, required this.from, required this.to, required final  List<HistoryDay> closedByDay, required this.closedTotal, required final  List<ProjectMovement> projects, required final  List<StaleTask> stale}): _closedByDay = closedByDay,_projects = projects,_stale = stale,super._();
  

@override final  HistoryRange range;
/// Начало окна, или null для «всё время» — которое не дата, и сервер
/// специально не делает вид, что дата.
@override final  String? from;
@override final  String to;
/// По записи на день, с нулями, — для 7d/30d. Для «всё время» только те
/// дни, в которые что-то закрылось.
 final  List<HistoryDay> _closedByDay;
/// По записи на день, с нулями, — для 7d/30d. Для «всё время» только те
/// дни, в которые что-то закрылось.
@override List<HistoryDay> get closedByDay {
  if (_closedByDay is EqualUnmodifiableListView) return _closedByDay;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_closedByDay);
}

@override final  int closedTotal;
 final  List<ProjectMovement> _projects;
@override List<ProjectMovement> get projects {
  if (_projects is EqualUnmodifiableListView) return _projects;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_projects);
}

 final  List<StaleTask> _stale;
@override List<StaleTask> get stale {
  if (_stale is EqualUnmodifiableListView) return _stale;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_stale);
}


/// Create a copy of HistorySnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistorySnapshotCopyWith<_HistorySnapshot> get copyWith => __$HistorySnapshotCopyWithImpl<_HistorySnapshot>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'HistorySnapshot'))
    ..add(DiagnosticsProperty('range', range))..add(DiagnosticsProperty('from', from))..add(DiagnosticsProperty('to', to))..add(DiagnosticsProperty('closedByDay', closedByDay))..add(DiagnosticsProperty('closedTotal', closedTotal))..add(DiagnosticsProperty('projects', projects))..add(DiagnosticsProperty('stale', stale));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HistorySnapshot&&(identical(other.range, range) || other.range == range)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&const DeepCollectionEquality().equals(other._closedByDay, _closedByDay)&&(identical(other.closedTotal, closedTotal) || other.closedTotal == closedTotal)&&const DeepCollectionEquality().equals(other._projects, _projects)&&const DeepCollectionEquality().equals(other._stale, _stale));
}


@override
int get hashCode => Object.hash(runtimeType,range,from,to,const DeepCollectionEquality().hash(_closedByDay),closedTotal,const DeepCollectionEquality().hash(_projects),const DeepCollectionEquality().hash(_stale));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'HistorySnapshot(range: $range, from: $from, to: $to, closedByDay: $closedByDay, closedTotal: $closedTotal, projects: $projects, stale: $stale)';
}


}

/// @nodoc
abstract mixin class _$HistorySnapshotCopyWith<$Res> implements $HistorySnapshotCopyWith<$Res> {
  factory _$HistorySnapshotCopyWith(_HistorySnapshot value, $Res Function(_HistorySnapshot) _then) = __$HistorySnapshotCopyWithImpl;
@override @useResult
$Res call({
 HistoryRange range, String? from, String to, List<HistoryDay> closedByDay, int closedTotal, List<ProjectMovement> projects, List<StaleTask> stale
});




}
/// @nodoc
class __$HistorySnapshotCopyWithImpl<$Res>
    implements _$HistorySnapshotCopyWith<$Res> {
  __$HistorySnapshotCopyWithImpl(this._self, this._then);

  final _HistorySnapshot _self;
  final $Res Function(_HistorySnapshot) _then;

/// Create a copy of HistorySnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? range = null,Object? from = freezed,Object? to = null,Object? closedByDay = null,Object? closedTotal = null,Object? projects = null,Object? stale = null,}) {
  return _then(_HistorySnapshot(
range: null == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as HistoryRange,from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,closedByDay: null == closedByDay ? _self._closedByDay : closedByDay // ignore: cast_nullable_to_non_nullable
as List<HistoryDay>,closedTotal: null == closedTotal ? _self.closedTotal : closedTotal // ignore: cast_nullable_to_non_nullable
as int,projects: null == projects ? _self._projects : projects // ignore: cast_nullable_to_non_nullable
as List<ProjectMovement>,stale: null == stale ? _self._stale : stale // ignore: cast_nullable_to_non_nullable
as List<StaleTask>,
  ));
}


}

// dart format on
