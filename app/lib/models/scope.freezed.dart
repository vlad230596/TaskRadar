// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'scope.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Scope {

 String get id; String get name;/// Server-assigned ordering key across scopes, the same gapped-float scheme
/// as `Task.position` -- and `double` for the same reason: the server
/// bisects the gap between two neighbours, so a few reorders into one slot
/// produce a fractional value that an `int` would silently truncate. See
/// the long note on [Task.position].
///
/// Nothing here ever re-sorts by it. List order is the server's order
/// (`GET /scopes` sorts by position); this field is read for diagnostics
/// and for nothing else.
 double get position; String get createdAt; String get updatedAt;
/// Create a copy of Scope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScopeCopyWith<Scope> get copyWith => _$ScopeCopyWithImpl<Scope>(this as Scope, _$identity);

  /// Serializes this Scope to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Scope&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,position,createdAt,updatedAt);

@override
String toString() {
  return 'Scope(id: $id, name: $name, position: $position, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ScopeCopyWith<$Res>  {
  factory $ScopeCopyWith(Scope value, $Res Function(Scope) _then) = _$ScopeCopyWithImpl;
@useResult
$Res call({
 String id, String name, double position, String createdAt, String updatedAt
});




}
/// @nodoc
class _$ScopeCopyWithImpl<$Res>
    implements $ScopeCopyWith<$Res> {
  _$ScopeCopyWithImpl(this._self, this._then);

  final Scope _self;
  final $Res Function(Scope) _then;

/// Create a copy of Scope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? position = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Scope].
extension ScopePatterns on Scope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Scope value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Scope() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Scope value)  $default,){
final _that = this;
switch (_that) {
case _Scope():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Scope value)?  $default,){
final _that = this;
switch (_that) {
case _Scope() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  double position,  String createdAt,  String updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Scope() when $default != null:
return $default(_that.id,_that.name,_that.position,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  double position,  String createdAt,  String updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Scope():
return $default(_that.id,_that.name,_that.position,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  double position,  String createdAt,  String updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Scope() when $default != null:
return $default(_that.id,_that.name,_that.position,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Scope implements Scope {
  const _Scope({required this.id, required this.name, required this.position, required this.createdAt, required this.updatedAt});
  factory _Scope.fromJson(Map<String, dynamic> json) => _$ScopeFromJson(json);

@override final  String id;
@override final  String name;
/// Server-assigned ordering key across scopes, the same gapped-float scheme
/// as `Task.position` -- and `double` for the same reason: the server
/// bisects the gap between two neighbours, so a few reorders into one slot
/// produce a fractional value that an `int` would silently truncate. See
/// the long note on [Task.position].
///
/// Nothing here ever re-sorts by it. List order is the server's order
/// (`GET /scopes` sorts by position); this field is read for diagnostics
/// and for nothing else.
@override final  double position;
@override final  String createdAt;
@override final  String updatedAt;

/// Create a copy of Scope
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScopeCopyWith<_Scope> get copyWith => __$ScopeCopyWithImpl<_Scope>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ScopeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Scope&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,position,createdAt,updatedAt);

@override
String toString() {
  return 'Scope(id: $id, name: $name, position: $position, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ScopeCopyWith<$Res> implements $ScopeCopyWith<$Res> {
  factory _$ScopeCopyWith(_Scope value, $Res Function(_Scope) _then) = __$ScopeCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, double position, String createdAt, String updatedAt
});




}
/// @nodoc
class __$ScopeCopyWithImpl<$Res>
    implements _$ScopeCopyWith<$Res> {
  __$ScopeCopyWithImpl(this._self, this._then);

  final _Scope _self;
  final $Res Function(_Scope) _then;

/// Create a copy of Scope
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? position = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Scope(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
