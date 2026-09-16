// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'login_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LoginResult {

 bool get ok; String get token;/// Token lifetime in **seconds** (30 days).
///
/// Seconds, not milliseconds: `@fastify/jwt` / fast-jwt interpret a numeric
/// `expiresIn` as seconds, and the route echoes the same number back. Mixing
/// the two units up would produce an expiry 1000x off in either direction,
/// which is exactly the kind of bug that only shows up a month later.
 int get expiresIn;
/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoginResultCopyWith<LoginResult> get copyWith => _$LoginResultCopyWithImpl<LoginResult>(this as LoginResult, _$identity);

  /// Serializes this LoginResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoginResult&&(identical(other.ok, ok) || other.ok == ok)&&(identical(other.token, token) || other.token == token)&&(identical(other.expiresIn, expiresIn) || other.expiresIn == expiresIn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ok,token,expiresIn);

@override
String toString() {
  return 'LoginResult(ok: $ok, token: $token, expiresIn: $expiresIn)';
}


}

/// @nodoc
abstract mixin class $LoginResultCopyWith<$Res>  {
  factory $LoginResultCopyWith(LoginResult value, $Res Function(LoginResult) _then) = _$LoginResultCopyWithImpl;
@useResult
$Res call({
 bool ok, String token, int expiresIn
});




}
/// @nodoc
class _$LoginResultCopyWithImpl<$Res>
    implements $LoginResultCopyWith<$Res> {
  _$LoginResultCopyWithImpl(this._self, this._then);

  final LoginResult _self;
  final $Res Function(LoginResult) _then;

/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ok = null,Object? token = null,Object? expiresIn = null,}) {
  return _then(_self.copyWith(
ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,expiresIn: null == expiresIn ? _self.expiresIn : expiresIn // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [LoginResult].
extension LoginResultPatterns on LoginResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LoginResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LoginResult value)  $default,){
final _that = this;
switch (_that) {
case _LoginResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LoginResult value)?  $default,){
final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool ok,  String token,  int expiresIn)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
return $default(_that.ok,_that.token,_that.expiresIn);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool ok,  String token,  int expiresIn)  $default,) {final _that = this;
switch (_that) {
case _LoginResult():
return $default(_that.ok,_that.token,_that.expiresIn);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool ok,  String token,  int expiresIn)?  $default,) {final _that = this;
switch (_that) {
case _LoginResult() when $default != null:
return $default(_that.ok,_that.token,_that.expiresIn);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LoginResult extends LoginResult {
  const _LoginResult({required this.ok, required this.token, required this.expiresIn}): super._();
  factory _LoginResult.fromJson(Map<String, dynamic> json) => _$LoginResultFromJson(json);

@override final  bool ok;
@override final  String token;
/// Token lifetime in **seconds** (30 days).
///
/// Seconds, not milliseconds: `@fastify/jwt` / fast-jwt interpret a numeric
/// `expiresIn` as seconds, and the route echoes the same number back. Mixing
/// the two units up would produce an expiry 1000x off in either direction,
/// which is exactly the kind of bug that only shows up a month later.
@override final  int expiresIn;

/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoginResultCopyWith<_LoginResult> get copyWith => __$LoginResultCopyWithImpl<_LoginResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LoginResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoginResult&&(identical(other.ok, ok) || other.ok == ok)&&(identical(other.token, token) || other.token == token)&&(identical(other.expiresIn, expiresIn) || other.expiresIn == expiresIn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ok,token,expiresIn);

@override
String toString() {
  return 'LoginResult(ok: $ok, token: $token, expiresIn: $expiresIn)';
}


}

/// @nodoc
abstract mixin class _$LoginResultCopyWith<$Res> implements $LoginResultCopyWith<$Res> {
  factory _$LoginResultCopyWith(_LoginResult value, $Res Function(_LoginResult) _then) = __$LoginResultCopyWithImpl;
@override @useResult
$Res call({
 bool ok, String token, int expiresIn
});




}
/// @nodoc
class __$LoginResultCopyWithImpl<$Res>
    implements _$LoginResultCopyWith<$Res> {
  __$LoginResultCopyWithImpl(this._self, this._then);

  final _LoginResult _self;
  final $Res Function(_LoginResult) _then;

/// Create a copy of LoginResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ok = null,Object? token = null,Object? expiresIn = null,}) {
  return _then(_LoginResult(
ok: null == ok ? _self.ok : ok // ignore: cast_nullable_to_non_nullable
as bool,token: null == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String,expiresIn: null == expiresIn ? _self.expiresIn : expiresIn // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
