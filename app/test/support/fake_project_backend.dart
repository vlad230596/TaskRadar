import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'fake_backend.dart';

/// An in-memory re-implementation of the project/task/note routes.
///
/// ## Why a stateful fake rather than canned responses
///
/// F3's whole difficulty is *sequences*: write, then re-read, then splice the
/// answer into the board. A canned `alwaysRespond` cannot express that -- the
/// re-read would return the state from before the write, so a test would pass
/// while the client did the wrong thing, or fail while it did the right one.
///
/// So this keeps real rows and applies the same rules the backend applies, and
/// the rules it copies are exactly the ones the client's correctness depends on:
///
/// - **`annotateIsCurrent`** (`backend/src/domain/isCurrent.ts`): the first
///   `pending` task in position order, and only on the list endpoints. The
///   mutation endpoints answer with a raw row and **no `isCurrent` key at all**,
///   which is the single most important thing this fake reproduces -- it is what
///   makes "the client must re-read after a structural change" a testable claim
///   rather than a comment.
/// - **`computeAppendPosition` / `computePositionBetween`** with the rebalance
///   fallback (`backend/src/domain/position.ts`), including the part where a
///   rebalance renumbers rows the response says nothing about.
/// - **the three-state PATCH** (`backend/src/schemas.ts`): a key that is absent
///   leaves the column alone, a key that is null clears it.
/// - 404 from `getActiveProjectOrThrow` for an unknown or archived project.
///
/// It is not a general-purpose server: no auth, no validation beyond what the
/// tests exercise, one flat namespace of ids.
class FakeProjectBackend {
  FakeProjectBackend(this.backend) {
    _install();
  }

  final FakeBackend backend;

  final Map<String, Map<String, dynamic>> projects =
      <String, Map<String, dynamic>>{};
  final List<Map<String, dynamic>> tasks = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> notes = <Map<String, dynamic>>[];

  /// Every PATCH body the client sent, keyed by route, newest last. The
  /// undefined-vs-null assertions read this.
  final List<({String path, Map<String, dynamic> body})> patches =
      <({String path, Map<String, dynamic> body})>[];

  int _nextId = 0;

  static const double positionGap = 1000;

  String _id(String prefix) => '${prefix}_${++_nextId}';

  // --- seeding ---------------------------------------------------------------

  String addProject({
    required String name,
    String? id,
    String? archivedAt,
    String createdAt = '2026-08-01T09:00:00.000Z',
  }) {
    final projectId = id ?? _id('prj');
    projects[projectId] = <String, dynamic>{
      'id': projectId,
      'name': name,
      'archivedAt': archivedAt,
      'createdAt': createdAt,
      'updatedAt': createdAt,
    };
    return projectId;
  }

  String addTask({
    required String projectId,
    required String title,
    String? id,
    String status = 'pending',
    String? description,
    String? remindAt,
    double? position,
  }) {
    final taskId = id ?? _id('tsk');
    tasks.add(<String, dynamic>{
      'id': taskId,
      'projectId': projectId,
      'title': title,
      'description': description,
      'status': status,
      'position': position ?? _appendPosition(projectId),
      'remindAt': remindAt,
      'createdAt': '2026-08-01T10:00:00.000Z',
      'updatedAt': '2026-08-01T10:00:00.000Z',
    });
    return taskId;
  }

  String addNote({
    required String projectId,
    required String title,
    String content = '',
    String? id,
  }) {
    final noteId = id ?? _id('nte');
    notes.add(<String, dynamic>{
      'id': noteId,
      'projectId': projectId,
      'title': title,
      'content': content,
      'createdAt': '2026-08-01T11:00:00.000Z',
      'updatedAt': '2026-08-01T11:00:00.000Z',
    });
    return noteId;
  }

  /// Puts two adjacent tasks a single double-epsilon apart, so that the next
  /// move between them exhausts the float gap and forces the server's rebalance
  /// path. This is the state a real project reaches after enough drags into the
  /// same slot; reproducing it deliberately is the only way to test what the
  /// client does about it.
  void squeezePositions(String firstTaskId, String secondTaskId) {
    final first = _task(firstTaskId)!;
    final second = _task(secondTaskId)!;
    final base = first['position'] as double;

    second['position'] = _nextDouble(base);
  }

  static double _nextDouble(double value) {
    // The smallest representable step up from `value`. `computePositionBetween`
    // bisects and then checks `mid <= before || mid >= after`, which is exactly
    // what fails for two consecutive doubles.
    var step = math.max(value.abs(), 1) * 1e-16;
    while (value + step == value) {
      step *= 2;
    }
    return value + step;
  }

  // --- the routes ------------------------------------------------------------

  void _install() {
    backend.on('GET', '/board', (match) {
      final archived = match.options.queryParameters['archived'] == 'true';

      return jsonResponse(<dynamic>[
        for (final project in _projectsInOrder())
          if ((project['archivedAt'] != null) == archived)
            <String, dynamic>{
              ...project,
              'tasks': _annotated(project['id'] as String),
            },
      ]);
    });

    backend.on('GET', '/projects/:id', (match) {
      final project = _activeProject(match.params['id']!);
      if (project == null) return _notFound('Project');
      return jsonResponse(project);
    });

    backend.on('GET', '/projects/:id/tasks', (match) {
      final projectId = match.params['id']!;
      if (_activeProject(projectId) == null) return _notFound('Project');
      return jsonResponse(_annotated(projectId));
    });

    backend.on('POST', '/projects/:id/tasks', (match) {
      final projectId = match.params['id']!;
      if (_activeProject(projectId) == null) return _notFound('Project');

      final body = match.body;
      final row = <String, dynamic>{
        'id': _id('tsk'),
        'projectId': projectId,
        'title': body['title'] as String,
        'description': body['description'],
        'status': body['status'] ?? 'pending',
        'position': _appendPosition(projectId),
        'remindAt': body['remindAt'],
        'createdAt': '2026-09-16T12:00:00.000Z',
        'updatedAt': '2026-09-16T12:00:00.000Z',
      };
      tasks.add(row);

      // 201 with the *raw* row: no `isCurrent`. See the class comment.
      return jsonResponse(row, statusCode: 201);
    });

    backend.on('GET', '/projects/:id/notes', (match) {
      final projectId = match.params['id']!;
      if (_activeProject(projectId) == null) return _notFound('Project');
      return jsonResponse(<dynamic>[
        for (final note in notes)
          if (note['projectId'] == projectId) note,
      ]);
    });

    backend.on('POST', '/projects/:id/notes', (match) {
      final projectId = match.params['id']!;
      if (_activeProject(projectId) == null) return _notFound('Project');

      final row = <String, dynamic>{
        'id': _id('nte'),
        'projectId': projectId,
        'title': match.body['title'] as String,
        'content': match.body['content'] ?? '',
        'createdAt': '2026-09-16T12:00:00.000Z',
        'updatedAt': '2026-09-16T12:00:00.000Z',
      };
      notes.add(row);
      return jsonResponse(row, statusCode: 201);
    });

    // Registered before `/tasks/:id` so the longer path wins.
    backend.on('PATCH', '/tasks/:id/position', (match) {
      final task = _task(match.params['id']!);
      if (task == null) return _notFound('Task');

      patches.add((path: match.options.path, body: match.body));

      final beforeId = match.body['beforeTaskId'] as String?;
      final afterId = match.body['afterTaskId'] as String?;
      if (beforeId == task['id'] || afterId == task['id']) {
        return _error(400, 'A task cannot be positioned relative to itself');
      }

      double? positionOf(String? id) =>
          id == null ? null : _task(id)?['position'] as double?;

      var before = positionOf(beforeId);
      var after = positionOf(afterId);

      double? between = _between(before, after);
      if (between == null) {
        // The rebalance path: renumber every task in the project, then retry.
        // Note what the response does *not* say about it.
        final ordered = _ordered(task['projectId'] as String);
        for (var i = 0; i < ordered.length; i++) {
          ordered[i]['position'] = (i + 1) * positionGap;
        }
        before = positionOf(beforeId);
        after = positionOf(afterId);
        between = _between(before, after);
      }

      task['position'] = between;
      return jsonResponse(task);
    });

    backend.on('PATCH', '/tasks/:id', (match) {
      final task = _task(match.params['id']!);
      if (task == null) return _notFound('Task');

      final body = match.body;
      patches.add((path: match.options.path, body: body));

      if (body.isEmpty) {
        return _error(400, 'At least one field must be provided');
      }

      // The three-state copy, exactly as `routes/tasks.ts` writes it:
      // `containsKey` is "was it provided", the value is what to store.
      for (final field in <String>['title', 'description', 'status']) {
        if (body.containsKey(field)) task[field] = body[field];
      }
      if (body.containsKey('remindAt')) {
        final value = body['remindAt'];
        // `z.coerce.date()` -> UTC midnight of the calendar date, which is the
        // representation `domain/reminders.dart` is built around.
        task['remindAt'] = value == null
            ? null
            : '${(value as String).substring(0, 10)}T00:00:00.000Z';
      }
      task['updatedAt'] = '2026-09-16T12:30:00.000Z';

      return jsonResponse(task);
    });

    backend.on('DELETE', '/tasks/:id', (match) {
      final task = _task(match.params['id']!);
      if (task == null) return _notFound('Task');
      tasks.remove(task);
      return ResponseBody.fromString('', 204);
    });

    backend.on('PATCH', '/notes/:id', (match) {
      final note = _note(match.params['id']!);
      if (note == null) return _notFound('Note');

      final body = match.body;
      patches.add((path: match.options.path, body: body));
      if (body.isEmpty) {
        return _error(400, 'At least one field must be provided');
      }

      for (final field in <String>['title', 'content']) {
        if (body.containsKey(field)) note[field] = body[field];
      }
      note['updatedAt'] = '2026-09-16T12:30:00.000Z';

      return jsonResponse(note);
    });

    backend.on('DELETE', '/notes/:id', (match) {
      final note = _note(match.params['id']!);
      if (note == null) return _notFound('Note');
      notes.remove(note);
      return ResponseBody.fromString('', 204);
    });
  }

  // --- the rules -------------------------------------------------------------

  /// `computePositionBetween`, including its exhaustion check. Null means
  /// "needs a rebalance".
  static double? _between(double? before, double? after) {
    if (before == null && after == null) return positionGap;
    if (before == null) return after! - positionGap;
    if (after == null) return before + positionGap;
    if (before >= after) return null;

    final mid = before + (after - before) / 2;
    if (mid <= before || mid >= after) return null;
    return mid;
  }

  double _appendPosition(String projectId) {
    final ordered = _ordered(projectId);
    if (ordered.isEmpty) return positionGap;
    return (ordered.last['position'] as double) + positionGap;
  }

  List<Map<String, dynamic>> _ordered(String projectId) {
    final rows = <Map<String, dynamic>>[
      for (final task in tasks)
        if (task['projectId'] == projectId) task,
    ];
    rows.sort(
      (a, b) => (a['position'] as double).compareTo(b['position'] as double),
    );
    return rows;
  }

  /// The list endpoints' shape: ordered, and with `isCurrent` attached.
  List<Map<String, dynamic>> _annotated(String projectId) {
    var assigned = false;

    return <Map<String, dynamic>>[
      for (final task in _ordered(projectId))
        <String, dynamic>{
          ...task,
          'isCurrent': () {
            if (assigned || task['status'] != 'pending') return false;
            assigned = true;
            return true;
          }(),
        },
    ];
  }

  Iterable<Map<String, dynamic>> _projectsInOrder() {
    final rows = projects.values.toList();
    rows.sort(
      (a, b) => (a['createdAt'] as String).compareTo(b['createdAt'] as String),
    );
    return rows;
  }

  Map<String, dynamic>? _activeProject(String id) {
    final project = projects[id];
    // `getActiveProjectOrThrow` in fact only checks existence, and archived
    // projects answer normally -- the guard against writing to an archived
    // project lives in the board query. Mirrored as-is so the fake cannot be
    // stricter than the server.
    return project;
  }

  Map<String, dynamic>? _task(String id) {
    for (final task in tasks) {
      if (task['id'] == id) return task;
    }
    return null;
  }

  Map<String, dynamic>? _note(String id) {
    for (final note in notes) {
      if (note['id'] == id) return note;
    }
    return null;
  }

  /// The task list as the client should end up seeing it, for assertions.
  List<String> titlesInOrder(String projectId) => <String>[
    for (final task in _ordered(projectId)) task['title'] as String,
  ];

  List<double> positionsInOrder(String projectId) => <double>[
    for (final task in _ordered(projectId)) task['position'] as double,
  ];

  String? currentTaskId(String projectId) {
    for (final task in _annotated(projectId)) {
      if (task['isCurrent'] == true) return task['id'] as String;
    }
    return null;
  }

  static ResponseBody _notFound(String what) => _error(404, '$what not found');

  static ResponseBody _error(int status, String message) => jsonResponse(
    <String, dynamic>{'error': 'Error', 'message': message},
    statusCode: status,
  );
}
