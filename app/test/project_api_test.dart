import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/api/patch_field.dart';
import 'package:taskradar/api/project_api.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';

import 'support/fake_backend.dart';
import 'support/fake_project_backend.dart';
import 'support/fixtures.dart';

/// [ProjectApi] against the fake transport: the requests it sends and the
/// responses it can parse.
///
/// Everything above the socket is real here -- the interceptors, dio's JSON
/// transformer, the `DioException -> ApiException` mapping -- because the bugs
/// this iteration can produce are all in the *bytes*: a key that should not have
/// been sent, a status name that does not match the enum, a `Float` parsed as an
/// `int`.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late ProjectApi api;
  late String projectId;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    api = ProjectApi(backend.client);
    projectId = server.addProject(name: 'Дача', id: 'prj_1');
  });

  group('reading', () {
    test('GET /projects/:id parses the project', () async {
      final project = await api.fetchProject(projectId);

      expect(project.id, 'prj_1');
      expect(project.name, 'Дача');
      expect(project.archivedAt, isNull);
      expect(backend.lastRequest.path, '/projects/prj_1');
    });

    test('an unknown project is a 404, not a network failure', () async {
      // The distinction the project screen turns into "проект не найден"
      // instead of "нет связи" -- the second is retryable and the first is not.
      await expectLater(
        api.fetchProject('nope'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e,
                'is not a NetworkException',
                isNot(isA<NetworkException>()),
              ),
        ),
      );
    });

    test('GET tasks comes back in position order with isCurrent', () async {
      server.addTask(projectId: projectId, title: 'Сделано', status: 'done');
      server.addTask(projectId: projectId, title: 'Текущая');
      server.addTask(projectId: projectId, title: 'Потом');

      final tasks = await api.fetchTasks(projectId);

      expect(tasks.map((task) => task.title), <String>[
        'Сделано',
        'Текущая',
        'Потом',
      ]);
      expect(tasks.map((task) => task.isCurrent), <bool>[false, true, false]);
    });

    test('a bisected position parses -- it is a Float, not an int', () async {
      // What this guards: `position` is a Prisma `Float`, so the fourth reorder
      // into the same slot produces 1062.5. Declared `int`, the generated
      // parser is `(json['position'] as num).toInt()` -- it does not throw, it
      // quietly returns 1062, and the client's ordering key stops matching the
      // server's with nothing anywhere to say so.
      server.addTask(projectId: projectId, title: 'Дробная', position: 1062.5);

      final tasks = await api.fetchTasks(projectId);
      expect(tasks.single.position, 1062.5);
    });

    test('GET notes parses them', () async {
      server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: '# Заголовок\n\nтекст',
      );

      final notes = await api.fetchNotes(projectId);

      expect(notes.single.title, 'Контекст');
      expect(notes.single.content, '# Заголовок\n\nтекст');
    });
  });

  group('creating a task', () {
    test('sends only the title and parses the 201', () async {
      final task = await api.createTask(
        projectId: projectId,
        title: 'Позвонить прорабу',
      );

      expect(backend.lastRequest.method, 'POST');
      expect(backend.lastRequest.path, '/projects/prj_1/tasks');
      expect(backend.lastRequest.data, <String, dynamic>{
        'title': 'Позвонить прорабу',
      });

      expect(task.title, 'Позвонить прорабу');
      expect(task.status, TaskStatus.pending);
      expect(task.position, 1000);
    });

    test('the 201 has no isCurrent and the placeholder is false', () async {
      // The server answers `POST` with the raw Prisma row. A required `bool`
      // would throw on the missing key, which is why `_taskFromMutation`
      // injects one -- and why nothing may believe it.
      final task = await api.createTask(projectId: projectId, title: 'Первая');

      expect(task.isCurrent, isFalse);

      // ...even though this task *is* in fact the current one, which only the
      // list endpoint will admit.
      final list = await api.fetchTasks(projectId);
      expect(list.single.isCurrent, isTrue);
    });
  });

  group('PATCH /tasks/:id -- undefined versus null', () {
    late String taskId;

    setUp(() {
      taskId = server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        description: 'у Петра, обещал во вторник',
        status: 'blocked',
        remindAt: '2026-09-18T00:00:00.000Z',
      );
    });

    test('a status change does not mention the description', () async {
      await api.updateTask(taskId, status: TaskStatus.pending);

      final body = server.patches.last.body;
      expect(body, <String, dynamic>{'status': 'pending'});

      // The assertion that matters: absent, not null. A null here would have
      // erased the description, with a 200 and no visible symptom.
      expect(body.containsKey('description'), isFalse);
      expect(body.containsKey('remindAt'), isFalse);

      final saved = await api.fetchTasks(projectId);
      expect(saved.single.description, 'у Петра, обещал во вторник');
      expect(saved.single.remindAt, '2026-09-18T00:00:00.000Z');
    });

    test('a title change mentions nothing else', () async {
      await api.updateTask(taskId, title: 'Жду кабель от Петра');

      expect(server.patches.last.body, <String, dynamic>{
        'title': 'Жду кабель от Петра',
      });

      final saved = await api.fetchTasks(projectId);
      expect(saved.single.description, 'у Петра, обещал во вторник');
      expect(saved.single.status, TaskStatus.blocked);
    });

    test('an explicit clear erases the description', () async {
      await api.updateTask(
        taskId,
        description: const PatchField<String>.clear(),
      );

      final body = server.patches.last.body;
      expect(body.containsKey('description'), isTrue);
      expect(body['description'], isNull);

      final saved = await api.fetchTasks(projectId);
      expect(saved.single.description, isNull);
      // ...and nothing else moved.
      expect(saved.single.title, 'Жду кабель');
      expect(saved.single.remindAt, '2026-09-18T00:00:00.000Z');
    });

    test('status and remindAt clear travel together', () async {
      // The real "back to pending" call: leaving `blocked` drops the date,
      // because a reminder only means something while the task is waiting.
      await api.updateTask(
        taskId,
        status: TaskStatus.pending,
        remindAt: const PatchField<String>.clear(),
      );

      expect(server.patches.last.body, <String, dynamic>{
        'status': 'pending',
        'remindAt': null,
      });

      final saved = await api.fetchTasks(projectId);
      expect(saved.single.status, TaskStatus.pending);
      expect(saved.single.remindAt, isNull);
    });

    test('a remindAt date is stored as UTC midnight of that day', () async {
      await api.updateTask(
        taskId,
        remindAt: const PatchField<String>.to('2026-10-01'),
      );

      final saved = await api.fetchTasks(projectId);
      // The representation every date comparison in the app depends on -- see
      // `domain/reminders.dart`.
      expect(saved.single.remindAt, '2026-10-01T00:00:00.000Z');
    });

    test('a patch with nothing in it never reaches the wire', () async {
      final before = backend.requests.length;

      expect(() => api.updateTask(taskId), throwsArgumentError);
      expect(backend.requests, hasLength(before));
    });

    test('the status name on the wire is the enum name', () async {
      // `TaskStatus`'s value names are spelled to match the wire strings, and
      // nothing must start sending `TaskStatus.blocked`.
      await api.updateTask(taskId, status: TaskStatus.done);
      expect(server.patches.last.body['status'], 'done');
    });
  });

  group('PATCH /tasks/:id/position', () {
    test('sends both neighbour keys, nulls included', () async {
      final a = server.addTask(projectId: projectId, title: 'a');
      server.addTask(projectId: projectId, title: 'b');

      await api.moveTask(a, beforeTaskId: null, afterTaskId: 'nonsense');

      // Both keys present: `updateTaskPositionSchema` rejects a body where both
      // are *absent*, and an explicit null is the protocol's "no neighbour".
      final body = server.patches.last.body;
      expect(body.containsKey('beforeTaskId'), isTrue);
      expect(body.containsKey('afterTaskId'), isTrue);
      expect(body['beforeTaskId'], isNull);
    });

    test('the reply is the moved row only', () async {
      final a = server.addTask(projectId: projectId, title: 'a');
      final b = server.addTask(projectId: projectId, title: 'b');
      final c = server.addTask(projectId: projectId, title: 'c');

      final moved = await api.moveTask(a, beforeTaskId: b, afterTaskId: c);

      expect(moved.id, a);
      expect(moved.position, 2500);
      // No isCurrent, and no word about b or c.
      expect(moved.isCurrent, isFalse);
    });

    test('an exhausted gap renumbers rows the reply says nothing about', () async {
      final a = server.addTask(projectId: projectId, title: 'a');
      final b = server.addTask(projectId: projectId, title: 'b');
      final c = server.addTask(projectId: projectId, title: 'c');

      // Squeeze b and c together until no double fits between them, the state a
      // real project reaches after enough drags into the same slot.
      server.squeezePositions(b, c);
      final squeezed = server.positionsInOrder(projectId);

      final moved = await api.moveTask(a, beforeTaskId: b, afterTaskId: c);

      // The server renumbered the whole project (b and c are on fresh
      // 1000-spaced positions) and then moved `a` between them -- and the reply
      // for `a` is the *only* thing the client was told about any of it. The
      // client's copy of `c` is now stale by 1000, silently.
      expect(server.positionsInOrder(projectId), isNot(squeezed));
      expect(moved.position, 2500);

      final fresh = await api.fetchTasks(projectId);
      expect(fresh.map((task) => task.title), <String>['b', 'a', 'c']);
      expect(fresh.map((task) => task.position), <double>[2000, 2500, 3000]);

      // Spelled out, because this is the whole reason
      // `ProjectTasks.move` re-reads the list unconditionally: the row that
      // changed without being mentioned.
      expect(squeezed.last, lessThan(2001));
      expect(fresh.last.position, 3000);
    });
  });

  group('deleting', () {
    test('a task, answered 204 with no body', () async {
      final id = server.addTask(projectId: projectId, title: 'Лишняя');

      await api.deleteTask(id);

      expect(backend.lastRequest.method, 'DELETE');
      expect(server.tasks, isEmpty);
    });

    test('a note, answered 204 with no body', () async {
      final id = server.addNote(projectId: projectId, title: 'Лишняя');

      await api.deleteNote(id);

      expect(server.notes, isEmpty);
    });
  });

  group('notes', () {
    test('create sends title and content', () async {
      final note = await api.createNote(
        projectId: projectId,
        title: 'Контекст',
        content: '- раз\n- два',
      );

      expect(backend.lastRequest.data, <String, dynamic>{
        'title': 'Контекст',
        'content': '- раз\n- два',
      });
      expect(note.content, '- раз\n- два');
    });

    test('an empty content is a value, not an omission', () async {
      // `Note.content` is a non-null column whose empty value is `""`, so
      // clearing a note is `content: ''` and there is no PatchField in sight.
      final id = server.addNote(
        projectId: projectId,
        title: 'Контекст',
        content: 'текст',
      );

      await api.updateNote(id, content: '');

      expect(server.patches.last.body, <String, dynamic>{'content': ''});
      final saved = await api.fetchNotes(projectId);
      expect(saved.single.content, '');
      expect(saved.single.title, 'Контекст');
    });

    test('a title-only patch leaves the content alone', () async {
      final id = server.addNote(
        projectId: projectId,
        title: 'Старый',
        content: 'важный текст',
      );

      await api.updateNote(id, title: 'Новый');

      expect(server.patches.last.body, <String, dynamic>{'title': 'Новый'});
      final saved = await api.fetchNotes(projectId);
      expect(saved.single.content, 'важный текст');
    });

    test('an empty patch never reaches the wire', () {
      expect(() => api.updateNote('nte_1'), throwsArgumentError);
    });
  });

  group('mergeMutatedTask', () {
    test('a raw mutation row does not parse as a Task on its own', () {
      // Why `_taskFromMutation` has to inject a placeholder at all: `isCurrent`
      // is a required non-null field and the mutation endpoints do not send it.
      expect(
        () => Task.fromJson(mutatedTaskJson(id: 'tsk_1')),
        throwsA(isA<TypeError>()),
      );
    });

    test('takes every field from the server except isCurrent', () {
      final known = Task.fromJson(
        taskJson(id: 'tsk_1', title: 'Старое', isCurrent: true),
      );
      // What `_taskFromMutation` produces: the row, plus the `false` placeholder.
      final mutated = Task.fromJson(
        taskJson(
          id: 'tsk_1',
          title: 'Новое',
          description: 'описание',
          position: 4500.5,
          updatedAt: '2026-09-16T12:30:00.000Z',
          isCurrent: false,
        ),
      );

      final merged = mergeMutatedTask(known, mutated);

      expect(merged.title, 'Новое');
      expect(merged.description, 'описание');
      expect(merged.position, 4500.5);
      expect(merged.updatedAt, '2026-09-16T12:30:00.000Z');

      // The one field the mutation response did not compute. Taking the
      // server's placeholder `false` here is the React client's bug
      // (`TaskListItem.onUpdated`): the highlight vanishes off the current task
      // the moment you rename it.
      expect(merged.isCurrent, isTrue);
    });
  });

  group('no network', () {
    test(
      'every write surfaces a NetworkException, not a status code',
      () async {
        final id = server.addTask(projectId: projectId, title: 'Задача');
        backend.alwaysFailToConnect();

        await expectLater(
          api.createTask(projectId: projectId, title: 'x'),
          throwsA(isA<NetworkException>()),
        );
        await expectLater(
          api.updateTask(id, title: 'x'),
          throwsA(isA<NetworkException>()),
        );
        await expectLater(
          api.moveTask(id, beforeTaskId: null, afterTaskId: null),
          throwsA(isA<NetworkException>()),
        );
        await expectLater(api.deleteTask(id), throwsA(isA<NetworkException>()));
        await expectLater(
          api.createNote(projectId: projectId, title: 'x'),
          throwsA(isA<NetworkException>()),
        );
      },
    );
  });
}
