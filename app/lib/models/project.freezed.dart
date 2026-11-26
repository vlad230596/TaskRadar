// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Project {

 String get id; String get name;/// Which scope this project belongs to (F7). Required on the wire and
/// required here: the board shows exactly one scope at a time, so a project
/// without one could not be drawn anywhere.
///
/// Only ever compared, never parsed. The client does **not** filter the
/// board on the server (`GET /board?scopeId=`) even though it could -- it
/// fetches every scope and filters locally, because the local reminder
/// queue is armed from the board and a server-filtered board would stop
/// raising reminders for whichever scopes are not on screen. See
/// `../providers/scope_providers.dart`.
 String get scopeId;/// Null means "active". Non-null is the ISO instant it was archived at.
 String? get archivedAt; String get createdAt; String get updatedAt;/// How many notes the project has, when the list endpoint says so.
///
/// Optional on the wire: `GET /projects` started carrying it for the
/// project screen's "Заметки · N" switch, and older servers, the board
/// snapshot and `GET /projects/:id` may not. Null means "not told", never
/// "none" -- the screen then waits for the notes themselves. Read
/// leniently ([_countFromJson]), because a counter is not worth failing a
/// whole project list over.
@JsonKey(fromJson: _countFromJson, includeIfNull: false) int? get noteCount;/// The project's rhythm (`design/today-history-contract.md`): the norm
/// «≥ N closed a week» and the ceiling «≤ M open», both optional; the
/// rhythm is on when either is set.
 int? get rhythmClosedPerWeek; int? get rhythmMaxOpen;/// What the server computed from them, or null when the rhythm is off
/// (or the server is older than rhythms).
@JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson) ProjectRhythm? get rhythm;
/// Create a copy of Project
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectCopyWith<Project> get copyWith => _$ProjectCopyWithImpl<Project>(this as Project, _$identity);

  /// Serializes this Project to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Project&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.archivedAt, archivedAt) || other.archivedAt == archivedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.noteCount, noteCount) || other.noteCount == noteCount)&&(identical(other.rhythmClosedPerWeek, rhythmClosedPerWeek) || other.rhythmClosedPerWeek == rhythmClosedPerWeek)&&(identical(other.rhythmMaxOpen, rhythmMaxOpen) || other.rhythmMaxOpen == rhythmMaxOpen)&&(identical(other.rhythm, rhythm) || other.rhythm == rhythm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,scopeId,archivedAt,createdAt,updatedAt,noteCount,rhythmClosedPerWeek,rhythmMaxOpen,rhythm);

@override
String toString() {
  return 'Project(id: $id, name: $name, scopeId: $scopeId, archivedAt: $archivedAt, createdAt: $createdAt, updatedAt: $updatedAt, noteCount: $noteCount, rhythmClosedPerWeek: $rhythmClosedPerWeek, rhythmMaxOpen: $rhythmMaxOpen, rhythm: $rhythm)';
}


}

/// @nodoc
abstract mixin class $ProjectCopyWith<$Res>  {
  factory $ProjectCopyWith(Project value, $Res Function(Project) _then) = _$ProjectCopyWithImpl;
@useResult
$Res call({
 String id, String name, String scopeId, String? archivedAt, String createdAt, String updatedAt,@JsonKey(fromJson: _countFromJson, includeIfNull: false) int? noteCount, int? rhythmClosedPerWeek, int? rhythmMaxOpen,@JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson) ProjectRhythm? rhythm
});




}
/// @nodoc
class _$ProjectCopyWithImpl<$Res>
    implements $ProjectCopyWith<$Res> {
  _$ProjectCopyWithImpl(this._self, this._then);

  final Project _self;
  final $Res Function(Project) _then;

/// Create a copy of Project
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? scopeId = null,Object? archivedAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? noteCount = freezed,Object? rhythmClosedPerWeek = freezed,Object? rhythmMaxOpen = freezed,Object? rhythm = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,archivedAt: freezed == archivedAt ? _self.archivedAt : archivedAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,noteCount: freezed == noteCount ? _self.noteCount : noteCount // ignore: cast_nullable_to_non_nullable
as int?,rhythmClosedPerWeek: freezed == rhythmClosedPerWeek ? _self.rhythmClosedPerWeek : rhythmClosedPerWeek // ignore: cast_nullable_to_non_nullable
as int?,rhythmMaxOpen: freezed == rhythmMaxOpen ? _self.rhythmMaxOpen : rhythmMaxOpen // ignore: cast_nullable_to_non_nullable
as int?,rhythm: freezed == rhythm ? _self.rhythm : rhythm // ignore: cast_nullable_to_non_nullable
as ProjectRhythm?,
  ));
}

}


/// Adds pattern-matching-related methods to [Project].
extension ProjectPatterns on Project {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Project value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Project() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Project value)  $default,){
final _that = this;
switch (_that) {
case _Project():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Project value)?  $default,){
final _that = this;
switch (_that) {
case _Project() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String scopeId,  String? archivedAt,  String createdAt,  String updatedAt, @JsonKey(fromJson: _countFromJson, includeIfNull: false)  int? noteCount,  int? rhythmClosedPerWeek,  int? rhythmMaxOpen, @JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson)  ProjectRhythm? rhythm)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Project() when $default != null:
return $default(_that.id,_that.name,_that.scopeId,_that.archivedAt,_that.createdAt,_that.updatedAt,_that.noteCount,_that.rhythmClosedPerWeek,_that.rhythmMaxOpen,_that.rhythm);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String scopeId,  String? archivedAt,  String createdAt,  String updatedAt, @JsonKey(fromJson: _countFromJson, includeIfNull: false)  int? noteCount,  int? rhythmClosedPerWeek,  int? rhythmMaxOpen, @JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson)  ProjectRhythm? rhythm)  $default,) {final _that = this;
switch (_that) {
case _Project():
return $default(_that.id,_that.name,_that.scopeId,_that.archivedAt,_that.createdAt,_that.updatedAt,_that.noteCount,_that.rhythmClosedPerWeek,_that.rhythmMaxOpen,_that.rhythm);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String scopeId,  String? archivedAt,  String createdAt,  String updatedAt, @JsonKey(fromJson: _countFromJson, includeIfNull: false)  int? noteCount,  int? rhythmClosedPerWeek,  int? rhythmMaxOpen, @JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson)  ProjectRhythm? rhythm)?  $default,) {final _that = this;
switch (_that) {
case _Project() when $default != null:
return $default(_that.id,_that.name,_that.scopeId,_that.archivedAt,_that.createdAt,_that.updatedAt,_that.noteCount,_that.rhythmClosedPerWeek,_that.rhythmMaxOpen,_that.rhythm);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Project implements Project {
  const _Project({required this.id, required this.name, required this.scopeId, required this.archivedAt, required this.createdAt, required this.updatedAt, @JsonKey(fromJson: _countFromJson, includeIfNull: false) this.noteCount, this.rhythmClosedPerWeek, this.rhythmMaxOpen, @JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson) this.rhythm});
  factory _Project.fromJson(Map<String, dynamic> json) => _$ProjectFromJson(json);

@override final  String id;
@override final  String name;
/// Which scope this project belongs to (F7). Required on the wire and
/// required here: the board shows exactly one scope at a time, so a project
/// without one could not be drawn anywhere.
///
/// Only ever compared, never parsed. The client does **not** filter the
/// board on the server (`GET /board?scopeId=`) even though it could -- it
/// fetches every scope and filters locally, because the local reminder
/// queue is armed from the board and a server-filtered board would stop
/// raising reminders for whichever scopes are not on screen. See
/// `../providers/scope_providers.dart`.
@override final  String scopeId;
/// Null means "active". Non-null is the ISO instant it was archived at.
@override final  String? archivedAt;
@override final  String createdAt;
@override final  String updatedAt;
/// How many notes the project has, when the list endpoint says so.
///
/// Optional on the wire: `GET /projects` started carrying it for the
/// project screen's "Заметки · N" switch, and older servers, the board
/// snapshot and `GET /projects/:id` may not. Null means "not told", never
/// "none" -- the screen then waits for the notes themselves. Read
/// leniently ([_countFromJson]), because a counter is not worth failing a
/// whole project list over.
@override@JsonKey(fromJson: _countFromJson, includeIfNull: false) final  int? noteCount;
/// The project's rhythm (`design/today-history-contract.md`): the norm
/// «≥ N closed a week» and the ceiling «≤ M open», both optional; the
/// rhythm is on when either is set.
@override final  int? rhythmClosedPerWeek;
@override final  int? rhythmMaxOpen;
/// What the server computed from them, or null when the rhythm is off
/// (or the server is older than rhythms).
@override@JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson) final  ProjectRhythm? rhythm;

/// Create a copy of Project
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectCopyWith<_Project> get copyWith => __$ProjectCopyWithImpl<_Project>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProjectToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Project&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.archivedAt, archivedAt) || other.archivedAt == archivedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.noteCount, noteCount) || other.noteCount == noteCount)&&(identical(other.rhythmClosedPerWeek, rhythmClosedPerWeek) || other.rhythmClosedPerWeek == rhythmClosedPerWeek)&&(identical(other.rhythmMaxOpen, rhythmMaxOpen) || other.rhythmMaxOpen == rhythmMaxOpen)&&(identical(other.rhythm, rhythm) || other.rhythm == rhythm));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,scopeId,archivedAt,createdAt,updatedAt,noteCount,rhythmClosedPerWeek,rhythmMaxOpen,rhythm);

@override
String toString() {
  return 'Project(id: $id, name: $name, scopeId: $scopeId, archivedAt: $archivedAt, createdAt: $createdAt, updatedAt: $updatedAt, noteCount: $noteCount, rhythmClosedPerWeek: $rhythmClosedPerWeek, rhythmMaxOpen: $rhythmMaxOpen, rhythm: $rhythm)';
}


}

/// @nodoc
abstract mixin class _$ProjectCopyWith<$Res> implements $ProjectCopyWith<$Res> {
  factory _$ProjectCopyWith(_Project value, $Res Function(_Project) _then) = __$ProjectCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String scopeId, String? archivedAt, String createdAt, String updatedAt,@JsonKey(fromJson: _countFromJson, includeIfNull: false) int? noteCount, int? rhythmClosedPerWeek, int? rhythmMaxOpen,@JsonKey(fromJson: ProjectRhythm.maybeFromJson, toJson: ProjectRhythm.maybeToJson) ProjectRhythm? rhythm
});




}
/// @nodoc
class __$ProjectCopyWithImpl<$Res>
    implements _$ProjectCopyWith<$Res> {
  __$ProjectCopyWithImpl(this._self, this._then);

  final _Project _self;
  final $Res Function(_Project) _then;

/// Create a copy of Project
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? scopeId = null,Object? archivedAt = freezed,Object? createdAt = null,Object? updatedAt = null,Object? noteCount = freezed,Object? rhythmClosedPerWeek = freezed,Object? rhythmMaxOpen = freezed,Object? rhythm = freezed,}) {
  return _then(_Project(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,archivedAt: freezed == archivedAt ? _self.archivedAt : archivedAt // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,noteCount: freezed == noteCount ? _self.noteCount : noteCount // ignore: cast_nullable_to_non_nullable
as int?,rhythmClosedPerWeek: freezed == rhythmClosedPerWeek ? _self.rhythmClosedPerWeek : rhythmClosedPerWeek // ignore: cast_nullable_to_non_nullable
as int?,rhythmMaxOpen: freezed == rhythmMaxOpen ? _self.rhythmMaxOpen : rhythmMaxOpen // ignore: cast_nullable_to_non_nullable
as int?,rhythm: freezed == rhythm ? _self.rhythm : rhythm // ignore: cast_nullable_to_non_nullable
as ProjectRhythm?,
  ));
}


}

// dart format on
