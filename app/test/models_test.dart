import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/login_result.dart';
import 'package:taskradar/models/note.dart';
import 'package:taskradar/models/project.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';

import 'support/fixtures.dart';

void main() {
  group('Project', () {
    test('parses an active project and keeps timestamps as ISO strings', () {
      final project = Project.fromJson(projectWithTasksJson());

      expect(project.id, 'prj_1');
      expect(project.name, 'TaskRadar');
      expect(project.archivedAt, isNull);
      // Not a DateTime, on purpose -- see the comment on Project.
      expect(project.createdAt, '2026-08-01T09:15:00.000Z');
    });

    test('ignores the extra board-only `tasks` key', () {
      // GET /board sends a flat object: project fields plus `tasks`. Project's
      // generated parser must skip the unknown key rather than choke, which is
      // what lets BoardProject reuse it instead of duplicating the fields.
      expect(() => Project.fromJson(projectWithTasksJson()), returnsNormally);
    });

    test('parses an archived project', () {
      final json = projectWithTasksJson()
        ..['archivedAt'] = '2026-09-01T00:00:00.000Z';

      expect(Project.fromJson(json).archivedAt, '2026-09-01T00:00:00.000Z');
    });
  });

  group('Task', () {
    test('parses every status without mapping tables', () {
      final tasks = (projectWithTasksJson()['tasks'] as List<dynamic>)
          .map((dynamic e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(
        tasks.map((task) => task.status),
        <TaskStatus>[TaskStatus.done, TaskStatus.pending, TaskStatus.blocked],
      );
    });

    test('keeps remindAt as the raw ISO string so its date prefix survives', () {
      final blocked = Task.fromJson(
        (projectWithTasksJson()['tasks'] as List<dynamic>)[2] as Map<String, dynamic>,
      );

      expect(blocked.remindAt, '2026-09-18T00:00:00.000Z');
      // The F2 reminder logic compares this prefix against the local calendar
      // date. Parsing into DateTime here would reintroduce the timezone bug
      // documented in frontend/src/lib/reminders.ts.
      expect(blocked.remindAt!.substring(0, 10), '2026-09-18');
    });

    test('carries the server-computed isCurrent flag', () {
      final tasks = (projectWithTasksJson()['tasks'] as List<dynamic>)
          .map((dynamic e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(tasks.map((task) => task.isCurrent), <bool>[false, true, false]);
    });

    test('accepts a null description', () {
      final json = (projectWithTasksJson()['tasks'] as List<dynamic>)[0]
          as Map<String, dynamic>;

      expect(Task.fromJson(json).description, isNull);
    });
  });

  group('Note', () {
    test('parses', () {
      final note = Note.fromJson(<String, dynamic>{
        'id': 'nte_1',
        'projectId': 'prj_1',
        'title': 'Контекст',
        'content': '# Заголовок\n\nтекст',
        'createdAt': '2026-08-01T09:15:00.000Z',
        'updatedAt': '2026-08-01T09:15:00.000Z',
      });

      expect(note.title, 'Контекст');
      expect(note.content, startsWith('# Заголовок'));
    });
  });

  group('BoardProject', () {
    test('parses the bare array and preserves server ordering', () {
      final board = BoardProject.listFromJson(boardJson());

      expect(board, hasLength(2));
      // Projects come back in createdAt ascending order and nothing re-sorts.
      expect(board.map((row) => row.project.id), <String>['prj_1', 'prj_2']);
      // Tasks in position ascending order -- annotateIsCurrent on the server
      // depends on it, so the client must not shuffle them either.
      expect(
        board.first.tasks.map((task) => task.position),
        <double>[1000, 2000, 3000],
      );
    });

    test('splits the flat JSON into a Project plus its tasks', () {
      final row = BoardProject.fromJson(projectWithTasksJson());

      expect(row.project.name, 'TaskRadar');
      expect(row.tasks, hasLength(3));
      expect(row.tasks.first.projectId, row.project.id);
    });

    test('a project with no tasks parses to an empty list, not a failure', () {
      final row = BoardProject.fromJson(emptyProjectJson());

      expect(row.tasks, isEmpty);
      expect(row.currentTask, isNull);
    });

    test('tolerates a missing tasks key rather than throwing away the board', () {
      final json = emptyProjectJson()..remove('tasks');

      expect(BoardProject.fromJson(json).tasks, isEmpty);
    });

    test('currentTask reads the server flag instead of recomputing it', () {
      final row = BoardProject.fromJson(projectWithTasksJson());

      expect(row.currentTask?.id, 'tsk_2');
    });

    test('currentTask trusts isCurrent even when it contradicts the statuses', () {
      // Deliberately perverse input: the flag says the *last* task is current
      // although an earlier pending one exists. The client must not second-guess
      // the server -- backend/src/domain/isCurrent.ts owns that rule.
      final json = projectWithTasksJson();
      final tasks = json['tasks'] as List<dynamic>;
      (tasks[1] as Map<String, dynamic>)['isCurrent'] = false;
      (tasks[2] as Map<String, dynamic>)['isCurrent'] = true;

      expect(BoardProject.fromJson(json).currentTask?.id, 'tsk_3');
    });

    test('toJson round-trips back through fromJson', () {
      // The F2 snapshot cache writes with toJson and reads with fromJson. If the
      // two disagreed about whether `tasks` is nested, the failure would only
      // show up on a device with no network.
      final original = BoardProject.fromJson(projectWithTasksJson());
      final restored = BoardProject.fromJson(original.toJson());

      expect(restored, original);
      expect(original.toJson()['tasks'], isA<List<dynamic>>());
      // Flat: project fields sit at the top level, not under a `project` key.
      expect(original.toJson()['name'], 'TaskRadar');
      expect(original.toJson().containsKey('project'), isFalse);
    });
  });

  group('LoginResult', () {
    test('parses the login body and reads expiresIn as seconds', () {
      final result = LoginResult.fromJson(loginOkJson());

      expect(result.ok, isTrue);
      expect(result.token, 'jwt.token.value');
      expect(result.expiresIn, 2592000);
      expect(result.lifetime, const Duration(days: 30));
    });
  });
}
