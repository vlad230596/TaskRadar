import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/api/dictation_api.dart';
import 'package:taskradar/api/sse.dart';
import 'package:taskradar/widgets/tidy_progress.dart';

import 'support/fake_backend.dart';

/// The streamed "Разобрать" (F14) below the screen: the event-stream parser,
/// `DictationApi.parseStream` against the protocol in
/// `backend/src/routes/dictation.ts`, and what the step card says at each
/// moment of it.
void main() {
  group('parseSse', () {
    Future<List<SseEvent>> parse(List<String> chunks) => parseSse(
      Stream<List<int>>.fromIterable(chunks.map(utf8.encode)),
    ).toList();

    test('reads events as the backend writes them', () async {
      expect(
        await parse(<String>[
          'event: accepted\ndata: {"kind":"task"}\n\n',
          'event: heartbeat\ndata: {}\n\n',
        ]),
        const <SseEvent>[
          SseEvent('accepted', '{"kind":"task"}'),
          SseEvent('heartbeat', '{}'),
        ],
      );
    });

    test('survives a chunk boundary anywhere, even inside a letter', () async {
      final bytes = utf8.encode(
        'event: result\ndata: {"title":"Позвонить"}\n\n',
      );
      // Split in the middle of the two-byte "П".
      final cut = utf8.encode('event: result\ndata: {"title":"').length + 1;
      final events = await parseSse(
        Stream<List<int>>.fromIterable(<List<int>>[
          bytes.sublist(0, cut),
          bytes.sublist(cut),
        ]),
      ).toList();

      expect(events, const <SseEvent>[
        SseEvent('result', '{"title":"Позвонить"}'),
      ]);
    });

    test(
      'takes CRLF, comments, several data lines and no event name',
      () async {
        expect(
          await parse(<String>[
            ': keep-alive\r\n\r\n',
            'data: first\r\ndata: second\r\n\r\n',
          ]),
          const <SseEvent>[SseEvent('message', 'first\nsecond')],
        );
      },
    );

    test('drops an event cut off by the end of the stream', () async {
      expect(
        await parse(<String>['event: result\ndata: {"title":"X"}\n']),
        isEmpty,
      );
    });
  });

  group('DictationApi.parseStream', () {
    late FakeBackend backend;
    late DictationApi api;

    setUp(() {
      backend = FakeBackend();
      api = DictationApi(backend.client);
    });

    test(
      'asks for a stream and reports every stage, ending in the answer',
      () async {
        backend.on(
          'POST',
          '/dictation/parse',
          (_) => sseResponse(<String>[
            sseEvent('accepted', <String, dynamic>{'kind': 'task'}),
            sseEvent('model_started', <String, dynamic>{
              'model': 'deepseek-chat',
            }),
            sseEvent('heartbeat'),
            sseEvent('model_done', <String, dynamic>{'durationMs': 5400}),
            sseEvent('validated'),
            sseEvent('result', <String, dynamic>{
              'title': 'Позвонить маме',
              'description': null,
              'remindDate': null,
              'remindTime': null,
              'parseId': 'dp-1',
            }),
          ]),
        );

        final events = await api
            .parseStream(text: 'позвонить маме', timeZone: 'Europe/Moscow')
            .toList();

        expect(backend.lastRequest.headers['Accept'], 'text/event-stream');
        expect(backend.lastRequest.data, <String, dynamic>{
          'text': 'позвонить маме',
          'timeZone': 'Europe/Moscow',
          'kind': 'task',
        });
        expect(events.map((e) => e.runtimeType).toList(), <Type>[
          // "Sent" comes from the transport; the fake reports no upload, so it
          // is said on the server's "accepted" instead.
          ParseSent,
          ParseAccepted,
          ParseModelStarted,
          ParseAlive,
          ParseModelDone,
          ParseValidated,
          ParseDone,
        ]);
        expect((events[2] as ParseModelStarted).model, 'deepseek-chat');
        expect((events[4] as ParseModelDone).durationMs, 5400);
        final done = events.last as ParseDone;
        expect(done.result.title, 'Позвонить маме');
        expect(done.result.parseId, 'dp-1');
      },
    );

    test("turns the server's error event into a 502", () async {
      backend.on(
        'POST',
        '/dictation/parse',
        (_) => sseResponse(<String>[
          sseEvent('accepted'),
          sseEvent('error', <String, dynamic>{
            'code': 'model_failed',
            'message': 'Dictation model did not answer',
          }),
        ]),
      );

      await expectLater(
        api.parseStream(text: 'x', timeZone: 'UTC'),
        emitsInOrder(<Object>[
          isA<ParseSent>(),
          isA<ParseAccepted>(),
          emitsError(
            isA<ApiException>().having((e) => e.statusCode, 'status', 502),
          ),
          emitsDone,
        ]),
      );
    });

    test(
      'a status before the stream is the same error as from parse',
      () async {
        backend.on(
          'POST',
          '/dictation/parse',
          (_) => jsonResponse(<String, dynamic>{
            'error': 'DictationUnavailableError',
            'message': 'Dictation parsing is not configured',
          }, statusCode: 503),
        );

        await expectLater(
          api.parseStream(text: 'x', timeZone: 'UTC'),
          emitsError(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 503)
                .having(
                  (e) => e.message,
                  'message',
                  'Dictation parsing is not configured',
                ),
          ),
        );
      },
    );

    test('gives up on silence, not on length', () async {
      final chunks = StreamController<String>();
      addTearDown(chunks.close);
      backend.on(
        'POST',
        '/dictation/parse',
        (_) => sseStreamResponse(chunks.stream),
      );

      final events = <ParseProgress>[];
      Object? failure;
      final done = Completer<void>();
      api
          .parseStream(
            text: 'x',
            timeZone: 'UTC',
            silence: const Duration(milliseconds: 150),
          )
          .listen(
            events.add,
            onError: (Object e) => failure = e,
            onDone: done.complete,
          );

      // Longer than the silence in total, but never silent for that long.
      for (var i = 0; i < 4; i++) {
        chunks.add(sseEvent(i == 0 ? 'accepted' : 'heartbeat'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      expect(failure, isNull);

      await done.future;
      expect(failure, isA<ParseSilenceException>());
      expect(events.whereType<ParseAlive>(), isNotEmpty);
    });

    test('cancelling drops the connection', () async {
      final chunks = StreamController<String>();
      backend.on(
        'POST',
        '/dictation/parse',
        (_) => sseStreamResponse(chunks.stream),
      );

      final run = api.parseStream(text: 'x', timeZone: 'UTC').listen((_) {});
      chunks.add(sseEvent('accepted'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(chunks.hasListener, isTrue);

      await run.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(chunks.hasListener, isFalse);
      await chunks.close();
    });
  });

  group('TidyProgress', () {
    final t0 = DateTime(2026, 9, 28, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    List<(String, TidyStepState, String?)> steps(TidyProgress p, int nowMs) =>
        p.steps(at(nowMs)).map((s) => (s.label, s.state, s.time)).toList();

    test('before anything came back: sending, the rest waiting', () {
      final p = TidyProgress(t0);
      expect(steps(p, 100), <(String, TidyStepState, String?)>[
        ('Запрос отправлен', TidyStepState.active, null),
        ('Сервер принял', TidyStepState.pending, null),
        ('Модель думает', TidyStepState.pending, null),
        ('Проверяю ответ', TidyStepState.pending, null),
      ]);
      expect(p.signal(at(100)), 'жду ответа сервера');
    });

    test(
      'while the model thinks: its seconds live, the rest with their times',
      () {
        final p = TidyProgress(t0)
          ..record(const ParseSent(), at(200))
          ..record(const ParseAccepted(), at(600))
          ..record(const ParseModelStarted('deepseek-chat'), at(650))
          ..record(const ParseAlive(), at(4650));

        expect(steps(p, 6650), <(String, TidyStepState, String?)>[
          ('Запрос отправлен', TidyStepState.done, '0,2 с'),
          ('Сервер принял · deepseek-chat', TidyStepState.done, '0,4 с'),
          ('Модель думает', TidyStepState.active, '6 с'),
          ('Проверяю ответ', TidyStepState.pending, null),
        ]);
        expect(p.signal(at(6650)), 'связь есть · последний сигнал 2 с назад');
        expect(p.signal(at(16650)), 'сигнала нет уже 12 с');
      },
    );

    test('checking the answer, after a long think', () {
      final p = TidyProgress(t0)
        ..record(const ParseAccepted(), at(300))
        ..record(const ParseModelStarted('m'), at(300))
        ..record(const ParseModelDone(41000), at(41300));

      expect(steps(p, 41400), <(String, TidyStepState, String?)>[
        ('Запрос отправлен', TidyStepState.done, '0,3 с'),
        ('Сервер принял · m', TidyStepState.done, '0,0 с'),
        ('Модель думает', TidyStepState.done, '41 с'),
        ('Проверяю ответ', TidyStepState.active, null),
      ]);
    });

    test('a failure marks the step that was running, and stops its clock', () {
      final p = TidyProgress(t0)
        ..record(const ParseAccepted(), at(300))
        ..record(const ParseModelStarted('m'), at(300))
        ..fail('Сервер замолчал', at(25300));

      expect(steps(p, 99000)[2], (
        'Модель думает',
        TidyStepState.failed,
        '25 с',
      ));
      expect(steps(p, 99000)[3].$2, TidyStepState.pending);
      expect(p.failed, isTrue);
    });
  });

  test('formatStepTime', () {
    expect(formatStepTime(const Duration(milliseconds: 180)), '0,2 с');
    expect(formatStepTime(const Duration(milliseconds: 9940)), '9,9 с');
    expect(formatStepTime(const Duration(milliseconds: 12400)), '12 с');
  });
}
