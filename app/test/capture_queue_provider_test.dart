import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/capture_queue_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/inbox_providers.dart';
import 'package:taskradar/storage/capture_queue_store.dart';

import 'support/fake_backend.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_project_backend.dart';

/// Offline capture (F8.1): writing a line down with no network, and getting it
/// to the server later without duplicating it.
///
/// The three properties these tests exist to hold:
///
/// 1. **the disk comes first.** Capture returns once the line is persisted, not
///    once the server has it -- that is what makes the promise "записано" true
///    in a lift;
/// 2. **a replay does not duplicate.** Every queued line carries an idempotency
///    key, and the flush can be run again over a line the server already took;
/// 3. **nothing is lost on the way.** A refused line stays in the queue, and a
///    network failure stops the drain rather than dropping what is left.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeCaptureQueueStore store;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    store = FakeCaptureQueueStore();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        captureQueueStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('capture', () {
    test('writes the line to disk before anything else', () async {
      final container = makeContainer();
      await container.read(captureQueueProvider.future);
      backend.failingPaths.add('/inbox');

      await container.read(captureQueueProvider.notifier).capture(
        '  Спросить про кабель  ',
      );
      // The capture kicks off a send of its own; awaiting it keeps this test
      // the owner of every future it started.
      await container.read(captureQueueProvider.notifier).flush();

      // On disk, trimmed, and visible -- with no server involved at all.
      expect(store.queue.single.text, 'Спросить про кабель');
      expect(
        container.read(pendingCapturesProvider).single.text,
        'Спросить про кабель',
      );
    });

    test('reports a failed disk write instead of pretending', () async {
      // The one failure the user has to know about: the line now exists
      // nowhere, and the text has to stay in the field.
      final container = makeContainer();
      await container.read(captureQueueProvider.future);
      store.writeFailure = Exception('disk full');

      await expectLater(
        container.read(captureQueueProvider.notifier).capture('Спросить'),
        throwsA(isA<Exception>()),
      );
      expect(container.read(pendingCapturesProvider), isEmpty);
    });

    test('an empty line is not a capture', () async {
      final container = makeContainer();
      await container.read(captureQueueProvider.future);

      expect(
        () => container.read(captureQueueProvider.notifier).capture('   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(store.writeCount, 0);
    });

    test('keeps what an earlier session left in the queue', () async {
      // A capture can happen before the file has finished loading -- the
      // composer autofocuses on a screen that has just opened -- and dropping
      // the not-yet-loaded queue would lose yesterday's lines.
      store.queue = <PendingCapture>[
        PendingCapture(
          key: 'aaaa1111bbbb2222',
          text: 'Вчерашняя строчка',
          capturedAt: DateTime.utc(2026, 9, 16),
        ),
      ];
      backend.failingPaths.add('/inbox');
      final container = makeContainer();

      await container.read(captureQueueProvider.notifier).capture('Сегодняшняя');
      await container.read(captureQueueProvider.notifier).flush();

      expect(store.queue.map((e) => e.text), <String>[
        'Вчерашняя строчка',
        'Сегодняшняя',
      ]);
    });

    test('sends the line when there is a network, without being asked', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);

      await container.read(captureQueueProvider.notifier).capture('Купить кабель');
      await container.read(captureQueueProvider.notifier).flush();

      expect(server.inbox.single['text'], 'Купить кабель');
      expect(container.read(pendingCapturesProvider), isEmpty);
      expect(store.queue, isEmpty);
    });
  });

  group('flushing', () {
    test('sends the whole queue oldest first and carries the key', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);
      backend.failingPaths.add('/inbox');
      final notifier = container.read(captureQueueProvider.notifier);
      await notifier.capture('Первое');
      await notifier.capture('Второе');
      await notifier.flush();
      backend.failingPaths.clear();

      await notifier.flush();

      expect(server.inbox.map((row) => row['text']), <String>['Первое', 'Второе']);
      // Every line carries the key it was captured with -- without it a retry
      // after a lost answer would create a twin.
      expect(server.inbox.every((row) => (row['captureKey'] as String).isNotEmpty), isTrue);
    });

    test('a replay of a line the server already took creates nothing', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);
      final notifier = container.read(captureQueueProvider.notifier);
      await notifier.capture('Купить кабель');
      await notifier.flush();

      // The exact shape of a lost answer: the line is still in the file, so the
      // next start sends it again.
      store.queue = <PendingCapture>[
        PendingCapture(
          key: server.inbox.single['captureKey'] as String,
          text: 'Купить кабель',
          capturedAt: DateTime.utc(2026, 9, 17),
        ),
      ];
      container.invalidate(captureQueueProvider);
      await container.read(captureQueueProvider.notifier).flush();

      expect(server.inbox, hasLength(1));
      expect(container.read(inboxProvider).requireValue, hasLength(1));
      expect(store.queue, isEmpty);
    });

    test('puts the sent lines into the pile without re-reading it', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);
      final before = backend.requests.length;

      await container.read(captureQueueProvider.notifier).capture('Купить кабель');
      await container.read(captureQueueProvider.notifier).flush();

      expect(
        container.read(inboxProvider).requireValue.map((i) => i.text),
        <String>['Купить кабель'],
      );
      // One request: the POST. The row it answered with is the row `GET /inbox`
      // would have sent.
      expect(backend.requests.length - before, 1);
    });

    test('no network leaves everything queued', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);
      backend.failingPaths.add('/inbox');
      final notifier = container.read(captureQueueProvider.notifier);
      await notifier.capture('Первое');
      await notifier.capture('Второе');

      await notifier.flush();

      expect(store.queue.map((e) => e.text), <String>['Первое', 'Второе']);
      expect(container.read(pendingCapturesProvider).every((e) => !e.failed), isTrue);
    });

    test('a line the server refuses is kept and marked', () async {
      // Not dropped: it is still the only copy of a thought. Not retried in a
      // loop either -- the server answered, so this is not connectivity.
      final container = makeContainer();
      await container.read(inboxProvider.future);
      store.queue = <PendingCapture>[
        PendingCapture(
          key: 'aaaa1111bbbb2222',
          // The fake server refuses an empty line with a 400, which is the
          // shape of "the server answered and said no".
          text: '',
          capturedAt: DateTime.utc(2026, 9, 17),
        ),
      ];
      container.invalidate(captureQueueProvider);

      await container.read(captureQueueProvider.notifier).flush();

      expect(container.read(pendingCapturesProvider).single.failed, isTrue);
      expect(store.queue, hasLength(1));
    });

    test('one refused line does not block the ones behind it', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);
      store.queue = <PendingCapture>[
        PendingCapture(
          key: 'aaaa1111bbbb2222',
          text: '',
          capturedAt: DateTime.utc(2026, 9, 17),
        ),
        PendingCapture(
          key: 'cccc3333dddd4444',
          text: 'Купить кабель',
          capturedAt: DateTime.utc(2026, 9, 17, 1),
        ),
      ];
      container.invalidate(captureQueueProvider);

      await container.read(captureQueueProvider.notifier).flush();

      expect(server.inbox.single['text'], 'Купить кабель');
      expect(store.queue.single.key, 'aaaa1111bbbb2222');
    });

    test('two flushes at once do not send the line twice', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);
      final notifier = container.read(captureQueueProvider.notifier);
      await notifier.capture('Купить кабель');
      final before = backend.requests.length;

      await Future.wait(<Future<void>>[notifier.flush(), notifier.flush()]);

      // They run one after another, so the second finds an empty queue. The key
      // would have forgiven a duplicate; spending the request anyway would
      // still be pointless work on a phone's radio.
      expect(backend.requests.length - before, 1);
      expect(server.inbox, hasLength(1));
    });

    test('a line captured mid-flight is not dropped', () async {
      // The normal case, not a corner one: typing the next line takes less time
      // than a round trip. A pass that wrote back "the queue as I found it,
      // minus what I sent" would quietly lose that line from both the screen
      // and the file -- the exact failure this feature exists to prevent.
      final container = makeContainer();
      await container.read(inboxProvider.future);
      final notifier = container.read(captureQueueProvider.notifier);
      await notifier.capture('Первое');

      final held = Completer<void>();
      backend.delay = (options) => held.future;
      final flushing = notifier.flush();

      backend.delay = null;
      await notifier.capture('Второе');
      held.complete();
      await flushing;
      await notifier.flush();

      expect(server.inbox.map((row) => row['text']), <String>['Первое', 'Второе']);
      expect(store.queue, isEmpty);
      expect(container.read(pendingCapturesProvider), isEmpty);
    });

    test('an empty queue sends nothing at all', () async {
      final container = makeContainer();
      await container.read(captureQueueProvider.future);
      final before = backend.requests.length;

      await container.read(captureQueueProvider.notifier).flush();

      expect(backend.requests, hasLength(before));
    });
  });

  group('discarding an unsent line', () {
    test('takes it out of the queue and off the disk', () async {
      final container = makeContainer();
      backend.failingPaths.add('/inbox');
      final notifier = container.read(captureQueueProvider.notifier);
      final entry = await notifier.capture('Записал по ошибке');
      await notifier.flush();

      await notifier.discard(entry);

      expect(container.read(pendingCapturesProvider), isEmpty);
      expect(store.queue, isEmpty);
    });
  });

  group('the badge on the board', () {
    test('counts the queued lines as part of the sandbox', () async {
      // A line captured in the lift is in the pile from the user's point of
      // view the moment it is typed.
      server.addInboxItem(text: 'Уже на сервере');
      final container = makeContainer();
      await container.read(inboxProvider.future);
      backend.failingPaths.add('/inbox');

      await container.read(captureQueueProvider.notifier).capture('Ещё в кармане');
      await container.read(captureQueueProvider.notifier).flush();

      expect(container.read(inboxCountProvider), 2);
    });

    test('shows the queued count even when the server half is unknown', () async {
      backend.failingPaths.add('/inbox');
      final container = makeContainer();
      await expectLater(container.read(inboxProvider.future), throwsA(anything));

      expect(container.read(inboxCountProvider), isNull);
      await container.read(captureQueueProvider.notifier).capture('В кармане');
      await container.read(captureQueueProvider.notifier).flush();

      expect(container.read(inboxCountProvider), 1);
    });
  });
}
