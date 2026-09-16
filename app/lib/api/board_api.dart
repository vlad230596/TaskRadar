import '../models/board_project.dart';
import 'api_client.dart';

/// `GET /board` -- the whole board in one request.
///
/// Present in F0 only so the model and its parser exist and are tested; the
/// board screen itself arrives in F2. The endpoint is the reason `GET /board`
/// was added at all: rendering the board from `/projects` + one
/// `/projects/:id/tasks` per project costs 1+N round trips, which is unnoticeable
/// over localhost and several seconds over a mobile network with 15 projects.
class BoardApi {
  const BoardApi(this._client);

  final ApiClient _client;

  /// Fetches the board.
  ///
  /// [archived] selects which half of the board to read -- active projects or
  /// the archive -- and is sent as the literal string `"true"`/`"false"` because
  /// the backend parses the query with a string enum, not a boolean coercion.
  ///
  /// The response is a bare JSON array, not an envelope object, so the decoded
  /// body is a `List` and there is no `data` key to reach through.
  Future<List<BoardProject>> fetchBoard({bool archived = false}) async {
    final json = await _client.get<List<dynamic>>(
      '/board',
      queryParameters: <String, dynamic>{'archived': archived ? 'true' : 'false'},
    );
    return BoardProject.listFromJson(json);
  }
}
