import 'package:taskradar/models/task_status.dart';

import 'fake_backend.dart';

/// Ответы истории: «Сделано», «Недели», пересмотр, «Вернуть» и журнал
/// задачи (`design/today-history-contract.md`, F13).
///
/// Фикстуры, а не маленький сервер: тело ответа задаётся тестом в той форме,
/// в какой его присылает роут. Даты строятся от `now`, а не написаны буквой:
/// «сегодня» и «эта неделя» на экране рисуются иначе.
class FakeHistoryBackend {
  FakeHistoryBackend(this.backend, {DateTime? now})
    : now = now ?? DateTime.now() {
    _install();
  }

  final FakeBackend backend;
  final DateTime now;

  /// Журналы по id задачи. Задача, которой здесь нет, получает пустой массив.
  final Map<String, List<dynamic>> events = <String, List<dynamic>>{};

  /// `GET /history/done`: все закрытия, свежие сверху; страницы режет фейк.
  List<Map<String, dynamic>> done = <Map<String, dynamic>>[];

  /// `GET /history/weeks`, свежие сверху.
  List<Map<String, dynamic>> weeks = <Map<String, dynamic>>[];

  /// `GET /reviews/status`.
  Map<String, dynamic> status = <String, dynamic>{
    'due': false,
    'nextAt': null,
    'lastAt': null,
  };

  /// `GET /reviews/draft`.
  late Map<String, dynamic> draft = draftJson();

  /// Тела `POST /reviews`, по порядку.
  final List<Map<String, dynamic>> savedReviews = <Map<String, dynamic>>[];

  /// Id задач, которым прислали `POST /tasks/:id/reopen`.
  final List<String> reopened = <String>[];

  void _install() {
    backend
      ..on('GET', '/tasks/:id/events', (match) {
        return jsonResponse(events[match.params['id']] ?? const <dynamic>[]);
      })
      ..on('GET', '/history/done', (match) {
        final query = match.options.queryParameters;
        final limit = int.tryParse('${query['limit'] ?? 50}') ?? 50;
        final before = query['before'] as String?;
        final rows = <Map<String, dynamic>>[
          for (final row in done)
            if (before == null ||
                (row['doneAt'] as String).compareTo(before) < 0)
              row,
        ];
        final page = rows.take(limit).toList();
        return jsonResponse(<String, dynamic>{
          'items': page,
          'nextBefore': rows.length > limit ? page.last['doneAt'] : null,
        });
      })
      ..on('GET', '/history/weeks', (match) {
        return jsonResponse(<String, dynamic>{'weeks': weeks});
      })
      ..on('GET', '/reviews/status', (match) => jsonResponse(status))
      ..on('GET', '/reviews/draft', (match) => jsonResponse(draft))
      ..on('POST', '/reviews', (match) {
        savedReviews.add(match.body);
        return jsonResponse(
          reviewJson(
            id: 'rev_${savedReviews.length}',
            daysAgo: 0,
            closed: (draft['done'] as List).length,
            summary: match.body['summary'] as String?,
          ),
          statusCode: 201,
        );
      })
      ..on('POST', '/tasks/:id/reopen', (match) {
        final id = match.params['id']!;
        reopened.add(id);
        final row = done
            .map((item) => item['task'] as Map<String, dynamic>)
            .where((task) => task['id'] == id)
            .firstOrNull;
        done.removeWhere((item) => (item['task'] as Map)['id'] == id);
        return jsonResponse(<String, dynamic>{
          ...?row,
          'id': id,
          'status': 'pending',
          'doneAt': null,
        });
      });
  }

  /// `YYYY-MM-DD` местного дня, [daysAgo] дней назад.
  String dayKey(int daysAgo) {
    final date = now.subtract(Duration(days: daysAgo));
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// ISO-метка [daysAgo] дней назад.
  String iso(num daysAgo) => now
      .toUtc()
      .subtract(Duration(milliseconds: (daysAgo * _day).round()))
      .toIso8601String();

  /// A placed task (`taskView` + project and scope).
  Map<String, dynamic> placedTaskJson({
    required String id,
    required String title,
    String projectId = 'prj_1',
    String projectName = 'TaskRadar',
    String status = 'done',
    String? doneAt,
    String? remindAt,
    List<Map<String, dynamic>> goals = const <Map<String, dynamic>>[],
  }) => <String, dynamic>{
    'id': id,
    'projectId': projectId,
    'title': title,
    'description': null,
    'status': status,
    'position': 1000,
    'remindAt': remindAt,
    'remindTime': null,
    'doneAt': doneAt,
    'createdAt': iso(20),
    'updatedAt': iso(1),
    'goals': goals,
    'projectName': projectName,
    'scopeId': 'scp_1',
    'scopeName': 'Работа',
  };

  /// One closing of «Сделано», [daysAgo] days and [hoursAgo] hours back.
  Map<String, dynamic> doneJson({
    required String id,
    required String title,
    num daysAgo = 0,
    num hoursAgo = 0,
    String projectId = 'prj_1',
    String projectName = 'TaskRadar',
    List<Map<String, dynamic>> goals = const <Map<String, dynamic>>[],
  }) {
    final at = now
        .toUtc()
        .subtract(
          Duration(milliseconds: (daysAgo * _day + hoursAgo * 3600000).round()),
        )
        .toIso8601String();
    return <String, dynamic>{
      'task': placedTaskJson(
        id: id,
        title: title,
        projectId: projectId,
        projectName: projectName,
        doneAt: at,
        goals: goals,
      ),
      'doneAt': at,
    };
  }

  /// The local Monday [weeksAgo] weeks back, `YYYY-MM-DD`.
  String mondayKey(int weeksAgo) {
    final local = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
      local.year,
      local.month,
      local.day - (local.weekday - 1) - 7 * weeksAgo,
    );
    return '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> reviewJson({
    String id = 'rev_1',
    num daysAgo = 7,
    int closed = 0,
    String? summary,
    bool monthly = false,
    List<Map<String, dynamic>> byProject = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> achievedGoals = const <Map<String, dynamic>>[],
  }) => <String, dynamic>{
    'id': id,
    'periodStart': iso(daysAgo + 7),
    'periodEnd': iso(daysAgo),
    'monthly': monthly,
    'closedCount': closed,
    'byProject': byProject,
    'achievedGoals': achievedGoals,
    'summary': summary,
    'createdAt': iso(daysAgo),
  };

  Map<String, dynamic> weekJson({
    required int weeksAgo,
    required int closed,
    List<Map<String, dynamic>> byProject = const <Map<String, dynamic>>[],
    Map<String, dynamic>? review,
  }) => <String, dynamic>{
    'start': mondayKey(weeksAgo),
    'closed': closed,
    'byProject': byProject,
    'review': review,
  };

  Map<String, dynamic> projectClosedJson(String name, int closed) =>
      <String, dynamic>{
        'projectId': 'prj_${name.hashCode}',
        'name': name,
        'closed': closed,
      };

  /// «Сделано» like `History-Done.html`: today, yesterday and before.
  List<Map<String, dynamic>> sampleDone() => <Map<String, dynamic>>[
    doneJson(id: 'd1', title: 'Зарелизить 0.15', hoursAgo: 0.2),
    doneJson(
      id: 'd2',
      title: 'Ответить Марине про макеты',
      hoursAgo: 0.5,
      projectId: 'prj_work',
      projectName: 'Работа',
    ),
    doneJson(
      id: 'd3',
      title: 'Купить лампочки в ванную',
      daysAgo: 1,
      projectId: 'prj_dom',
      projectName: 'Дом',
    ),
    doneJson(id: 'd4', title: 'Починить виджет на Android', daysAgo: 1),
    doneJson(
      id: 'd5',
      title: 'Записать сына на секцию',
      daysAgo: 3,
      projectId: 'prj_fam',
      projectName: 'Семья',
    ),
  ];

  /// 12 weeks like `History-Weeks.html`: this one and eleven before, one of
  /// them with a review.
  List<Map<String, dynamic>> sampleWeeks() => <Map<String, dynamic>>[
    weekJson(
      weeksAgo: 0,
      closed: 9,
      byProject: <Map<String, dynamic>>[projectClosedJson('TaskRadar', 6)],
    ),
    weekJson(
      weeksAgo: 1,
      closed: 23,
      byProject: <Map<String, dynamic>>[
        projectClosedJson('TaskRadar', 11),
        projectClosedJson('Дом', 6),
        projectClosedJson('Семья', 4),
        projectClosedJson('Авоська', 1),
        projectClosedJson('Работа', 1),
      ],
      review: reviewJson(
        daysAgo: 1,
        closed: 23,
        summary: 'Дожал стенды, дом стоял. Следующая — отзывы по 0.15.',
        achievedGoals: <Map<String, dynamic>>[
          <String, dynamic>{'goalId': 'g1', 'title': 'Релиз 0.15'},
        ],
      ),
    ),
    weekJson(weeksAgo: 2, closed: 15),
    weekJson(weeksAgo: 3, closed: 18),
    weekJson(weeksAgo: 4, closed: 0),
    for (var i = 5; i < 12; i++) weekJson(weeksAgo: i, closed: (i * 7) % 20),
  ];

  /// `GET /reviews/draft` with something in every step.
  Map<String, dynamic> draftJson({bool monthly = false}) => <String, dynamic>{
    'periodStart': iso(7),
    'periodEnd': iso(0),
    'monthly': monthly,
    'done': <dynamic>[
      doneJson(id: 'd1', title: 'Зарелизить 0.15', daysAgo: 2),
      doneJson(id: 'd2', title: 'Починить диктовку', daysAgo: 3),
      doneJson(
        id: 'd3',
        title: 'Купить лампочки',
        daysAgo: 4,
        projectId: 'prj_dom',
        projectName: 'Дом',
      ),
    ],
    'intended': <dynamic>[
      <String, dynamic>{
        'task': placedTaskJson(
          id: 'i1',
          title: 'Собрать отзывы',
          status: 'pending',
        ),
        'reasons': <String>['workingSet'],
      },
      <String, dynamic>{
        'task': placedTaskJson(
          id: 'i2',
          title: 'Позвонить в УК',
          status: 'pending',
          projectId: 'prj_dom',
          projectName: 'Дом',
          remindAt: '${dayKey(2)}T00:00:00.000Z',
        ),
        'reasons': <String>['dated'],
      },
    ],
    'goals': <dynamic>[
      <String, dynamic>{
        'id': 'g_slot',
        'contourId': 'c_work',
        'title': 'Выпустить 0.16',
        'state': 'slot',
        'windowDays': 7,
        'windowEndsAt': iso(1),
        'windowExpired': true,
        'position': 1000,
        'createdAt': iso(20),
        'tasks': <dynamic>[],
        'ideas': <dynamic>[],
        'progress': <String, dynamic>{'done': 2, 'total': 5},
      },
    ],
    'rhythm': <dynamic>[
      <String, dynamic>{
        'project': <String, dynamic>{
          'id': 'prj_dom',
          'name': 'Дом',
          'scopeId': 'scp_1',
          'archivedAt': null,
          'createdAt': iso(100),
          'updatedAt': iso(1),
          'rhythmClosedPerWeek': 2,
          'rhythmMaxOpen': null,
        },
        'rhythm': <String, dynamic>{
          'closedPerWeek': 2,
          'maxOpen': null,
          'closedAvg': 0.5,
          'open': 24,
          'lastClosedAt': iso(22),
          'silentWeeks': 3,
          'signal': 'silence',
        },
      },
    ],
    'month': monthly
        ? <String, dynamic>{
            'month': '2026-11',
            'byProject': <dynamic>[
              projectClosedJson('TaskRadar', 40),
              projectClosedJson('Дом', 24),
            ],
            'achievedGoals': <dynamic>[],
          }
        : null,
  };

  /// Одна строка журнала задачи.
  Map<String, dynamic> eventJson({
    required String taskId,
    required String kind,
    required num daysAgo,
    TaskStatus? toStatus,
    TaskStatus? fromStatus,
    String? id,
  }) => <String, dynamic>{
    'id': id ?? 'ev_${taskId}_$daysAgo$kind',
    'taskId': taskId,
    'kind': kind,
    'fromStatus': fromStatus?.name,
    'toStatus': toStatus?.name,
    'at': iso(daysAgo),
  };

  /// Журнал задачи из `design/reference/Edit.html`: восемь дней жизни —
  /// четыре в очереди, один в работе, три в блокере.
  List<dynamic> sampleJournal(String taskId) => <dynamic>[
    eventJson(
      taskId: taskId,
      kind: 'created',
      daysAgo: 8,
      toStatus: TaskStatus.pending,
    ),
    eventJson(taskId: taskId, kind: 'focused', daysAgo: 4),
    eventJson(taskId: taskId, kind: 'unfocused', daysAgo: 3),
    eventJson(
      taskId: taskId,
      kind: 'status',
      daysAgo: 3,
      fromStatus: TaskStatus.pending,
      toStatus: TaskStatus.blocked,
    ),
  ];
}

const int _day = Duration.millisecondsPerDay;
