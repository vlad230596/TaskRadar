import '../models/scope.dart';
import 'api_client.dart';

/// The scope endpoints (F7): the spaces the board is partitioned into.
///
/// A class of its own rather than more methods on [ProjectApi], because scopes
/// are read on a different rhythm: the whole list is fetched once when the app
/// starts and then changed a few times a year, while the project endpoints are
/// the write path of every working day.
///
/// ## What is deliberately missing
///
/// There is no `fetchScope(id)`. The list is a handful of rows that the client
/// always holds in full, so a single-row read would only ever be a slower way
/// to look in a list it already has.
class ScopeApi {
  const ScopeApi(this._client);

  final ApiClient _client;

  /// `GET /scopes`, in `position` order. Never filtered: the switcher needs all
  /// of them, and there is no archived flavour of a scope.
  Future<List<Scope>> fetchScopes() async {
    final json = await _client.get<List<dynamic>>('/scopes');
    return List<Scope>.unmodifiable(
      json.map((dynamic e) => Scope.fromJson(e as Map<String, dynamic>)),
    );
  }

  /// `POST /scopes`. The new scope is appended to the end of the order by the
  /// server; the client does not choose a position.
  Future<Scope> createScope({required String name}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/scopes',
      body: <String, dynamic>{'name': name},
    );
    return Scope.fromJson(json);
  }

  /// `PATCH /scopes/:id` -- the rename, and a scope's only field update.
  Future<Scope> renameScope(String scopeId, {required String name}) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/scopes/$scopeId',
      body: <String, dynamic>{'name': name},
    );
    return Scope.fromJson(json);
  }

  /// `PATCH /scopes/:id/position` -- reorder by naming the **neighbours**.
  ///
  /// Ids, not an index, and `null` for "no neighbour on that side". Exactly the
  /// contract `ProjectApi.moveTask` uses, and for the same reason: when the
  /// float gap between two neighbours is exhausted the server renumbers every
  /// scope in one transaction and still answers with only the moved row, so an
  /// index or a position computed here would be stale the moment that happens.
  /// An id survives a rebalance.
  Future<Scope> moveScope(
    String scopeId, {
    required String? beforeScopeId,
    required String? afterScopeId,
  }) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/scopes/$scopeId/position',
      body: <String, dynamic>{
        'beforeScopeId': beforeScopeId,
        'afterScopeId': afterScopeId,
      },
    );
    return Scope.fromJson(json);
  }

  /// `DELETE /scopes/:id`. Answers 204, or **409** when the scope still holds
  /// projects (archived ones included) or is the only scope left.
  ///
  /// There is no archive step in front of it, unlike a project: a scope holds
  /// no content of its own, so there would be nothing to restore. What it holds
  /// is other people's work, and that is what the 409 protects --
  /// `backend/src/domain/scopeDeleteGuard.ts` has both rules.
  Future<void> deleteScope(String scopeId) async {
    await _client.delete('/scopes/$scopeId');
  }
}
