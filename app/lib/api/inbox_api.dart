import '../models/inbox_item.dart';
import '../models/task.dart';
import 'api_client.dart';

/// The sandbox endpoints (F8): capture now, file later.
///
/// ## The one contract detail worth knowing
///
/// [fileItem] answers with the **created task**, in the raw shape a mutation
/// endpoint uses -- so it has **no `isCurrent` key**, exactly like
/// `POST /projects/:id/tasks`. That is correct of the server (`isCurrent` is a
/// property of a project's whole ordered list, not of one row) and it means the
/// caller cannot splice that row into a task list without losing the
/// current-task highlight. `Inbox.file` does not try: it invalidates the board
/// instead. See the note there.
class InboxApi {
  const InboxApi(this._client);

  final ApiClient _client;

  /// `GET /inbox`, **oldest first**.
  ///
  /// The order is the server's and is a product decision rather than a default:
  /// the pile is processed from the top, and the item at risk of rotting is the
  /// one that has been waiting longest. Nothing here re-sorts it.
  Future<List<InboxItem>> fetchInbox() async {
    final json = await _client.get<List<dynamic>>('/inbox');
    return List<InboxItem>.unmodifiable(
      json.map((dynamic e) => InboxItem.fromJson(e as Map<String, dynamic>)),
    );
  }

  /// `POST /inbox`. The whole payload is one line of text.
  Future<InboxItem> capture({required String text}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/inbox',
      body: <String, dynamic>{'text': text},
    );
    return InboxItem.fromJson(json);
  }

  /// `PATCH /inbox/:id` -- fixing what was captured in a hurry (or, from F9,
  /// dictated) before it becomes a task.
  Future<InboxItem> editItem(String itemId, {required String text}) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/inbox/$itemId',
      body: <String, dynamic>{'text': text},
    );
    return InboxItem.fromJson(json);
  }

  /// `DELETE /inbox/:id`. No archive step and no undo: this is a sentence
  /// somebody typed a moment ago, not a project.
  Future<void> deleteItem(String itemId) async {
    await _client.delete('/inbox/$itemId');
  }

  /// `POST /inbox/:id/file` -- the item becomes a task at the end of
  /// [projectId], and stops being an inbox item.
  ///
  /// One request rather than "create a task, then delete the item": from a
  /// phone, two requests have two ways to be half-done -- the same thing filed
  /// twice, or the thought gone entirely -- and the server does both halves in
  /// one transaction.
  Future<Task> fileItem(String itemId, {required String projectId}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/inbox/$itemId/file',
      body: <String, dynamic>{'projectId': projectId},
    );
    // The response has no `isCurrent`; `Task.fromJson` requires one. Filling it
    // in as false here is safe and deliberate -- the row is only ever used to
    // report what was created, never spliced into a list, because the board is
    // re-read afterwards.
    return Task.fromJson(<String, dynamic>{'isCurrent': false, ...json});
  }
}
