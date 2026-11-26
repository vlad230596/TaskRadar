import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/task_events_api.dart';
import '../models/history_task_event.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'history_providers.g.dart';

/// Журнал одной задачи — для блока «жизнь задачи» в редакторе (F13).
///
/// Сводки режима «История» (`/history/done`, `/history/weeks`, пересмотр)
/// живут в `today_providers.dart`; старый `GET /history` приложение больше
/// не зовёт (сервер держит его для старых версий).

@Riverpod(keepAlive: true)
TaskEventsApi taskEventsApi(Ref ref) =>
    TaskEventsApi(ref.watch(apiClientProvider));

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
