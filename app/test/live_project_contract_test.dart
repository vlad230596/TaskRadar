import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_client.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/api/auth_api.dart';
import 'package:taskradar/api/board_api.dart';
import 'package:taskradar/api/patch_field.dart';
import 'package:taskradar/api/project_api.dart';
import 'package:taskradar/api/scope_api.dart';
import 'package:taskradar/domain/reminders.dart';
import 'package:taskradar/domain/task_reorder.dart';
import 'package:taskradar/models/project.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';

/// **Manual test.** Runs *writes* against a real, running TaskRadar backend.
///
/// ## Why this exists next to `live_board_contract_test.dart`
///
/// That file proves the read contract: the real `GET /board` parses into the
/// real models. This one is about the writes -- and writes are where fixtures
/// are weakest, because a fixture is a recording of what someone *believed* the
/// server answers. Three of F3's findings are invisible to any fixture:
///
/// - `POST`/`PATCH` on a task answer with the raw row and **no `isCurrent`**;
/// - `position` is a **Float**, so a few reorders into the same slot produce
///   `2937.5`, which a client that declared `int` silently truncates to `2937`;
/// - `description`/`remindAt` distinguish "absent" from "null", so a patch that
///   sends a stray null erases text with a 200 and no symptom.
///
/// F4 adds two more that no fake can settle:
///
/// - the **calendar date** a date picker produces survives the round trip as
///   the same day, on a machine in whatever timezone this one happens to be in;
/// - the **archive / unarchive / delete** ordering, including the 409 that makes
///   the archive a precondition rather than a convention, and the fact that an
///   archived project is still readable by id -- which is what lets a reminder
///   deep link open a task in a project that was archived since.
///
/// Each of those is asserted here against the actual server.
///
/// ## It works in its own disposable project and removes it afterwards
///
/// The dev database is seeded with three projects a human looks at by eye, and a
/// test that scribbled on them would ruin that. So this creates a project of its
/// own, does everything inside it, and archives-then-deletes it in a teardown
/// that runs even when an expectation fails. (Archive first is required:
/// `canHardDeleteProject` refuses to delete an active project.)
///
/// ## Running it
///
/// Skipped by default -- `flutter test` must stay green with no server and no
/// credentials:
///
/// ```
/// flutter test test/live_project_contract_test.dart \
///   --dart-define=TASKRADAR_LIVE_URL=http://127.0.0.1:3001 \
///   --dart-define=TASKRADAR_LIVE_EMAIL=... \
///   --dart-define=TASKRADAR_LIVE_PASSWORD=...
/// ```
void main() {
  const baseUrl = String.fromEnvironment('TASKRADAR_LIVE_URL');
  const email = String.fromEnvironment('TASKRADAR_LIVE_EMAIL');
  const password = String.fromEnvironment('TASKRADAR_LIVE_PASSWORD');

  final skip = baseUrl.isEmpty || email.isEmpty || password.isEmpty
      ? 'manual: pass --dart-define=TASKRADAR_LIVE_URL/_EMAIL/_PASSWORD'
      : null;

  late ApiClient client;
  late ProjectApi api;
  late String projectId;

  /// Logs in and creates the scratch project, registering its removal.
  Future<void> openScratchProject() async {
    client = ApiClient.forBaseUrl(baseUrl);
    final login = await AuthApi(client).login(email: email, password: password);
    client.setToken(login.token);
    api = ProjectApi(client);

    // Non-ASCII in the name on purpose: it goes out as a JSON body from this
    // UTF-8 source file, and reading it back proves the round trip did not
    // mangle it. (Passing Cyrillic as a *command-line argument* on Windows is
    // what breaks -- hence a literal here rather than a dart-define.)
    final created = await client.post<Map<String, dynamic>>(
      '/projects',
      body: <String, dynamic>{
        'name': 'Проверка записи ${DateTime.now().toIso8601String()}',
      },
    );
    final project = Project.fromJson(created);
    projectId = project.id;
    expect(project.name, contains('Проверка записи'));

    // Registered immediately after creation, so a failure anywhere below still
    // cleans up. Archive, then delete -- the delete guard requires it.
    addTearDown(() async {
      try {
        await client.post<Map<String, dynamic>>('/projects/$projectId/archive');
        await client.delete<dynamic>('/projects/$projectId');
        // ignore: avoid_print
        print('live: removed scratch project $projectId');
      } on ApiException catch (error) {
        // The lifecycle test deletes its own project on purpose, so a 404 here
        // means the cleanup already happened. Reported as noise rather than as
        // a failure, because the alternative -- a scary line on a green run --
        // trains the reader to ignore this message, and the message is the only
        // warning there will ever be that a project was left behind on the dev
        // server a human looks at by eye.
        if (error.statusCode == 404) {
          // ignore: avoid_print
          print('live: scratch project $projectId was already removed');
          return;
        }
        // ignore: avoid_print
        print(
          'live: FAILED to remove scratch project $projectId -- archive and '
          'delete it by hand: $error',
        );
      } catch (error) {
        // ignore: avoid_print
        print(
          'live: FAILED to remove scratch project $projectId -- archive and '
          'delete it by hand: $error',
        );
      }
    });
  }

  test('the live task write path answers what the models expect', () async {
    await openScratchProject();

    // --- create ------------------------------------------------------------

    final first = await api.createTask(
      projectId: projectId,
      title: 'Первая задача',
    );
    await api.createTask(projectId: projectId, title: 'Вторая задача');
    await api.createTask(projectId: projectId, title: 'Третья задача');

    // The finding a fixture cannot make: the 201 carries no `isCurrent`, so
    // `_taskFromMutation` had to inject one -- and this task really is the
    // current one, which only the list endpoint will say.
    expect(first.isCurrent, isFalse);

    var tasks = await api.fetchTasks(projectId);
    expect(tasks.map((task) => task.title), <String>[
      'Первая задача',
      'Вторая задача',
      'Третья задача',
    ]);
    expect(tasks.map((task) => task.isCurrent), <bool>[true, false, false]);
    expect(tasks.map((task) => task.position), <double>[1000, 2000, 3000]);

    // --- reorder -----------------------------------------------------------

    // Drag the first row to the bottom, exactly as the widget does it:
    // ReorderableListView reports (0, 3) and `planTaskMove` turns that into the
    // neighbour ids.
    final move = planTaskMove(tasks, 0, tasks.length)!;
    expect(move.beforeTaskId, tasks.last.id);
    expect(move.afterTaskId, isNull);

    await api.moveTask(
      move.taskId,
      beforeTaskId: move.beforeTaskId,
      afterTaskId: move.afterTaskId,
    );

    tasks = await api.fetchTasks(projectId);
    expect(tasks.map((task) => task.title), <String>[
      'Вторая задача',
      'Третья задача',
      'Первая задача',
    ]);
    // The current task moved with the order, computed server-side.
    expect(tasks.first.isCurrent, isTrue);

    // --- a Float position, for real ----------------------------------------

    // Four alternating moves into the same gap bisect it down to a
    // non-integer: 1000/2000/3000 -> 2500 -> 2750 -> 2875 -> 2937.5. That last
    // value is what a client declaring `int position` silently truncates, and
    // nothing short of a live server (or a faithful fake) produces it.
    for (var i = 0; i < 4; i++) {
      final plan = planTaskMove(tasks, 0, 2)!;
      await api.moveTask(
        plan.taskId,
        beforeTaskId: plan.beforeTaskId,
        afterTaskId: plan.afterTaskId,
      );
      tasks = await api.fetchTasks(projectId);
    }

    expect(
      tasks.any((task) => task.position != task.position.roundToDouble()),
      isTrue,
      reason:
          'position is a Prisma Float and bisection produces fractions; if this '
          'fails, the gap arithmetic changed and the `double` on Task.position '
          'is no longer load-bearing',
    );

    // Whatever the positions are, they are ascending and the order is the
    // server's -- the client never sorts by them.
    var previous = double.negativeInfinity;
    for (final task in tasks) {
      expect(task.position, greaterThan(previous));
      previous = task.position;
    }

    // --- status, and the undefined-vs-null distinction ---------------------

    final target = tasks.first;
    await api.updateTask(
      target.id,
      description: const PatchField<String>.to('жду кабель у Петра'),
    );
    await api.updateTask(target.id, status: TaskStatus.blocked);

    tasks = await api.fetchTasks(projectId);
    var blocked = tasks.firstWhere((task) => task.id == target.id);
    expect(blocked.status, TaskStatus.blocked);
    // The whole point: the status patch did not mention `description`, and the
    // server left it alone. A stray `description: null` would have wiped it
    // here, with a 200.
    expect(blocked.description, 'жду кабель у Петра');
    // A blocked task is not current, and something else became current.
    expect(blocked.isCurrent, isFalse);
    expect(tasks.where((task) => task.isCurrent), hasLength(1));

    // A calendar date goes in as `YYYY-MM-DD` and comes back as UTC midnight of
    // that day, which is the representation every date comparison in the app
    // depends on (`domain/reminders.dart`). This is F4's feature, but it is F3's
    // contract to verify.
    await api.updateTask(
      target.id,
      remindAt: const PatchField<String>.to('2026-10-01'),
    );
    blocked = (await api.fetchTasks(
      projectId,
    )).firstWhere((task) => task.id == target.id);
    expect(blocked.remindAt, '2026-10-01T00:00:00.000Z');
    expect(reminderCalendarDate(blocked.remindAt!), '2026-10-01');

    // ...and the explicit clear really clears, while the description survives.
    await api.updateTask(
      target.id,
      status: TaskStatus.pending,
      remindAt: const PatchField<String>.clear(),
    );
    blocked = (await api.fetchTasks(
      projectId,
    )).firstWhere((task) => task.id == target.id);
    expect(blocked.remindAt, isNull);
    expect(blocked.description, 'жду кабель у Петра');

    // --- delete ------------------------------------------------------------

    final doomed = tasks.last;
    await api.deleteTask(doomed.id);

    tasks = await api.fetchTasks(projectId);
    expect(tasks.map((task) => task.id), isNot(contains(doomed.id)));
    expect(tasks, hasLength(2));

    // Printed rather than asserted: the point of running this by hand is to see
    // what the server actually did.
    // ignore: avoid_print
    print(
      'live tasks: ${tasks.length} left, positions '
      '${tasks.map((Task task) => task.position).toList()}',
    );
  }, skip: skip);

  test('the live note write path answers what the models expect', () async {
    await openScratchProject();

    final created = await api.createNote(
      projectId: projectId,
      title: 'Контекст проекта',
      content: '# Что помнить\n\n- ключи у соседей\n- **счётчик** в подвале',
    );
    expect(created.title, 'Контекст проекта');
    expect(created.content, contains('ключи у соседей'));

    var notes = await api.fetchNotes(projectId);
    expect(notes, hasLength(1));
    expect(notes.single.id, created.id);

    // Content only: the title must survive a patch that does not mention it.
    await api.updateNote(created.id, content: '## Обновлено\n\nновый текст');
    notes = await api.fetchNotes(projectId);
    expect(notes.single.content, '## Обновлено\n\nновый текст');
    expect(notes.single.title, 'Контекст проекта');

    // Title only: and now the content must survive.
    await api.updateNote(created.id, title: 'Контекст, переименованный');
    notes = await api.fetchNotes(projectId);
    expect(notes.single.title, 'Контекст, переименованный');
    expect(notes.single.content, '## Обновлено\n\nновый текст');

    // An empty body is a real value here, not a null -- `content` is a non-null
    // column whose empty value is `""`.
    await api.updateNote(created.id, content: '');
    notes = await api.fetchNotes(projectId);
    expect(notes.single.content, '');

    await api.deleteNote(created.id);
    expect(await api.fetchNotes(projectId), isEmpty);

    // ignore: avoid_print
    print('live notes: create/patch/delete round-tripped');
  }, skip: skip);

  test('the live reminder date round-trips the day the picker produced', () async {
    await openScratchProject();

    final task = await api.createTask(
      projectId: projectId,
      title: 'Жду кабель',
    );
    await api.updateTask(task.id, status: TaskStatus.blocked);

    // Exactly what the widget sends: `showDatePicker` hands back a local
    // `DateTime`, `calendarDateForApi` reduces it to its wall-clock date parts,
    // and that string is the body. Three days out so no midnight can make this
    // flaky.
    final picked = DateTime.now().add(const Duration(days: 3));
    final sent = calendarDateForApi(picked);

    await api.updateTask(
      task.id,
      remindAt: PatchField<String>.to(sent),
    );

    var stored = (await api.fetchTasks(
      projectId,
    )).firstWhere((row) => row.id == task.id);

    // The assertion the whole timezone note is about: the day the user tapped
    // is the day the server stored, and the day every reader in the app reads
    // back -- on a machine in *this* timezone, whatever it is.
    expect(stored.remindAt, '${sent}T00:00:00.000Z');
    expect(reminderCalendarDate(stored.remindAt!), sent);
    expect(remindAtAsLocalDay(stored.remindAt!), DateTime(picked.year, picked.month, picked.day));
    expect(isReminderDue(stored.remindAt!), isFalse, reason: 'three days out');

    // A date that has arrived is due -- the badge, and the reason the board is
    // worth looking at in the morning.
    final today = calendarDateForApi(DateTime.now());
    await api.updateTask(task.id, remindAt: PatchField<String>.to(today));
    stored = (await api.fetchTasks(
      projectId,
    )).firstWhere((row) => row.id == task.id);
    expect(isReminderDue(stored.remindAt!), isTrue);

    // And "убрать дату" really clears it, rather than leaving a value that
    // resurfaces the next time the task is blocked.
    await api.updateTask(task.id, remindAt: const PatchField<String>.clear());
    stored = (await api.fetchTasks(
      projectId,
    )).firstWhere((row) => row.id == task.id);
    expect(stored.remindAt, isNull);

    // ignore: avoid_print
    print('live remindAt: $sent round-tripped as UTC midnight and cleared');
  }, skip: skip);

  test('the live rename: active, archived, and what it refuses', () async {
    await openScratchProject();

    final original = await api.fetchProject(projectId);

    // --- the ordinary rename ------------------------------------------------

    // Non-ASCII and padded, both on purpose: the names in this tool are Russian,
    // and the server trims. (The literal lives in this UTF-8 source rather than
    // in a --dart-define, because Git Bash on Windows mangles Cyrillic in
    // command-line arguments -- the same trap `openScratchProject` names.)
    final renamed = await api.renameProject(
      projectId,
      name: '  Переименованный проект  ',
    );
    expect(renamed.id, projectId);
    expect(renamed.name, 'Переименованный проект');
    expect(renamed.archivedAt, isNull);
    expect(
      renamed.createdAt,
      original.createdAt,
      reason: 'a rename is an update, not a re-creation',
    );

    // The same object `GET /projects/:id` hands back -- one `Project` model, no
    // rename-flavoured twin of it.
    expect(await api.fetchProject(projectId), renamed);

    // And the board carries the new name, which is what the client splices into
    // its own row instead of re-reading the board.
    final boardApi = BoardApi(client);
    expect(
      (await boardApi.fetchBoard())
          .firstWhere((row) => row.project.id == projectId)
          .project
          .name,
      'Переименованный проект',
    );

    // --- renaming an archived project ---------------------------------------

    // The decision B6 argues in full: the archive screen is where a badly named
    // old project is met, so it must be fixable there. Only a live server can
    // prove the route really allows it.
    await api.archiveProject(projectId);
    final archivedRename = await api.renameProject(
      projectId,
      name: 'Архивный, переименованный',
    );
    expect(archivedRename.name, 'Архивный, переименованный');
    expect(
      archivedRename.archivedAt,
      isNotNull,
      reason: 'renaming must not resurrect a project as a side effect',
    );
    expect(
      (await boardApi.fetchBoard(archived: true))
          .firstWhere((row) => row.project.id == projectId)
          .project
          .name,
      'Архивный, переименованный',
      reason: 'the row stays in the archive, with the new name',
    );

    await api.unarchiveProject(projectId);

    // --- what it refuses ----------------------------------------------------

    for (final rejected in <String>['', '   ']) {
      await expectLater(
        api.renameProject(projectId, name: rejected),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
        reason: 'an empty or whitespace-only name is a 400, not a stored ""',
      );
    }

    await expectLater(
      api.renameProject('nosuchprojectid', name: 'Неважно'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );

    // Nothing the refusals touched: the last accepted name is still there.
    expect(
      (await api.fetchProject(projectId)).name,
      'Архивный, переименованный',
    );

    // ignore: avoid_print
    print('live rename: active and archived project renamed, 400/404 refused');
  }, skip: skip);

  test('the live project lifecycle: archive, unarchive, delete', () async {
    await openScratchProject();

    // Something inside it, so the delete at the end is a real cascade rather
    // than a delete of an empty row.
    await api.createTask(projectId: projectId, title: 'Задача перед архивом');
    await api.createNote(
      projectId: projectId,
      title: 'Контекст',
      content: 'что помнить',
    );

    // --- the guard ---------------------------------------------------------

    // Deleting an active project is refused: `canHardDeleteProject`. The client
    // refuses before asking, but the rule lives here, and this is the only
    // place that can prove it.
    await expectLater(
      api.deleteProject(projectId),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
      ),
      reason: 'archive is a precondition of delete, not a suggestion',
    );

    // --- archive -----------------------------------------------------------

    final archived = await api.archiveProject(projectId);
    expect(archived.archivedAt, isNotNull);

    final boardApi = BoardApi(client);
    expect(
      (await boardApi.fetchBoard()).map((row) => row.project.id),
      isNot(contains(projectId)),
      reason: 'an archived project leaves the board',
    );
    expect(
      (await boardApi.fetchBoard(archived: true)).map((row) => row.project.id),
      contains(projectId),
    );

    // Still readable by id, which is what lets a reminder deep link open a task
    // in a project that was archived after the alarm was armed. The route helper
    // (`getProjectOrThrow`) checks existence and nothing else, deliberately.
    expect((await api.fetchProject(projectId)).archivedAt, isNotNull);
    expect(await api.fetchTasks(projectId), hasLength(1));

    // --- unarchive ---------------------------------------------------------

    final restored = await api.unarchiveProject(projectId);
    expect(restored.archivedAt, isNull);
    expect(
      (await boardApi.fetchBoard()).map((row) => row.project.id),
      contains(projectId),
    );

    // --- delete ------------------------------------------------------------

    await api.archiveProject(projectId);
    await api.deleteProject(projectId);

    await expectLater(
      api.fetchProject(projectId),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
      reason: 'the delete is real and there is nothing to restore from',
    );

    // The teardown registered by `openScratchProject` will now fail to remove
    // an already-removed project; it prints and moves on, which is why it
    // catches.
    // ignore: avoid_print
    print('live project lifecycle: archived, unarchived, deleted $projectId');
  }, skip: skip);

  test('the live scope contract: create, move a project, refuse, delete', () async {
    // F7. The one part of scopes no fake can settle: what the real server does
    // when a scope is asked to disappear while a project still points at it.
    await openScratchProject();
    final scopes = ScopeApi(client);

    final before = await scopes.fetchScopes();
    expect(before, isNotEmpty, reason: 'the migration seeds one scope');
    expect(
      before.map((s) => s.position).toList(),
      orderedEquals(<double>[...before.map((s) => s.position)]..sort()),
      reason: 'GET /scopes is ordered by position',
    );

    final scratch = await scopes.createScope(
      name: 'Проверка скоупа ${DateTime.now().toIso8601String()}',
    );
    var cleanedUp = false;
    addTearDown(() async {
      if (cleanedUp) return;
      try {
        await scopes.deleteScope(scratch.id);
      } catch (error) {
        // ignore: avoid_print
        print('live: FAILED to remove scratch scope ${scratch.id}: $error');
      }
    });

    // Appended at the end, and carrying a real position rather than whatever
    // the client guessed -- `position` is a Float on the wire for the same
    // reason `Task.position` is, so a client that declared `int` would truncate
    // a bisected value here too.
    expect(scratch.position, greaterThan(before.last.position));
    expect(scratch.position, isA<double>());

    // The scratch project moves into it, with no name in the payload.
    final moved = await api.moveProjectToScope(projectId, scopeId: scratch.id);
    expect(moved.scopeId, scratch.id);
    expect(
      moved.name,
      contains('Проверка записи'),
      reason: 'a move must not rewrite the name',
    );

    // ...and now the scope cannot be deleted, which is the whole guard.
    await expectLater(
      scopes.deleteScope(scratch.id),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('projects')),
      ),
    );

    // An unknown scope is a 404 about the scope, not a 500 about a constraint.
    await expectLater(
      api.moveProjectToScope(projectId, scopeId: 'scope_does_not_exist'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
      ),
    );

    // Move the project back out, and the scope deletes.
    await api.moveProjectToScope(projectId, scopeId: before.first.id);
    await scopes.deleteScope(scratch.id);
    cleanedUp = true;

    final after = await scopes.fetchScopes();
    expect(after.map((s) => s.id), isNot(contains(scratch.id)));
    expect(after.map((s) => s.id), containsAll(before.map((s) => s.id)));

    // ignore: avoid_print
    print('live scopes: created, moved a project in and out, 409 and 404 seen');
  }, skip: skip);
}
