import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_client.dart';
import 'api_exception.dart';
import 'sse.dart';

/// What the server's model is asked to turn the words into -- the request's
/// `kind` (`backend/src/domain/parsePipeline.ts`).
///
/// Every kind runs from the words it is sent, never from an earlier answer:
/// "Разобрать заново" sends the source again.
enum ParseKind {
  /// A new dictation as a proposed task, with a reminder: [ParsedDictation].
  task('task'),

  /// An existing task's text, tidied into its two fields: [TidiedTask].
  taskTidy('task_tidy'),

  /// A note's body as paragraphs and lists: [TidiedNote].
  note('note'),

  /// A sandbox line tidied, with a project for it: [TidiedLine].
  sandbox('sandbox');

  const ParseKind(this.wire);

  /// What the request says.
  final String wire;
}

/// One answer of the model, of whichever [ParseKind] was asked for.
///
/// Plain classes rather than freezed models: each is read once, on the screen
/// that asked for it, and never cached, compared or copied.
sealed class TidyResult {
  const TidyResult();

  /// The answer of [kind] in [json] -- the `result` of the stream. Throws when
  /// [json] is not that shape.
  static TidyResult fromJson(ParseKind kind, Map<String, dynamic> json) =>
      switch (kind) {
        ParseKind.task => ParsedDictation.fromJson(json),
        ParseKind.taskTidy => TidiedTask(
          title: json['title'] as String,
          description: json['description'] as String?,
          parseId: json['parseId'] as String?,
          warnings: TidyWarning.listFrom(json['warnings']),
        ),
        ParseKind.note => TidiedNote(
          title: json['title'] as String?,
          content: json['content'] as String,
          parseId: json['parseId'] as String?,
          warnings: TidyWarning.listFrom(json['warnings']),
        ),
        ParseKind.sandbox => TidiedLine.fromJson(json),
      };

  /// The server's record of this parse in its dataset, or null when it could
  /// not keep one.
  String? get parseId;

  /// What the user should check before taking the answer. Empty almost always.
  List<TidyWarning> get warnings => const <TidyWarning>[];
}

/// Something in an answer the user should look at before taking it
/// (`TidyWarning` in `backend/src/domain/tidy.ts`).
///
/// Today one kind: [inventedDate], a day, a date or a time the words did not
/// say -- "три ноль" written down as "3.00", or a "до пятницы" the model made
/// up. The server cannot tell the two apart, so it never withholds the answer
/// for it; it names the [token], as the answer spells it, and the screen says
/// so over the answer.
class TidyWarning {
  const TidyWarning({required this.kind, required this.token});

  /// The one kind there is.
  static const String inventedDate = 'invented_date';

  final String kind;
  final String token;

  /// The `warnings` of a result: a list of `{kind, token}`. Anything else --
  /// an older server that sends none, an entry of an unknown shape -- is no
  /// warning rather than a failed parse: a warning is advice, and the answer
  /// is usable without it.
  static List<TidyWarning> listFrom(Object? json) {
    if (json is! List) return const <TidyWarning>[];
    return List<TidyWarning>.unmodifiable(<TidyWarning>[
      for (final entry in json)
        if (entry case {
          'kind': final String kind,
          'token': final String token,
        } when token.isNotEmpty)
          TidyWarning(kind: kind, token: token),
    ]);
  }
}

/// A dictation turned into a task by the server's language model (F14).
class ParsedDictation extends TidyResult {
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

  /// `HH:MM`, or null: the reminder's time of day, saved as the task's
  /// `remindTime`. Only meaningful with [remindDate].
  final String? remindTime;

  /// The server's record of this parse in its dataset, sent back when the
  /// task is created so the record gets linked to it and learns what was kept.
  /// Null when the server could not keep the record.
  @override
  final String? parseId;
}

/// An existing task's text, tidied: the same words, split into a title and a
/// description, with nothing added -- no date the text did not say.
class TidiedTask extends TidyResult {
  const TidiedTask({
    required this.title,
    this.description,
    this.parseId,
    this.warnings = const <TidyWarning>[],
  });

  final String title;
  final String? description;

  @override
  final String? parseId;

  @override
  final List<TidyWarning> warnings;
}

/// A note's body as markdown paragraphs and lists. [title] only when the note
/// had none to begin with.
class TidiedNote extends TidyResult {
  const TidiedNote({
    required this.content,
    this.title,
    this.parseId,
    this.warnings = const <TidyWarning>[],
  });

  final String? title;
  final String content;

  @override
  final String? parseId;

  @override
  final List<TidyWarning> warnings;
}

/// A sandbox line tidied, and the project it most likely belongs to -- one of
/// the projects the server has, checked there, or null.
///
/// Also the same text as a task, [title] and [description]: when the line
/// goes to its project instead of staying in the sandbox, it is filed in that
/// shape, from this one answer -- there is no second call to the model.
class TidiedLine extends TidyResult {
  const TidiedLine({
    required this.text,
    String? title,
    this.description,
    this.projectId,
    this.projectName,
    this.parseId,
    this.warnings = const <TidyWarning>[],
  }) : _title = title;

  factory TidiedLine.fromJson(Map<String, dynamic> json) => TidiedLine(
    text: json['text'] as String,
    title: json['title'] as String?,
    description: json['description'] as String?,
    projectId: json['projectId'] as String?,
    projectName: json['projectName'] as String?,
    parseId: json['parseId'] as String?,
    warnings: TidyWarning.listFrom(json['warnings']),
  );

  final String text;

  final String? _title;

  /// [text] as a task's title. The line itself when the server sent none --
  /// a server from before the sandbox answer had one.
  String get title {
    final title = _title?.trim() ?? '';
    return title.isEmpty ? text : title;
  }

  /// Null with no [title] from the server: the line is then all title.
  final String? description;

  /// Whether [title] and [description] are the model's split of [text]. False
  /// once the line has been corrected by hand ([edited]) or when the server
  /// sent no split: the split would then be of words that are no longer the
  /// line, and filing it would put back what the user just took out.
  bool get hasTaskShape => (_title?.trim() ?? '').isNotEmpty;

  /// This answer with [text] corrected by hand. The split goes unless the
  /// text is the same -- see [hasTaskShape].
  TidiedLine edited(String text) => text == this.text
      ? this
      : TidiedLine(
          text: text,
          projectId: projectId,
          projectName: projectName,
          parseId: parseId,
          warnings: warnings,
        );

  final String? projectId;
  final String? projectName;

  @override
  final String? parseId;

  @override
  final List<TidyWarning> warnings;
}

/// A stage of [DictationApi.parseStream], in the order they come.
sealed class ParseProgress {
  const ParseProgress();
}

/// The request body has left the phone. Said by the transport, not by the
/// server, so it is the one stage that can be seen with no server at all.
final class ParseSent extends ParseProgress {
  const ParseSent();
}

/// The server read a valid request and started on it.
final class ParseAccepted extends ParseProgress {
  const ParseAccepted();
}

/// The request to the model is out; [model] is the one that will answer.
final class ParseModelStarted extends ParseProgress {
  const ParseModelStarted(this.model);

  final String model;
}

/// The model answered, after [durationMs] by the server's clock.
final class ParseModelDone extends ParseProgress {
  const ParseModelDone(this.durationMs);

  final int? durationMs;
}

/// The model's answer was checked and is usable.
final class ParseValidated extends ParseProgress {
  const ParseValidated();
}

/// Nothing new, but the server is still there: a heartbeat, or bytes arriving.
final class ParseAlive extends ParseProgress {
  const ParseAlive();
}

/// The answer. Always the last event of a stream that did not fail. Of the
/// [TidyResult] subtype the stream's [ParseKind] names.
final class ParseDone extends ParseProgress {
  const ParseDone(this.result, {this.modelLabel});

  final TidyResult result;

  /// Which model answered, as the server's roster names it; null from a
  /// server older than the roster (`backend/src/domain/modelRoster.ts`).
  final String? modelLabel;
}

/// One model's answer in "отправить в несколько": each arrives as soon as
/// that model is done, before the stream's [ParseDone].
final class ParseCandidate extends ParseProgress {
  const ParseCandidate(this.candidate);

  final TidyCandidate candidate;
}

/// One model's answer, or its failure, in "отправить в несколько".
class TidyCandidate {
  const TidyCandidate({
    required this.model,
    required this.label,
    this.result,
    this.cause,
  });

  /// The model's name at its provider.
  final String model;

  /// What the app calls it.
  final String label;

  /// The answer; null when the model failed.
  final TidyResult? result;

  /// Why it failed (`UpstreamCause` in `backend/src/lib/llmClient.ts`).
  final String? cause;

  bool get ok => result != null;
}

/// Nothing came from the server for [silence] in the middle of a parse. A
/// [NetworkException], because what it means for the user is the same -- the
/// server cannot be heard -- but its own type, because the words differ: the
/// request did go out, and trying again is the likely fix.
class ParseSilenceException extends NetworkException {
  ParseSilenceException(this.silence) : super('The server went silent');

  final Duration silence;
}

/// Why the model gave no answer: the class of the provider's failure, as the
/// server tells it (`UpstreamCause` in `backend/src/lib/llmClient.ts`), and the
/// model that was asked. The provider's own words stay in the server's log.
class ModelFailure {
  const ModelFailure(this.cause, {this.model});

  /// The failure behind [error], or null when [error] is not the model's -- or
  /// came from a server too old to say why. Read from either reply: the JSON
  /// one keeps it under `details`, the stream's `error` event at the top.
  static ModelFailure? of(Object error) {
    if (error is! ApiException || error.statusCode != 502) return null;
    final body = error.body;
    if (body is! Map) return null;
    final details = body['details'];
    final fields = details is Map ? details : body;
    final cause = fields['cause'];
    if (cause is! String) return null;
    return ModelFailure(cause, model: fields['model'] as String?);
  }

  /// One of `model_not_found`, `unauthorized`, `no_credits`, `rate_limited`,
  /// `provider_down`, `rejected`, `timeout`, `unreachable`, `bad_reply`,
  /// `cancelled` -- or a class a newer server added.
  final String cause;

  final String? model;
}

/// One model of the server's roster (`backend/src/domain/modelRoster.ts`),
/// as `GET /dictation/models` describes it.
///
/// [baseUrl], [apiKeyEnv] and [keyPresent] come only to the owner; for
/// everyone else they are null.
class AiModelEntry {
  const AiModelEntry({
    required this.id,
    required this.name,
    required this.label,
    required this.enabled,
    required this.status,
    this.baseUrl,
    this.apiKeyEnv,
    this.keyPresent,
    this.autoDisabledReason,
    this.consecutiveFailures = 0,
    this.lastSuccessAt,
    this.lastFailureAt,
  });

  factory AiModelEntry.fromJson(Map<String, dynamic> json) => AiModelEntry(
    id: json['id'] as String?,
    name: json['name'] as String,
    label: json['label'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    status: json['status'] as String? ?? 'ok',
    baseUrl: json['baseUrl'] as String?,
    apiKeyEnv: json['apiKeyEnv'] as String?,
    keyPresent: json['keyPresent'] as bool?,
    autoDisabledReason: json['autoDisabledReason'] as String?,
    consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
    lastSuccessAt: DateTime.tryParse(json['lastSuccessAt'] as String? ?? ''),
    lastFailureAt: DateTime.tryParse(json['lastFailureAt'] as String? ?? ''),
  );

  /// Null for an entry not saved yet.
  final String? id;

  /// The model's name at its provider.
  final String name;
  final String? label;
  final bool enabled;

  /// `ok`, `cooling_down` (three failures, skipped for a while), `disabled`
  /// (by the owner) or `auto_disabled` (by its own failures).
  final String status;
  final String? baseUrl;
  final String? apiKeyEnv;

  /// Whether the variable [apiKeyEnv] names is set on the server.
  final bool? keyPresent;
  final String? autoDisabledReason;
  final int consecutiveFailures;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  String get title => label ?? name;

  /// The body `PUT /dictation/models` takes for this entry.
  Map<String, dynamic> toInput() => <String, dynamic>{
    'id': ?id,
    'name': name,
    'label': label,
    'baseUrl': baseUrl,
    'apiKeyEnv': apiKeyEnv,
    'enabled': enabled,
  };

  AiModelEntry edited({
    required String name,
    required String? label,
    required String? baseUrl,
    required String? apiKeyEnv,
    bool? enabled,
  }) => AiModelEntry(
    id: id,
    name: name,
    label: label,
    enabled: enabled ?? this.enabled,
    status: status,
    baseUrl: baseUrl,
    apiKeyEnv: apiKeyEnv,
    keyPresent: keyPresent,
    autoDisabledReason: autoDisabledReason,
    consecutiveFailures: consecutiveFailures,
    lastSuccessAt: lastSuccessAt,
    lastFailureAt: lastFailureAt,
  );
}

/// The roster, and the model the server falls back to when it is empty.
class AiModels {
  const AiModels({required this.models, required this.fallbackModel});

  factory AiModels.fromJson(Map<String, dynamic> json) => AiModels(
    models: <AiModelEntry>[
      for (final entry in json['models'] as List<dynamic>? ?? const <dynamic>[])
        AiModelEntry.fromJson((entry as Map).cast<String, dynamic>()),
    ],
    fallbackModel: json['defaultModel'] as String?,
  );

  final List<AiModelEntry> models;

  /// The `.env` model (or the old app setting) used while [models] is empty.
  final String? fallbackModel;
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

  /// The same parse, as the stages it goes through (`Accept:
  /// text/event-stream`, see `backend/src/routes/dictation.ts`).
  ///
  /// ## Why a stream
  ///
  /// A long dictation takes the model tens of seconds, and a spinner that
  /// says nothing for that long cannot be told from a request that died. So
  /// the server says what it is doing -- accepted, model started, model done,
  /// checked -- and sends a heartbeat every 5 s, and the stream ends with
  /// [ParseDone].
  ///
  /// ## When it gives up
  ///
  /// Not after a fixed total, which is what killed long dictations: the
  /// server bounds the model call itself, growing with the text. This side
  /// fails only when nothing at all has arrived for [silence] -- no event, no
  /// byte -- with a [NetworkException], as for no network at all.
  ///
  /// A failure before the stream starts (401, 503, a 400) is the same
  /// [ApiException] as from [parse]; the server's `error` event is an
  /// [ApiException] with 502 (the model failed) or 500. Cancelling the
  /// subscription, or [cancelToken], drops the connection, and the server
  /// stops the model call when it notices.
  ///
  /// On the web the browser's XHR hands over the body only when it is
  /// complete: the stages then arrive together at the end, and liveness is
  /// told by the bytes arriving ([ParseAlive]) rather than by the events.
  ///
  /// [kind] picks the prompt and the shape of [ParseDone.result];
  /// [noteTitle] is sent for [ParseKind.note] only, so the model knows the
  /// note already has a title; [level] is how freely the model may reword.
  Stream<ParseProgress> parseStream({
    required String text,
    required String timeZone,
    ParseKind kind = ParseKind.task,
    String? noteTitle,
    int? level,
    bool multi = false,
    CancelToken? cancelToken,
    Duration silence = const Duration(seconds: 20),
  }) {
    final cancel = cancelToken ?? CancelToken();
    late final StreamController<ParseProgress> out;
    StreamSubscription<SseEvent>? events;
    Timer? watchdog;
    var sent = false;
    var finished = false;

    void finish() {
      if (finished) return;
      finished = true;
      watchdog?.cancel();
      // The token is what closes the connection -- dio's body stream does not
      // pass a cancelled subscription on to the socket. It also pushes a
      // "cancelled" error into that stream, so the subscription goes first
      // and nobody is left to hear it.
      unawaited(events?.cancel());
      if (!cancel.isCancelled) cancel.cancel('parse finished');
    }

    void fail(Object error) {
      if (finished) return;
      out.addError(error);
      finish();
      unawaited(out.close());
    }

    void emit(ParseProgress progress) {
      if (!finished) out.add(progress);
    }

    void arm() {
      watchdog?.cancel();
      watchdog = Timer(silence, () => fail(ParseSilenceException(silence)));
    }

    void markSent() {
      if (sent) return;
      sent = true;
      emit(const ParseSent());
    }

    void onEvent(SseEvent event) {
      arm();
      final data = _eventData(event.data);
      switch (event.event) {
        case 'accepted':
          // The server read the whole body, so it was sent, whether or not
          // the transport reported the upload.
          markSent();
          emit(const ParseAccepted());
        case 'model_started':
          emit(ParseModelStarted(data['model'] as String? ?? ''));
        case 'model_done':
          emit(ParseModelDone((data['durationMs'] as num?)?.toInt()));
        case 'validated':
          emit(const ParseValidated());
        case 'heartbeat':
          emit(const ParseAlive());
        case 'candidate':
          final model = data['model'] as String? ?? '';
          final label = data['modelLabel'] as String? ?? model;
          final result = data['result'];
          try {
            emit(
              ParseCandidate(
                TidyCandidate(
                  model: model,
                  label: label,
                  result: TidyResult.fromJson(
                    kind,
                    (result as Map).cast<String, dynamic>(),
                  ),
                ),
              ),
            );
          } catch (_) {
            // An answer of a shape this app cannot read is no answer, and
            // the other model may still have one.
            emit(
              ParseCandidate(
                TidyCandidate(model: model, label: label, cause: 'bad_reply'),
              ),
            );
          }
        case 'candidate_failed':
          final model = data['model'] as String? ?? '';
          emit(
            ParseCandidate(
              TidyCandidate(
                model: model,
                label: data['modelLabel'] as String? ?? model,
                cause: data['cause'] as String? ?? 'bad_reply',
              ),
            ),
          );
        case 'result':
          final TidyResult parsed;
          try {
            parsed = TidyResult.fromJson(kind, data);
          } catch (_) {
            fail(ApiException(null, 'Unexpected result shape', data));
            return;
          }
          emit(
            ParseDone(
              parsed,
              modelLabel:
                  data['modelLabel'] as String? ?? data['model'] as String?,
            ),
          );
          finish();
          unawaited(out.close());
        case 'error':
          fail(
            ApiException(
              data['code'] == 'model_failed' ? 502 : 500,
              data['message'] as String? ?? 'Dictation parse failed',
              data,
            ),
          );
        // Anything else is a stage a newer server added: alive, and ignored.
        default:
          emit(const ParseAlive());
      }
    }

    Future<void> start() async {
      arm();
      try {
        final bytes = await _client.openStream(
          '/dictation/parse',
          body: <String, dynamic>{
            'text': text,
            'timeZone': timeZone,
            'kind': kind.wire,
            if (kind == ParseKind.note && noteTitle != null)
              'noteTitle': noteTitle,
            // How freely to reword (`domain/ai_level.dart`); the server's
            // default when absent.
            'level': ?level,
            // "Отправить в несколько": the first models of the roster at
            // once, each answer a [ParseCandidate].
            if (multi) 'multi': true,
          },
          headers: const <String, String>{
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
          // Dio's own idea of silence, a little longer than ours so ours is
          // the one that speaks. The web adapter counts it into the XHR's
          // *total* timeout, so there it has to outlast the whole parse.
          receiveTimeout: kIsWeb
              ? const Duration(seconds: 150)
              : silence + const Duration(seconds: 5),
          cancelToken: cancel,
          onSendProgress: (count, total) {
            if (total > 0 && count >= total) markSent();
          },
          // On the web this is the only sign of life before the end: the
          // body is handed over whole, but its bytes are counted as they come.
          onReceiveProgress: (_, _) {
            if (finished) return;
            arm();
            if (kIsWeb) emit(const ParseAlive());
          },
        );
        if (finished) return;
        arm();
        events = parseSse(bytes).listen(
          onEvent,
          onError: fail,
          onDone: () =>
              fail(NetworkException('The connection closed before the answer')),
        );
      } catch (error) {
        fail(error);
      }
    }

    out = StreamController<ParseProgress>(
      onListen: () => unawaited(start()),
      onCancel: finish,
    );
    return out.stream;
  }

  static Map<String, dynamic> _eventData(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // A malformed event is still a sign of life; its fields are just empty.
    }
    return const <String, dynamic>{};
  }

  /// `GET /dictation/models`: the roster. A 503 means no model is configured
  /// on the server at all.
  Future<AiModels> fetchModels() async {
    final json = await _client.get<Map<String, dynamic>>('/dictation/models');
    return AiModels.fromJson(json);
  }

  /// `PUT /dictation/models`: the whole list, in this order. Owner only (403
  /// otherwise). Keys stay on the server: an entry names the `LLM_*`
  /// variable that holds its key, never the key.
  Future<AiModels> saveModels(List<AiModelEntry> models) async {
    final json = await _client.request<Map<String, dynamic>>(
      'PUT',
      '/dictation/models',
      body: <String, dynamic>{
        'models': <Map<String, dynamic>>[
          for (final model in models) model.toInput(),
        ],
      },
    );
    return AiModels.fromJson(json);
  }

  /// `POST /dictation/models/:id/reenable`: a model its failures switched off,
  /// back on with a clean slate.
  Future<AiModels> reenableModel(String id) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/dictation/models/$id/reenable',
    );
    return AiModels.fromJson(json);
  }
}
