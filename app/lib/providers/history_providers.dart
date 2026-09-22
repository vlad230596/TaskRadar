import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/history_api.dart';
import '../api/task_events_api.dart';
import '../models/history_snapshot.dart';
import '../models/history_task_event.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'history_providers.g.dart';

/// Данные режима «История» и журнал одной задачи (F13).
///
/// ## Почему здесь нет кеша на диске, в отличие от доски
///
/// Доска — это то, ради чего приложение открывают без сети: снимок на диске
/// существует, чтобы в лифте было видно, что надо сделать. История — это ответ
/// на «как оно шло», и он никогда не бывает срочным. Показывать вчерашние
/// столбики как сегодняшние ради экрана, который смотрят раз в неделю, — это
/// вся сложность снимка (схема, версия, устаревание) ради единственного
/// результата: неверных чисел без предупреждения.
///
/// ## Почему обёртки API объявлены здесь, а не в `dependencies.dart`
///
/// Только чтобы не трогать общий файл: в дереве параллельно идёт вторая
/// итерация. По смыслу им место рядом с `projectApi` — это такие же
/// `keepAlive`-обёртки над общим `ApiClient`, — и переезд туда ничего не меняет
/// ни в одном вызывающем.

@Riverpod(keepAlive: true)
HistoryApi historyApi(Ref ref) => HistoryApi(ref.watch(apiClientProvider));

@Riverpod(keepAlive: true)
TaskEventsApi taskEventsApi(Ref ref) =>
    TaskEventsApi(ref.watch(apiClientProvider));

/// Выбранный диапазон: неделя, месяц, всё время.
///
/// Неделя по умолчанию, хотя сервер по умолчанию отдаёт месяц. Это не разнобой:
/// умолчание схемы — для curl, а экран открывают с вопросом «как прошла эта
/// неделя», и эталон (`design/reference/History.html`) подписывает кнопку «7
/// дней». Клиент всегда присылает `range` явно, так что серверное умолчание с
/// этим выбором и не встречается.
///
/// Выбор живёт до конца запуска и не пишется в настройки: в отличие от
/// «списком/плитками» это не то, как человеку удобно смотреть, а вопрос, с
/// которым он сюда пришёл сегодня.
@Riverpod(keepAlive: true)
class HistoryRangeChoice extends _$HistoryRangeChoice {
  @override
  HistoryRange build() => HistoryRange.week;

  void select(HistoryRange range) {
    if (state == range) return;
    state = range;
  }
}

/// `GET /history` для выбранного диапазона.
///
/// `watch` на диапазон, а не `read`: смена диапазона — это и есть новый
/// запрос, и написать её как «сменить состояние и не забыть перезапросить»
/// значило бы завести второе место, которое обязано об этом помнить.
///
/// Автоповтор выключен ([noAutomaticRetry]) по той же причине, что и у доски:
/// у пользователя есть явный повтор — жест и кнопка, — а невидимый на тридцать
/// восемь секунд поверх него делает видимый похожим на сломанный.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class HistoryFeed extends _$HistoryFeed {
  @override
  Future<HistorySnapshot> build() {
    final range = ref.watch(historyRangeChoiceProvider);

    return ref.read(historyApiProvider).fetchHistory(
      range: range,
      // Настоящее смещение устройства. Ноль здесь — это столбики недели,
      // посчитанные по UTC: см. длинный комментарий в `HistoryApi`.
      tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    );
  }

  /// Жест «потянуть вниз» и кнопка «Повторить».
  ///
  /// Возвращает управление и при неудаче: вызывающий — `RefreshIndicator`,
  /// чей future крутит только спиннер, а сама неудача принадлежит экрану.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('History refresh failed: $error');
    }
  }
}

/// Журнал одной задачи для блока «жизнь задачи».
///
/// Семейство и **не** `keepAlive`: журнал нужен, пока открыт экран этой задачи,
/// и держать в памяти историю каждой задачи, которую за день открыли, — это
/// кеш без единого читателя. Пере-открытие задачи стоит одного запроса к
/// роуту, который отдаёт десяток строк по индексу `[taskId, at]`.
///
/// Автоповтор выключен по той же причине, что и у [HistoryFeed]: блок сам
/// говорит, что журнал не прочитался, и остальной экран задачи при этом
/// полностью рабочий.
@Riverpod(retry: noAutomaticRetry)
Future<List<TaskEvent>> taskEvents(Ref ref, String taskId) =>
    ref.watch(taskEventsApiProvider).fetchEvents(taskId);
