import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/board_project.dart';
import '../models/project.dart';
import 'board_providers.dart';
import 'dependencies.dart';
import 'project_providers.dart';

part 'archive_providers.g.dart';

/// The archive, the four writes that move a project between the board, the
/// archive and nothing at all (F4), and the rename that moves it nowhere (B6).
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
/// ## Why some of these invalidate the board and one of them splices it
///
/// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
/// write inside a project: the row is still there, only its tasks changed.
/// Create, archive, unarchive and delete change **which rows exist**, on both
/// boards at once, and there is no splice that can express "this project is now
/// on the other board". So they invalidate, which costs one `GET /board` per
/// action -- something a person does a handful of times a week.
///
/// [ProjectLifecycle.rename] is the opposite case and therefore takes the
/// opposite route: the row stays exactly where it is and one string in it
/// changes, so it is spliced into whichever lists are on screen
/// ([Board.applyProject], [ArchivedBoard.applyProject],
/// [ProjectHeader.applyProject]) and costs no read at all.
///
/// Either way the alarms follow, with no scheduler call anywhere: whatever
/// changes the board -- an invalidation or a splice -- changes the target set,
/// `boardReminderBridge` publishes it, and `reminderSync` re-arms. An archived
/// project stops nagging because its blocked tasks are no longer on the board
/// (that is what archiving *means*), and a renamed project's alarms start saying
/// the new name because the notification text carries it.

/// `GET /board?archived=true` -- the archive, in the same shape as the board.
///
/// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
/// app's home. Letting it dispose means re-opening it re-reads, which is what
/// you want from a list whose whole purpose is to be acted on.
///
/// No snapshot and no cache. The archive is never the thing you need at 09:00
/// with no signal, and a second cache file to keep in step would be pure cost.
///
/// A notifier rather than a plain future provider only because of [applyProject]
/// -- renaming a project from this screen has to show up in it without paying
/// for a second `GET /board?archived=true`.
@Riverpod(retry: noAutomaticRetry)
class ArchivedBoard extends _$ArchivedBoard {
  @override
  Future<List<BoardProject>> build() =>
      ref.watch(boardApiProvider).fetchBoard(archived: true);

  /// Splices a project's own row into the archive already on screen, the way
  /// [Board.applyProject] does it for the board.
  ///
  /// Only a rename reaches this. Archiving and unarchiving change *which rows
  /// exist* on two lists at once and still invalidate both, because no splice can
  /// express "this project is now on the other board".
  void applyProject(Project project) {
    final current = state.value;
    if (current == null) return;

    var found = false;
    final rows = <BoardProject>[
      for (final row in current)
        if (row.project.id == project.id)
          () {
            found = true;
            return row.copyWith(project: project);
          }()
        else
          row,
    ];

    // The usual case when a rename comes from the project screen: the project is
    // active, so it is not in the archive at all.
    if (!found) return;

    state = AsyncData(List<BoardProject>.unmodifiable(rows));
  }
}

/// Create, rename, archive, unarchive, delete: every write a *project* has.
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
  ///
  /// [scopeId] is the scope the board was showing when the button was pressed
  /// (F7). It is optional here only because the server has its own fallback --
  /// the first scope -- and a caller with no board in front of it (a test, a
  /// future quick-capture entry point) should not have to invent one.
  Future<Project> create(String name, {String? scopeId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a project needs a name');
    }

    return _enqueue(() async {
      final project = await ref
          .read(projectApiProvider)
          .createProject(name: trimmed, scopeId: scopeId);

      // Not spliced in by hand. `GET /board` orders by `createdAt` ascending and
      // a board row carries a `tasks` array; inventing one here would mean
      // guessing at both, and the new project is the one case where a full
      // refresh is unarguably cheap -- nothing else is on screen yet.
      ref.invalidate(boardProvider);
      return project;
    });
  }

  /// `PATCH /projects/:id` -- the only field a project has.
  ///
  /// ## Optimistic, spliced, and not a board reload
  ///
  /// The name is shown in three places at once (the board card, the project
  /// screen's app bar, the archive row), and it is a string the user just
  /// typed, so it appears everywhere immediately and is put back everywhere if
  /// the server refuses -- the same contract as every task write, and the same
  /// reason: there is no offline editing here, so an optimistic update is a
  /// prediction with a one-round-trip lifetime, never a queued edit.
  ///
  /// Both halves go through [_publishProject], which **splices** rather than
  /// invalidating. A rename changes one string in one row and cannot move a
  /// task, change `isCurrent`, or add or remove a project from either list, so
  /// the `GET /board` that archive/unarchive/delete pay for would buy nothing
  /// here. What it *does* change is the text of any alarm armed for that
  /// project's tasks (`TaskReminder.projectName`), and that follows for free
  /// from the spliced board without a scheduler call -- rule 3 in
  /// `project_providers.dart`.
  ///
  /// ## Renaming an archived project is allowed
  ///
  /// The server permits it deliberately (`backend/src/routes/projects.ts`, B6 in
  /// `../../../flutter-migration-plan.md`): the archive screen is precisely where
  /// a badly named old project is met, and the alternative is an
  /// unarchive/rename/re-archive dance that writes `archivedAt` twice to change
  /// a name. `archivedAt` is not in the payload, so this cannot move a project
  /// between the board and the archive as a side effect.
  Future<void> rename(Project project, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a project needs a name');
    }
    // The server would answer 200 and change nothing; not asking is cheaper and
    // keeps "закрыл диалог, ничего не трогая" from writing to the network.
    if (trimmed == project.name) return Future<void>.value();

    return _enqueue(() async {
      _publishProject(project.copyWith(name: trimmed));

      try {
        final saved = await ref
            .read(projectApiProvider)
            .renameProject(project.id, name: trimmed);
        // The server's row, not the guess: it carries the authoritative
        // `updatedAt`, and the trim is the server's to perform.
        _publishProject(saved);
      } catch (error) {
        // Rollback to the row this started from -- which the queue guarantees is
        // still the row on screen. See [_enqueue].
        _publishProject(project);
        rethrow;
      }
    });
  }

  /// `PATCH /projects/:id` with the other field it has (F7): which scope the
  /// project lives in.
  ///
  /// Optimistic and spliced, exactly like [rename], and for exactly the same
  /// reason: the row does not appear or disappear anywhere, it changes one
  /// string. A move cannot touch task order, `isCurrent`, `archivedAt` or the
  /// notes, so there is nothing a `GET /board` would correct.
  ///
  /// The visible effect is that the project leaves the board *currently on
  /// screen* if it was moved elsewhere -- but that is the scope filter
  /// (`projectsInScope`) reacting to data that is already correct, not a
  /// refetch.
  Future<void> moveToScope(Project project, String scopeId) {
    if (scopeId == project.scopeId) return Future<void>.value();

    return _enqueue(() async {
      _publishProject(project.copyWith(scopeId: scopeId));

      try {
        final saved = await ref
            .read(projectApiProvider)
            .moveProjectToScope(project.id, scopeId: scopeId);
        _publishProject(saved);
      } catch (error) {
        _publishProject(project);
        rethrow;
      }
    });
  }

  /// `POST /projects/:id/archive`. Reversible; the project leaves the board and
  /// its reminders stop.
  Future<void> archive(String projectId) {
    return _enqueue(() async {
      await ref.read(projectApiProvider).archiveProject(projectId);
      _refreshBothBoards();
    });
  }

  /// `POST /projects/:id/unarchive`. The project comes back, and so do its
  /// reminders -- including, deliberately, ones whose date has already passed:
  /// those show as a due badge on the board rather than firing an alarm for a
  /// day that is gone (see `reminderFireTime`).
  Future<void> unarchive(String projectId) {
    return _enqueue(() async {
      await ref.read(projectApiProvider).unarchiveProject(projectId);
      _refreshBothBoards();
    });
  }

  /// `DELETE /projects/:id`, with its tasks and its notes. There is no undo.
  ///
  /// Refuses an active project **without a request**. The server would answer
  /// 409 anyway, and relying on that would be fine for correctness -- but "the
  /// project must be archived first" is a rule the user should meet as a
  /// disabled action, not as an error message after a round trip, and a client
  /// that can state the rule can also state it before asking.
  Future<void> delete(Project project) {
    if (project.archivedAt == null) {
      throw StateError(
        'project ${project.id} is not archived; archive it before deleting',
      );
    }

    return _enqueue(() async {
      await ref.read(projectApiProvider).deleteProject(project.id);
      _refreshBothBoards();
    });
  }

  /// Both, always. A project only ever moves *between* them, so refreshing one
  /// leaves the other showing a row that is now in two places or in none.
  void _refreshBothBoards() {
    ref.invalidate(boardProvider);
    ref.invalidate(archivedBoardProvider);
  }

  /// Shows one project row everywhere it is currently on screen, without a
  /// single request.
  ///
  /// `exists` before `read(...notifier)` is the point of this method.
  /// `ref.read(p.notifier)` **creates** a provider that is not alive, and both
  /// of these fetch on creation: renaming from the project screen would spin up
  /// the archive and fetch `GET /board?archived=true` for a list nobody has
  /// opened, and renaming from the archive would do the same to the board. A
  /// provider that does not exist has nothing stale to correct, so skipping it
  /// is not a compromise.
  void _publishProject(Project project) {
    if (ref.exists(boardProvider)) {
      ref.read(boardProvider.notifier).applyProject(project);
    }
    if (ref.exists(archivedBoardProvider)) {
      ref.read(archivedBoardProvider.notifier).applyProject(project);
    }
    // The project screen, when it is the screen the rename came from. Its header
    // is a one-shot read of the board row (see [ProjectHeader]), so it is the
    // one place that cannot pick the change up by watching.
    final header = projectHeaderProvider(project.id);
    if (ref.exists(header)) {
      ref.read(header.notifier).applyProject(project);
    }
  }

  /// Serialises project writes, for the same reason `ProjectTasks` serialises
  /// task writes: an optimistic rollback is only well defined against a known
  /// "before", and two overlapping writes do not have one -- the second would
  /// capture the first's *prediction* as its rollback target and restore a name
  /// that was never saved.
  ///
  /// Only [rename] is optimistic today; the others are here so that an archive
  /// and a rename cannot interleave into "renamed a project that had already
  /// left this list". The queue keeps its own copy of the failure so one refused
  /// write does not poison the next, while the caller still gets the error to
  /// show.
  Future<void> _pending = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final chained = _pending.then<T>(
      (_) => action(),
      onError: (Object _) => action(),
    );
    _pending = chained.then<void>((_) {}).catchError((Object _) {});
    return chained;
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
