import 'package:dio/dio.dart';
import 'package:taskradar/models/task_status.dart';

import 'fake_backend.dart';

/// Ответы истории: `GET /history` и `GET /tasks/:id/events` (F13).
///
/// Отдельный файл, а не пара строк в `fake_project_backend.dart`: там живёт
/// маленький настоящий сервер — он держит состояние и отвечает на записи, — а
/// история состоит из **сводок**, которые сервер считает по журналу. Считать их
/// ещё раз в фейке значило бы написать второй `backend/src/domain/history.ts` и
/// проверять экран против него, а не против контракта. Здесь поэтому фикстуры:
/// тело ответа задаётся тестом целиком, ровно в той форме, в какой его
/// присылает роут.
///
/// Даты строятся от `now`, а не написаны буквой, по единственной причине:
/// «сегодняшний столбик» на экране красится иначе, и фикстура с прошлогодними
/// датами эту ветку никогда не прошла бы.
class FakeHistoryBackend {
  FakeHistoryBackend(this.backend, {DateTime? now})
    : now = now ?? DateTime.now() {
    _install();
  }

  final FakeBackend backend;
  final DateTime now;

  /// Тело `GET /history`. По умолчанию — неделя из [sampleWeek].
  late Map<String, dynamic> history = sampleWeek();

  /// Журналы по id задачи. Задача, которой здесь нет, получает пустой массив —
  /// это честный ответ сервера для задачи без событий.
  final Map<String, List<dynamic>> events = <String, List<dynamic>>{};

  /// Последние параметры запроса истории — по ним проверяется, что клиент
  /// прислал настоящее смещение часового пояса.
  RequestOptions? lastHistoryRequest;

  void _install() {
    backend.on('GET', '/history', (match) {
      lastHistoryRequest = match.options;
      return jsonResponse(history);
    });
    backend.on('GET', '/tasks/:id/events', (match) {
      return jsonResponse(events[match.params['id']] ?? const <dynamic>[]);
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

  /// Неделя, похожая на `design/reference/History.html`: девять закрытых,
  /// четыре долгожителя, движение в четырёх проектах.
  Map<String, dynamic> sampleWeek() => historyJson(
    range: '7d',
    closedByDay: <int>[3, 0, 1, 2, 0, 2, 1],
    stale: <Map<String, dynamic>>[
      staleJson(
        id: 't4',
        title: 'Посмотреть, почему не работает вентилятор',
        projectName: 'Дом',
        status: TaskStatus.blocked,
        ageDays: 8,
        pendingDays: 4,
        blockedDays: 4,
      ),
      staleJson(
        id: 't2',
        title: 'Купить лампочки',
        projectName: 'Дом',
        ageDays: 5,
        pendingDays: 5,
      ),
      staleJson(
        id: 't3',
        title: 'Заказать крючки для полок в ванной',
        projectName: 'Дом',
        ageDays: 5,
        pendingDays: 5,
      ),
      staleJson(
        id: 't7',
        title: 'Потестить диктовку на телефоне',
        projectName: 'TaskRadar',
        ageDays: 5,
        pendingDays: 5,
        focusedDaysAgo: 2,
      ),
      staleJson(
        id: 't8',
        title: 'Адаптировать кнопку распознавания',
        projectName: 'TaskRadar',
        ageDays: 4,
        pendingDays: 4,
      ),
    ],
    projects: <Map<String, dynamic>>[
      projectMovementJson(name: 'Дом', opened: 6, closed: 2),
      projectMovementJson(name: 'TaskRadar', opened: 2, closed: 4),
      projectMovementJson(name: 'Семья', opened: 2, closed: 3),
      projectMovementJson(name: 'Авоська', opened: 1),
    ],
  );

  /// Ответ, в котором нет ничего: журнал есть, а событий в нём ещё не было.
  Map<String, dynamic> emptyWeek() => historyJson(
    range: '7d',
    closedByDay: const <int>[0, 0, 0, 0, 0, 0, 0],
  );

  /// Тело `GET /history` целиком.
  ///
  /// [closedByDay] — счётчики по дням, самый старый первым, как их отдаёт
  /// `countByDay`; последний элемент — сегодня.
  Map<String, dynamic> historyJson({
    String range = '7d',
    List<int> closedByDay = const <int>[],
    List<Map<String, dynamic>> stale = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> projects = const <Map<String, dynamic>>[],
  }) {
    final days = <Map<String, dynamic>>[
      for (var i = 0; i < closedByDay.length; i++)
        <String, dynamic>{
          'date': dayKey(closedByDay.length - 1 - i),
          'count': closedByDay[i],
        },
    ];

    var total = 0;
    for (final count in closedByDay) {
      total += count;
    }

    return <String, dynamic>{
      'range': range,
      'from': range == 'all' ? null : iso(closedByDay.length - 1),
      'to': iso(0),
      'closedByDay': days,
      'closedTotal': total,
      'projects': projects,
      'stale': stale,
    };
  }

  /// Одна строка «висит дольше всего», в форме роута.
  ///
  /// `byStatus` задаётся днями по статусам, а не миллисекундами: тест про
  /// экран читается как «четыре дня в очереди, четыре в блокере», а не как
  /// `345600000`.
  Map<String, dynamic> staleJson({
    required String id,
    required String title,
    required String projectName,
    TaskStatus status = TaskStatus.pending,
    String? projectId,
    required num ageDays,
    num pendingDays = 0,
    num blockedDays = 0,
    num doneDays = 0,

    /// Когда задачу взяли в набор. Null — она не в работе.
    num? focusedDaysAgo,
  }) {
    final currentDays = status == TaskStatus.blocked ? blockedDays : pendingDays;
    return <String, dynamic>{
      'id': id,
      'title': title,
      'status': status.name,
      'projectId': projectId ?? 'prj_${projectName.hashCode}',
      'projectName': projectName,
      'createdAt': iso(ageDays),
      'focusedAt': focusedDaysAgo == null ? null : iso(focusedDaysAgo),
      'ageMs': (ageDays * _day).round(),
      'currentSince': iso(currentDays),
      'currentForMs': (currentDays * _day).round(),
      'byStatus': <String, dynamic>{
        'pending': (pendingDays * _day).round(),
        'blocked': (blockedDays * _day).round(),
        'done': (doneDays * _day).round(),
      },
    };
  }

  Map<String, dynamic> projectMovementJson({
    required String name,
    int opened = 0,
    int closed = 0,
    String? projectId,
  }) => <String, dynamic>{
    'projectId': projectId ?? 'prj_${name.hashCode}',
    'name': name,
    'opened': opened,
    'closed': closed,
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
