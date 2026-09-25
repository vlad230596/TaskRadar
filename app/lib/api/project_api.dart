import '../models/note.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import 'api_client.dart';
import 'patch_field.dart';

/// Everything the project screen (F3) talks to: one project, its tasks, its
/// notes.
///
/// Kept separate from `BoardApi` because the two answer different questions.
/// `GET /board` is the morning overview -- many projects, read-only, one round
/// trip. These are the endpoints you use once you are *inside* a project, and
/// they are where every write in the app lives.
///
/// ## Two contract details that fixtures cannot teach you
///
/// **1. The mutation endpoints do not compute `isCurrent`.**
/// `GET /projects/:id/tasks` runs its rows through `annotateIsCurrent`
/// (`backend/src/routes/tasks.ts`), but `POST /projects/:id/tasks`,
/// `PATCH /tasks/:id` and `PATCH /tasks/:id/position` all answer with the raw
/// Prisma row -- which has no `isCurrent` key at all. That is correct of the
/// server: `isCurrent` is a property of the whole ordered *list* ("the first
/// `pending` task"), not of a row, so a single-row response has no honest value
/// to put there. It does mean a client that merges a mutation response straight
/// into its list silently drops the highlight -- see [mergeMutatedTask], and
/// see `frontend/src/components/TaskListItem.tsx`, which has exactly that bug.
///
/// **2. `PATCH /tasks/:id/position` can renumber rows it does not return.**
/// Normally the move writes one row: the new position is bisected between the
/// two neighbours the client named. But when that gap is exhausted
/// (`PositionExhaustedError`), the route renumbers **every task in the project**
/// with fresh 1000-spaced positions inside a transaction and then moves the
/// task -- while still replying with only the moved row. So after a move the
/// client's positions for the *other* rows may be silently stale. The only
/// answer the server offers is to ask again, which is what
/// `ProjectTasks.move` does unconditionally; see the long note there.
class ProjectApi {
  const ProjectApi(this._client);

  final ApiClient _client;

  // --- project ---------------------------------------------------------------

  /// `GET /projects/:id`. A 404 (an [ApiException] with `statusCode == 404`)
  /// means the project does not exist any more.
  ///
  /// It does **not** mean "archived": the route's helper (`getProjectOrThrow`,
  /// `backend/src/routes/projects.ts`) only checks existence, so an archived
  /// project answers 200 with a non-null `archivedAt`. That is what lets a
  /// reminder deep link open a task in a project that was archived since the
  /// alarm was armed, rather than dead-ending on a 404.
  Future<Project> fetchProject(String projectId) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/projects/$projectId',
    );
    return Project.fromJson(json);
  }

  /// `POST /projects`. Answers 201 with the new row.
  ///
  /// `name` and, since F7, which scope it lands in. There is still no
  /// description: a project's body is its notes, not a column.
  ///
  /// [scopeId] is optional on the wire -- the server falls back to the first
  /// scope by position -- but the client always sends it, because the board the
  /// project is being created from is already showing one specific scope and
  /// landing it anywhere else would be a surprise.
  Future<Project> createProject({
    required String name,
    String? scopeId,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/projects',
      body: <String, dynamic>{'name': name, 'scopeId': ?scopeId},
    );
    return Project.fromJson(json);
  }

  /// `PATCH /projects/:id` -- the rename, and a project's only field update.
  ///
  /// The server trims the name and rejects an empty or whitespace-only one with
  /// a 400; the caller trims too, so that refusal is reached by a broken client
  /// rather than by an ordinary user typing spaces.
  ///
  /// **`archivedAt` is not in the payload**, by the route's design: a rename can
  /// neither resurrect an archived project nor archive a live one, and
  /// `/archive` + `/unarchive` stay the only two routes that move a project
  /// between those states. Which is also why renaming an **archived** project is
  /// allowed and is a feature, not an oversight -- the archive screen is exactly
  /// where a badly named old project gets looked at, and the alternative would be
  /// an unarchive/rename/re-archive dance that changes more state than the rename
  /// does. The long argument is in the comment above the route and in B6 of
  /// `../../../flutter-migration-plan.md`.
  ///
  /// Answers the same object as [fetchProject], so there is one `Project` model
  /// and no rename-flavoured twin of it.
  Future<Project> renameProject(String projectId, {required String name}) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/projects/$projectId',
      body: <String, dynamic>{'name': name},
    );
    return Project.fromJson(json);
  }

  /// `PATCH /projects/:id` again, with the other field it grew in F7: which
  /// scope the project belongs to.
  ///
  /// A separate method rather than optional parameters on [renameProject],
  /// because the two are different intentions with different call sites -- and
  /// because sending both in one request is never what the UI wants: renaming
  /// happens in a text field, moving happens in a picker.
  ///
  /// **The move has no side effects on anything else**, which is what lets the
  /// caller splice the answer into the lists it already holds instead of
  /// re-reading the board: tasks keep their positions (those order tasks within
  /// a *project*, which did not change), `isCurrent` is computed from those same
  /// positions, and `archivedAt` is not in the payload -- so a move cannot take
  /// a project off the board or bring it back. Same argument as the rename.
  Future<Project> moveProjectToScope(
    String projectId, {
    required String scopeId,
  }) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/projects/$projectId',
      body: <String, dynamic>{'scopeId': scopeId},
    );
    return Project.fromJson(json);
  }

  /// `POST /projects/:id/archive` -- reversible; the project leaves the board.
  ///
  /// A route of its own rather than a field on [renameProject]'s patch: archiving
  /// is a state transition with a guard behind it (`DELETE` refuses an
  /// unarchived project), and a body key that could flip it would make every
  /// rename a potential archive.
  Future<Project> archiveProject(String projectId) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/archive',
    );
    return Project.fromJson(json);
  }

  /// `POST /projects/:id/unarchive` -- the other half of the pair.
  Future<Project> unarchiveProject(String projectId) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/unarchive',
    );
    return Project.fromJson(json);
  }

  /// `DELETE /projects/:id`. Answers 204, and takes the project's tasks and
  /// notes with it -- there is no undo and no soft delete.
  ///
  /// **The server refuses an active project with a 409**
  /// (`canHardDeleteProject`, `backend/src/domain/projectDeleteGuard.ts`): a
  /// project has to be archived first. That is Trello's split copied on purpose
  /// (`../project-tracker-brief.md`) -- a reversible step in front of an
  /// irreversible one, so the irreversible one is never the first thing a
  /// mis-tap reaches. The client mirrors the rule in its UI rather than relying
  /// on the 409, but does not *implement* it: the guard stays server-side, where
  /// it cannot be bypassed.
  ///
  /// Typed `dynamic` for the same reason as [deleteTask]: an empty body is the
  /// correct answer.
  Future<void> deleteProject(String projectId) =>
      _client.delete<dynamic>('/projects/$projectId');

  // --- tasks -----------------------------------------------------------------

  /// `GET /projects/:projectId/tasks` -- the authoritative list: sorted by
  /// `position` ascending, with `isCurrent` computed across it.
  ///
  /// This is the only task response the client may believe in full, which is
  /// why every structural mutation ends with a call to it.
  Future<List<Task>> fetchTasks(String projectId) async {
    final json = await _client.get<List<dynamic>>('/projects/$projectId/tasks');
    return _taskList(json);
  }

  /// `POST /projects/:projectId/tasks`. The task is appended to the end of the
  /// list -- the server picks the position (`computeAppendPosition`), the client
  /// never proposes one.
  ///
  /// Inline creation (the fast path this screen is built around) sends only
  /// `title`; the server defaults the rest to null/`pending`. A dictated task
  /// (F14) can arrive with a description and a reminder, and then with
  /// `blocked` -- a reminder only fires for a blocked task
  /// (`domain/board_reminders.dart`).
  ///
  /// [remindAt] is the `YYYY-MM-DD` calendar date, for the reason given on
  /// [updateTask].
  Future<Task> createTask({
    required String projectId,
    required String title,
    String? description,
    TaskStatus? status,
    String? remindAt,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/tasks',
      body: <String, dynamic>{
        'title': title,
        'description': ?description,
        'status': ?status?.name,
        'remindAt': ?remindAt,
      },
    );
    return _taskFromMutation(json);
  }

  /// `PATCH /tasks/:id`.
  ///
  /// [title] and [status] are plain nullable parameters because the server
  /// declares them `optional()` but not `nullable()`: null here means "not
  /// provided", and there is no third state to express.
  ///
  /// [description] and [remindAt] are [PatchField]s because those two *do* have
  /// a third state. Read the class comment on [PatchField] before changing this
  /// signature -- the difference between the two shapes is the difference
  /// between "leave the description alone" and "erase the description".
  ///
  /// [remindAt] is the `YYYY-MM-DD` calendar date, not an instant: the server
  /// runs it through `z.coerce.date()`, which turns a bare date into UTC
  /// midnight of that day -- exactly the representation
  /// `lib/domain/reminders.dart` depends on.
  Future<Task> updateTask(
    String taskId, {
    String? title,
    PatchField<String> description = const PatchField<String>.keep(),
    TaskStatus? status,
    PatchField<String> remindAt = const PatchField<String>.keep(),
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (status != null) body['status'] = status.name;
    description.writeTo(body, 'description');
    remindAt.writeTo(body, 'remindAt');

    // The server rejects `{}` with a 400 ("At least one field must be
    // provided"). Failing here instead says *which* call was empty, and it
    // fails without a round trip.
    if (body.isEmpty) {
      throw ArgumentError.value(
        taskId,
        'taskId',
        'PATCH /tasks/:id with no fields to change',
      );
    }

    final json = await _client.patch<Map<String, dynamic>>(
      '/tasks/$taskId',
      body: body,
    );
    return _taskFromMutation(json);
  }

  /// `PATCH /tasks/:id/position`.
  ///
  /// Both keys are always sent, including as `null`. That is the protocol, not
  /// sloppiness: `updateTaskPositionSchema` refuses a body where *both* are
  /// absent, and an explicit `null` is how the client says "there is no
  /// neighbour on this side", i.e. "move to the very start / very end". Omitting
  /// the null one instead would read to the server as "no neighbour" too -- the
  /// route does `body.beforeTaskId ?? null` -- but sending it makes the intent
  /// legible in a request log, and keeps a one-item move from becoming the
  /// rejected empty body.
  ///
  /// The neighbours come from the list the client already has, never from a
  /// fresh read: see `frontend/src/components/TaskList.tsx`, which does the
  /// same, and `lib/domain/task_reorder.dart` for how they are picked.
  Future<Task> moveTask(
    String taskId, {
    required String? beforeTaskId,
    required String? afterTaskId,
  }) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/tasks/$taskId/position',
      body: <String, dynamic>{
        'beforeTaskId': beforeTaskId,
        'afterTaskId': afterTaskId,
      },
    );
    return _taskFromMutation(json);
  }

  /// `DELETE /tasks/:id`. Answers 204 with no body.
  ///
  /// Typed `dynamic` rather than `void` so that [ApiClient.request]'s
  /// "empty body where a shape was expected" guard takes the `null is T` branch
  /// -- an empty response is the *correct* answer here.
  Future<void> deleteTask(String taskId) =>
      _client.delete<dynamic>('/tasks/$taskId');

  // --- notes -----------------------------------------------------------------

  /// `GET /projects/:projectId/notes`, in `createdAt` ascending order.
  Future<List<Note>> fetchNotes(String projectId) async {
    final json = await _client.get<List<dynamic>>('/projects/$projectId/notes');
    return List<Note>.unmodifiable(
      json.map((dynamic e) => Note.fromJson(e as Map<String, dynamic>)),
    );
  }

  /// `POST /projects/:projectId/notes`.
  ///
  /// [content] is sent even when empty: `createNoteSchema` defaults it to `""`,
  /// so this is only ever explicit about what would have happened anyway, and it
  /// keeps the create path identical whether the note was born from the inline
  /// "new note" field or from an editor that already has text in it.
  Future<Note> createNote({
    required String projectId,
    required String title,
    String content = '',
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/projects/$projectId/notes',
      body: <String, dynamic>{'title': title, 'content': content},
    );
    return Note.fromJson(json);
  }

  /// `PATCH /notes/:id`.
  ///
  /// Both fields are `optional()` and **not** `nullable()` on the server, and
  /// `content` is a non-null column whose empty value is `""`. So null means
  /// "not provided" here and there is no [PatchField] in sight -- an empty note
  /// body is `content: ''`, which is a perfectly ordinary value.
  Future<Note> updateNote(
    String noteId, {
    String? title,
    String? content,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (content != null) body['content'] = content;

    if (body.isEmpty) {
      throw ArgumentError.value(
        noteId,
        'noteId',
        'PATCH /notes/:id with no fields to change',
      );
    }

    final json = await _client.patch<Map<String, dynamic>>(
      '/notes/$noteId',
      body: body,
    );
    return Note.fromJson(json);
  }

  /// `DELETE /notes/:id`. Answers 204; see [deleteTask] for the `dynamic`.
  Future<void> deleteNote(String noteId) =>
      _client.delete<dynamic>('/notes/$noteId');

  // --- parsing ---------------------------------------------------------------

  static List<Task> _taskList(List<dynamic> json) => List<Task>.unmodifiable(
    json.map((dynamic e) => Task.fromJson(e as Map<String, dynamic>)),
  );

  /// Parses a row from a mutation endpoint, which has no `isCurrent`.
  ///
  /// The placeholder is `false`, and callers must treat it as "unknown", never
  /// as an answer -- [mergeMutatedTask] is how. `json['isCurrent'] ?? false`
  /// rather than a flat `false` so that if the server ever does start annotating
  /// these responses, the real value wins and this line quietly becomes dead
  /// instead of quietly wrong.
  static Task _taskFromMutation(Map<String, dynamic> json) => Task.fromJson(
    <String, dynamic>{...json, 'isCurrent': json['isCurrent'] ?? false},
  );
}

/// Folds a mutation response into the row the client already had.
///
/// Every field comes from the server's answer -- including `position` and
/// `updatedAt`, which the client must not guess -- except `isCurrent`, which
/// the mutation endpoints do not compute and which is therefore kept from the
/// row being replaced.
///
/// **This is only sound for a mutation that cannot change which task is
/// current**, i.e. a title or description edit. A status change, a create, a
/// delete or a move all move the "first `pending` task" around, and for those
/// the client has no business merging anything: it re-reads the list. The rule
/// from `flutter-migration-plan.md` is that the server computes `isCurrent` and
/// the client never re-derives it, and "keep the last value the server gave me
/// for a field that provably did not change" is the only way to honour that
/// without a round trip.
Task mergeMutatedTask(Task known, Task mutated) =>
    mutated.copyWith(isCurrent: known.isCurrent);
