import 'package:dio/dio.dart';

import 'fake_backend.dart';

/// A project «Публикации» with three ideas, two contours and two goals --
/// the data of `design/reference/Ideas.html`. Shared by `ideas_test.dart`
/// and `zz_capture_ideas_test.dart`.
class FakeIdeasBackend {
  FakeIdeasBackend() {
    backend.responder = _respond;
  }

  final FakeBackend backend = FakeBackend();

  static const String projectId = 'prj_pub';

  final List<Map<String, dynamic>> notes = <Map<String, dynamic>>[
    _note(
      'n3',
      'Серия коротких постов «как я веду задачи»',
      '',
      '2026-11-01T10:00:00.000Z',
    ),
    _note(
      'n2',
      'Доклад на митапе про Flutter-виджеты на Android',
      'RemoteViews, ограничения, как жить без своих шрифтов.',
      '2026-11-10T10:00:00.000Z',
    ),
    _note(
      'n1',
      'Статья: диктовка без облака',
      'Whisper на телефоне, гонка моделей, почему аудио не уходит на сервер. '
          'Сравнить с [Google Recorder](https://recorder.google.com).',
      '2026-11-20T10:00:00.000Z',
    ),
  ];

  final List<Map<String, dynamic>> tasks = <Map<String, dynamic>>[];

  /// Paths answered with a connection failure.
  final Set<String> offline = <String>{};

  static Map<String, dynamic> _note(
    String id,
    String title,
    String content,
    String createdAt,
  ) => <String, dynamic>{
    'id': id,
    'projectId': projectId,
    'title': title,
    'content': content,
    'createdAt': createdAt,
    'updatedAt': createdAt,
  };

  Map<String, dynamic> _goal(
    String id,
    String contourId,
    String title,
    List<String> ideaIds,
  ) => <String, dynamic>{
    'id': id,
    'contourId': contourId,
    'title': title,
    'why': null,
    'state': 'slot',
    'slottedAt': '2026-11-20T10:00:00.000Z',
    'windowDays': 7,
    'windowEndsAt': '2026-12-30T10:00:00.000Z',
    'windowExpired': false,
    'achievedAt': null,
    'position': 1000,
    'createdAt': '2026-11-01T10:00:00.000Z',
    'tasks': <dynamic>[],
    'nextStep': null,
    'ideas': <dynamic>[
      for (final idea in notes)
        if (ideaIds.contains(idea['id']))
          <String, dynamic>{
            'id': idea['id'],
            'title': idea['title'],
            'projectId': projectId,
            'projectName': 'Публикации',
          },
    ],
    'progress': <String, dynamic>{'done': 0, 'total': 0},
  };

  ResponseBody _respond(RequestOptions options) {
    final path = options.path.split('?').first;
    if (offline.any(path.contains)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'simulated connection failure',
      );
    }
    if (path == '/board') {
      return jsonResponse(<dynamic>[
        <String, dynamic>{..._project, 'tasks': tasks, 'noteCount': 3},
      ]);
    }
    if (path == '/scopes') {
      return jsonResponse(<dynamic>[
        <String, dynamic>{
          'id': 'scope_main',
          'name': 'Основной',
          'position': 1000,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
      ]);
    }
    if (path == '/contours') {
      return jsonResponse(<String, dynamic>{
        'contours': <dynamic>[
          <String, dynamic>{
            'id': 'c_work',
            'name': 'Работа',
            'slots': 2,
            'windowDays': 7,
            'schedule': null,
            'position': 1000,
          },
          <String, dynamic>{
            'id': 'c_life',
            'name': 'Личное',
            'slots': 2,
            'windowDays': 7,
            'schedule': null,
            'position': 2000,
          },
        ],
        'active': <String, dynamic>{'contourId': null, 'until': null},
      });
    }
    if (path == '/goals') {
      return jsonResponse(<dynamic>[
        _goal('g1', 'c_work', 'Первая публикация', <String>['n1']),
        _goal('g2', 'c_life', 'Положение на рынке труда', <String>['n2']),
      ]);
    }
    if (path == '/projects/$projectId/notes') return jsonResponse(notes);
    if (path == '/projects/$projectId/tasks') return jsonResponse(tasks);
    if (path == '/projects/$projectId/categories') {
      return jsonResponse(<dynamic>[]);
    }
    if (path == '/projects/$projectId') return jsonResponse(_project);
    if (path.endsWith('/to-task')) {
      final id = path.split('/')[2];
      final note = notes.firstWhere((n) => n['id'] == id);
      notes.remove(note);
      final task = <String, dynamic>{
        'id': 't_$id',
        'projectId': projectId,
        'title': note['title'],
        'description': (note['content'] as String).isEmpty
            ? null
            : note['content'],
        'status': 'pending',
        'position': 1000.0 * (tasks.length + 1),
        'remindAt': null,
        'createdAt': '2026-11-24T10:00:00.000Z',
        'updatedAt': '2026-11-24T10:00:00.000Z',
        'isCurrent': false,
        'goals': <dynamic>[],
      };
      tasks.add(task);
      return jsonResponse(task, statusCode: 201);
    }
    return jsonResponse(<dynamic>[]);
  }

  static final Map<String, dynamic> _project = <String, dynamic>{
    'id': projectId,
    'name': 'Публикации',
    'scopeId': 'scope_main',
    'archivedAt': null,
    'createdAt': '2026-10-01T10:00:00.000Z',
    'updatedAt': '2026-11-20T10:00:00.000Z',
  };
}
