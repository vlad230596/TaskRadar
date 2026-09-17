import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/storage/capture_queue_store.dart';

/// The offline capture queue (F8.1), tested against a **real directory**.
///
/// Not against a fake: the whole risk this class carries is in the file. For a
/// line captured with no network this file is the only copy that exists
/// anywhere, which makes two of its properties load-bearing in a way the board
/// snapshot's are not -- a failed write must be *reported*, and bytes that
/// cannot be parsed must not be deleted. Only `path_provider` (a platform
/// channel absent from the test VM) is replaced, via the injected directory
/// resolver.
void main() {
  late Directory directory;
  late CaptureQueueStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('taskradar_queue_test');
    store = CaptureQueueStore(directory: () async => directory);
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  File queueFile() => File(
    '${directory.path}${Platform.pathSeparator}${CaptureQueueStore.fileName}',
  );

  PendingCapture entry(String text, {String? key, DateTime? at}) =>
      PendingCapture(
        key: key ?? PendingCapture.newKey(),
        text: text,
        capturedAt: at ?? DateTime.utc(2026, 9, 17, 8, 30),
      );

  group('a queue that survives the app being killed', () {
    test('what was written is what is read back', () async {
      final queued = <PendingCapture>[
        entry('Спросить про кабель', key: 'aaaa1111bbbb2222'),
        entry('Посмотреть налоги', key: 'cccc3333dddd4444'),
      ];

      await store.write(queued);

      final read = await store.read();
      expect(read.map((e) => e.text), <String>[
        'Спросить про кабель',
        'Посмотреть налоги',
      ]);
      // The key has to survive verbatim: it is the only thing that stops a
      // replay after a lost answer from creating a twin on the server.
      expect(read.map((e) => e.key), <String>[
        'aaaa1111bbbb2222',
        'cccc3333dddd4444',
      ]);
      expect(read.first.capturedAt, queued.first.capturedAt);
    });

    test('the order is kept, because it is the order things were thought of', () async {
      await store.write(<PendingCapture>[
        entry('Первое'),
        entry('Второе'),
        entry('Третье'),
      ]);

      expect((await store.read()).map((e) => e.text), <String>[
        'Первое',
        'Второе',
        'Третье',
      ]);
    });

    test('the "failed" mark is not persisted', () async {
      // It is this client's read of one attempt, not a fact about the line. A
      // fresh start deserves a fresh attempt, rather than a line painted as
      // broken for a reason nobody can see any more.
      await store.write(<PendingCapture>[
        entry('Спросить про кабель').copyWith(failed: true),
      ]);

      expect((await store.read()).single.failed, isFalse);
    });

    test('no file yet means an empty queue, not an error', () async {
      expect(await store.read(), isEmpty);
    });

    test('a directory that cannot be resolved also means an empty queue', () async {
      final broken = CaptureQueueStore(
        directory: () async => throw const FileSystemException('no such volume'),
      );

      expect(await broken.read(), isEmpty);
    });
  });

  group('a write that fails is reported, not swallowed', () {
    test('an impossible directory throws out of write', () async {
      // The opposite of `BoardSnapshotStore`, which swallows exactly this: that
      // file is a cache of data the server still has, and this one is the only
      // copy of a line captured offline. Capture turns this into a message with
      // the text still in the field.
      final broken = CaptureQueueStore(
        directory: () async => Directory('${directory.path}/file-not-a-dir')
          ..parent.createSync(recursive: true),
      );
      File('${directory.path}/file-not-a-dir').writeAsStringSync('not a dir');

      expect(
        () => broken.write(<PendingCapture>[entry('Спросить про кабель')]),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('bytes that cannot be trusted', () {
    test('unparseable bytes read as an empty queue and are set aside', () async {
      queueFile().writeAsStringSync('{"version":1,"queue":[{"key":');

      expect(await store.read(), isEmpty);
      // Kept, not deleted. The app has no use for these bytes; a person with a
      // file manager might still read a thought out of them, and nobody else
      // has a copy.
      expect(queueFile().existsSync(), isFalse);
      expect(File('${queueFile().path}.corrupt').existsSync(), isTrue);
    });

    test('a queue written by a future schema is set aside too', () async {
      queueFile().writeAsStringSync(
        jsonEncode(<String, dynamic>{'version': 99, 'queue': <dynamic>[]}),
      );

      expect(await store.read(), isEmpty);
      expect(File('${queueFile().path}.corrupt').existsSync(), isTrue);
    });

    test('a row missing a field does not take the whole queue down silently', () async {
      queueFile().writeAsStringSync(
        jsonEncode(<String, dynamic>{
          'version': CaptureQueueStore.schemaVersion,
          'queue': <dynamic>[
            <String, dynamic>{'text': 'нет ключа'},
          ],
        }),
      );

      expect(await store.read(), isEmpty);
      expect(File('${queueFile().path}.corrupt').existsSync(), isTrue);
    });
  });

  group('the key', () {
    test('is long enough for the server to accept and never repeats', () {
      final keys = <String>{for (var i = 0; i < 500; i++) PendingCapture.newKey()};

      expect(keys, hasLength(500));
      // The server's bound is 8..100 characters; 128 bits of hex is 32.
      expect(keys.first.length, 32);
      expect(keys.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  test('clear empties the queue, for a future sign-out', () async {
    await store.write(<PendingCapture>[entry('Спросить про кабель')]);

    await store.clear();

    expect(await store.read(), isEmpty);
    expect(queueFile().existsSync(), isFalse);
  });
}
