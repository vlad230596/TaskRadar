import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_status.dart';

part 'history_snapshot.freezed.dart';

/// Весь режим «История» одним ответом: `GET /history` (F11/F13).
///
/// ## Почему это один объект, а не три модели рядом
///
/// Потому что это один ответ. `backend/src/routes/history.ts` специально
/// собирает столбики недели, «висит дольше всего» и движение по проектам в один
/// роут — чтобы три блока экрана не разошлись в том, что такое «сейчас». Три
/// модели, каждая со своим временем загрузки, вернули бы ровно ту рассинхронизацию,
/// которую сервер убрал.
///
/// ## Почему разбор написан руками
///
/// `json_serializable` здесь пришлось бы уговаривать в трёх местах: диапазон на
/// проводе — это `"7d"`, а не идентификатор Dart; `byStatus` — это вложенный
/// объект с ключами-статусами, а не список; а миллисекунды приходят числами,
/// которые в JSON бывают и `int`, и `double`. Каждое из трёх лечится
/// аннотацией с конвертером, то есть всё равно написанной руками функцией — но
/// спрятанной так, что её не видно рядом с полем. Прецедент в репозитории уже
/// есть: `BoardProject` разбирает себя сам и объясняет, почему.
///
/// Временные метки остаются ISO-строками — как в `Task` и по той же причине:
/// клиент их сравнивает и показывает, а не считает в них.

/// Диапазон, за который смотрят историю.
///
/// `wire` — это то, что понимает `historyQuerySchema` (`backend/src/schemas.ts`),
/// и единственное место, где эта строка написана. `label` и `caption` —
/// подписи переключателя и карточки итога; они живут здесь, а не на экране,
/// потому что «за неделю» под числом и «7 дней» на кнопке — это два падежа
/// одного и того же выбора, и разъехаться они могут только если лежат порознь.
enum HistoryRange {
  week('7d', '7 дней', 'за неделю'),
  month('30d', '30 дней', 'за месяц'),
  all('all', 'всё время', 'за всё время');

  const HistoryRange(this.wire, this.label, this.caption);

  /// Значение параметра `range`.
  final String wire;

  /// Подпись на переключателе.
  final String label;

  /// Подпись под числом закрытых: «сделано ...».
  final String caption;

  /// Разбор `range` из ответа. Неизвестное значение — это сервер новее
  /// клиента; показать месяц честнее, чем упасть на экране, который весь
  /// состоит из чисел за какой-то период.
  static HistoryRange fromWire(String? wire) {
    for (final range in values) {
      if (range.wire == wire) return range;
    }
    debugPrint('Unknown history range: $wire');
    return HistoryRange.month;
  }
}

/// Сколько задач закрыто в один местный день.
///
/// `date` — `YYYY-MM-DD` **в часовом поясе клиента**: границы суток считает
/// сервер по присланному `tzOffsetMinutes`, и пересчитывать их здесь заново
/// значило бы завести второе правило дня (см. `localDayKey` на сервере).
@freezed
abstract class HistoryDay with _$HistoryDay {
  const factory HistoryDay({
    required String date,
    required int count,
  }) = _HistoryDay;

  const HistoryDay._();

  static HistoryDay fromJson(Map<String, dynamic> json) => HistoryDay(
    date: json['date'] as String,
    count: (json['count'] as num).toInt(),
  );

  /// Дата как `DateTime`, или null для строки, которую не прочитать.
  ///
  /// Нужна ровно для подписи столбика (день недели) и для сравнения с
  /// сегодняшним днём, поэтому разбирается по требованию, а не при парсинге:
  /// столбиков тридцать, а подпись нужна семи.
  DateTime? get day => DateTime.tryParse(date);
}

/// Сколько миллисекунд задача провела в каждом статусе.
///
/// Все три ключа сервер присылает всегда, включая нули (`StatusSpans` в
/// `backend/src/domain/history.ts`), — так что «этого статуса не было» и «ноль»
/// здесь одно и то же, и ни один вызывающий не обязан обрабатывать отсутствие.
@freezed
abstract class StatusSpans with _$StatusSpans {
  const factory StatusSpans({
    required int pendingMs,
    required int doneMs,
    required int blockedMs,
  }) = _StatusSpans;

  const StatusSpans._();

  static StatusSpans fromJson(Map<String, dynamic> json) => StatusSpans(
    pendingMs: _ms(json['pending']),
    doneMs: _ms(json['done']),
    blockedMs: _ms(json['blocked']),
  );

  int get totalMs => pendingMs + doneMs + blockedMs;
}

/// Открытая задача, которая висит: строка блока «висит дольше всего».
@freezed
abstract class StaleTask with _$StaleTask {
  const factory StaleTask({
    required String id,
    required String title,
    required TaskStatus status,
    required String projectId,
    required String projectName,
    required String createdAt,

    /// Когда задачу взяли в набор, или null. См. [inWorkMs].
    required String? focusedAt,

    /// Сколько задача живёт незакрытой. По нему сервер и сортирует.
    required int ageMs,

    /// Когда начался текущий статус.
    required String currentSince,

    /// Сколько текущий статус держится.
    required int currentForMs,

    /// Куда ушёл возраст. Полоска под строкой — это он.
    required StatusSpans byStatus,
  }) = _StaleTask;

  const StaleTask._();

  static StaleTask fromJson(Map<String, dynamic> json) => StaleTask(
    id: json['id'] as String,
    title: json['title'] as String,
    status: _status(json['status']),
    projectId: json['projectId'] as String,
    projectName: json['projectName'] as String,
    createdAt: json['createdAt'] as String,
    focusedAt: json['focusedAt'] as String?,
    ageMs: _ms(json['ageMs']),
    currentSince: json['currentSince'] as String,
    currentForMs: _ms(json['currentForMs']),
    byStatus: StatusSpans.fromJson(
      (json['byStatus'] as Map).cast<String, dynamic>(),
    ),
  );

  static List<StaleTask> listFromJson(List<dynamic> json) =>
      List<StaleTask>.unmodifiable(
        json.map((dynamic e) => StaleTask.fromJson((e as Map).cast<String, dynamic>())),
      );

  /// Сколько задача провела в наборе «в работе».
  ///
  /// ## Почему это считается здесь, а не приходит с сервера
  ///
  /// `byStatus` знает три статуса и не знает про набор: `replayStatusTime`
  /// специально проходит мимо событий `focused`/`unfocused`, потому что взятие
  /// в работу — не смена статуса, и рисовать его переходом было бы враньём про
  /// журнал. Но на эталонной полоске (`design/reference/History.html`) синий
  /// сегмент «в работе» есть, и он там не лишний: пятидневная задача, которую
  /// уже держат в руках, и пятидневная, до которой никто не дошёл, — это две
  /// разные жалобы.
  ///
  /// Выводимо ровно одно и ровно из `focusedAt`: **текущий** заход в набор, от
  /// него до сейчас. Прошлые заходы здесь не восстановить — они есть только в
  /// журнале задачи (`GET /tasks/:id/events`, экран задачи). Поэтому это
  /// «сколько она в работе сейчас», а не «сколько была за всю жизнь», и
  /// урезано по [StatusSpans.pendingMs]: время в наборе идёт поверх очереди, а
  /// не рядом с ней, и сумма сегментов не должна вылезать за возраст.
  int inWorkMs({DateTime? now}) {
    final since = DateTime.tryParse(focusedAt ?? '');
    if (since == null) return 0;

    final elapsed = (now ?? DateTime.now()).difference(since).inMilliseconds;
    if (elapsed <= 0) return 0;
    return elapsed > byStatus.pendingMs ? byStatus.pendingMs : elapsed;
  }
}

/// Что сдвинулось в одном проекте за диапазон.
///
/// Сервер присылает только проекты, в которых что-то происходило: строка с
/// двумя нулями — это не «проект, где ничего не было», а строка, которой нет.
@freezed
abstract class ProjectMovement with _$ProjectMovement {
  const factory ProjectMovement({
    required String projectId,
    required String name,
    required int opened,
    required int closed,
  }) = _ProjectMovement;

  const ProjectMovement._();

  static ProjectMovement fromJson(Map<String, dynamic> json) => ProjectMovement(
    projectId: json['projectId'] as String,
    name: json['name'] as String,
    opened: (json['opened'] as num).toInt(),
    closed: (json['closed'] as num).toInt(),
  );

  int get total => opened + closed;
}

/// Весь ответ `GET /history`.
@freezed
abstract class HistorySnapshot with _$HistorySnapshot {
  const factory HistorySnapshot({
    required HistoryRange range,

    /// Начало окна, или null для «всё время» — которое не дата, и сервер
    /// специально не делает вид, что дата.
    required String? from,
    required String to,

    /// По записи на день, с нулями, — для 7d/30d. Для «всё время» только те
    /// дни, в которые что-то закрылось.
    required List<HistoryDay> closedByDay,
    required int closedTotal,
    required List<ProjectMovement> projects,
    required List<StaleTask> stale,
  }) = _HistorySnapshot;

  const HistorySnapshot._();

  static HistorySnapshot fromJson(Map<String, dynamic> json) => HistorySnapshot(
    range: HistoryRange.fromWire(json['range'] as String?),
    from: json['from'] as String?,
    to: json['to'] as String,
    closedByDay: List<HistoryDay>.unmodifiable(
      (json['closedByDay'] as List<dynamic>? ?? const <dynamic>[]).map(
        (dynamic e) => HistoryDay.fromJson((e as Map).cast<String, dynamic>()),
      ),
    ),
    closedTotal: (json['closedTotal'] as num?)?.toInt() ?? 0,
    projects: List<ProjectMovement>.unmodifiable(
      (json['projects'] as List<dynamic>? ?? const <dynamic>[]).map(
        (dynamic e) =>
            ProjectMovement.fromJson((e as Map).cast<String, dynamic>()),
      ),
    ),
    stale: StaleTask.listFromJson(
      json['stale'] as List<dynamic>? ?? const <dynamic>[],
    ),
  );

  /// В базе нечего показывать: ни закрытий, ни висящих задач, ни движения.
  ///
  /// Отдельный признак, а не проверка `closedTotal == 0` на экране: ноль
  /// закрытых при четырёх висящих — это нормальная неделя, а ноль во всех трёх
  /// блоках — это «тут ещё ничего не происходило», и на экране это два разных
  /// текста.
  bool get isEmpty =>
      closedTotal == 0 && stale.isEmpty && projects.isEmpty;

  /// Самый старый возраст среди висящих, в миллисекундах, или 0.
  ///
  /// Общий знаменатель полосок: у всех строк одна шкала, поэтому «эта висит
  /// вдвое дольше той» читается по длине, а не по числу справа. Ровно поэтому
  /// же он считается по всему списку, а не по видимым строкам.
  int get oldestAgeMs {
    var oldest = 0;
    for (final task in stale) {
      if (task.ageMs > oldest) oldest = task.ageMs;
    }
    return oldest;
  }
}

/// Число миллисекунд из JSON: на проводе оно бывает и `int`, и `double`.
int _ms(Object? value) => value is num ? value.round() : 0;

/// Статус задачи из строки. Неизвестный — `pending`: строка блока «висит
/// дольше всего» и так о незакрытой задаче, а падать на новом статусе из-за
/// цвета точки было бы несоразмерно.
TaskStatus _status(Object? value) {
  for (final status in TaskStatus.values) {
    if (status.name == value) return status;
  }
  debugPrint('Unknown task status: $value');
  return TaskStatus.pending;
}
