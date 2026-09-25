import 'api_client.dart';

/// A dictation turned into a task by the server's language model (F14).
///
/// A plain class rather than a freezed model: it is read once, on the
/// dictation screen, and never cached, compared or copied.
class ParsedDictation {
  const ParsedDictation({
    required this.title,
    required this.description,
    required this.remindDate,
    required this.remindTime,
  });

  factory ParsedDictation.fromJson(Map<String, dynamic> json) =>
      ParsedDictation(
        title: json['title'] as String,
        description: json['description'] as String?,
        remindDate: json['remindDate'] as String?,
        remindTime: json['remindTime'] as String?,
      );

  /// Short, starts with a verb.
  final String title;

  /// Everything the title left out, or null.
  final String? description;

  /// `YYYY-MM-DD` in the device's zone -- the exact shape `remindAt` is sent
  /// in (see `ProjectApi.updateTask`) -- or null.
  final String? remindDate;

  /// `HH:MM`, or null. Returned by the server, but not stored anywhere yet:
  /// reminders have day granularity (`domain/reminders.dart`).
  final String? remindTime;
}

/// `POST /dictation/parse` (F14).
///
/// ## The server writes nothing
///
/// The answer is a *proposal*; the caller creates the task through the
/// ordinary task route. So every failure here -- no network, 503 (no model
/// configured on the server), 502 (the model failed) -- costs nothing but the
/// tidying: the caller falls back to the words as recognised.
class DictationApi {
  const DictationApi(this._client);

  final ApiClient _client;

  /// [timeZone] is the device's IANA zone: "завтра" is a different day in
  /// Vladivostok and in Kaliningrad, and the server refuses to guess.
  Future<ParsedDictation> parse({
    required String text,
    required String timeZone,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/dictation/parse',
      body: <String, dynamic>{'text': text, 'timeZone': timeZone},
    );
    return ParsedDictation.fromJson(json);
  }
}
