// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'goal.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ContourSchedule {

 List<int> get days; String get from; String get to;
/// Create a copy of ContourSchedule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContourScheduleCopyWith<ContourSchedule> get copyWith => _$ContourScheduleCopyWithImpl<ContourSchedule>(this as ContourSchedule, _$identity);

  /// Serializes this ContourSchedule to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContourSchedule&&const DeepCollectionEquality().equals(other.days, days)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(days),from,to);

@override
String toString() {
  return 'ContourSchedule(days: $days, from: $from, to: $to)';
}


}

/// @nodoc
abstract mixin class $ContourScheduleCopyWith<$Res>  {
  factory $ContourScheduleCopyWith(ContourSchedule value, $Res Function(ContourSchedule) _then) = _$ContourScheduleCopyWithImpl;
@useResult
$Res call({
 List<int> days, String from, String to
});




}
/// @nodoc
class _$ContourScheduleCopyWithImpl<$Res>
    implements $ContourScheduleCopyWith<$Res> {
  _$ContourScheduleCopyWithImpl(this._self, this._then);

  final ContourSchedule _self;
  final $Res Function(ContourSchedule) _then;

/// Create a copy of ContourSchedule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? days = null,Object? from = null,Object? to = null,}) {
  return _then(_self.copyWith(
days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as List<int>,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ContourSchedule].
extension ContourSchedulePatterns on ContourSchedule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContourSchedule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContourSchedule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContourSchedule value)  $default,){
final _that = this;
switch (_that) {
case _ContourSchedule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContourSchedule value)?  $default,){
final _that = this;
switch (_that) {
case _ContourSchedule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<int> days,  String from,  String to)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContourSchedule() when $default != null:
return $default(_that.days,_that.from,_that.to);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<int> days,  String from,  String to)  $default,) {final _that = this;
switch (_that) {
case _ContourSchedule():
return $default(_that.days,_that.from,_that.to);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<int> days,  String from,  String to)?  $default,) {final _that = this;
switch (_that) {
case _ContourSchedule() when $default != null:
return $default(_that.days,_that.from,_that.to);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ContourSchedule implements ContourSchedule {
  const _ContourSchedule({required final  List<int> days, required this.from, required this.to}): _days = days;
  factory _ContourSchedule.fromJson(Map<String, dynamic> json) => _$ContourScheduleFromJson(json);

 final  List<int> _days;
@override List<int> get days {
  if (_days is EqualUnmodifiableListView) return _days;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_days);
}

@override final  String from;
@override final  String to;

/// Create a copy of ContourSchedule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContourScheduleCopyWith<_ContourSchedule> get copyWith => __$ContourScheduleCopyWithImpl<_ContourSchedule>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ContourScheduleToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContourSchedule&&const DeepCollectionEquality().equals(other._days, _days)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_days),from,to);

@override
String toString() {
  return 'ContourSchedule(days: $days, from: $from, to: $to)';
}


}

/// @nodoc
abstract mixin class _$ContourScheduleCopyWith<$Res> implements $ContourScheduleCopyWith<$Res> {
  factory _$ContourScheduleCopyWith(_ContourSchedule value, $Res Function(_ContourSchedule) _then) = __$ContourScheduleCopyWithImpl;
@override @useResult
$Res call({
 List<int> days, String from, String to
});




}
/// @nodoc
class __$ContourScheduleCopyWithImpl<$Res>
    implements _$ContourScheduleCopyWith<$Res> {
  __$ContourScheduleCopyWithImpl(this._self, this._then);

  final _ContourSchedule _self;
  final $Res Function(_ContourSchedule) _then;

/// Create a copy of ContourSchedule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? days = null,Object? from = null,Object? to = null,}) {
  return _then(_ContourSchedule(
days: null == days ? _self._days : days // ignore: cast_nullable_to_non_nullable
as List<int>,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$Contour {

 String get id; String get name; int get slots; int get windowDays; ContourSchedule? get schedule;/// Gapped float, `double` for the reason given on `Task.position`.
 double get position; String? get createdAt; String? get updatedAt;
/// Create a copy of Contour
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContourCopyWith<Contour> get copyWith => _$ContourCopyWithImpl<Contour>(this as Contour, _$identity);

  /// Serializes this Contour to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Contour&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.slots, slots) || other.slots == slots)&&(identical(other.windowDays, windowDays) || other.windowDays == windowDays)&&(identical(other.schedule, schedule) || other.schedule == schedule)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,slots,windowDays,schedule,position,createdAt,updatedAt);

@override
String toString() {
  return 'Contour(id: $id, name: $name, slots: $slots, windowDays: $windowDays, schedule: $schedule, position: $position, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ContourCopyWith<$Res>  {
  factory $ContourCopyWith(Contour value, $Res Function(Contour) _then) = _$ContourCopyWithImpl;
@useResult
$Res call({
 String id, String name, int slots, int windowDays, ContourSchedule? schedule, double position, String? createdAt, String? updatedAt
});


$ContourScheduleCopyWith<$Res>? get schedule;

}
/// @nodoc
class _$ContourCopyWithImpl<$Res>
    implements $ContourCopyWith<$Res> {
  _$ContourCopyWithImpl(this._self, this._then);

  final Contour _self;
  final $Res Function(Contour) _then;

/// Create a copy of Contour
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? slots = null,Object? windowDays = null,Object? schedule = freezed,Object? position = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,slots: null == slots ? _self.slots : slots // ignore: cast_nullable_to_non_nullable
as int,windowDays: null == windowDays ? _self.windowDays : windowDays // ignore: cast_nullable_to_non_nullable
as int,schedule: freezed == schedule ? _self.schedule : schedule // ignore: cast_nullable_to_non_nullable
as ContourSchedule?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of Contour
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContourScheduleCopyWith<$Res>? get schedule {
    if (_self.schedule == null) {
    return null;
  }

  return $ContourScheduleCopyWith<$Res>(_self.schedule!, (value) {
    return _then(_self.copyWith(schedule: value));
  });
}
}


/// Adds pattern-matching-related methods to [Contour].
extension ContourPatterns on Contour {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Contour value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Contour() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Contour value)  $default,){
final _that = this;
switch (_that) {
case _Contour():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Contour value)?  $default,){
final _that = this;
switch (_that) {
case _Contour() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int slots,  int windowDays,  ContourSchedule? schedule,  double position,  String? createdAt,  String? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Contour() when $default != null:
return $default(_that.id,_that.name,_that.slots,_that.windowDays,_that.schedule,_that.position,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int slots,  int windowDays,  ContourSchedule? schedule,  double position,  String? createdAt,  String? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Contour():
return $default(_that.id,_that.name,_that.slots,_that.windowDays,_that.schedule,_that.position,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int slots,  int windowDays,  ContourSchedule? schedule,  double position,  String? createdAt,  String? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Contour() when $default != null:
return $default(_that.id,_that.name,_that.slots,_that.windowDays,_that.schedule,_that.position,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _Contour implements Contour {
  const _Contour({required this.id, required this.name, this.slots = 2, this.windowDays = 7, this.schedule, required this.position, this.createdAt, this.updatedAt});
  factory _Contour.fromJson(Map<String, dynamic> json) => _$ContourFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey() final  int slots;
@override@JsonKey() final  int windowDays;
@override final  ContourSchedule? schedule;
/// Gapped float, `double` for the reason given on `Task.position`.
@override final  double position;
@override final  String? createdAt;
@override final  String? updatedAt;

/// Create a copy of Contour
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContourCopyWith<_Contour> get copyWith => __$ContourCopyWithImpl<_Contour>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ContourToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Contour&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.slots, slots) || other.slots == slots)&&(identical(other.windowDays, windowDays) || other.windowDays == windowDays)&&(identical(other.schedule, schedule) || other.schedule == schedule)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,slots,windowDays,schedule,position,createdAt,updatedAt);

@override
String toString() {
  return 'Contour(id: $id, name: $name, slots: $slots, windowDays: $windowDays, schedule: $schedule, position: $position, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ContourCopyWith<$Res> implements $ContourCopyWith<$Res> {
  factory _$ContourCopyWith(_Contour value, $Res Function(_Contour) _then) = __$ContourCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int slots, int windowDays, ContourSchedule? schedule, double position, String? createdAt, String? updatedAt
});


@override $ContourScheduleCopyWith<$Res>? get schedule;

}
/// @nodoc
class __$ContourCopyWithImpl<$Res>
    implements _$ContourCopyWith<$Res> {
  __$ContourCopyWithImpl(this._self, this._then);

  final _Contour _self;
  final $Res Function(_Contour) _then;

/// Create a copy of Contour
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? slots = null,Object? windowDays = null,Object? schedule = freezed,Object? position = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_Contour(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,slots: null == slots ? _self.slots : slots // ignore: cast_nullable_to_non_nullable
as int,windowDays: null == windowDays ? _self.windowDays : windowDays // ignore: cast_nullable_to_non_nullable
as int,schedule: freezed == schedule ? _self.schedule : schedule // ignore: cast_nullable_to_non_nullable
as ContourSchedule?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of Contour
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContourScheduleCopyWith<$Res>? get schedule {
    if (_self.schedule == null) {
    return null;
  }

  return $ContourScheduleCopyWith<$Res>(_self.schedule!, (value) {
    return _then(_self.copyWith(schedule: value));
  });
}
}


/// @nodoc
mixin _$ActiveContourChoice {

 String? get contourId; String? get until;
/// Create a copy of ActiveContourChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveContourChoiceCopyWith<ActiveContourChoice> get copyWith => _$ActiveContourChoiceCopyWithImpl<ActiveContourChoice>(this as ActiveContourChoice, _$identity);

  /// Serializes this ActiveContourChoice to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveContourChoice&&(identical(other.contourId, contourId) || other.contourId == contourId)&&(identical(other.until, until) || other.until == until));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,contourId,until);

@override
String toString() {
  return 'ActiveContourChoice(contourId: $contourId, until: $until)';
}


}

/// @nodoc
abstract mixin class $ActiveContourChoiceCopyWith<$Res>  {
  factory $ActiveContourChoiceCopyWith(ActiveContourChoice value, $Res Function(ActiveContourChoice) _then) = _$ActiveContourChoiceCopyWithImpl;
@useResult
$Res call({
 String? contourId, String? until
});




}
/// @nodoc
class _$ActiveContourChoiceCopyWithImpl<$Res>
    implements $ActiveContourChoiceCopyWith<$Res> {
  _$ActiveContourChoiceCopyWithImpl(this._self, this._then);

  final ActiveContourChoice _self;
  final $Res Function(ActiveContourChoice) _then;

/// Create a copy of ActiveContourChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? contourId = freezed,Object? until = freezed,}) {
  return _then(_self.copyWith(
contourId: freezed == contourId ? _self.contourId : contourId // ignore: cast_nullable_to_non_nullable
as String?,until: freezed == until ? _self.until : until // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ActiveContourChoice].
extension ActiveContourChoicePatterns on ActiveContourChoice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveContourChoice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveContourChoice() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveContourChoice value)  $default,){
final _that = this;
switch (_that) {
case _ActiveContourChoice():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveContourChoice value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveContourChoice() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? contourId,  String? until)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveContourChoice() when $default != null:
return $default(_that.contourId,_that.until);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? contourId,  String? until)  $default,) {final _that = this;
switch (_that) {
case _ActiveContourChoice():
return $default(_that.contourId,_that.until);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? contourId,  String? until)?  $default,) {final _that = this;
switch (_that) {
case _ActiveContourChoice() when $default != null:
return $default(_that.contourId,_that.until);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ActiveContourChoice implements ActiveContourChoice {
  const _ActiveContourChoice({this.contourId, this.until});
  factory _ActiveContourChoice.fromJson(Map<String, dynamic> json) => _$ActiveContourChoiceFromJson(json);

@override final  String? contourId;
@override final  String? until;

/// Create a copy of ActiveContourChoice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveContourChoiceCopyWith<_ActiveContourChoice> get copyWith => __$ActiveContourChoiceCopyWithImpl<_ActiveContourChoice>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ActiveContourChoiceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveContourChoice&&(identical(other.contourId, contourId) || other.contourId == contourId)&&(identical(other.until, until) || other.until == until));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,contourId,until);

@override
String toString() {
  return 'ActiveContourChoice(contourId: $contourId, until: $until)';
}


}

/// @nodoc
abstract mixin class _$ActiveContourChoiceCopyWith<$Res> implements $ActiveContourChoiceCopyWith<$Res> {
  factory _$ActiveContourChoiceCopyWith(_ActiveContourChoice value, $Res Function(_ActiveContourChoice) _then) = __$ActiveContourChoiceCopyWithImpl;
@override @useResult
$Res call({
 String? contourId, String? until
});




}
/// @nodoc
class __$ActiveContourChoiceCopyWithImpl<$Res>
    implements _$ActiveContourChoiceCopyWith<$Res> {
  __$ActiveContourChoiceCopyWithImpl(this._self, this._then);

  final _ActiveContourChoice _self;
  final $Res Function(_ActiveContourChoice) _then;

/// Create a copy of ActiveContourChoice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? contourId = freezed,Object? until = freezed,}) {
  return _then(_ActiveContourChoice(
contourId: freezed == contourId ? _self.contourId : contourId // ignore: cast_nullable_to_non_nullable
as String?,until: freezed == until ? _self.until : until // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ContourList {

 List<Contour> get contours; ActiveContourChoice get active;
/// Create a copy of ContourList
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContourListCopyWith<ContourList> get copyWith => _$ContourListCopyWithImpl<ContourList>(this as ContourList, _$identity);

  /// Serializes this ContourList to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContourList&&const DeepCollectionEquality().equals(other.contours, contours)&&(identical(other.active, active) || other.active == active));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(contours),active);

@override
String toString() {
  return 'ContourList(contours: $contours, active: $active)';
}


}

/// @nodoc
abstract mixin class $ContourListCopyWith<$Res>  {
  factory $ContourListCopyWith(ContourList value, $Res Function(ContourList) _then) = _$ContourListCopyWithImpl;
@useResult
$Res call({
 List<Contour> contours, ActiveContourChoice active
});


$ActiveContourChoiceCopyWith<$Res> get active;

}
/// @nodoc
class _$ContourListCopyWithImpl<$Res>
    implements $ContourListCopyWith<$Res> {
  _$ContourListCopyWithImpl(this._self, this._then);

  final ContourList _self;
  final $Res Function(ContourList) _then;

/// Create a copy of ContourList
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? contours = null,Object? active = null,}) {
  return _then(_self.copyWith(
contours: null == contours ? _self.contours : contours // ignore: cast_nullable_to_non_nullable
as List<Contour>,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as ActiveContourChoice,
  ));
}
/// Create a copy of ContourList
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActiveContourChoiceCopyWith<$Res> get active {
  
  return $ActiveContourChoiceCopyWith<$Res>(_self.active, (value) {
    return _then(_self.copyWith(active: value));
  });
}
}


/// Adds pattern-matching-related methods to [ContourList].
extension ContourListPatterns on ContourList {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContourList value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContourList() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContourList value)  $default,){
final _that = this;
switch (_that) {
case _ContourList():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContourList value)?  $default,){
final _that = this;
switch (_that) {
case _ContourList() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Contour> contours,  ActiveContourChoice active)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContourList() when $default != null:
return $default(_that.contours,_that.active);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Contour> contours,  ActiveContourChoice active)  $default,) {final _that = this;
switch (_that) {
case _ContourList():
return $default(_that.contours,_that.active);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Contour> contours,  ActiveContourChoice active)?  $default,) {final _that = this;
switch (_that) {
case _ContourList() when $default != null:
return $default(_that.contours,_that.active);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _ContourList implements ContourList {
  const _ContourList({required final  List<Contour> contours, this.active = const ActiveContourChoice()}): _contours = contours;
  factory _ContourList.fromJson(Map<String, dynamic> json) => _$ContourListFromJson(json);

 final  List<Contour> _contours;
@override List<Contour> get contours {
  if (_contours is EqualUnmodifiableListView) return _contours;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_contours);
}

@override@JsonKey() final  ActiveContourChoice active;

/// Create a copy of ContourList
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContourListCopyWith<_ContourList> get copyWith => __$ContourListCopyWithImpl<_ContourList>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ContourListToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContourList&&const DeepCollectionEquality().equals(other._contours, _contours)&&(identical(other.active, active) || other.active == active));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_contours),active);

@override
String toString() {
  return 'ContourList(contours: $contours, active: $active)';
}


}

/// @nodoc
abstract mixin class _$ContourListCopyWith<$Res> implements $ContourListCopyWith<$Res> {
  factory _$ContourListCopyWith(_ContourList value, $Res Function(_ContourList) _then) = __$ContourListCopyWithImpl;
@override @useResult
$Res call({
 List<Contour> contours, ActiveContourChoice active
});


@override $ActiveContourChoiceCopyWith<$Res> get active;

}
/// @nodoc
class __$ContourListCopyWithImpl<$Res>
    implements _$ContourListCopyWith<$Res> {
  __$ContourListCopyWithImpl(this._self, this._then);

  final _ContourList _self;
  final $Res Function(_ContourList) _then;

/// Create a copy of ContourList
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? contours = null,Object? active = null,}) {
  return _then(_ContourList(
contours: null == contours ? _self._contours : contours // ignore: cast_nullable_to_non_nullable
as List<Contour>,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as ActiveContourChoice,
  ));
}

/// Create a copy of ContourList
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActiveContourChoiceCopyWith<$Res> get active {
  
  return $ActiveContourChoiceCopyWith<$Res>(_self.active, (value) {
    return _then(_self.copyWith(active: value));
  });
}
}


/// @nodoc
mixin _$TaskGoalRef {

 String get id; String get title; String get contourId;
/// Create a copy of TaskGoalRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskGoalRefCopyWith<TaskGoalRef> get copyWith => _$TaskGoalRefCopyWithImpl<TaskGoalRef>(this as TaskGoalRef, _$identity);

  /// Serializes this TaskGoalRef to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskGoalRef&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.contourId, contourId) || other.contourId == contourId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,contourId);

@override
String toString() {
  return 'TaskGoalRef(id: $id, title: $title, contourId: $contourId)';
}


}

/// @nodoc
abstract mixin class $TaskGoalRefCopyWith<$Res>  {
  factory $TaskGoalRefCopyWith(TaskGoalRef value, $Res Function(TaskGoalRef) _then) = _$TaskGoalRefCopyWithImpl;
@useResult
$Res call({
 String id, String title, String contourId
});




}
/// @nodoc
class _$TaskGoalRefCopyWithImpl<$Res>
    implements $TaskGoalRefCopyWith<$Res> {
  _$TaskGoalRefCopyWithImpl(this._self, this._then);

  final TaskGoalRef _self;
  final $Res Function(TaskGoalRef) _then;

/// Create a copy of TaskGoalRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? contourId = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,contourId: null == contourId ? _self.contourId : contourId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskGoalRef].
extension TaskGoalRefPatterns on TaskGoalRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskGoalRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskGoalRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskGoalRef value)  $default,){
final _that = this;
switch (_that) {
case _TaskGoalRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskGoalRef value)?  $default,){
final _that = this;
switch (_that) {
case _TaskGoalRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String contourId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskGoalRef() when $default != null:
return $default(_that.id,_that.title,_that.contourId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String contourId)  $default,) {final _that = this;
switch (_that) {
case _TaskGoalRef():
return $default(_that.id,_that.title,_that.contourId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String contourId)?  $default,) {final _that = this;
switch (_that) {
case _TaskGoalRef() when $default != null:
return $default(_that.id,_that.title,_that.contourId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskGoalRef implements TaskGoalRef {
  const _TaskGoalRef({required this.id, required this.title, required this.contourId});
  factory _TaskGoalRef.fromJson(Map<String, dynamic> json) => _$TaskGoalRefFromJson(json);

@override final  String id;
@override final  String title;
@override final  String contourId;

/// Create a copy of TaskGoalRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskGoalRefCopyWith<_TaskGoalRef> get copyWith => __$TaskGoalRefCopyWithImpl<_TaskGoalRef>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskGoalRefToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskGoalRef&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.contourId, contourId) || other.contourId == contourId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,contourId);

@override
String toString() {
  return 'TaskGoalRef(id: $id, title: $title, contourId: $contourId)';
}


}

/// @nodoc
abstract mixin class _$TaskGoalRefCopyWith<$Res> implements $TaskGoalRefCopyWith<$Res> {
  factory _$TaskGoalRefCopyWith(_TaskGoalRef value, $Res Function(_TaskGoalRef) _then) = __$TaskGoalRefCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String contourId
});




}
/// @nodoc
class __$TaskGoalRefCopyWithImpl<$Res>
    implements _$TaskGoalRefCopyWith<$Res> {
  __$TaskGoalRefCopyWithImpl(this._self, this._then);

  final _TaskGoalRef _self;
  final $Res Function(_TaskGoalRef) _then;

/// Create a copy of TaskGoalRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? contourId = null,}) {
  return _then(_TaskGoalRef(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,contourId: null == contourId ? _self.contourId : contourId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$GoalTask {

 String get id; String get title; TaskStatus get status; String get projectId; String get projectName; String? get focusedAt; String? get focusContourId;/// The task's date (`design/today-history-contract.md`), when the server
/// sends it.
 String? get remindAt;
/// Create a copy of GoalTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GoalTaskCopyWith<GoalTask> get copyWith => _$GoalTaskCopyWithImpl<GoalTask>(this as GoalTask, _$identity);

  /// Serializes this GoalTask to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GoalTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.projectName, projectName) || other.projectName == projectName)&&(identical(other.focusedAt, focusedAt) || other.focusedAt == focusedAt)&&(identical(other.focusContourId, focusContourId) || other.focusContourId == focusContourId)&&(identical(other.remindAt, remindAt) || other.remindAt == remindAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,status,projectId,projectName,focusedAt,focusContourId,remindAt);

@override
String toString() {
  return 'GoalTask(id: $id, title: $title, status: $status, projectId: $projectId, projectName: $projectName, focusedAt: $focusedAt, focusContourId: $focusContourId, remindAt: $remindAt)';
}


}

/// @nodoc
abstract mixin class $GoalTaskCopyWith<$Res>  {
  factory $GoalTaskCopyWith(GoalTask value, $Res Function(GoalTask) _then) = _$GoalTaskCopyWithImpl;
@useResult
$Res call({
 String id, String title, TaskStatus status, String projectId, String projectName, String? focusedAt, String? focusContourId, String? remindAt
});




}
/// @nodoc
class _$GoalTaskCopyWithImpl<$Res>
    implements $GoalTaskCopyWith<$Res> {
  _$GoalTaskCopyWithImpl(this._self, this._then);

  final GoalTask _self;
  final $Res Function(GoalTask) _then;

/// Create a copy of GoalTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? status = null,Object? projectId = null,Object? projectName = null,Object? focusedAt = freezed,Object? focusContourId = freezed,Object? remindAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,projectName: null == projectName ? _self.projectName : projectName // ignore: cast_nullable_to_non_nullable
as String,focusedAt: freezed == focusedAt ? _self.focusedAt : focusedAt // ignore: cast_nullable_to_non_nullable
as String?,focusContourId: freezed == focusContourId ? _self.focusContourId : focusContourId // ignore: cast_nullable_to_non_nullable
as String?,remindAt: freezed == remindAt ? _self.remindAt : remindAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [GoalTask].
extension GoalTaskPatterns on GoalTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GoalTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GoalTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GoalTask value)  $default,){
final _that = this;
switch (_that) {
case _GoalTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GoalTask value)?  $default,){
final _that = this;
switch (_that) {
case _GoalTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  TaskStatus status,  String projectId,  String projectName,  String? focusedAt,  String? focusContourId,  String? remindAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GoalTask() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.projectId,_that.projectName,_that.focusedAt,_that.focusContourId,_that.remindAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  TaskStatus status,  String projectId,  String projectName,  String? focusedAt,  String? focusContourId,  String? remindAt)  $default,) {final _that = this;
switch (_that) {
case _GoalTask():
return $default(_that.id,_that.title,_that.status,_that.projectId,_that.projectName,_that.focusedAt,_that.focusContourId,_that.remindAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  TaskStatus status,  String projectId,  String projectName,  String? focusedAt,  String? focusContourId,  String? remindAt)?  $default,) {final _that = this;
switch (_that) {
case _GoalTask() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.projectId,_that.projectName,_that.focusedAt,_that.focusContourId,_that.remindAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GoalTask implements GoalTask {
  const _GoalTask({required this.id, required this.title, required this.status, required this.projectId, required this.projectName, this.focusedAt, this.focusContourId, this.remindAt});
  factory _GoalTask.fromJson(Map<String, dynamic> json) => _$GoalTaskFromJson(json);

@override final  String id;
@override final  String title;
@override final  TaskStatus status;
@override final  String projectId;
@override final  String projectName;
@override final  String? focusedAt;
@override final  String? focusContourId;
/// The task's date (`design/today-history-contract.md`), when the server
/// sends it.
@override final  String? remindAt;

/// Create a copy of GoalTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GoalTaskCopyWith<_GoalTask> get copyWith => __$GoalTaskCopyWithImpl<_GoalTask>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GoalTaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GoalTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.projectName, projectName) || other.projectName == projectName)&&(identical(other.focusedAt, focusedAt) || other.focusedAt == focusedAt)&&(identical(other.focusContourId, focusContourId) || other.focusContourId == focusContourId)&&(identical(other.remindAt, remindAt) || other.remindAt == remindAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,status,projectId,projectName,focusedAt,focusContourId,remindAt);

@override
String toString() {
  return 'GoalTask(id: $id, title: $title, status: $status, projectId: $projectId, projectName: $projectName, focusedAt: $focusedAt, focusContourId: $focusContourId, remindAt: $remindAt)';
}


}

/// @nodoc
abstract mixin class _$GoalTaskCopyWith<$Res> implements $GoalTaskCopyWith<$Res> {
  factory _$GoalTaskCopyWith(_GoalTask value, $Res Function(_GoalTask) _then) = __$GoalTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, TaskStatus status, String projectId, String projectName, String? focusedAt, String? focusContourId, String? remindAt
});




}
/// @nodoc
class __$GoalTaskCopyWithImpl<$Res>
    implements _$GoalTaskCopyWith<$Res> {
  __$GoalTaskCopyWithImpl(this._self, this._then);

  final _GoalTask _self;
  final $Res Function(_GoalTask) _then;

/// Create a copy of GoalTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? status = null,Object? projectId = null,Object? projectName = null,Object? focusedAt = freezed,Object? focusContourId = freezed,Object? remindAt = freezed,}) {
  return _then(_GoalTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,projectName: null == projectName ? _self.projectName : projectName // ignore: cast_nullable_to_non_nullable
as String,focusedAt: freezed == focusedAt ? _self.focusedAt : focusedAt // ignore: cast_nullable_to_non_nullable
as String?,focusContourId: freezed == focusContourId ? _self.focusContourId : focusContourId // ignore: cast_nullable_to_non_nullable
as String?,remindAt: freezed == remindAt ? _self.remindAt : remindAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$GoalIdea {

 String get id; String get title; String get projectId; String get projectName;
/// Create a copy of GoalIdea
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GoalIdeaCopyWith<GoalIdea> get copyWith => _$GoalIdeaCopyWithImpl<GoalIdea>(this as GoalIdea, _$identity);

  /// Serializes this GoalIdea to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GoalIdea&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.projectName, projectName) || other.projectName == projectName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,projectId,projectName);

@override
String toString() {
  return 'GoalIdea(id: $id, title: $title, projectId: $projectId, projectName: $projectName)';
}


}

/// @nodoc
abstract mixin class $GoalIdeaCopyWith<$Res>  {
  factory $GoalIdeaCopyWith(GoalIdea value, $Res Function(GoalIdea) _then) = _$GoalIdeaCopyWithImpl;
@useResult
$Res call({
 String id, String title, String projectId, String projectName
});




}
/// @nodoc
class _$GoalIdeaCopyWithImpl<$Res>
    implements $GoalIdeaCopyWith<$Res> {
  _$GoalIdeaCopyWithImpl(this._self, this._then);

  final GoalIdea _self;
  final $Res Function(GoalIdea) _then;

/// Create a copy of GoalIdea
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? projectId = null,Object? projectName = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,projectName: null == projectName ? _self.projectName : projectName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [GoalIdea].
extension GoalIdeaPatterns on GoalIdea {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GoalIdea value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GoalIdea() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GoalIdea value)  $default,){
final _that = this;
switch (_that) {
case _GoalIdea():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GoalIdea value)?  $default,){
final _that = this;
switch (_that) {
case _GoalIdea() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String projectId,  String projectName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GoalIdea() when $default != null:
return $default(_that.id,_that.title,_that.projectId,_that.projectName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String projectId,  String projectName)  $default,) {final _that = this;
switch (_that) {
case _GoalIdea():
return $default(_that.id,_that.title,_that.projectId,_that.projectName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String projectId,  String projectName)?  $default,) {final _that = this;
switch (_that) {
case _GoalIdea() when $default != null:
return $default(_that.id,_that.title,_that.projectId,_that.projectName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GoalIdea implements GoalIdea {
  const _GoalIdea({required this.id, required this.title, required this.projectId, required this.projectName});
  factory _GoalIdea.fromJson(Map<String, dynamic> json) => _$GoalIdeaFromJson(json);

@override final  String id;
@override final  String title;
@override final  String projectId;
@override final  String projectName;

/// Create a copy of GoalIdea
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GoalIdeaCopyWith<_GoalIdea> get copyWith => __$GoalIdeaCopyWithImpl<_GoalIdea>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GoalIdeaToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GoalIdea&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.projectName, projectName) || other.projectName == projectName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,projectId,projectName);

@override
String toString() {
  return 'GoalIdea(id: $id, title: $title, projectId: $projectId, projectName: $projectName)';
}


}

/// @nodoc
abstract mixin class _$GoalIdeaCopyWith<$Res> implements $GoalIdeaCopyWith<$Res> {
  factory _$GoalIdeaCopyWith(_GoalIdea value, $Res Function(_GoalIdea) _then) = __$GoalIdeaCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String projectId, String projectName
});




}
/// @nodoc
class __$GoalIdeaCopyWithImpl<$Res>
    implements _$GoalIdeaCopyWith<$Res> {
  __$GoalIdeaCopyWithImpl(this._self, this._then);

  final _GoalIdea _self;
  final $Res Function(_GoalIdea) _then;

/// Create a copy of GoalIdea
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? projectId = null,Object? projectName = null,}) {
  return _then(_GoalIdea(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,projectName: null == projectName ? _self.projectName : projectName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$GoalProgress {

 int get done; int get total;
/// Create a copy of GoalProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GoalProgressCopyWith<GoalProgress> get copyWith => _$GoalProgressCopyWithImpl<GoalProgress>(this as GoalProgress, _$identity);

  /// Serializes this GoalProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GoalProgress&&(identical(other.done, done) || other.done == done)&&(identical(other.total, total) || other.total == total));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,done,total);

@override
String toString() {
  return 'GoalProgress(done: $done, total: $total)';
}


}

/// @nodoc
abstract mixin class $GoalProgressCopyWith<$Res>  {
  factory $GoalProgressCopyWith(GoalProgress value, $Res Function(GoalProgress) _then) = _$GoalProgressCopyWithImpl;
@useResult
$Res call({
 int done, int total
});




}
/// @nodoc
class _$GoalProgressCopyWithImpl<$Res>
    implements $GoalProgressCopyWith<$Res> {
  _$GoalProgressCopyWithImpl(this._self, this._then);

  final GoalProgress _self;
  final $Res Function(GoalProgress) _then;

/// Create a copy of GoalProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? done = null,Object? total = null,}) {
  return _then(_self.copyWith(
done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GoalProgress].
extension GoalProgressPatterns on GoalProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GoalProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GoalProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GoalProgress value)  $default,){
final _that = this;
switch (_that) {
case _GoalProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GoalProgress value)?  $default,){
final _that = this;
switch (_that) {
case _GoalProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int done,  int total)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GoalProgress() when $default != null:
return $default(_that.done,_that.total);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int done,  int total)  $default,) {final _that = this;
switch (_that) {
case _GoalProgress():
return $default(_that.done,_that.total);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int done,  int total)?  $default,) {final _that = this;
switch (_that) {
case _GoalProgress() when $default != null:
return $default(_that.done,_that.total);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GoalProgress implements GoalProgress {
  const _GoalProgress({this.done = 0, this.total = 0});
  factory _GoalProgress.fromJson(Map<String, dynamic> json) => _$GoalProgressFromJson(json);

@override@JsonKey() final  int done;
@override@JsonKey() final  int total;

/// Create a copy of GoalProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GoalProgressCopyWith<_GoalProgress> get copyWith => __$GoalProgressCopyWithImpl<_GoalProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GoalProgressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GoalProgress&&(identical(other.done, done) || other.done == done)&&(identical(other.total, total) || other.total == total));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,done,total);

@override
String toString() {
  return 'GoalProgress(done: $done, total: $total)';
}


}

/// @nodoc
abstract mixin class _$GoalProgressCopyWith<$Res> implements $GoalProgressCopyWith<$Res> {
  factory _$GoalProgressCopyWith(_GoalProgress value, $Res Function(_GoalProgress) _then) = __$GoalProgressCopyWithImpl;
@override @useResult
$Res call({
 int done, int total
});




}
/// @nodoc
class __$GoalProgressCopyWithImpl<$Res>
    implements _$GoalProgressCopyWith<$Res> {
  __$GoalProgressCopyWithImpl(this._self, this._then);

  final _GoalProgress _self;
  final $Res Function(_GoalProgress) _then;

/// Create a copy of GoalProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? done = null,Object? total = null,}) {
  return _then(_GoalProgress(
done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$GoalView {

 String get id; String get contourId; String get title; String? get why;@JsonKey(unknownEnumValue: GoalState.bench) GoalState get state; String? get slottedAt;/// The window that applies (the goal's own, else its contour's).
 int get windowDays;/// The goal's own window, or null for its contour's.
 int? get ownWindowDays; String? get windowEndsAt; bool get windowExpired; String? get achievedAt; double get position; String get createdAt; List<GoalTask> get tasks; GoalTask? get nextStep; List<GoalIdea> get ideas; GoalProgress get progress;
/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GoalViewCopyWith<GoalView> get copyWith => _$GoalViewCopyWithImpl<GoalView>(this as GoalView, _$identity);

  /// Serializes this GoalView to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GoalView&&(identical(other.id, id) || other.id == id)&&(identical(other.contourId, contourId) || other.contourId == contourId)&&(identical(other.title, title) || other.title == title)&&(identical(other.why, why) || other.why == why)&&(identical(other.state, state) || other.state == state)&&(identical(other.slottedAt, slottedAt) || other.slottedAt == slottedAt)&&(identical(other.windowDays, windowDays) || other.windowDays == windowDays)&&(identical(other.ownWindowDays, ownWindowDays) || other.ownWindowDays == ownWindowDays)&&(identical(other.windowEndsAt, windowEndsAt) || other.windowEndsAt == windowEndsAt)&&(identical(other.windowExpired, windowExpired) || other.windowExpired == windowExpired)&&(identical(other.achievedAt, achievedAt) || other.achievedAt == achievedAt)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.tasks, tasks)&&(identical(other.nextStep, nextStep) || other.nextStep == nextStep)&&const DeepCollectionEquality().equals(other.ideas, ideas)&&(identical(other.progress, progress) || other.progress == progress));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,contourId,title,why,state,slottedAt,windowDays,ownWindowDays,windowEndsAt,windowExpired,achievedAt,position,createdAt,const DeepCollectionEquality().hash(tasks),nextStep,const DeepCollectionEquality().hash(ideas),progress);

@override
String toString() {
  return 'GoalView(id: $id, contourId: $contourId, title: $title, why: $why, state: $state, slottedAt: $slottedAt, windowDays: $windowDays, ownWindowDays: $ownWindowDays, windowEndsAt: $windowEndsAt, windowExpired: $windowExpired, achievedAt: $achievedAt, position: $position, createdAt: $createdAt, tasks: $tasks, nextStep: $nextStep, ideas: $ideas, progress: $progress)';
}


}

/// @nodoc
abstract mixin class $GoalViewCopyWith<$Res>  {
  factory $GoalViewCopyWith(GoalView value, $Res Function(GoalView) _then) = _$GoalViewCopyWithImpl;
@useResult
$Res call({
 String id, String contourId, String title, String? why,@JsonKey(unknownEnumValue: GoalState.bench) GoalState state, String? slottedAt, int windowDays, int? ownWindowDays, String? windowEndsAt, bool windowExpired, String? achievedAt, double position, String createdAt, List<GoalTask> tasks, GoalTask? nextStep, List<GoalIdea> ideas, GoalProgress progress
});


$GoalTaskCopyWith<$Res>? get nextStep;$GoalProgressCopyWith<$Res> get progress;

}
/// @nodoc
class _$GoalViewCopyWithImpl<$Res>
    implements $GoalViewCopyWith<$Res> {
  _$GoalViewCopyWithImpl(this._self, this._then);

  final GoalView _self;
  final $Res Function(GoalView) _then;

/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? contourId = null,Object? title = null,Object? why = freezed,Object? state = null,Object? slottedAt = freezed,Object? windowDays = null,Object? ownWindowDays = freezed,Object? windowEndsAt = freezed,Object? windowExpired = null,Object? achievedAt = freezed,Object? position = null,Object? createdAt = null,Object? tasks = null,Object? nextStep = freezed,Object? ideas = null,Object? progress = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,contourId: null == contourId ? _self.contourId : contourId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,why: freezed == why ? _self.why : why // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as GoalState,slottedAt: freezed == slottedAt ? _self.slottedAt : slottedAt // ignore: cast_nullable_to_non_nullable
as String?,windowDays: null == windowDays ? _self.windowDays : windowDays // ignore: cast_nullable_to_non_nullable
as int,ownWindowDays: freezed == ownWindowDays ? _self.ownWindowDays : ownWindowDays // ignore: cast_nullable_to_non_nullable
as int?,windowEndsAt: freezed == windowEndsAt ? _self.windowEndsAt : windowEndsAt // ignore: cast_nullable_to_non_nullable
as String?,windowExpired: null == windowExpired ? _self.windowExpired : windowExpired // ignore: cast_nullable_to_non_nullable
as bool,achievedAt: freezed == achievedAt ? _self.achievedAt : achievedAt // ignore: cast_nullable_to_non_nullable
as String?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<GoalTask>,nextStep: freezed == nextStep ? _self.nextStep : nextStep // ignore: cast_nullable_to_non_nullable
as GoalTask?,ideas: null == ideas ? _self.ideas : ideas // ignore: cast_nullable_to_non_nullable
as List<GoalIdea>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as GoalProgress,
  ));
}
/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GoalTaskCopyWith<$Res>? get nextStep {
    if (_self.nextStep == null) {
    return null;
  }

  return $GoalTaskCopyWith<$Res>(_self.nextStep!, (value) {
    return _then(_self.copyWith(nextStep: value));
  });
}/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GoalProgressCopyWith<$Res> get progress {
  
  return $GoalProgressCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}


/// Adds pattern-matching-related methods to [GoalView].
extension GoalViewPatterns on GoalView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GoalView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GoalView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GoalView value)  $default,){
final _that = this;
switch (_that) {
case _GoalView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GoalView value)?  $default,){
final _that = this;
switch (_that) {
case _GoalView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String contourId,  String title,  String? why, @JsonKey(unknownEnumValue: GoalState.bench)  GoalState state,  String? slottedAt,  int windowDays,  int? ownWindowDays,  String? windowEndsAt,  bool windowExpired,  String? achievedAt,  double position,  String createdAt,  List<GoalTask> tasks,  GoalTask? nextStep,  List<GoalIdea> ideas,  GoalProgress progress)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GoalView() when $default != null:
return $default(_that.id,_that.contourId,_that.title,_that.why,_that.state,_that.slottedAt,_that.windowDays,_that.ownWindowDays,_that.windowEndsAt,_that.windowExpired,_that.achievedAt,_that.position,_that.createdAt,_that.tasks,_that.nextStep,_that.ideas,_that.progress);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String contourId,  String title,  String? why, @JsonKey(unknownEnumValue: GoalState.bench)  GoalState state,  String? slottedAt,  int windowDays,  int? ownWindowDays,  String? windowEndsAt,  bool windowExpired,  String? achievedAt,  double position,  String createdAt,  List<GoalTask> tasks,  GoalTask? nextStep,  List<GoalIdea> ideas,  GoalProgress progress)  $default,) {final _that = this;
switch (_that) {
case _GoalView():
return $default(_that.id,_that.contourId,_that.title,_that.why,_that.state,_that.slottedAt,_that.windowDays,_that.ownWindowDays,_that.windowEndsAt,_that.windowExpired,_that.achievedAt,_that.position,_that.createdAt,_that.tasks,_that.nextStep,_that.ideas,_that.progress);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String contourId,  String title,  String? why, @JsonKey(unknownEnumValue: GoalState.bench)  GoalState state,  String? slottedAt,  int windowDays,  int? ownWindowDays,  String? windowEndsAt,  bool windowExpired,  String? achievedAt,  double position,  String createdAt,  List<GoalTask> tasks,  GoalTask? nextStep,  List<GoalIdea> ideas,  GoalProgress progress)?  $default,) {final _that = this;
switch (_that) {
case _GoalView() when $default != null:
return $default(_that.id,_that.contourId,_that.title,_that.why,_that.state,_that.slottedAt,_that.windowDays,_that.ownWindowDays,_that.windowEndsAt,_that.windowExpired,_that.achievedAt,_that.position,_that.createdAt,_that.tasks,_that.nextStep,_that.ideas,_that.progress);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _GoalView extends GoalView {
  const _GoalView({required this.id, required this.contourId, required this.title, this.why, @JsonKey(unknownEnumValue: GoalState.bench) required this.state, this.slottedAt, this.windowDays = 7, this.ownWindowDays, this.windowEndsAt, this.windowExpired = false, this.achievedAt, required this.position, required this.createdAt, final  List<GoalTask> tasks = const <GoalTask>[], this.nextStep, final  List<GoalIdea> ideas = const <GoalIdea>[], this.progress = const GoalProgress()}): _tasks = tasks,_ideas = ideas,super._();
  factory _GoalView.fromJson(Map<String, dynamic> json) => _$GoalViewFromJson(json);

@override final  String id;
@override final  String contourId;
@override final  String title;
@override final  String? why;
@override@JsonKey(unknownEnumValue: GoalState.bench) final  GoalState state;
@override final  String? slottedAt;
/// The window that applies (the goal's own, else its contour's).
@override@JsonKey() final  int windowDays;
/// The goal's own window, or null for its contour's.
@override final  int? ownWindowDays;
@override final  String? windowEndsAt;
@override@JsonKey() final  bool windowExpired;
@override final  String? achievedAt;
@override final  double position;
@override final  String createdAt;
 final  List<GoalTask> _tasks;
@override@JsonKey() List<GoalTask> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}

@override final  GoalTask? nextStep;
 final  List<GoalIdea> _ideas;
@override@JsonKey() List<GoalIdea> get ideas {
  if (_ideas is EqualUnmodifiableListView) return _ideas;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ideas);
}

@override@JsonKey() final  GoalProgress progress;

/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GoalViewCopyWith<_GoalView> get copyWith => __$GoalViewCopyWithImpl<_GoalView>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GoalViewToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GoalView&&(identical(other.id, id) || other.id == id)&&(identical(other.contourId, contourId) || other.contourId == contourId)&&(identical(other.title, title) || other.title == title)&&(identical(other.why, why) || other.why == why)&&(identical(other.state, state) || other.state == state)&&(identical(other.slottedAt, slottedAt) || other.slottedAt == slottedAt)&&(identical(other.windowDays, windowDays) || other.windowDays == windowDays)&&(identical(other.ownWindowDays, ownWindowDays) || other.ownWindowDays == ownWindowDays)&&(identical(other.windowEndsAt, windowEndsAt) || other.windowEndsAt == windowEndsAt)&&(identical(other.windowExpired, windowExpired) || other.windowExpired == windowExpired)&&(identical(other.achievedAt, achievedAt) || other.achievedAt == achievedAt)&&(identical(other.position, position) || other.position == position)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._tasks, _tasks)&&(identical(other.nextStep, nextStep) || other.nextStep == nextStep)&&const DeepCollectionEquality().equals(other._ideas, _ideas)&&(identical(other.progress, progress) || other.progress == progress));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,contourId,title,why,state,slottedAt,windowDays,ownWindowDays,windowEndsAt,windowExpired,achievedAt,position,createdAt,const DeepCollectionEquality().hash(_tasks),nextStep,const DeepCollectionEquality().hash(_ideas),progress);

@override
String toString() {
  return 'GoalView(id: $id, contourId: $contourId, title: $title, why: $why, state: $state, slottedAt: $slottedAt, windowDays: $windowDays, ownWindowDays: $ownWindowDays, windowEndsAt: $windowEndsAt, windowExpired: $windowExpired, achievedAt: $achievedAt, position: $position, createdAt: $createdAt, tasks: $tasks, nextStep: $nextStep, ideas: $ideas, progress: $progress)';
}


}

/// @nodoc
abstract mixin class _$GoalViewCopyWith<$Res> implements $GoalViewCopyWith<$Res> {
  factory _$GoalViewCopyWith(_GoalView value, $Res Function(_GoalView) _then) = __$GoalViewCopyWithImpl;
@override @useResult
$Res call({
 String id, String contourId, String title, String? why,@JsonKey(unknownEnumValue: GoalState.bench) GoalState state, String? slottedAt, int windowDays, int? ownWindowDays, String? windowEndsAt, bool windowExpired, String? achievedAt, double position, String createdAt, List<GoalTask> tasks, GoalTask? nextStep, List<GoalIdea> ideas, GoalProgress progress
});


@override $GoalTaskCopyWith<$Res>? get nextStep;@override $GoalProgressCopyWith<$Res> get progress;

}
/// @nodoc
class __$GoalViewCopyWithImpl<$Res>
    implements _$GoalViewCopyWith<$Res> {
  __$GoalViewCopyWithImpl(this._self, this._then);

  final _GoalView _self;
  final $Res Function(_GoalView) _then;

/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? contourId = null,Object? title = null,Object? why = freezed,Object? state = null,Object? slottedAt = freezed,Object? windowDays = null,Object? ownWindowDays = freezed,Object? windowEndsAt = freezed,Object? windowExpired = null,Object? achievedAt = freezed,Object? position = null,Object? createdAt = null,Object? tasks = null,Object? nextStep = freezed,Object? ideas = null,Object? progress = null,}) {
  return _then(_GoalView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,contourId: null == contourId ? _self.contourId : contourId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,why: freezed == why ? _self.why : why // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as GoalState,slottedAt: freezed == slottedAt ? _self.slottedAt : slottedAt // ignore: cast_nullable_to_non_nullable
as String?,windowDays: null == windowDays ? _self.windowDays : windowDays // ignore: cast_nullable_to_non_nullable
as int,ownWindowDays: freezed == ownWindowDays ? _self.ownWindowDays : ownWindowDays // ignore: cast_nullable_to_non_nullable
as int?,windowEndsAt: freezed == windowEndsAt ? _self.windowEndsAt : windowEndsAt // ignore: cast_nullable_to_non_nullable
as String?,windowExpired: null == windowExpired ? _self.windowExpired : windowExpired // ignore: cast_nullable_to_non_nullable
as bool,achievedAt: freezed == achievedAt ? _self.achievedAt : achievedAt // ignore: cast_nullable_to_non_nullable
as String?,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<GoalTask>,nextStep: freezed == nextStep ? _self.nextStep : nextStep // ignore: cast_nullable_to_non_nullable
as GoalTask?,ideas: null == ideas ? _self._ideas : ideas // ignore: cast_nullable_to_non_nullable
as List<GoalIdea>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as GoalProgress,
  ));
}

/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GoalTaskCopyWith<$Res>? get nextStep {
    if (_self.nextStep == null) {
    return null;
  }

  return $GoalTaskCopyWith<$Res>(_self.nextStep!, (value) {
    return _then(_self.copyWith(nextStep: value));
  });
}/// Create a copy of GoalView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GoalProgressCopyWith<$Res> get progress {
  
  return $GoalProgressCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

// dart format on
