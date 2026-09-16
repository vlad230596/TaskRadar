import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_client.dart';
import 'package:taskradar/api/auth_api.dart';
import 'package:taskradar/api/patch_field.dart';
import 'package:taskradar/api/project_api.dart';
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
/// real models. This one is about everything F3 added, which is all writes -- and
/// writes are where fixtures are weakest, because a fixture is a recording of
/// what someone *believed* the server answers. Three of this iteration's
/// findings are invisible to any fixture:
///
/// - `POST`/`PATCH` on a task answer with the raw row and **no `isCurrent`**;
/// - `position` is a **Float**, so a few reorders into the same slot produce
///   `2937.5`, which a client that declared `int` silently truncates to `2937`;
/// - `description`/`remindAt` distinguish "absent" from "null", so a patch that
///   sends a stray null erases text with a 200 and no symptom.
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
        'name': 'F3 проверка записи ${DateTime.now().toIso8601String()}',
      },
    );
    final project = Project.fromJson(created);
    projectId = project.id;
    expect(project.name, contains('проверка записи'));

    // Registered immediately after creation, so a failure anywhere below still
    // cleans up. Archive, then delete -- the delete guard requires it.
    addTearDown(() async {
      try {
        await client.post<Map<String, dynamic>>('/projects/$projectId/archive');
        await client.delete<dynamic>('/projects/$projectId');
        // ignore: avoid_print
        print('live: removed scratch project $projectId');
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
}
