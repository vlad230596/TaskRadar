// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_location.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TaskLocation {

/// -90..90.
 double get lat;/// -180..180.
 double get lng;/// Metres, [minRadius]..[maxRadius].
 int get radius;/// ≤ 80 characters; the picker defaults it to «Место». Optional on the
/// wire, and left out of it when null.
 String? get label;
/// Create a copy of TaskLocation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskLocationCopyWith<TaskLocation> get copyWith => _$TaskLocationCopyWithImpl<TaskLocation>(this as TaskLocation, _$identity);

  /// Serializes this TaskLocation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskLocation&&(identical(other.lat, lat) || other.lat == lat)&&(identical(other.lng, lng) || other.lng == lng)&&(identical(other.radius, radius) || other.radius == radius)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,lat,lng,radius,label);

@override
String toString() {
  return 'TaskLocation(lat: $lat, lng: $lng, radius: $radius, label: $label)';
}


}

/// @nodoc
abstract mixin class $TaskLocationCopyWith<$Res>  {
  factory $TaskLocationCopyWith(TaskLocation value, $Res Function(TaskLocation) _then) = _$TaskLocationCopyWithImpl;
@useResult
$Res call({
 double lat, double lng, int radius, String? label
});




}
/// @nodoc
class _$TaskLocationCopyWithImpl<$Res>
    implements $TaskLocationCopyWith<$Res> {
  _$TaskLocationCopyWithImpl(this._self, this._then);

  final TaskLocation _self;
  final $Res Function(TaskLocation) _then;

/// Create a copy of TaskLocation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lat = null,Object? lng = null,Object? radius = null,Object? label = freezed,}) {
  return _then(_self.copyWith(
lat: null == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double,lng: null == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double,radius: null == radius ? _self.radius : radius // ignore: cast_nullable_to_non_nullable
as int,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskLocation].
extension TaskLocationPatterns on TaskLocation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskLocation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskLocation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskLocation value)  $default,){
final _that = this;
switch (_that) {
case _TaskLocation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskLocation value)?  $default,){
final _that = this;
switch (_that) {
case _TaskLocation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double lat,  double lng,  int radius,  String? label)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskLocation() when $default != null:
return $default(_that.lat,_that.lng,_that.radius,_that.label);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double lat,  double lng,  int radius,  String? label)  $default,) {final _that = this;
switch (_that) {
case _TaskLocation():
return $default(_that.lat,_that.lng,_that.radius,_that.label);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double lat,  double lng,  int radius,  String? label)?  $default,) {final _that = this;
switch (_that) {
case _TaskLocation() when $default != null:
return $default(_that.lat,_that.lng,_that.radius,_that.label);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(includeIfNull: false)
class _TaskLocation extends TaskLocation {
  const _TaskLocation({required this.lat, required this.lng, this.radius = TaskLocation.defaultRadius, this.label}): super._();
  factory _TaskLocation.fromJson(Map<String, dynamic> json) => _$TaskLocationFromJson(json);

/// -90..90.
@override final  double lat;
/// -180..180.
@override final  double lng;
/// Metres, [minRadius]..[maxRadius].
@override@JsonKey() final  int radius;
/// ≤ 80 characters; the picker defaults it to «Место». Optional on the
/// wire, and left out of it when null.
@override final  String? label;

/// Create a copy of TaskLocation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskLocationCopyWith<_TaskLocation> get copyWith => __$TaskLocationCopyWithImpl<_TaskLocation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskLocationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskLocation&&(identical(other.lat, lat) || other.lat == lat)&&(identical(other.lng, lng) || other.lng == lng)&&(identical(other.radius, radius) || other.radius == radius)&&(identical(other.label, label) || other.label == label));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,lat,lng,radius,label);

@override
String toString() {
  return 'TaskLocation(lat: $lat, lng: $lng, radius: $radius, label: $label)';
}


}

/// @nodoc
abstract mixin class _$TaskLocationCopyWith<$Res> implements $TaskLocationCopyWith<$Res> {
  factory _$TaskLocationCopyWith(_TaskLocation value, $Res Function(_TaskLocation) _then) = __$TaskLocationCopyWithImpl;
@override @useResult
$Res call({
 double lat, double lng, int radius, String? label
});




}
/// @nodoc
class __$TaskLocationCopyWithImpl<$Res>
    implements _$TaskLocationCopyWith<$Res> {
  __$TaskLocationCopyWithImpl(this._self, this._then);

  final _TaskLocation _self;
  final $Res Function(_TaskLocation) _then;

/// Create a copy of TaskLocation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lat = null,Object? lng = null,Object? radius = null,Object? label = freezed,}) {
  return _then(_TaskLocation(
lat: null == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double,lng: null == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double,radius: null == radius ? _self.radius : radius // ignore: cast_nullable_to_non_nullable
as int,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
