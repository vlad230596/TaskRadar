import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_status.dart';

part 'history_task_event.freezed.dart';

/// Журнал одной задачи: `GET /tasks/:id/events` (F11/F13).
///
/// Это единственное место, где клиент получает сырые строки `task_events`.
/// Сводки по журналу считает сервер (`GET /history`); здесь нужен именно
/// первоисточник, потому что блок «жизнь задачи» показывает не три числа, а
/// то, из чего они сложились, — и потому что «была в работе» в сводку не
/// попадает вовсе (см. `StaleTask.inWorkMs`).

/// Что за переход записан.
///
/// `focused`/`unfocused` — про набор «в работе», а не про статус: задача,
/// взятая в работу, остаётся `pending`. Именно поэтому серверный
/// `replayStatusTime` проходит мимо них, а здешний [replayTaskLife] — нет.
enum TaskEventKind { created, status, focused, unfocused }

@freezed
abstract class TaskEvent with _$TaskEvent {
  const factory TaskEvent({
    required String id,
    required String taskId,
    required TaskEventKind kind,
    required TaskStatus? fromStatus,
    required TaskStatus? toStatus,
    required String at,
  }) = _TaskEvent;

  const TaskEvent._();

  /// Разбор одной строки, или null для события с неизвестным `kind`.
  ///
  /// Null, а не исключение: новый вид события на сервере — это задача, чья
  /// история вдруг перестала открываться на телефоне. Пропустить незнакомую
  /// строку значит нарисовать историю чуть грубее; упасть — значит не
  /// нарисовать ничего.
  static TaskEvent? tryFromJson(Map<String, dynamic> json) {
    final kind = _kind(json['kind']);
    if (kind == null) return null;

    return TaskEvent(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      kind: kind,
      fromStatus: _status(json['fromStatus']),
      toStatus: _status(json['toStatus']),
      at: json['at'] as String,
    );
  }

  /// Весь ответ роута: голый массив в порядке `at` по возрастанию.
  ///
  /// Порядок сервера сохраняется как есть — на нём держится [replayTaskLife],
  /// и пересортировка здесь была бы вторым правилом порядка.
  static List<TaskEvent> listFromJson(List<dynamic> json) {
    final events = <TaskEvent>[];
    for (final dynamic raw in json) {
      final event = TaskEvent.tryFromJson((raw as Map).cast<String, dynamic>());
      if (event != null) events.add(event);
    }
    return List<TaskEvent>.unmodifiable(events);
  }

  /// Момент события, или null для нечитаемой метки.
  DateTime? get moment => DateTime.tryParse(at);
}

/// Фаза жизни задачи — то, из чего состоит полоска на экране задачи.
///
/// Четыре, а не три статуса: «в работе» — это `pending` плюс набор, и на
/// эталоне (`design/reference/Edit.html`) это отдельный синий сегмент со своей
/// строкой «была в работе». Считать его статусом было бы неправдой про базу,
/// не считать вовсе — неправдой про то, куда ушла неделя.
enum TaskLifePhase {
  /// Лежала в очереди.
  queued,

  /// Была в наборе «в работе».
  working,

  /// Ждала: блокер.
  blocked,

  /// Закрыта.
  done,
}

/// Куда ушла жизнь задачи, посчитанная по журналу.
@immutable
class TaskLife {
  const TaskLife({
    required this.spans,
    required this.totalMs,
    required this.phase,
    required this.since,
  });

  /// Миллисекунды по фазам. Все четыре ключа есть всегда, нули включительно.
  final Map<TaskLifePhase, int> spans;

  /// Сумма фаз. Она же — возраст задачи, по построению: разбор не оставляет
  /// дыр (см. [replayTaskLife]).
  final int totalMs;

  /// В какой фазе задача сейчас.
  final TaskLifePhase phase;

  /// Когда началась текущая фаза.
  final DateTime since;

  int operator [](TaskLifePhase phase) => spans[phase] ?? 0;
}

/// Проигрывает журнал задачи в «сколько она провела в каждой фазе».
///
/// ## Почему это считается на клиенте, хотя сводки считает сервер
///
/// Потому что это не сводка. `GET /history` отдаёт `byStatus` по всем висящим
/// задачам сразу — и специально не знает про набор. А экран задачи открыт про
/// одну задачу, её журнал — это десяток строк, и единственный способ узнать
/// «была в работе два дня» — пройти по `focused`/`unfocused` самому. Просить за
/// этим отдельную серверную сводку значило бы завести роут ради одной задачи на
/// экране, который уже держит её журнал в руках.
///
/// ## Полно по построению
///
/// То же свойство, что у серверного `replayStatusTime`, и по той же причине:
/// журнал, в котором нет ничего пригодного, отдаёт всю жизнь задачи её
/// нынешней фазе, начиная с `createdAt`. Значит, ни один вызывающий не обязан
/// обрабатывать «у этой задачи нет истории»: худший случай — первый отрезок
/// длиннее, чем было на самом деле, а не дыра.
///
/// [events] должны идти по возрастанию `at` — как их отдаёт роут.
TaskLife replayTaskLife({
  required String createdAt,
  required TaskStatus status,
  required String? focusedAt,
  required List<TaskEvent> events,
  DateTime? now,
}) {
  final end = (now ?? DateTime.now()).toUtc();
  final birth = DateTime.tryParse(createdAt)?.toUtc() ?? end;

  final spans = <TaskLifePhase, int>{
    for (final phase in TaskLifePhase.values) phase: 0,
  };

  // Состояние до первого события неизвестно: `created` его и задаёт. Пока оно
  // не задано, время не начисляется никуда — иначе задача, чей журнал начат
  // позже её создания, получила бы отрезок в выдуманной фазе.
  TaskStatus? state;
  var focused = false;

  var since = birth;
  TaskLifePhase? phase;

  void advance(DateTime at) {
    if (phase == null) return;
    final ms = at.difference(since).inMilliseconds;
    if (ms > 0) spans[phase] = spans[phase]! + ms;
  }

  for (final event in events) {
    final at = event.moment?.toUtc();
    if (at == null) continue;

    switch (event.kind) {
      case TaskEventKind.created:
      case TaskEventKind.status:
        if (event.toStatus != null) state = event.toStatus;
      case TaskEventKind.focused:
        focused = true;
      case TaskEventKind.unfocused:
        focused = false;
    }

    final next = state == null ? null : _phaseOf(state, focused);

    // Граница считается по смене *фазы*, а не события: взятие в работу
    // блокера ничего не меняет на полоске, и сбрасывать им «ждёт с 18.09» было
    // бы неправдой в подписи.
    if (next != phase) {
      advance(at);
      since = at;
      phase = next;
    }
  }

  // Открытый отрезок: от последней смены фазы до сейчас. Если журнал не сказал
  // ничего — вся жизнь принадлежит нынешнему состоянию строки задачи.
  phase ??= _phaseOf(status, focusedAt != null);
  advance(end);

  var total = 0;
  for (final ms in spans.values) {
    total += ms;
  }

  return TaskLife(
    spans: Map<TaskLifePhase, int>.unmodifiable(spans),
    totalMs: total,
    phase: phase,
    since: since.toLocal(),
  );
}

TaskLifePhase _phaseOf(TaskStatus status, bool focused) => switch (status) {
  TaskStatus.blocked => TaskLifePhase.blocked,
  TaskStatus.done => TaskLifePhase.done,
  TaskStatus.pending =>
    focused ? TaskLifePhase.working : TaskLifePhase.queued,
};

TaskEventKind? _kind(Object? value) {
  for (final kind in TaskEventKind.values) {
    if (kind.name == value) return kind;
  }
  debugPrint('Unknown task event kind: $value');
  return null;
}

TaskStatus? _status(Object? value) {
  if (value == null) return null;
  for (final status in TaskStatus.values) {
    if (status.name == value) return status;
  }
  debugPrint('Unknown task status in journal: $value');
  return null;
}
