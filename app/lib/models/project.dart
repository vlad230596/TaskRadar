import 'package:freezed_annotation/freezed_annotation.dart';

part 'project.freezed.dart';
part 'project.g.dart';

/// A TaskRadar project, exactly as `GET /projects` returns it.
///
/// Port of the `Project` interface in `frontend/src/lib/types.ts`.
///
/// ## Why the timestamps are `String` and not `DateTime`
///
/// Dates travel over JSON as ISO-8601 strings, and this client keeps them that
/// way rather than parsing them into `DateTime` at the edge. That is a deliberate
/// choice, not laziness:
///
/// `Task.remindAt` is a *calendar date* stored as UTC midnight of that date, and
/// `frontend/src/lib/reminders.ts` documents at length why it must be compared
/// by its `YYYY-MM-DD` prefix rather than as a moment in time -- parse it into a
/// local `DateTime` and the effective date shifts by a day for any user west of
/// UTC. The plan calls for porting that logic verbatim in F2. Storing the raw
/// string on the model keeps the prefix available and makes the wrong thing
/// (`someDate.day`) require an explicit parse, which is a good speed bump.
///
/// The same representation is used for every timestamp so there is one rule
/// instead of two, and so the model round-trips byte-for-byte through the F2
/// board snapshot cache without a converter in the middle.
@freezed
abstract class Project with _$Project {
  const factory Project({
    required String id,
    required String name,

    /// Null means "active". Non-null is the ISO instant it was archived at.
    required String? archivedAt,
    required String createdAt,
    required String updatedAt,
  }) = _Project;

  factory Project.fromJson(Map<String, dynamic> json) => _$ProjectFromJson(json);
}
