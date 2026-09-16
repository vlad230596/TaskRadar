import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_status.dart';

part 'task.freezed.dart';
part 'task.g.dart';

/// A task inside a project, as returned by `GET /projects/:projectId/tasks` and
/// (identically) inside each element of `GET /board`.
///
/// Port of the `Task` interface in `frontend/src/lib/types.ts`. See the comment
/// on [Project] for why the timestamps stay ISO strings.
@freezed
abstract class Task with _$Task {
  const factory Task({
    required String id,
    required String projectId,
    required String title,
    required String? description,
    required TaskStatus status,

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
    required double position,

    /// Calendar date (stored server-side as UTC midnight) to be reminded about a
    /// `blocked` task. Only ever compare this by its `YYYY-MM-DD` prefix -- see
    /// the note on [Project] and `frontend/src/lib/reminders.ts`.
    required String? remindAt,
    required String createdAt,
    required String updatedAt,

    /// Computed by the server, never stored: the first task in `position` order
    /// that is neither done nor blocked.
    ///
    /// It is a property of the *list*, not of the row, so it is only meaningful
    /// in a response that carried the project's whole task list. The client must
    /// not try to recompute or patch it locally after a mutation -- re-read the
    /// affected project instead.
    required bool isCurrent,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}
