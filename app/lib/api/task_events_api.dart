import '../models/history_task_event.dart';
import 'api_client.dart';

/// Журнал одной задачи: `GET /tasks/:id/events` (F11/F13).
///
/// Отдельный класс, а не метод на `ProjectApi`, по той же границе, по которой
/// `BoardApi` отделён от него: `ProjectApi` — это всё, чем экран проекта пишет
/// и читает задачи, а это read-only роут, который нужен ровно одному блоку
/// одного экрана и появился вместе с историей. Сложить его к задачам значило
/// бы, что экран проекта тянет за собой модель журнала, которая ему не нужна.
///
/// **Роут отдаёт сырые строки**, в порядке `at` по возрастанию, и это его
/// решение, а не упущение: «3 дня в блокере» клиент получает из `GET /history`,
/// а здесь ему нужна сама последовательность переходов (см. `replayTaskLife`).
///
/// 404 (ApiException со `statusCode == 404`) означает, что задачи нет: роут
/// сначала проверяет задачу и только потом читает журнал. Пустой массив —
/// другое: задача есть, а событий у неё нет. Разница важна для экрана — он
/// показывает по ней разные вещи.
class TaskEventsApi {
  const TaskEventsApi(this._client);

  final ApiClient _client;

  Future<List<TaskEvent>> fetchEvents(String taskId) async {
    final json = await _client.get<List<dynamic>>('/tasks/$taskId/events');
    return TaskEvent.listFromJson(json);
  }
}
