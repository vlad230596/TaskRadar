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
    this.parseId,
  });

  factory ParsedDictation.fromJson(Map<String, dynamic> json) =>
      ParsedDictation(
        title: json['title'] as String,
        description: json['description'] as String?,
        remindDate: json['remindDate'] as String?,
        remindTime: json['remindTime'] as String?,
        parseId: json['parseId'] as String?,
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

  /// The server's record of this parse in its dataset, sent back when the
  /// task is created so the record gets linked to it and learns what was kept.
  /// Null when the server could not keep the record.
  final String? parseId;
}

/// Which model parses dictation, as `GET/PUT /dictation/model` describe it.
class DictationModel {
  const DictationModel({
    required this.model,
    required this.defaultModel,
    required this.override,
  });

  factory DictationModel.fromJson(Map<String, dynamic> json) => DictationModel(
    model: json['model'] as String,
    defaultModel: json['defaultModel'] as String,
    override: json['override'] as String?,
  );

  /// The model in use right now.
  final String model;

  /// `LLM_MODEL` from the server's `.env`.
  final String defaultModel;

  /// The model chosen in the app, or null when [defaultModel] is in use.
  final String? override;
}

/// `POST /dictation/parse` (F14), and the model it runs on.
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

  /// `GET /dictation/model`. A 503 means no model is configured on the server
  /// at all -- there is then nothing to choose between.
  Future<DictationModel> fetchModel() async {
    final json = await _client.get<Map<String, dynamic>>('/dictation/model');
    return DictationModel.fromJson(json);
  }

  /// `PUT /dictation/model`. Null goes back to the server's `.env` model.
  ///
  /// Only the model: the API key stays on the server, in a file the app can
  /// neither read nor write (`backend/src/domain/dictationModel.ts`).
  Future<DictationModel> setModel(String? model) async {
    final json = await _client.request<Map<String, dynamic>>(
      'PUT',
      '/dictation/model',
      body: <String, dynamic>{'model': model},
    );
    return DictationModel.fromJson(json);
  }
}
