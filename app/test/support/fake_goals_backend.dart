import 'package:dio/dio.dart';

import 'fake_backend.dart';
import 'fixtures.dart';

/// A routed [FakeBackend] that keeps goals, contours and a board in memory
/// and answers the goals API the way `backend/src/routes/goals.ts` does --
/// enough for the goals screen, the goal screen and the link sheet.
class FakeGoalsBackend {
  FakeGoalsBackend({int workSlots = 2, bool twoContours = true}) {
    contours = <Map<String, dynamic>>[
      _contour('c_work', 'Работа', slots: workSlots, position: 1000),
      if (twoContours) _contour('c_home', 'Личное', position: 2000),
    ];
    _routes();
  }

  final FakeBackend backend = FakeBackend();

  late List<Map<String, dynamic>> contours;
  final List<Map<String, dynamic>> goals = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> achieved = <Map<String, dynamic>>[];

  /// `[taskId, title, status, projectId, projectName]` per task on the board.
  final List<Map<String, dynamic>> board = <Map<String, dynamic>>[
    boardProjectJson(
      id: 'prj_tr',
      name: 'TaskRadar',
      tasks: <Map<String, dynamic>>[
        taskJson(
          id: 't1',
          projectId: 'prj_tr',
          title: 'Спроектировать экран целей',
        ),
        taskJson(
          id: 't2',
          projectId: 'prj_tr',
          title: 'Шаги целей в виджете',
          position: 2000,
        ),
        taskJson(
          id: 't3',
          projectId: 'prj_tr',
          title: 'Старая сделанная',
          status: 'done',
          position: 3000,
        ),
      ],
    ),
    boardProjectJson(
      id: 'prj_dom',
      name: 'Дом',
      tasks: <Map<String, dynamic>>[
        taskJson(id: 't4', projectId: 'prj_dom', title: 'Купить лампочки'),
      ],
    ),
  ];

  /// Every write, as `METHOD path body`.
  final List<String> writes = <String>[];

  /// The working sets: task id -> contour id (null for "no contour", as a
  /// task taken by a server from before contours).
  final Map<String, String?> focused = <String, String?>{};

  /// The stored manual choice, as `GET /contours` answers it.
  Map<String, dynamic> active = <String, dynamic>{
    'contourId': 'c_work',
    'until': null,
  };

  Map<String, dynamic>? _boardTask(String taskId) {
    for (final project in board) {
      for (final task in project['tasks'] as List) {
        if (task['id'] == taskId) {
          return <String, dynamic>{
            ...(task as Map<String, dynamic>),
            'project': <String, dynamic>{
              'id': project['id'],
              'name': project['name'],
            },
          };
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _focusRows() => <Map<String, dynamic>>[
    for (final (index, entry) in focused.entries.indexed)
      <String, dynamic>{
        ...?_boardTask(entry.key),
        'focusedAt': DateTime.utc(
          2026,
          11,
          24,
          9,
          40 + index,
        ).toIso8601String(),
        'focusContourId': entry.value,
      },
  ];

  /// Paths answered with 409 `slots_full`.
  final Set<String> slotsFullOn = <String>{};

  static Map<String, dynamic> _contour(
    String id,
    String name, {
    int slots = 2,
    num position = 1000,
  }) => <String, dynamic>{
    'id': id,
    'name': name,
    'slots': slots,
    'windowDays': 7,
    'schedule': null,
    'position': position,
  };

  /// A goal row; [state] is `slot`, `bench` or `achieved`.
  Map<String, dynamic> addGoal(
    String id,
    String title, {
    String contourId = 'c_work',
    String state = 'slot',
    String? why,
    List<String> taskIds = const <String>[],
    bool expired = false,
    num position = 1000,
  }) {
    final row = <String, dynamic>{
      'id': id,
      'contourId': contourId,
      'title': title,
      'why': why,
      'state': state,
      'position': position,
      'createdAt': '2026-11-01T10:00:00.000Z',
      'windowDays': 7,
      'ownWindowDays': null,
      'windowExpired': expired,
      'slottedAt': state == 'slot' ? '2026-11-20T10:00:00.000Z' : null,
      'windowEndsAt': state == 'slot'
          ? (expired
                ? DateTime.now()
                      .subtract(const Duration(days: 1))
                      .toUtc()
                      .toIso8601String()
                : DateTime.now()
                      .add(const Duration(days: 3, hours: 2))
                      .toUtc()
                      .toIso8601String())
          : null,
      'achievedAt': state == 'achieved' ? '2026-11-21T10:00:00.000Z' : null,
      'tasks': <Map<String, dynamic>>[],
      'ideas': <Map<String, dynamic>>[],
    };
    for (final taskId in taskIds) {
      (row['tasks'] as List).add(_goalTask(taskId));
    }
    _recount(row);
    (state == 'achieved' ? achieved : goals).add(row);
    return row;
  }

  Map<String, dynamic> _goalTask(String taskId) {
    for (final project in board) {
      for (final task in project['tasks'] as List) {
        if (task['id'] == taskId) {
          return <String, dynamic>{
            'id': taskId,
            'title': task['title'],
            'status': task['status'],
            'projectId': project['id'],
            'projectName': project['name'],
            'focusedAt': null,
            'focusContourId': null,
          };
        }
      }
    }
    throw StateError('no task $taskId');
  }

  void _recount(Map<String, dynamic> row) {
    final tasks = (row['tasks'] as List).cast<Map<String, dynamic>>();
    row['progress'] = <String, dynamic>{
      'done': tasks.where((t) => t['status'] == 'done').length,
      'total': tasks.length,
    };
    row['nextStep'] = tasks.where((t) => t['status'] == 'pending').firstOrNull;
  }

  Map<String, dynamic> _find(String id) => <Map<String, dynamic>>[
    ...goals,
    ...achieved,
  ].firstWhere((g) => g['id'] == id);

  int _inSlots(String contourId) => goals
      .where((g) => g['contourId'] == contourId && g['state'] == 'slot')
      .length;

  ResponseBody _slotsFull() => jsonResponse(<String, dynamic>{
    'error': 'slots_full',
    'message': 'All slots are taken',
    'details': <String, dynamic>{'slots': 2},
  }, statusCode: 409);

  void _routes() {
    backend
      ..on(
        'GET',
        '/contours',
        (_) => jsonResponse(<String, dynamic>{
          'contours': contours,
          'active': active,
        }),
      )
      ..on('PUT', '/contours/active', (match) {
        writes.add('PUT /contours/active ${match.body['contourId']}');
        active = <String, dynamic>{
          'contourId': match.body['contourId'],
          'until': match.body['contourId'] == null ? null : match.body['until'],
        };
        return jsonResponse(active);
      })
      ..on('POST', '/tasks/:id/focus', (match) {
        final id = match.params['id']!;
        final contourId = match.body['contourId'] as String?;
        writes.add('POST /tasks/$id/focus ${contourId ?? '-'}');
        focused[id] = contourId ?? contours.first['id'] as String;
        return jsonResponse(_boardTask(id));
      })
      ..on('DELETE', '/tasks/:id/focus', (match) {
        final id = match.params['id']!;
        writes.add('DELETE /tasks/$id/focus');
        focused.remove(id);
        return jsonResponse(_boardTask(id));
      })
      ..on('GET', '/goals', (match) {
        final state = match.options.queryParameters['state'] as String?;
        return jsonResponse(state == 'achieved' ? achieved : goals);
      })
      ..on(
        'GET',
        '/goals/:id',
        (match) => jsonResponse(_find(match.params['id']!)),
      )
      ..on('POST', '/goals', (match) {
        final body = match.body;
        writes.add('POST /goals ${body['slot']}');
        final contourId = body['contourId'] as String;
        final slot = body['slot'] == true;
        final limit =
            contours.firstWhere((c) => c['id'] == contourId)['slots'] as int;
        if (slot && _inSlots(contourId) >= limit) return _slotsFull();
        final row = addGoal(
          'g_new${goals.length}',
          body['title'] as String,
          contourId: contourId,
          state: slot ? 'slot' : 'bench',
          why: body['why'] as String?,
          position: 9000,
        );
        return jsonResponse(row, statusCode: 201);
      })
      ..on('PATCH', '/goals/:id', (match) {
        final row = _find(match.params['id']!);
        writes.add('PATCH /goals/${row['id']}');
        for (final key in <String>['title', 'why', 'contourId', 'position']) {
          if (match.body.containsKey(key)) row[key] = match.body[key];
        }
        return jsonResponse(row);
      })
      ..on('POST', '/goals/:id/:action', (match) {
        final id = match.params['id']!;
        final action = match.params['action']!;
        writes.add('POST /goals/$id/$action');
        if (slotsFullOn.contains(action)) return _slotsFull();
        final row = _find(id);
        switch (action) {
          case 'slot':
            final contourId = row['contourId'] as String;
            final limit =
                contours.firstWhere((c) => c['id'] == contourId)['slots']
                    as int;
            if (row['state'] != 'slot' && _inSlots(contourId) >= limit) {
              return _slotsFull();
            }
            row['state'] = 'slot';
            row['windowExpired'] = false;
            row['windowEndsAt'] = DateTime.now()
                .add(const Duration(days: 7))
                .toUtc()
                .toIso8601String();
          case 'extend':
            row['windowExpired'] = false;
            row['windowEndsAt'] = DateTime.now()
                .add(const Duration(days: 7))
                .toUtc()
                .toIso8601String();
          case 'bench':
            row['state'] = 'bench';
            row['windowEndsAt'] = null;
            row['windowExpired'] = false;
          case 'achieve':
            row['state'] = 'achieved';
            row['achievedAt'] = DateTime.now().toUtc().toIso8601String();
            goals.remove(row);
            achieved.add(row);
          case 'reopen':
            row['state'] = 'bench';
            achieved.remove(row);
            goals.add(row);
        }
        return jsonResponse(row);
      })
      ..on('DELETE', '/goals/:id', (match) {
        writes.add('DELETE /goals/${match.params['id']}');
        goals.removeWhere((g) => g['id'] == match.params['id']);
        return jsonResponse(null, statusCode: 204);
      })
      ..on('PUT', '/goals/:id/tasks/:taskId', (match) {
        final row = _find(match.params['id']!);
        final taskId = match.params['taskId']!;
        writes.add('PUT /goals/${row['id']}/tasks/$taskId');
        final tasks = row['tasks'] as List;
        if (!tasks.any((t) => t['id'] == taskId)) tasks.add(_goalTask(taskId));
        _recount(row);
        return jsonResponse(row);
      })
      ..on('DELETE', '/goals/:id/tasks/:taskId', (match) {
        final row = _find(match.params['id']!);
        final taskId = match.params['taskId']!;
        writes.add('DELETE /goals/${row['id']}/tasks/$taskId');
        (row['tasks'] as List).removeWhere((t) => t['id'] == taskId);
        _recount(row);
        return jsonResponse(row);
      })
      ..on('GET', '/board', (_) => jsonResponse(board))
      ..on('GET', '/scopes', (_) => jsonResponse(defaultScopesJson()))
      ..on('GET', '/inbox', (_) => jsonResponse(<dynamic>[]))
      ..on('GET', '/focus', (_) => jsonResponse(_focusRows()))
      ..on('GET', '/projects/:id/tasks', (match) {
        final project = board.firstWhere((p) => p['id'] == match.params['id']);
        return jsonResponse(project['tasks']);
      })
      ..on('GET', '/projects/:id', (match) {
        final project = Map<String, dynamic>.from(
          board.firstWhere((p) => p['id'] == match.params['id']),
        )..remove('tasks');
        return jsonResponse(project);
      })
      ..on('GET', '/projects/:id/categories', (_) => jsonResponse(<dynamic>[]))
      ..on('GET', '/projects/:id/notes', (_) => jsonResponse(<dynamic>[]));
  }
}
