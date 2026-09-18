import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';
import 'package:taskradar/storage/capture_queue_store.dart';
import 'package:taskradar/storage/web_stores.dart';

import 'support/fixtures.dart';

/// The browser stores, tested against an in-memory [WebKeyValueStore].
///
/// The file stores next door are tested against a real temp directory, because
/// their risk is in the filesystem. These two have no filesystem: everything
/// they own is the JSON envelope and the two contracts inherited from the
/// interfaces they stand in for -- the snapshot never throws, and the queue
/// throws when the bytes did not land. Those are exactly what is asserted here,
/// and an in-memory backend is the only way to make a *failing* write happen on
/// demand.
class _MemoryKeyValueStore implements WebKeyValueStore {
  final Map<String, String> values = <String, String>{};

  /// When set, [write] throws it -- the quota-exceeded case, which is the one
  /// the capture queue must report rather than swallow.
  Object? writeFailure;

  /// When set, [read] throws it.
  Object? readFailure;

  @override
  Future<String?> read(String key) async {
    final failure = readFailure;
    if (failure != null) throw failure;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

void main() {
  late _MemoryKeyValueStore storage;

  setUp(() => storage = _MemoryKeyValueStore());

  group('the board snapshot in a browser', () {
    test('what was written is what is read back', () async {
      final store = WebBoardSnapshotStore(storage: storage);
      final savedAt = DateTime.utc(2026, 9, 18, 7, 15);

      await store.write(
        BoardProject.listFromJson(boardJson()),
        savedAt: savedAt,
      );
      final read = await store.read();

      expect(read, isNotNull);
      expect(read!.savedAt, savedAt);
      expect(read.projects.length, 2);
      expect(read.projects.first.project.name, 'TaskRadar');
      expect(read.projects.first.tasks.length, 3);
      // The one field the board's own reminder logic reads straight off the
      // cache, so it has to survive the round trip through storage verbatim.
      expect(
        read.projects.first.tasks.last.remindAt,
        '2026-09-18T00:00:00.000Z',
      );
    });

    test('the envelope is the file store\'s, field for field', () async {
      final store = WebBoardSnapshotStore(storage: storage);
      await store.write(BoardProject.listFromJson(boardJson()));

      // Not decoration: the two stores never share a device, but they do share
      // a schema version, and a reader that assumed one shape and got the other
      // would report "no cache" forever instead of failing visibly.
      final decoded =
          jsonDecode(storage.values[WebBoardSnapshotStore.key]!)
              as Map<String, dynamic>;
      expect(decoded['version'], BoardSnapshotStore.schemaVersion);
      expect(decoded['savedAt'], isA<String>());
      expect(decoded['board'], isA<List<dynamic>>());
      expect(WebBoardSnapshotStore.key, BoardSnapshotStore.fileName);
    });

    test('an unusable value reads as "no snapshot" and is dropped', () async {
      storage.values[WebBoardSnapshotStore.key] = '{"version":1,"board":';
      final store = WebBoardSnapshotStore(storage: storage);

      expect(await store.read(), isNull);
      // Kept, it would cost the same failed parse on every single launch.
      expect(storage.values, isNot(contains(WebBoardSnapshotStore.key)));
    });

    test('a snapshot from another schema version is discarded', () async {
      storage.values[WebBoardSnapshotStore.key] = jsonEncode(<String, dynamic>{
        'version': BoardSnapshotStore.schemaVersion + 1,
        'savedAt': DateTime.utc(2026).toIso8601String(),
        'board': <dynamic>[],
      });
      final store = WebBoardSnapshotStore(storage: storage);

      expect(await store.read(), isNull);
    });

    test('a failing write is swallowed, and still answers', () async {
      storage.writeFailure = StateError('quota exceeded');
      final store = WebBoardSnapshotStore(storage: storage);

      // The contract the board screen depends on: a cache that cannot be
      // written must not turn a good `GET /board` into an error on screen.
      final written = await store.write(BoardProject.listFromJson(boardJson()));
      expect(written.projects.first.project.name, 'TaskRadar');
    });

    test('a failing read is swallowed', () async {
      storage.readFailure = StateError('storage is blocked');
      final store = WebBoardSnapshotStore(storage: storage);

      expect(await store.read(), isNull);
    });
  });

  group('the capture queue in a browser', () {
    PendingCapture entry(String text, String key) => PendingCapture(
      key: key,
      text: text,
      capturedAt: DateTime.utc(2026, 9, 18, 9, 30),
    );

    test('what was written is what is read back', () async {
      final store = WebCaptureQueueStore(storage: storage);
      await store.write(<PendingCapture>[
        entry('Спросить про кабель', 'aaaa1111bbbb2222'),
        entry('Посмотреть налоги', 'cccc3333dddd4444'),
      ]);

      final read = await store.read();
      expect(read.map((e) => e.text), <String>[
        'Спросить про кабель',
        'Посмотреть налоги',
      ]);
      // The idempotency key has to survive verbatim, here for the same reason
      // as on a phone: it is what stops a replay after a lost answer from
      // creating a twin on the server.
      expect(read.map((e) => e.key), <String>[
        'aaaa1111bbbb2222',
        'cccc3333dddd4444',
      ]);
      expect(read.first.capturedAt, DateTime.utc(2026, 9, 18, 9, 30));
    });

    test('a write that did not land throws', () async {
      storage.writeFailure = StateError('quota exceeded');
      final store = WebCaptureQueueStore(storage: storage);

      // The whole feature hinges on this: for a line captured with no network
      // this is the only copy, so a silent failure is a lost thought. The
      // capture screen turns the exception into an error the user can act on,
      // with the text still in the field.
      expect(
        () => store.write(<PendingCapture>[entry('Не потерять', 'a' * 16)]),
        throwsA(isA<StateError>()),
      );
    });

    test('unreadable bytes are set aside, not deleted', () async {
      storage.values[WebCaptureQueueStore.key] = '{"version":1,"queue":[{"te';
      final store = WebCaptureQueueStore(storage: storage);

      expect(await store.read(), isEmpty);
      expect(storage.values, isNot(contains(WebCaptureQueueStore.key)));
      expect(
        storage.values[WebCaptureQueueStore.corruptKey],
        '{"version":1,"queue":[{"te',
      );
    });

    test('a queue from another schema version is set aside', () async {
      final foreign = jsonEncode(<String, dynamic>{
        'version': CaptureQueueStore.schemaVersion + 1,
        'queue': <dynamic>[],
      });
      storage.values[WebCaptureQueueStore.key] = foreign;
      final store = WebCaptureQueueStore(storage: storage);

      expect(await store.read(), isEmpty);
      expect(storage.values[WebCaptureQueueStore.corruptKey], foreign);
    });

    test('an unreadable store reads as an empty queue', () async {
      storage.readFailure = StateError('storage is blocked');
      final store = WebCaptureQueueStore(storage: storage);

      expect(await store.read(), isEmpty);
    });

    test('clear empties the queue', () async {
      final store = WebCaptureQueueStore(storage: storage);
      await store.write(<PendingCapture>[entry('Пока', 'b' * 16)]);

      await store.clear();

      expect(storage.values, isNot(contains(WebCaptureQueueStore.key)));
      expect(await store.read(), isEmpty);
    });
  });
}
