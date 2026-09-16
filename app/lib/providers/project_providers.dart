import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_exception.dart';
import '../api/patch_field.dart';
import '../api/project_api.dart';
import '../domain/task_reorder.dart';
import '../models/board_project.dart';
import '../models/note.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'project_providers.g.dart';

/// The project screen's state (F3): one project, its tasks, its notes, and
/// every write in the application.
///
/// ## The three rules this file is built around
///
/// The migration plan fixes three properties that a mutation path is very good
/// at breaking, so they are restated here where the breaking would happen:
///
/// 1. **The server computes `isCurrent`; the client never re-derives it.** The
///    rule ("the first `pending` task in `position` order") is three lines long
///    and lives in `backend/src/domain/isCurrent.ts` -- which is exactly why
///    reimplementing it is tempting and wrong. It is a property of the whole
///    ordered list, and a second copy of it would drift the first time the
///    backend gains a status, an archived flag, or a scope.
///
/// 2. **The cache is read-only; every write needs the network.** There is no
///    operation queue and no conflict resolution. An optimistic update is a
///    *prediction shown for one round trip*, not an offline edit: when the write
///    fails the prediction is rolled back and the failure is said out loud.
///
/// 3. **Changing the reminder target set *is* the reschedule.** Nothing in this
///    file mentions the scheduler. Writes flow into the board (see
///    [Board.applyProjectTasks]) and `boardReminderBridge` does the rest,
///    because a second place that remembers to re-arm alarms is a second place
///    that can forget.
///
/// ## What "reconcile" means, and why most writes do one
///
/// `POST /projects/:id/tasks`, `PATCH /tasks/:id` and `PATCH /tasks/:id/position`
/// each answer with a single raw row: no `isCurrent`, and -- for a move -- no
/// word about the *other* rows the server may have renumbered when the float gap
/// between two neighbours ran out (see `ProjectApi`, and
/// `backend/src/domain/position.ts`). So any mutation that can move the "first
/// pending task" around, or that can trigger a rebalance, ends with one
/// `GET /projects/:id/tasks`: the cheapest question whose answer is complete.
///
/// That is one extra request for a create, a status change, a delete or a move,
/// and **zero** for a title or description edit (which provably change neither
/// the order nor which task is current -- see [mergeMutatedTask]) and zero for
/// anything to do with notes. The board is then updated from the very same
/// response instead of being refetched, so a write costs at most two round
/// trips total, never a board reload on top.

// --- reading ----------------------------------------------------------------

/// The project's own row.
///
/// ## Why this usually costs nothing
///
/// A board row is `GET /projects/:id`'s answer with the tasks attached
/// (`backend/src/routes/board.ts`), so when the board is loaded -- which is
/// every time the user got here by tapping a card -- the project is already in
/// memory and asking the server again would be asking a question we hold the
/// answer to. The fetch is for the other entry point: F4's notification deep
/// link, which can land here on a cold start with nothing loaded.
///
/// `ref.read` rather than `ref.watch` on the board: the only field anyone reads
/// off this is `name`, and there is no endpoint that can rename a project, so a
/// later board refresh has nothing to tell us. Watching would rebuild this
/// provider on every board tick for no change at all.
///
/// A 404 (deleted, or archived -- `getActiveProjectOrThrow` makes no
/// distinction) is not caught: [projectView] turns it into [ProjectMissing].
@Riverpod(retry: noAutomaticRetry)
Future<Project> projectHeader(Ref ref, String projectId) async {
  final cached = _boardRow(ref.read(boardViewProvider), projectId);
  if (cached != null) return cached.project;

  return ref.watch(projectApiProvider).fetchProject(projectId);
}

/// One project's tasks, and every write that touches them.
@Riverpod(retry: noAutomaticRetry)
class ProjectTasks extends _$ProjectTasks {
  @override
  Future<List<Task>> build(String projectId) =>
      ref.watch(projectApiProvider).fetchTasks(projectId);

  ProjectApi get _api => ref.read(projectApiProvider);

  /// Pull-to-refresh and the retry button. Returns normally on failure for the
  /// same reason [Board.refresh] does -- the gesture's future only drives a
  /// spinner, and the failure belongs on screen.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Task refresh failed: $error');
    }
  }

  // --- writes ---------------------------------------------------------------

  /// Inline creation -- the fast path this screen is designed around.
  ///
  /// The optimistic row carries a `local:` id and a guessed position, both of
  /// which the reconcile throws away. It does **not** guess `isCurrent`: a new
  /// task may or may not become the current one (it does exactly when nothing
  /// ahead of it is `pending`), and that is the server's call, so the row shows
  /// as not-current for one round trip rather than flickering the highlight onto
  /// the wrong row.
  Future<void> create(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return Future<void>.value();

    return _mutate((rows) {
      return _MutationPlan(
        optimistic: <Task>[...rows, _optimisticTask(trimmed, rows)],
        send: () async {
          await _api.createTask(projectId: projectId, title: trimmed);
          return null; // reconcile: the new row may be the current one now
        },
      );
    });
  }

  /// Moves a task between `pending` / `done` / `blocked`.
  ///
  /// Leaving `blocked` clears `remindAt`, which is the one place in F3 that uses
  /// [PatchField.clear] in anger. The reasoning is the React client's
  /// (`TaskListItem.handleStatusChange`) and still holds: a reminder date only
  /// means something while the task is actually waiting on something. Kept
  /// invisibly (the date is only shown for a blocked task), a stale one would
  /// resurface as an alarm the next time the task was blocked, on a day the user
  /// never chose. Note the asymmetry -- entering `blocked` keeps whatever date
  /// is there, because F4 owns setting it and must not have F3 wiping it first.
  ///
  /// `description` is left as [PatchField.keep], which is the whole point of
  /// that type: a status change must not touch the description, and the way to
  /// not touch it is to omit the key.
  Future<void> setStatus(Task task, TaskStatus status) {
    if (task.status == status) return Future<void>.value();

    return _mutate((rows) {
      final index = rows.indexWhere((row) => row.id == task.id);
      if (index < 0) return null;

      final leavingBlocked =
          rows[index].status == TaskStatus.blocked &&
          status != TaskStatus.blocked;

      return _MutationPlan(
        optimistic: _replaceAt(
          rows,
          index,
          rows[index].copyWith(
            status: status,
            remindAt: leavingBlocked ? null : rows[index].remindAt,
            // The one optimistic touch of `isCurrent` anywhere, and it is a
            // weakening, never an invention: a task that is not `pending`
            // cannot be current, so dropping the highlight is knowledge, not a
            // guess. Which task gains it instead is the reconcile's answer.
            isCurrent: rows[index].isCurrent && status == TaskStatus.pending,
          ),
        ),
        send: () async {
          await _api.updateTask(
            task.id,
            status: status,
            remindAt: leavingBlocked
                ? const PatchField<String>.clear()
                : const PatchField<String>.keep(),
          );
          return null; // reconcile: the current task has almost certainly moved
        },
      );
    });
  }

  /// Renames a task. No reconcile: a title cannot change the order or which task
  /// is current, so the server's row is merged in with [mergeMutatedTask].
  Future<void> editTitle(Task task, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == task.title) return Future<void>.value();

    return _editText(
      task,
      (rows, index) => rows[index].copyWith(title: trimmed),
      () => _api.updateTask(task.id, title: trimmed),
    );
  }

  /// Sets or clears a task's description.
  ///
  /// [description] is nullable here and null genuinely means "erase it" -- the
  /// caller is a text field that the user emptied on purpose. That intent is
  /// converted to a [PatchField.clear] one line down, and the conversion is the
  /// only place in the app where a null description becomes a wire `null`.
  Future<void> editDescription(Task task, String? description) {
    final trimmed = description?.trim();
    final next = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (next == task.description) return Future<void>.value();

    return _editText(
      task,
      (rows, index) => rows[index].copyWith(description: next),
      () => _api.updateTask(
        task.id,
        description: PatchField<String>.toOrClear(next),
      ),
    );
  }

  Future<void> remove(Task task) {
    return _mutate((rows) {
      if (!rows.any((row) => row.id == task.id)) return null;

      return _MutationPlan(
        optimistic: <Task>[
          for (final row in rows)
            if (row.id != task.id) row,
        ],
        send: () async {
          await _api.deleteTask(task.id);
          return null; // reconcile: deleting the current task promotes another
        },
      );
    });
  }

  /// Drag-and-drop reordering. [oldIndex] and [newIndex] come straight from
  /// `ReorderableListView.onReorder`; [planTaskMove] owns that convention.
  ///
  /// ## Why this always re-reads, even though the move succeeded
  ///
  /// `PATCH /tasks/:id/position` replies with the moved row only. In the normal
  /// case that is the complete truth -- one row changed. But when the float gap
  /// between the two neighbours is exhausted, the route renumbers **every task
  /// in the project** inside a transaction before performing the move, and says
  /// nothing about it in the response. A client that trusted the reply would
  /// keep stale positions for every other row, which is invisible right up until
  /// it is not.
  ///
  /// This is also the reason the neighbours are named by **id** rather than by
  /// position: ids survive a rebalance, positions do not. The re-read here is
  /// what makes the whole scheme safe, and it is not a special case -- a move
  /// also changes which task is `pending`-first, so this list had to be re-read
  /// anyway.
  Future<void> move(int oldIndex, int newIndex) {
    return _mutate((rows) {
      final plan = planTaskMove(rows, oldIndex, newIndex);
      if (plan == null) return null;

      return _MutationPlan(
        optimistic: plan.reordered,
        send: () async {
          await _api.moveTask(
            plan.taskId,
            beforeTaskId: plan.beforeTaskId,
            afterTaskId: plan.afterTaskId,
          );
          return null; // see above: positions elsewhere may have moved
        },
      );
    });
  }

  // --- plumbing -------------------------------------------------------------

  /// The shared shape of a text edit: optimistic swap, one PATCH, merge the
  /// answer, no reconcile.
  Future<void> _editText(
    Task task,
    Task Function(List<Task> rows, int index) optimistic,
    Future<Task> Function() send,
  ) {
    return _mutate((rows) {
      final index = rows.indexWhere((row) => row.id == task.id);
      if (index < 0) return null;

      return _MutationPlan(
        optimistic: _replaceAt(rows, index, optimistic(rows, index)),
        send: () async {
          final saved = await send();
          final current = state.value ?? rows;
          final at = current.indexWhere((row) => row.id == task.id);
          if (at < 0) return current;

          return _replaceAt(current, at, mergeMutatedTask(current[at], saved));
        },
      );
    });
  }

  /// Runs one mutation: show the prediction, send the write, settle on the
  /// truth, and put everything back if the write failed.
  ///
  /// [plan] receives the rows as they are *when this mutation actually runs*,
  /// which is not necessarily when it was requested -- see [_enqueue]. It
  /// returns null when there is nothing to do.
  ///
  /// `send` returning null means "re-read the list"; returning a list means "this
  /// is already the truth" (a text edit).
  ///
  /// Errors are rethrown rather than parked in `state`: an [AsyncError] would
  /// replace the list with an error page for a failed single-row edit, and the
  /// list is still perfectly good -- it is the *edit* that failed. The caller (a
  /// button handler) turns the exception into a message.
  Future<void> _mutate(_MutationPlan? Function(List<Task> rows) plan) {
    return _enqueue(() async {
      final previous = state.value;
      if (previous == null) return;

      final step = plan(previous);
      if (step == null) return;

      state = AsyncData(step.optimistic);

      try {
        final settled = await step.send() ?? await _api.fetchTasks(projectId);

        // The screen may have been popped mid-flight. The write still happened
        // and that is fine; there is simply nobody left to tell.
        if (!ref.mounted) return;

        final rows = List<Task>.unmodifiable(settled);
        state = AsyncData(rows);

        // The board is keepAlive and outlives this provider, so it is updated
        // even when nothing is watching this screen any more.
        ref.read(boardProvider.notifier).applyProjectTasks(projectId, rows);
      } catch (error) {
        // Rollback. Rule 2: no network, no write, no pretending otherwise.
        if (ref.mounted) state = AsyncData(previous);
        rethrow;
      }
    });
  }

  /// Serialises mutations.
  ///
  /// Optimistic rollback is only well defined against a known "before" state,
  /// and two writes in flight at once do not have one: the second would capture
  /// the first's *prediction* as its rollback target, so a failure of the first
  /// would restore a list containing a change that never happened. Typing two
  /// tasks in quick succession -- the primary way this screen is used -- is
  /// exactly how you get there.
  ///
  /// A queue of one is enough because every mutation is short and ends in a
  /// settled list. The caller still gets its own error; the copy kept in
  /// [_pending] swallows it so that one failed write does not poison every
  /// write after it.
  Future<void> _pending = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final chained = _pending.then<void>(
      (_) => action(),
      onError: (Object _) => action(),
    );
    _pending = chained.catchError((Object _) {});
    return chained;
  }

  /// A stand-in row for the one frame between "typed a title" and "the server
  /// answered". Its id is namespaced so it can never be mistaken for a cuid, and
  /// so a `ValueKey` on it stays unique while it exists.
  Task _optimisticTask(String title, List<Task> rows) {
    final now = DateTime.now().toUtc().toIso8601String();

    return Task(
      id: 'local:${now}_${rows.length}',
      projectId: projectId,
      title: title,
      description: null,
      status: TaskStatus.pending,
      // Mirrors `computeAppendPosition`, purely so the row sorts last if anyone
      // ever does sort. It is discarded by the reconcile a moment later.
      position: rows.isEmpty ? 1000 : rows.last.position + 1000,
      remindAt: null,
      createdAt: now,
      updatedAt: now,
      isCurrent: false,
    );
  }
}

/// True for a row this client invented and the server has not confirmed yet.
/// The row cannot be edited, dragged or deleted while that is the case -- it has
/// no id the server would recognise.
bool isOptimisticId(String id) => id.startsWith('local:');

/// One project's notes, and their CRUD.
///
/// Much simpler than [ProjectTasks] for one structural reason: a note has no
/// server-computed field and no ordering key, so `POST` and `PATCH` return the
/// complete truth about the row and there is nothing to reconcile. Notes also
/// never appear on the board, so nothing is pushed there.
@Riverpod(retry: noAutomaticRetry)
class ProjectNotes extends _$ProjectNotes {
  @override
  Future<List<Note>> build(String projectId) =>
      ref.watch(projectApiProvider).fetchNotes(projectId);

  ProjectApi get _api => ref.read(projectApiProvider);

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Note refresh failed: $error');
    }
  }

  Future<void> create(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final previous = state.value;
    if (previous == null) return;

    final placeholder = _optimisticNote(trimmed);
    state = AsyncData(<Note>[...previous, placeholder]);

    try {
      final created = await _api.createNote(
        projectId: projectId,
        title: trimmed,
      );
      if (!ref.mounted) return;
      state = AsyncData(<Note>[
        for (final note in state.value ?? previous)
          if (note.id == placeholder.id) created else note,
      ]);
    } catch (error) {
      if (ref.mounted) state = AsyncData(previous);
      rethrow;
    }
  }

  /// Saves a note. Either field may be omitted; passing neither is a no-op
  /// rather than a 400.
  Future<void> edit(Note note, {String? title, String? content}) async {
    final nextTitle = title?.trim();
    final changedTitle =
        nextTitle != null && nextTitle.isNotEmpty && nextTitle != note.title;
    final changedContent = content != null && content != note.content;
    if (!changedTitle && !changedContent) return;

    final previous = state.value;
    if (previous == null) return;

    final index = previous.indexWhere((row) => row.id == note.id);
    if (index < 0) return;

    state = AsyncData(
      _replaceAt(
        previous,
        index,
        previous[index].copyWith(
          title: changedTitle ? nextTitle : previous[index].title,
          content: changedContent ? content : previous[index].content,
        ),
      ),
    );

    try {
      final saved = await _api.updateNote(
        note.id,
        title: changedTitle ? nextTitle : null,
        content: changedContent ? content : null,
      );
      if (!ref.mounted) return;

      final rows = state.value ?? previous;
      final at = rows.indexWhere((row) => row.id == note.id);
      if (at >= 0) state = AsyncData(_replaceAt(rows, at, saved));
    } catch (error) {
      if (ref.mounted) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> remove(Note note) async {
    final previous = state.value;
    if (previous == null) return;

    state = AsyncData(<Note>[
      for (final row in previous)
        if (row.id != note.id) row,
    ]);

    try {
      await _api.deleteNote(note.id);
    } catch (error) {
      if (ref.mounted) state = AsyncData(previous);
      rethrow;
    }
  }

  Note _optimisticNote(String title) {
    final now = DateTime.now().toUtc().toIso8601String();
    return Note(
      id: 'local:$now',
      projectId: projectId,
      title: title,
      content: '',
      createdAt: now,
      updatedAt: now,
    );
  }
}

// --- the fold ---------------------------------------------------------------

/// Where the tasks on screen came from. Same distinction as [BoardOrigin], and
/// it exists for the same reason: a list read out of yesterday's snapshot must
/// not look like a live one.
enum TaskOrigin { network, cache }

/// What the project screen renders.
@immutable
sealed class ProjectView {
  const ProjectView();
}

/// Neither the network nor the board has anything yet.
class ProjectLoading extends ProjectView {
  const ProjectLoading();
}

/// The server says 404. Reached when the project was deleted or archived
/// elsewhere -- `getActiveProjectOrThrow` answers the same way for both -- and
/// it must win over a board row that still shows it, because that row is by
/// definition out of date.
class ProjectMissing extends ProjectView {
  const ProjectMissing();
}

/// Nothing to show and a reason why.
class ProjectUnavailable extends ProjectView {
  const ProjectUnavailable(this.error);

  final Object error;
}

/// There is a project and a task list to draw.
class ProjectReady extends ProjectView {
  const ProjectReady({
    required this.project,
    required this.tasks,
    required this.origin,
    this.isRefreshing = false,
    this.refreshError,
  });

  final Project project;

  /// In server order (`position` ascending). Never re-sorted here.
  final List<Task> tasks;

  final TaskOrigin origin;
  final bool isRefreshing;
  final Object? refreshError;

  bool get isStale => origin == TaskOrigin.cache;
}

/// Folds the network reads and the board snapshot into the single value the
/// screen renders.
///
/// Same shape, and the same reasoning, as `boardView`: two sources that must not
/// race are kept apart and combined in a plain synchronous provider. The payoff
/// here is that a project opened from the board draws instantly -- its tasks are
/// already in memory, and after F4's notification deep link they may be in the
/// *snapshot* with no network at all, which is the whole reason the snapshot
/// holds tasks rather than just project names.
@riverpod
ProjectView projectView(Ref ref, String projectId) {
  final header = ref.watch(projectHeaderProvider(projectId));
  final live = ref.watch(projectTasksProvider(projectId));
  final cached = _boardRow(ref.watch(boardViewProvider), projectId);

  if (_isNotFound(header.error) || _isNotFound(live.error)) {
    return const ProjectMissing();
  }

  final project = header.value ?? cached?.project;
  final tasks = live.value ?? cached?.tasks;
  final error = live.error ?? header.error;

  if (project != null && tasks != null) {
    return ProjectReady(
      project: project,
      tasks: tasks,
      origin: live.value != null ? TaskOrigin.network : TaskOrigin.cache,
      isRefreshing: live.isLoading || header.isLoading,
      refreshError: error,
    );
  }

  // Report a failure only once both halves have settled, so a refused
  // connection (which fails in microseconds) does not flash an error page over
  // a board row that was about to arrive.
  if (error != null && !header.isLoading && !live.isLoading) {
    return ProjectUnavailable(error);
  }

  return const ProjectLoading();
}

// --- helpers ----------------------------------------------------------------

BoardProject? _boardRow(BoardView view, String projectId) {
  if (view is! BoardReady) return null;
  for (final row in view.projects) {
    if (row.project.id == projectId) return row;
  }
  return null;
}

bool _isNotFound(Object? error) =>
    error is ApiException && error.statusCode == 404;

List<T> _replaceAt<T>(List<T> rows, int index, T value) => List<T>.unmodifiable(
  <T>[...rows.take(index), value, ...rows.skip(index + 1)],
);

/// A single optimistic step: what to show now, and what to send.
@immutable
class _MutationPlan {
  const _MutationPlan({required this.optimistic, required this.send});

  final List<Task> optimistic;

  /// Performs the write. Returns the settled list, or null to ask the server
  /// for it (see the note on reconciling at the top of this file).
  final Future<List<Task>?> Function() send;
}
