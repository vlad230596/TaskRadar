import 'package:json_annotation/json_annotation.dart';

/// Mirrors the `TaskStatus` union in `frontend/src/lib/types.ts`, which in turn
/// mirrors the Prisma enum.
///
/// The Dart enum value names are spelled to match the wire strings exactly, so
/// `json_serializable` needs no `@JsonValue` annotations and there is no
/// second place to update when a status is added. Keep it that way.
@JsonEnum()
enum TaskStatus {
  pending,
  done,

  /// The status that carries `remindAt` -- the whole reason the native client
  /// exists (see flutter-migration-plan.md).
  blocked,
}
