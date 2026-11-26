import '../models/project.dart';
import '../models/task.dart';
import '../models/today_history.dart';
import 'api_client.dart';

/// The routes of «Сегодня», «Сделано», «Недели», the review, the rhythm and
/// the owner's server settings (`design/today-history-contract.md`).
///
/// `tzOffsetMinutes` is "minutes to add to UTC" -- `DateTime.timeZoneOffset`
/// in Dart (Moscow is +180), the same as `/history` always took.
class TodayHistoryApi {
  const TodayHistoryApi(this._client);

  final ApiClient _client;

  static int get _tz => DateTime.now().timeZoneOffset.inMinutes;

  // --- settings ---------------------------------------------------------------

  Future<OwnerSettings> fetchSettings() async {
    final json = await _client.get<Map<String, dynamic>>('/settings');
    return OwnerSettings.fromJson(json);
  }

  /// Any subset of the three; null leaves a field as it is.
  Future<OwnerSettings> updateSettings({
    int? laterHorizonDays,
    int? reviewWeekday,
    String? reviewTime,
  }) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/settings',
      body: <String, dynamic>{
        'laterHorizonDays': ?laterHorizonDays,
        'reviewWeekday': ?reviewWeekday,
        'reviewTime': ?reviewTime,
      },
    );
    return OwnerSettings.fromJson(json);
  }

  // --- tasks ------------------------------------------------------------------

  /// `POST /tasks/:id/reopen` -- «Вернуть»: back to the status before the
  /// closing, and into the working set it left. Online only (coordinator,
  /// answer 6).
  Future<Task> reopenTask(String taskId) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/tasks/$taskId/reopen',
    );
    return Task.fromJson(<String, dynamic>{'isCurrent': false, ...json});
  }

  // --- history ----------------------------------------------------------------

  Future<DonePage> fetchDone({String? before, int limit = 50}) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/history/done',
      queryParameters: <String, dynamic>{
        'before': ?before,
        'limit': limit,
        'tzOffsetMinutes': _tz,
      },
    );
    return DonePage.fromJson(json);
  }

  Future<List<HistoryWeek>> fetchWeeks({int weeks = 12}) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/history/weeks',
      queryParameters: <String, dynamic>{
        'weeks': weeks,
        'tzOffsetMinutes': _tz,
      },
    );
    return HistoryWeek.listFromJson(json);
  }

  // --- reviews ----------------------------------------------------------------

  Future<ReviewStatus> fetchReviewStatus() async {
    final json = await _client.get<Map<String, dynamic>>(
      '/reviews/status',
      queryParameters: <String, dynamic>{'tzOffsetMinutes': _tz},
    );
    return ReviewStatus.fromJson(json);
  }

  Future<ReviewDraft> fetchReviewDraft() async {
    final json = await _client.get<Map<String, dynamic>>(
      '/reviews/draft',
      queryParameters: <String, dynamic>{'tzOffsetMinutes': _tz},
    );
    return ReviewDraft.fromJson(json);
  }

  /// Records the review. Idempotent on the server for ten minutes, so a
  /// retry after a lost answer is safe.
  Future<Review> saveReview({String? summary}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/reviews',
      body: <String, dynamic>{
        if (summary != null && summary.trim().isNotEmpty)
          'summary': summary.trim(),
        'tzOffsetMinutes': _tz,
      },
    );
    return Review.fromJson(json);
  }

  Future<List<Review>> fetchReviews({int limit = 20}) async {
    final json = await _client.get<List<dynamic>>(
      '/reviews',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    return <Review>[
      for (final row in json)
        if (row is Map) Review.fromJson(row.cast<String, dynamic>()),
    ];
  }

  // --- rhythm -----------------------------------------------------------------

  /// `PATCH /projects/:id` with the rhythm: a number sets it, null switches
  /// that half off.
  Future<Project> setRhythm(
    String projectId, {
    required int? closedPerWeek,
    required int? maxOpen,
  }) async {
    final json = await _client.patch<Map<String, dynamic>>(
      '/projects/$projectId',
      body: <String, dynamic>{
        'rhythmClosedPerWeek': closedPerWeek,
        'rhythmMaxOpen': maxOpen,
      },
    );
    return Project.fromJson(json);
  }
}
