import '../models/goal.dart';
import '../models/task.dart';
import 'api_client.dart';

/// Contours and goals (`design/goals-ideas-contract.md`, «API»).
///
/// Writes here are online-only in this iteration: there is no outbox to
/// replay them, so a failure is reported where the button was pressed. Every
/// goal write answers with the whole [GoalView], which the providers swap into
/// their list as it came -- one shape whichever button was pressed.
class GoalsApi {
  const GoalsApi(this._client);

  final ApiClient _client;

  // -- Contours ---------------------------------------------------------------

  /// `GET /contours` -- every contour in order and the stored manual choice.
  Future<ContourList> fetchContours() async {
    final json = await _client.get<Map<String, dynamic>>('/contours');
    return ContourList.fromJson(json);
  }

  Future<Contour> createContour({
    required String name,
    int? slots,
    int? windowDays,
    ContourSchedule? schedule,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/contours',
      body: <String, dynamic>{
        'name': name,
        'slots': ?slots,
        'windowDays': ?windowDays,
        if (schedule != null) 'schedule': schedule.toJson(),
      },
    );
    return Contour.fromJson(json);
  }

  /// `PATCH /contours/:id`. [clearSchedule] sends `schedule: null`.
  Future<Contour> updateContour(
    String id, {
    String? name,
    int? slots,
    int? windowDays,
    ContourSchedule? schedule,
    bool clearSchedule = false,
    double? position,
  }) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/contours/$id',
      body: <String, dynamic>{
        'name': ?name,
        'slots': ?slots,
        'windowDays': ?windowDays,
        if (schedule != null || clearSchedule) 'schedule': schedule?.toJson(),
        'position': ?position,
      },
    );
    return Contour.fromJson(json);
  }

  /// `DELETE /contours/:id` -- 204, or 409 for the last contour and for one
  /// that still has goals.
  Future<void> deleteContour(String id) =>
      _client.delete<dynamic>('/contours/$id');

  /// `PUT /contours/active`. `contourId: null` hands the choice back to the
  /// schedules.
  Future<ActiveContourChoice> setActiveContour({
    required String? contourId,
    required DateTime? until,
  }) async {
    final json = await _client.request<Map<String, dynamic>>(
      'PUT',
      '/contours/active',
      body: <String, dynamic>{
        'contourId': contourId,
        'until': until?.toUtc().toIso8601String(),
      },
    );
    return ActiveContourChoice.fromJson(json);
  }

  // -- Goals ------------------------------------------------------------------

  /// `GET /goals?state=...` in contour order, then position.
  Future<List<GoalView>> fetchGoals({
    List<GoalState> states = const <GoalState>[GoalState.slot, GoalState.bench],
  }) async {
    final json = await _client.get<List<dynamic>>(
      '/goals',
      queryParameters: <String, dynamic>{
        'state': states.map((state) => state.name).join(','),
      },
    );
    return List<GoalView>.unmodifiable(
      json.map((dynamic e) => GoalView.fromJson(e as Map<String, dynamic>)),
    );
  }

  Future<GoalView> fetchGoal(String id) async =>
      GoalView.fromJson(await _client.get<Map<String, dynamic>>('/goals/$id'));

  Future<GoalView> createGoal({
    required String contourId,
    required String title,
    String? why,
    bool slot = false,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/goals',
      body: <String, dynamic>{
        'contourId': contourId,
        'title': title,
        'why': ?why,
        'slot': slot,
      },
    );
    return GoalView.fromJson(json);
  }

  /// `PATCH /goals/:id`. [clearWhy] sends `why: null`; [clearWindow] sends
  /// `windowDays: null` (back to the contour's window).
  Future<GoalView> updateGoal(
    String id, {
    String? title,
    String? why,
    bool clearWhy = false,
    String? contourId,
    int? windowDays,
    bool clearWindow = false,
    double? position,
  }) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/goals/$id',
      body: <String, dynamic>{
        'title': ?title,
        if (why != null || clearWhy) 'why': why,
        'contourId': ?contourId,
        if (windowDays != null || clearWindow) 'windowDays': windowDays,
        'position': ?position,
      },
    );
    return GoalView.fromJson(json);
  }

  Future<GoalView> slotGoal(String id, {int? windowDays}) =>
      _action(id, 'slot', <String, dynamic>{'windowDays': ?windowDays});

  Future<GoalView> extendGoal(String id) => _action(id, 'extend');
  Future<GoalView> benchGoal(String id) => _action(id, 'bench');
  Future<GoalView> achieveGoal(String id) => _action(id, 'achieve');
  Future<GoalView> reopenGoal(String id) => _action(id, 'reopen');

  Future<void> deleteGoal(String id) => _client.delete<dynamic>('/goals/$id');

  Future<GoalView> linkTask(String goalId, String taskId) async =>
      GoalView.fromJson(
        await _client.request<Map<String, dynamic>>(
          'PUT',
          '/goals/$goalId/tasks/$taskId',
        ),
      );

  Future<GoalView> unlinkTask(String goalId, String taskId) async =>
      GoalView.fromJson(
        await _client.delete<Map<String, dynamic>>(
          '/goals/$goalId/tasks/$taskId',
        ),
      );

  /// Reorder within the goal: [beforeTaskId] comes just before the task,
  /// [afterTaskId] just after.
  Future<GoalView> moveTask(
    String goalId,
    String taskId, {
    String? beforeTaskId,
    String? afterTaskId,
  }) async => GoalView.fromJson(
    await _client.post<Map<String, dynamic>>(
      '/goals/$goalId/tasks/$taskId/move',
      body: <String, dynamic>{
        'beforeTaskId': ?beforeTaskId,
        'afterTaskId': ?afterTaskId,
      },
    ),
  );

  Future<GoalView> linkIdea(String goalId, String noteId) async =>
      GoalView.fromJson(
        await _client.request<Map<String, dynamic>>(
          'PUT',
          '/goals/$goalId/ideas/$noteId',
        ),
      );

  Future<GoalView> unlinkIdea(String goalId, String noteId) async =>
      GoalView.fromJson(
        await _client.delete<Map<String, dynamic>>(
          '/goals/$goalId/ideas/$noteId',
        ),
      );

  // -- Ideas and tasks ----------------------------------------------------------

  /// `POST /notes/:id/to-task`: the idea becomes a task at the end of its
  /// project, its goals carried over; the idea is gone.
  Future<Task> ideaToTask(String noteId) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/notes/$noteId/to-task',
    );
    // A single task row carries no list, so no `isCurrent`; the project is
    // re-read by the caller anyway.
    return Task.fromJson(<String, dynamic>{'isCurrent': false, ...json});
  }

  /// `GET /tasks/:id` -- one task, for a step opened from a goal.
  Future<Task> fetchTask(String id) async {
    final json = await _client.get<Map<String, dynamic>>('/tasks/$id');
    return Task.fromJson(<String, dynamic>{'isCurrent': false, ...json});
  }

  Future<GoalView> _action(
    String id,
    String action, [
    Map<String, dynamic>? body,
  ]) async => GoalView.fromJson(
    await _client.post<Map<String, dynamic>>(
      '/goals/$id/$action',
      body: body ?? const <String, dynamic>{},
    ),
  );
}
