import 'package:freezed_annotation/freezed_annotation.dart';

import 'project.dart';
import 'task.dart';

part 'board_project.freezed.dart';

/// One element of the `GET /board` response: a project together with its tasks.
///
/// ## Why this composes [Project] instead of repeating its fields
///
/// `backend/src/routes/board.ts` is explicit that each row is "exactly the shape
/// `GET /projects` returns, with a `tasks` array added", precisely so the client
/// can keep one `Project` model rather than a board-flavoured twin that drifts.
/// Holding a [Project] makes that guarantee structural: if the project shape
/// changes, there is only one model to change, and a `BoardProject` can be
/// handed to anything that wants a plain project.
///
/// ## Why the JSON is hand-written
///
/// The wire format is *flat* -- `tasks` sits next to `id`/`name`, it is not
/// nested under a `project` key -- so the generated codec for this shape would
/// be wrong. Both directions are written here, and they are deliberately
/// symmetric: F2 caches the last good board as a JSON snapshot on disk, and a
/// `toJson` that nested what `fromJson` expects flat would produce a snapshot
/// that only fails to load later, on a device, with no network to fall back on.
@freezed
abstract class BoardProject with _$BoardProject {
  const factory BoardProject({
    required Project project,
    required List<Task> tasks,
  }) = _BoardProject;

  const BoardProject._();

  /// Parses one board row.
  ///
  /// Declared as a static method rather than a `factory` on purpose: a
  /// `factory fromJson` is how freezed decides to generate a json_serializable
  /// codec, which is exactly what must not happen here.
  ///
  /// `Project.fromJson` ignores the extra `tasks` key (json_serializable skips
  /// unknown fields by default), so the flat object can be fed to it as-is.
  static BoardProject fromJson(Map<String, dynamic> json) {
    // The server always sends `tasks`, as `[]` for an empty project rather than
    // omitting the key. Tolerating a missing key anyway is cheap insurance: a
    // board that renders one project without its tasks beats a board that
    // throws and shows nothing.
    final rawTasks = json['tasks'] as List<dynamic>? ?? const <dynamic>[];

    return BoardProject(
      project: Project.fromJson(json),
      tasks: List<Task>.unmodifiable(
        rawTasks.map((dynamic e) => Task.fromJson(e as Map<String, dynamic>)),
      ),
    );
  }

  /// Parses the whole `GET /board` body, which is a bare array rather than an
  /// envelope object (again see `backend/src/routes/board.ts`). Order is
  /// significant and preserved: projects by `createdAt` ascending, tasks by
  /// `position` ascending.
  static List<BoardProject> listFromJson(List<dynamic> json) {
    return List<BoardProject>.unmodifiable(
      json.map((dynamic e) => BoardProject.fromJson(e as Map<String, dynamic>)),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    ...project.toJson(),
    'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
  };

  /// The project's current task, or null if everything is done or blocked.
  ///
  /// Reads the server's flag instead of re-deriving "first task that is neither
  /// done nor blocked". The rule lives in `backend/src/domain/isCurrent.ts` and
  /// is covered by backend tests; a second implementation here would be a second
  /// thing to keep in sync for no benefit.
  Task? get currentTask {
    for (final task in tasks) {
      if (task.isCurrent) return task;
    }
    return null;
  }
}
