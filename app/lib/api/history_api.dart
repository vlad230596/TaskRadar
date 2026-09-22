import '../models/history_snapshot.dart';
import 'api_client.dart';

/// Режим «История», один роут: `GET /history` (F11/F13).
///
/// ## Что важно знать вызывающему
///
/// **Границы суток считает сервер — по тому, что прислал клиент.** Параметр
/// `tzOffsetMinutes` не украшение: столбики недели группируются по местным
/// дням, и задача, закрытая в час ночи в Москве, принадлежит этому дню, а не
/// предыдущему только потому, что сервер хранит UTC. Не прислать смещение —
/// значит получить неделю, посчитанную по UTC, и столбики, которые едут на
/// границе суток. Поэтому [fetchHistory] требует его, а не подставляет ноль:
/// на сервере значение по умолчанию есть (`historyQuerySchema`), и оно там для
/// curl, а не для приложения, у которого часовой пояс всегда под рукой.
///
/// Знак — «сколько прибавить к UTC»: Москва — это `+180`, то есть ровно
/// `DateTime.timeZoneOffset.inMinutes` в Dart, и **не** `getTimezoneOffset()`
/// из JavaScript, у которого он противоположный.
///
/// **`staleLimit` режет уже посчитанное.** Сервер в любом случае проигрывает
/// журнал каждой открытой задачи — иначе он не знает, какие из них висят
/// дольше всего, — и обрезает список только в конце. Так что просить пять
/// строк вместо пятидесяти ничего не экономит на сервере, зато делает
/// невозможным честный ответ на «сколько всего висит дольше недели». Клиент
/// просит потолок ([kHistoryStaleLimit]).
class HistoryApi {
  const HistoryApi(this._client);

  final ApiClient _client;

  Future<HistorySnapshot> fetchHistory({
    required HistoryRange range,
    required int tzOffsetMinutes,
    int staleLimit = kHistoryStaleLimit,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/history',
      queryParameters: <String, dynamic>{
        'range': range.wire,
        'tzOffsetMinutes': tzOffsetMinutes,
        'staleLimit': staleLimit,
      },
    );
    return HistorySnapshot.fromJson(json);
  }
}

/// Потолок `staleLimit` из `historyQuerySchema`, и то, что клиент просит
/// всегда.
///
/// Пятьдесят открытых задач — это больше, чем бывает в личном трекере, так что
/// на практике это «все», и именно на этом держатся два числа на широком
/// экране: средний возраст висящего и сколько его висит дольше недели. Считать
/// их по пяти присланным строкам значило бы подписать словом «средний»
/// среднее из пяти самых старых.
const int kHistoryStaleLimit = 50;
