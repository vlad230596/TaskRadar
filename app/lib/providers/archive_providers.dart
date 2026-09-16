import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/board_project.dart';
import '../models/project.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'archive_providers.g.dart';

/// The archive, and the four writes that move a project between the board, the
/// archive and nothing at all (F4).
///
/// ## Why archive and delete are two different things
///
/// Copied from Trello on purpose -- `../../project-tracker-brief.md` records the
/// observation and the decision. An archive is reversible and is the move you
/// make constantly ("this one is done for now"); a delete is irreversible and is
/// the move you make twice a year. Collapsing them into one button means the
/// frequent gesture and the unrecoverable one are the same gesture.
///
/// The backend enforces the ordering rather than trusting the UI:
/// `canHardDeleteProject` (`backend/src/domain/projectDeleteGuard.ts`) answers
/// 409 for a project that is still active, so `DELETE /projects/:id` is only
/// ever reachable *through* the archive. This file mirrors that in the client so
/// the refusal is instant and legible, but the guard itself stays on the server,
/// where no client can skip it.
///
/// ## Why these invalidate the board instead of splicing it
///
/// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
/// write inside a project: the row is still there, only its tasks changed. These
/// four change **which rows exist**, on both boards at once, and there is no
/// splice that can express "this project is now on the other board". So they
/// invalidate, which costs one `GET /board` per archive/unarchive/delete -- an
/// action a person performs a handful of times a week.
///
/// That invalidation is also what re-arms the alarms, with no scheduler call
/// anywhere: the refreshed board no longer contains the archived project's
/// blocked tasks, `boardReminderBridge` publishes the smaller target set, and
/// the scheduler cancels what is no longer wanted. An archived project must stop
/// nagging -- that is the point of archiving it -- and this is the only place
/// that has to be true for it to happen.

/// `GET /board?archived=true` -- the archive, in the same shape as the board.
///
/// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
/// app's home. Letting it dispose means re-opening it re-reads, which is what
/// you want from a list whose whole purpose is to be acted on.
///
/// No snapshot and no cache. The archive is never the thing you need at 09:00
/// with no signal, and a second cache file to keep in step would be pure cost.
@Riverpod(retry: noAutomaticRetry)
Future<List<BoardProject>> archivedBoard(Ref ref) =>
    ref.watch(boardApiProvider).fetchBoard(archived: true);

/// Create, archive, unarchive, delete.
///
/// A notifier with no state of its own: the state these produce lives in the two
/// board providers, and giving this one a copy would be a second source of truth
/// for "which projects exist". Every method throws on failure -- the caller (a
/// button) turns that into a message, exactly as the task writes do.
@Riverpod(keepAlive: true)
class ProjectLifecycle extends _$ProjectLifecycle {
  @override
  void build() {}

  /// `POST /projects`, then refresh the board so the new column appears.
  ///
  /// Returns the created project so the caller can navigate straight into it --
  /// a project created from the board is empty, and the next thing anyone does
  /// is type its first task.
  Future<Project> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a project needs a name');
    }

    final project = await ref
        .read(projectApiProvider)
        .createProject(name: trimmed);

    // Not spliced in by hand. `GET /board` orders by `createdAt` ascending and
    // a board row carries a `tasks` array; inventing one here would mean
    // guessing at both, and the new project is the one case where a full
    // refresh is unarguably cheap -- nothing else is on screen yet.
    ref.invalidate(boardProvider);
    return project;
  }

  /// `POST /projects/:id/archive`. Reversible; the project leaves the board and
  /// its reminders stop.
  Future<void> archive(String projectId) async {
    await ref.read(projectApiProvider).archiveProject(projectId);
    _refreshBothBoards();
  }

  /// `POST /projects/:id/unarchive`. The project comes back, and so do its
  /// reminders -- including, deliberately, ones whose date has already passed:
  /// those show as a due badge on the board rather than firing an alarm for a
  /// day that is gone (see `reminderFireTime`).
  Future<void> unarchive(String projectId) async {
    await ref.read(projectApiProvider).unarchiveProject(projectId);
    _refreshBothBoards();
  }

  /// `DELETE /projects/:id`, with its tasks and its notes. There is no undo.
  ///
  /// Refuses an active project **without a request**. The server would answer
  /// 409 anyway, and relying on that would be fine for correctness -- but "the
  /// project must be archived first" is a rule the user should meet as a
  /// disabled action, not as an error message after a round trip, and a client
  /// that can state the rule can also state it before asking.
  Future<void> delete(Project project) async {
    if (project.archivedAt == null) {
      throw StateError(
        'project ${project.id} is not archived; archive it before deleting',
      );
    }

    await ref.read(projectApiProvider).deleteProject(project.id);
    _refreshBothBoards();
  }

  /// Both, always. A project only ever moves *between* them, so refreshing one
  /// leaves the other showing a row that is now in two places or in none.
  void _refreshBothBoards() {
    ref.invalidate(boardProvider);
    ref.invalidate(archivedBoardProvider);
  }
}

/// Finds the project a task belongs to, by scanning board rows.
///
/// ## Why this is how a notification deep link resolves its project
///
/// The reminder payload carries `task:<id>` and nothing else (F1 fixed that
/// format), while the project route needs a `projectId`. The obvious fix would
/// be a `GET /tasks/:id` -- **and the backend does not have one.** There is no
/// route anywhere that answers a question about a task by id alone
/// (`backend/src/routes/tasks.ts`); every read goes through a project. So the
/// mapping has to come from data the client already holds or can fetch as a
/// board.
///
/// That turns out to be the better answer anyway, because it is the one that
/// works with no network: the board snapshot on disk holds tasks, which is half
/// the reason it holds tasks at all, so a reminder tapped in a basement still
/// opens the right project.
///
/// Widening the payload to `task:<id>:<projectId>` was the other candidate and
/// was rejected: a payload is written when the alarm is armed and read up to
/// weeks later, so an embedded project id is a cached copy that can go stale
/// silently -- exactly the class of bug that a board lookup cannot have, because
/// the board is the current truth by construction.
String? projectIdForTask(Iterable<BoardProject> rows, String taskId) {
  for (final row in rows) {
    for (final task in row.tasks) {
      if (task.id == taskId) return row.project.id;
    }
  }
  return null;
}

/// The rows currently on screen, whatever their source, or null if there are
/// none yet. Cache counts: see [projectIdForTask].
List<BoardProject>? boardRowsOrNull(BoardView view) =>
    view is BoardReady ? view.projects : null;
