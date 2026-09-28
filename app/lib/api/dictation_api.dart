import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_client.dart';
import 'api_exception.dart';
import 'sse.dart';

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

/// The answer. Always the last event of a stream that did not fail.
final class ParseDone extends ParseProgress {
  const ParseDone(this.result);

  final ParsedDictation result;
}

/// Nothing came from the server for [silence] in the middle of a parse. A
/// [NetworkException], because what it means for the user is the same -- the
/// server cannot be heard -- but its own type, because the words differ: the
/// request did go out, and trying again is the likely fix.
class ParseSilenceException extends NetworkException {
  ParseSilenceException(this.silence) : super('The server went silent');

  final Duration silence;
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
  Stream<ParseProgress> parseStream({
    required String text,
    required String timeZone,
    String kind = 'task',
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
        case 'result':
          final ParsedDictation parsed;
          try {
            parsed = ParsedDictation.fromJson(data);
          } catch (_) {
            fail(ApiException(null, 'Unexpected result shape', data));
            return;
          }
          emit(ParseDone(parsed));
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
            'kind': kind,
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
