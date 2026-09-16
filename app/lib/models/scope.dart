import 'package:freezed_annotation/freezed_annotation.dart';

part 'scope.freezed.dart';
part 'scope.g.dart';

/// A space projects live in -- "work at company A", "home", "the dacha" -- as
/// `GET /scopes` returns it (F7).
///
/// ## What a scope is for
///
/// `../../../README.md` builds the product around a board you take in at a
/// glance and states its own limit out loud: 10-15 projects fit on one screen.
/// A scope is what keeps that true once the projects belong to unrelated parts
/// of a life. It partitions the **board**, not a list -- the board shows exactly
/// one scope at a time, which is why a project has exactly one scope and why
/// `Project.scopeId` is not nullable.
///
/// It is deliberately *not* the "потоки/направления" idea that the README keeps
/// deferring: that one would group tasks **inside** a project and is still
/// deferred. A scope changes nothing about what a project is.
///
/// Timestamps stay `String` for the same reason as everywhere else in this
/// client -- see the long note on [Project].
@freezed
abstract class Scope with _$Scope {
  const factory Scope({
    required String id,
    required String name,

    /// Server-assigned ordering key across scopes, the same gapped-float scheme
    /// as `Task.position` -- and `double` for the same reason: the server
    /// bisects the gap between two neighbours, so a few reorders into one slot
    /// produce a fractional value that an `int` would silently truncate. See
    /// the long note on [Task.position].
    ///
    /// Nothing here ever re-sorts by it. List order is the server's order
    /// (`GET /scopes` sorts by position); this field is read for diagnostics
    /// and for nothing else.
    required double position,
    required String createdAt,
    required String updatedAt,
  }) = _Scope;

  factory Scope.fromJson(Map<String, dynamic> json) => _$ScopeFromJson(json);
}
