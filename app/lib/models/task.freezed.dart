// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Task {

 String get id; String get projectId; String get title; String? get description; TaskStatus get status;/// Server-assigned ordering key. Sparse and not necessarily contiguous --
/// reordering (F3) sends neighbour ids (`beforeTaskId` / `afterTaskId`) and
/// lets the server pick the new value, so nothing on the client should ever
/// compute a position itself.
///
/// ## Why `double` and not `int`
///
/// `position` is a **Float** in the Prisma schema, and that is load-bearing:
/// `backend/src/domain/position.ts` picks a new position by bisecting the
/// gap between the two neighbours, so the fourth or fifth reorder into the
/// same spot produces 1062.5 and JSON carries it as `1062.5`.
///
/// Declared `int`, this does **not** crash, which is worse than if it did:
/// `json_serializable` emits `(json['position'] as num).toInt()`, so 1062.5
/// silently becomes 1062. Two rows bisected into the same integer gap then
/// collapse to the same position on the client while the server has them
/// distinct and ordered -- a divergence with no error, no log line, and no
/// way to notice except by watching a list come back in a different order
/// than it went out. Seeded data (1000/2000/3000) can never show it; a few
/// drags into one spot can.
///
/// The client reads this field for diagnostics only. **List order is the
/// server's order** (`GET /projects/:id/tasks` sorts by `position` for us);
/// nothing here ever re-sorts by it, which is what makes an optimistic
/// reorder -- rows in the new order still carrying their old positions --
/// safe for the one frame before the server's answer lands.
 double get position;/// Calendar date (stored server-side as UTC midnight) to be reminded about a
/// `blocked` task. Only ever compare this by its `YYYY-MM-DD` prefix -- see
/// the note on [Project] and `frontend/src/lib/reminders.ts`.
 String? get remindAt;/// The reminder's time of day, local wall clock `HH:MM`, or null for "the
/// day only" -- which fires at the hour from the settings
/// (`domain/reminder_schedule.dart`). Never set without [remindAt]: the
/// server clears the two together.
 String? get remindTime;/// The project's category this task is grouped under, or null for "без
/// категории" -- see `task_category.dart`. Optional on the wire: older
/// servers and the board snapshot cached before categories do not carry
/// it, and "not told" draws the same as "none".
 String? get categoryId;/// AI processing (backend `src/domain/aiMark.ts`): the words before the
/// first "Обработать", the kind of that first parse, and the fields as
/// the last AI answer saved them. All null when AI never touched it.
/// Read through `domain/ai_mark.dart`.
 String? get aiSource; String? get aiKind; Map<String, dynamic>? get aiResult;/// The checklist (`design/task-editor-spec.md` §6), in its order, or null
/// for none -- the server stores an empty list as null too. Optional on
/// the wire like [categoryId]: older servers and snapshots lack it.
 List<ChecklistItem>? get checklist;/// The place reminder (§7), or null.
 TaskLocation? get location;/// The pictures' metadata, oldest first. Never null: a response without
/// the key (an older server, an older snapshot) reads as "none".
 List<TaskAttachment> get attachments;/// Whose working set the task is in (`design/goals-ideas-contract.md`);
/// null when it is in none, or when the server is older than contours.
 String? get focusContourId;/// The goals the task serves, achieved ones left out -- the source of the
/// crown. Never null: an older server or snapshot reads as "none".
 List<TaskGoalRef> get goals; String get createdAt; String get updatedAt;/// When the task was closed (`design/today-history-contract.md`): set on
/// the move into `done`, cleared on any move out of it. Null for an open
/// task, and on the wire from an older server or snapshot.
 String? get doneAt;/// Computed by the server, never stored: the first task in `position` order
/// that is neither done nor blocked.
///
/// It is a property of the *list*, not of the row, so it is only meaningful
/// in a response that carried the project's whole task list. The client must
/// not try to recompute or patch it locally after a mutation -- re-read the
/// affected project instead.
 bool get isCurrent;
/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskCopyWith<Task> get copyWith => _$TaskCopyWithImpl<Task>(this as Task, _$identity);

  /// Serializes this Task to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Task&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.remindAt, remindAt) || other.remindAt == remindAt)&&(identical(other.remindTime, remindTime) || other.remindTime == remindTime)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.aiSource, aiSource) || other.aiSource == aiSource)&&(identical(other.aiKind, aiKind) || other.aiKind == aiKind)&&const DeepCollectionEquality().equals(other.aiResult, aiResult)&&const DeepCollectionEquality().equals(other.checklist, checklist)&&(identical(other.location, location) || other.location == location)&&const DeepCollectionEquality().equals(other.attachments, attachments)&&(identical(other.focusContourId, focusContourId) || other.focusContourId == focusContourId)&&const DeepCollectionEquality().equals(other.goals, goals)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.doneAt, doneAt) || other.doneAt == doneAt)&&(identical(other.isCurrent, isCurrent) || other.isCurrent == isCurrent));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,projectId,title,description,status,position,remindAt,remindTime,categoryId,aiSource,aiKind,const DeepCollectionEquality().hash(aiResult),const DeepCollectionEquality().hash(checklist),location,const DeepCollectionEquality().hash(attachments),focusContourId,const DeepCollectionEquality().hash(goals),createdAt,updatedAt,doneAt,isCurrent]);

@override
String toString() {
  return 'Task(id: $id, projectId: $projectId, title: $title, description: $description, status: $status, position: $position, remindAt: $remindAt, remindTime: $remindTime, categoryId: $categoryId, aiSource: $aiSource, aiKind: $aiKind, aiResult: $aiResult, checklist: $checklist, location: $location, attachments: $attachments, focusContourId: $focusContourId, goals: $goals, createdAt: $createdAt, updatedAt: $updatedAt, doneAt: $doneAt, isCurrent: $isCurrent)';
}


}

/// @nodoc
abstract mixin class $TaskCopyWith<$Res>  {
  factory $TaskCopyWith(Task value, $Res Function(Task) _then) = _$TaskCopyWithImpl;
@useResult
$Res call({
 String id, String projectId, String title, String? description, TaskStatus status, double position, String? remindAt, String? remindTime, String? categoryId, String? aiSource, String? aiKind, Map<String, dynamic>? aiResult, List<ChecklistItem>? checklist, TaskLocation? location, List<TaskAttachment> attachments, String? focusContourId, List<TaskGoalRef> goals, String createdAt, String updatedAt, String? doneAt, bool isCurrent
});


$TaskLocationCopyWith<$Res>? get location;

}
/// @nodoc
class _$TaskCopyWithImpl<$Res>
    implements $TaskCopyWith<$Res> {
  _$TaskCopyWithImpl(this._self, this._then);

  final Task _self;
  final $Res Function(Task) _then;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? description = freezed,Object? status = null,Object? position = null,Object? remindAt = freezed,Object? remindTime = freezed,Object? categoryId = freezed,Object? aiSource = freezed,Object? aiKind = freezed,Object? aiResult = freezed,Object? checklist = freezed,Object? location = freezed,Object? attachments = null,Object? focusContourId = freezed,Object? goals = null,Object? createdAt = null,Object? updatedAt = null,Object? doneAt = freezed,Object? isCurrent = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,remindAt: freezed == remindAt ? _self.remindAt : remindAt // ignore: cast_nullable_to_non_nullable
as String?,remindTime: freezed == remindTime ? _self.remindTime : remindTime // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,aiSource: freezed == aiSource ? _self.aiSource : aiSource // ignore: cast_nullable_to_non_nullable
as String?,aiKind: freezed == aiKind ? _self.aiKind : aiKind // ignore: cast_nullable_to_non_nullable
as String?,aiResult: freezed == aiResult ? _self.aiResult : aiResult // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,checklist: freezed == checklist ? _self.checklist : checklist // ignore: cast_nullable_to_non_nullable
as List<ChecklistItem>?,location: freezed == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as TaskLocation?,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<TaskAttachment>,focusContourId: freezed == focusContourId ? _self.focusContourId : focusContourId // ignore: cast_nullable_to_non_nullable
as String?,goals: null == goals ? _self.goals : goals // ignore: cast_nullable_to_non_nullable
as List<TaskGoalRef>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,doneAt: freezed == doneAt ? _self.doneAt : doneAt // ignore: cast_nullable_to_non_nullable
as String?,isCurrent: null == isCurrent ? _self.isCurrent : isCurrent // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TaskLocationCopyWith<$Res>? get location {
    if (_self.location == null) {
    return null;
  }

  return $TaskLocationCopyWith<$Res>(_self.location!, (value) {
    return _then(_self.copyWith(location: value));
  });
}
}


/// Adds pattern-matching-related methods to [Task].
extension TaskPatterns on Task {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Task value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Task() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Task value)  $default,){
final _that = this;
switch (_that) {
case _Task():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Task value)?  $default,){
final _that = this;
switch (_that) {
case _Task() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  String? description,  TaskStatus status,  double position,  String? remindAt,  String? remindTime,  String? categoryId,  String? aiSource,  String? aiKind,  Map<String, dynamic>? aiResult,  List<ChecklistItem>? checklist,  TaskLocation? location,  List<TaskAttachment> attachments,  String? focusContourId,  List<TaskGoalRef> goals,  String createdAt,  String updatedAt,  String? doneAt,  bool isCurrent)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.description,_that.status,_that.position,_that.remindAt,_that.remindTime,_that.categoryId,_that.aiSource,_that.aiKind,_that.aiResult,_that.checklist,_that.location,_that.attachments,_that.focusContourId,_that.goals,_that.createdAt,_that.updatedAt,_that.doneAt,_that.isCurrent);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  String? description,  TaskStatus status,  double position,  String? remindAt,  String? remindTime,  String? categoryId,  String? aiSource,  String? aiKind,  Map<String, dynamic>? aiResult,  List<ChecklistItem>? checklist,  TaskLocation? location,  List<TaskAttachment> attachments,  String? focusContourId,  List<TaskGoalRef> goals,  String createdAt,  String updatedAt,  String? doneAt,  bool isCurrent)  $default,) {final _that = this;
switch (_that) {
case _Task():
return $default(_that.id,_that.projectId,_that.title,_that.description,_that.status,_that.position,_that.remindAt,_that.remindTime,_that.categoryId,_that.aiSource,_that.aiKind,_that.aiResult,_that.checklist,_that.location,_that.attachments,_that.focusContourId,_that.goals,_that.createdAt,_that.updatedAt,_that.doneAt,_that.isCurrent);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String projectId,  String title,  String? description,  TaskStatus status,  double position,  String? remindAt,  String? remindTime,  String? categoryId,  String? aiSource,  String? aiKind,  Map<String, dynamic>? aiResult,  List<ChecklistItem>? checklist,  TaskLocation? location,  List<TaskAttachment> attachments,  String? focusContourId,  List<TaskGoalRef> goals,  String createdAt,  String updatedAt,  String? doneAt,  bool isCurrent)?  $default,) {final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.description,_that.status,_that.position,_that.remindAt,_that.remindTime,_that.categoryId,_that.aiSource,_that.aiKind,_that.aiResult,_that.checklist,_that.location,_that.attachments,_that.focusContourId,_that.goals,_that.createdAt,_that.updatedAt,_that.doneAt,_that.isCurrent);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _Task implements Task {
  const _Task({required this.id, required this.projectId, required this.title, required this.description, required this.status, required this.position, required this.remindAt, this.remindTime, this.categoryId, this.aiSource, this.aiKind, final  Map<String, dynamic>? aiResult, final  List<ChecklistItem>? checklist, this.location, final  List<TaskAttachment> attachments = const <TaskAttachment>[], this.focusContourId, final  List<TaskGoalRef> goals = const <TaskGoalRef>[], required this.createdAt, required this.updatedAt, this.doneAt, required this.isCurrent}): _aiResult = aiResult,_checklist = checklist,_attachments = attachments,_goals = goals;
  factory _Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);

@override final  String id;
@override final  String projectId;
@override final  String title;
@override final  String? description;
@override final  TaskStatus status;
/// Server-assigned ordering key. Sparse and not necessarily contiguous --
/// reordering (F3) sends neighbour ids (`beforeTaskId` / `afterTaskId`) and
/// lets the server pick the new value, so nothing on the client should ever
/// compute a position itself.
///
/// ## Why `double` and not `int`
///
/// `position` is a **Float** in the Prisma schema, and that is load-bearing:
/// `backend/src/domain/position.ts` picks a new position by bisecting the
/// gap between the two neighbours, so the fourth or fifth reorder into the
/// same spot produces 1062.5 and JSON carries it as `1062.5`.
///
/// Declared `int`, this does **not** crash, which is worse than if it did:
/// `json_serializable` emits `(json['position'] as num).toInt()`, so 1062.5
/// silently becomes 1062. Two rows bisected into the same integer gap then
/// collapse to the same position on the client while the server has them
/// distinct and ordered -- a divergence with no error, no log line, and no
/// way to notice except by watching a list come back in a different order
/// than it went out. Seeded data (1000/2000/3000) can never show it; a few
/// drags into one spot can.
///
/// The client reads this field for diagnostics only. **List order is the
/// server's order** (`GET /projects/:id/tasks` sorts by `position` for us);
/// nothing here ever re-sorts by it, which is what makes an optimistic
/// reorder -- rows in the new order still carrying their old positions --
/// safe for the one frame before the server's answer lands.
@override final  double position;
/// Calendar date (stored server-side as UTC midnight) to be reminded about a
/// `blocked` task. Only ever compare this by its `YYYY-MM-DD` prefix -- see
/// the note on [Project] and `frontend/src/lib/reminders.ts`.
@override final  String? remindAt;
/// The reminder's time of day, local wall clock `HH:MM`, or null for "the
/// day only" -- which fires at the hour from the settings
/// (`domain/reminder_schedule.dart`). Never set without [remindAt]: the
/// server clears the two together.
@override final  String? remindTime;
/// The project's category this task is grouped under, or null for "без
/// категории" -- see `task_category.dart`. Optional on the wire: older
/// servers and the board snapshot cached before categories do not carry
/// it, and "not told" draws the same as "none".
@override final  String? categoryId;
/// AI processing (backend `src/domain/aiMark.ts`): the words before the
/// first "Обработать", the kind of that first parse, and the fields as
/// the last AI answer saved them. All null when AI never touched it.
/// Read through `domain/ai_mark.dart`.
@override final  String? aiSource;
@override final  String? aiKind;
 final  Map<String, dynamic>? _aiResult;
@override Map<String, dynamic>? get aiResult {
  final value = _aiResult;
  if (value == null) return null;
  if (_aiResult is EqualUnmodifiableMapView) return _aiResult;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

/// The checklist (`design/task-editor-spec.md` §6), in its order, or null
/// for none -- the server stores an empty list as null too. Optional on
/// the wire like [categoryId]: older servers and snapshots lack it.
 final  List<ChecklistItem>? _checklist;
/// The checklist (`design/task-editor-spec.md` §6), in its order, or null
/// for none -- the server stores an empty list as null too. Optional on
/// the wire like [categoryId]: older servers and snapshots lack it.
@override List<ChecklistItem>? get checklist {
  final value = _checklist;
  if (value == null) return null;
  if (_checklist is EqualUnmodifiableListView) return _checklist;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// The place reminder (§7), or null.
@override final  TaskLocation? location;
/// The pictures' metadata, oldest first. Never null: a response without
/// the key (an older server, an older snapshot) reads as "none".
 final  List<TaskAttachment> _attachments;
/// The pictures' metadata, oldest first. Never null: a response without
/// the key (an older server, an older snapshot) reads as "none".
@override@JsonKey() List<TaskAttachment> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}

/// Whose working set the task is in (`design/goals-ideas-contract.md`);
/// null when it is in none, or when the server is older than contours.
@override final  String? focusContourId;
/// The goals the task serves, achieved ones left out -- the source of the
/// crown. Never null: an older server or snapshot reads as "none".
 final  List<TaskGoalRef> _goals;
/// The goals the task serves, achieved ones left out -- the source of the
/// crown. Never null: an older server or snapshot reads as "none".
@override@JsonKey() List<TaskGoalRef> get goals {
  if (_goals is EqualUnmodifiableListView) return _goals;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_goals);
}

@override final  String createdAt;
@override final  String updatedAt;
/// When the task was closed (`design/today-history-contract.md`): set on
/// the move into `done`, cleared on any move out of it. Null for an open
/// task, and on the wire from an older server or snapshot.
@override final  String? doneAt;
/// Computed by the server, never stored: the first task in `position` order
/// that is neither done nor blocked.
///
/// It is a property of the *list*, not of the row, so it is only meaningful
/// in a response that carried the project's whole task list. The client must
/// not try to recompute or patch it locally after a mutation -- re-read the
/// affected project instead.
@override final  bool isCurrent;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskCopyWith<_Task> get copyWith => __$TaskCopyWithImpl<_Task>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Task&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.remindAt, remindAt) || other.remindAt == remindAt)&&(identical(other.remindTime, remindTime) || other.remindTime == remindTime)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.aiSource, aiSource) || other.aiSource == aiSource)&&(identical(other.aiKind, aiKind) || other.aiKind == aiKind)&&const DeepCollectionEquality().equals(other._aiResult, _aiResult)&&const DeepCollectionEquality().equals(other._checklist, _checklist)&&(identical(other.location, location) || other.location == location)&&const DeepCollectionEquality().equals(other._attachments, _attachments)&&(identical(other.focusContourId, focusContourId) || other.focusContourId == focusContourId)&&const DeepCollectionEquality().equals(other._goals, _goals)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.doneAt, doneAt) || other.doneAt == doneAt)&&(identical(other.isCurrent, isCurrent) || other.isCurrent == isCurrent));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,projectId,title,description,status,position,remindAt,remindTime,categoryId,aiSource,aiKind,const DeepCollectionEquality().hash(_aiResult),const DeepCollectionEquality().hash(_checklist),location,const DeepCollectionEquality().hash(_attachments),focusContourId,const DeepCollectionEquality().hash(_goals),createdAt,updatedAt,doneAt,isCurrent]);

@override
String toString() {
  return 'Task(id: $id, projectId: $projectId, title: $title, description: $description, status: $status, position: $position, remindAt: $remindAt, remindTime: $remindTime, categoryId: $categoryId, aiSource: $aiSource, aiKind: $aiKind, aiResult: $aiResult, checklist: $checklist, location: $location, attachments: $attachments, focusContourId: $focusContourId, goals: $goals, createdAt: $createdAt, updatedAt: $updatedAt, doneAt: $doneAt, isCurrent: $isCurrent)';
}


}

/// @nodoc
abstract mixin class _$TaskCopyWith<$Res> implements $TaskCopyWith<$Res> {
  factory _$TaskCopyWith(_Task value, $Res Function(_Task) _then) = __$TaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String projectId, String title, String? description, TaskStatus status, double position, String? remindAt, String? remindTime, String? categoryId, String? aiSource, String? aiKind, Map<String, dynamic>? aiResult, List<ChecklistItem>? checklist, TaskLocation? location, List<TaskAttachment> attachments, String? focusContourId, List<TaskGoalRef> goals, String createdAt, String updatedAt, String? doneAt, bool isCurrent
});


@override $TaskLocationCopyWith<$Res>? get location;

}
/// @nodoc
class __$TaskCopyWithImpl<$Res>
    implements _$TaskCopyWith<$Res> {
  __$TaskCopyWithImpl(this._self, this._then);

  final _Task _self;
  final $Res Function(_Task) _then;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? description = freezed,Object? status = null,Object? position = null,Object? remindAt = freezed,Object? remindTime = freezed,Object? categoryId = freezed,Object? aiSource = freezed,Object? aiKind = freezed,Object? aiResult = freezed,Object? checklist = freezed,Object? location = freezed,Object? attachments = null,Object? focusContourId = freezed,Object? goals = null,Object? createdAt = null,Object? updatedAt = null,Object? doneAt = freezed,Object? isCurrent = null,}) {
  return _then(_Task(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,remindAt: freezed == remindAt ? _self.remindAt : remindAt // ignore: cast_nullable_to_non_nullable
as String?,remindTime: freezed == remindTime ? _self.remindTime : remindTime // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,aiSource: freezed == aiSource ? _self.aiSource : aiSource // ignore: cast_nullable_to_non_nullable
as String?,aiKind: freezed == aiKind ? _self.aiKind : aiKind // ignore: cast_nullable_to_non_nullable
as String?,aiResult: freezed == aiResult ? _self._aiResult : aiResult // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,checklist: freezed == checklist ? _self._checklist : checklist // ignore: cast_nullable_to_non_nullable
as List<ChecklistItem>?,location: freezed == location ? _self.location : location // ignore: cast_nullable_to_non_nullable
as TaskLocation?,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<TaskAttachment>,focusContourId: freezed == focusContourId ? _self.focusContourId : focusContourId // ignore: cast_nullable_to_non_nullable
as String?,goals: null == goals ? _self._goals : goals // ignore: cast_nullable_to_non_nullable
as List<TaskGoalRef>,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,doneAt: freezed == doneAt ? _self.doneAt : doneAt // ignore: cast_nullable_to_non_nullable
as String?,isCurrent: null == isCurrent ? _self.isCurrent : isCurrent // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TaskLocationCopyWith<$Res>? get location {
    if (_self.location == null) {
    return null;
  }

  return $TaskLocationCopyWith<$Res>(_self.location!, (value) {
    return _then(_self.copyWith(location: value));
  });
}
}

// dart format on
