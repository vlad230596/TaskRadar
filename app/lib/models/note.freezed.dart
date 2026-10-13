// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'note.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Note {

 String get id; String get projectId; String get title; String get content;/// AI processing (backend `src/domain/aiMark.ts`): the words before the
/// first "Обработать", the kind of that first parse, and the fields as
/// the last AI answer saved them. All null when AI never touched it.
/// Read through `domain/ai_mark.dart`.
 String? get aiSource; String? get aiKind; Map<String, dynamic>? get aiResult; String get createdAt; String get updatedAt;
/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteCopyWith<Note> get copyWith => _$NoteCopyWithImpl<Note>(this as Note, _$identity);

  /// Serializes this Note to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Note&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.content, content) || other.content == content)&&(identical(other.aiSource, aiSource) || other.aiSource == aiSource)&&(identical(other.aiKind, aiKind) || other.aiKind == aiKind)&&const DeepCollectionEquality().equals(other.aiResult, aiResult)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,title,content,aiSource,aiKind,const DeepCollectionEquality().hash(aiResult),createdAt,updatedAt);

@override
String toString() {
  return 'Note(id: $id, projectId: $projectId, title: $title, content: $content, aiSource: $aiSource, aiKind: $aiKind, aiResult: $aiResult, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $NoteCopyWith<$Res>  {
  factory $NoteCopyWith(Note value, $Res Function(Note) _then) = _$NoteCopyWithImpl;
@useResult
$Res call({
 String id, String projectId, String title, String content, String? aiSource, String? aiKind, Map<String, dynamic>? aiResult, String createdAt, String updatedAt
});




}
/// @nodoc
class _$NoteCopyWithImpl<$Res>
    implements $NoteCopyWith<$Res> {
  _$NoteCopyWithImpl(this._self, this._then);

  final Note _self;
  final $Res Function(Note) _then;

/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? content = null,Object? aiSource = freezed,Object? aiKind = freezed,Object? aiResult = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,aiSource: freezed == aiSource ? _self.aiSource : aiSource // ignore: cast_nullable_to_non_nullable
as String?,aiKind: freezed == aiKind ? _self.aiKind : aiKind // ignore: cast_nullable_to_non_nullable
as String?,aiResult: freezed == aiResult ? _self.aiResult : aiResult // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Note].
extension NotePatterns on Note {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Note value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Note() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Note value)  $default,){
final _that = this;
switch (_that) {
case _Note():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Note value)?  $default,){
final _that = this;
switch (_that) {
case _Note() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  String content,  String? aiSource,  String? aiKind,  Map<String, dynamic>? aiResult,  String createdAt,  String updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Note() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.content,_that.aiSource,_that.aiKind,_that.aiResult,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String projectId,  String title,  String content,  String? aiSource,  String? aiKind,  Map<String, dynamic>? aiResult,  String createdAt,  String updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Note():
return $default(_that.id,_that.projectId,_that.title,_that.content,_that.aiSource,_that.aiKind,_that.aiResult,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String projectId,  String title,  String content,  String? aiSource,  String? aiKind,  Map<String, dynamic>? aiResult,  String createdAt,  String updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Note() when $default != null:
return $default(_that.id,_that.projectId,_that.title,_that.content,_that.aiSource,_that.aiKind,_that.aiResult,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Note implements Note {
  const _Note({required this.id, required this.projectId, required this.title, required this.content, this.aiSource, this.aiKind, final  Map<String, dynamic>? aiResult, required this.createdAt, required this.updatedAt}): _aiResult = aiResult;
  factory _Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);

@override final  String id;
@override final  String projectId;
@override final  String title;
@override final  String content;
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

@override final  String createdAt;
@override final  String updatedAt;

/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NoteCopyWith<_Note> get copyWith => __$NoteCopyWithImpl<_Note>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NoteToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Note&&(identical(other.id, id) || other.id == id)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.content, content) || other.content == content)&&(identical(other.aiSource, aiSource) || other.aiSource == aiSource)&&(identical(other.aiKind, aiKind) || other.aiKind == aiKind)&&const DeepCollectionEquality().equals(other._aiResult, _aiResult)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,projectId,title,content,aiSource,aiKind,const DeepCollectionEquality().hash(_aiResult),createdAt,updatedAt);

@override
String toString() {
  return 'Note(id: $id, projectId: $projectId, title: $title, content: $content, aiSource: $aiSource, aiKind: $aiKind, aiResult: $aiResult, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$NoteCopyWith<$Res> implements $NoteCopyWith<$Res> {
  factory _$NoteCopyWith(_Note value, $Res Function(_Note) _then) = __$NoteCopyWithImpl;
@override @useResult
$Res call({
 String id, String projectId, String title, String content, String? aiSource, String? aiKind, Map<String, dynamic>? aiResult, String createdAt, String updatedAt
});




}
/// @nodoc
class __$NoteCopyWithImpl<$Res>
    implements _$NoteCopyWith<$Res> {
  __$NoteCopyWithImpl(this._self, this._then);

  final _Note _self;
  final $Res Function(_Note) _then;

/// Create a copy of Note
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? projectId = null,Object? title = null,Object? content = null,Object? aiSource = freezed,Object? aiKind = freezed,Object? aiResult = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Note(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,aiSource: freezed == aiSource ? _self.aiSource : aiSource // ignore: cast_nullable_to_non_nullable
as String?,aiKind: freezed == aiKind ? _self.aiKind : aiKind // ignore: cast_nullable_to_non_nullable
as String?,aiResult: freezed == aiResult ? _self._aiResult : aiResult // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
