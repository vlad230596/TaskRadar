import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';

import 'support/fixtures.dart';

/// Tests for the read cache, run against a **real directory on disk**.
///
/// Not against a fake filesystem, and not against a fake store: the whole risk
/// this class carries is in the file -- its JSON envelope, its schema version,
/// and what happens when the bytes on disk are not what this version of the app
/// expects. A fake would test none of that. Only `path_provider` (a platform
/// channel that does not exist in the test VM) is replaced, via the store's
/// injected directory resolver.
void main() {
  late Directory directory;
  late BoardSnapshotStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('taskradar_snapshot_test');
    store = BoardSnapshotStore(directory: () async => directory);
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  File snapshotFile() =>
      File('${directory.path}${Platform.pathSeparator}${BoardSnapshotStore.fileName}');

  /// Writes raw bytes as the snapshot, bypassing [BoardSnapshotStore.write] --
  /// which is the only way to reproduce a file this version of the app would
  /// never have produced.
  void putRaw(String contents) => snapshotFile().writeAsStringSync(contents);

  group('a snapshot that cannot be trusted reads as "there is none"', () {
    // Each of these must come back null rather than throwing and rather than
    // producing an empty board: `BoardView` turns null into "loading", which is
    // the honest answer, while an empty list would be the lie "you have no
    // projects".

    test('no file at all (first launch, cleared app data)', () async {
      expect(await store.read(), isNull);
    });

    test('a directory that cannot even be resolved', () async {
      final broken = BoardSnapshotStore(
        directory: () async => throw const FileSystemException('no such volume'),
      );

      expect(await broken.read(), isNull);
    });

    test('bytes that are not JSON (a kill mid-write, a corrupted block)', () async {
      putRaw('{"version":1,"board":[{"id":');

      expect(await store.read(), isNull);
      expect(
        snapshotFile().existsSync(),
        isFalse,
        reason: 'a file that cannot be parsed is deleted, not re-parsed every '
            'launch for the rest of the install\'s life',
      );
    });

    test('valid JSON of the wrong shape', () async {
      putRaw(jsonEncode(boardJson()));

      expect(await store.read(), isNull);
    });

    test('a snapshot from an older schema version', () async {
      putRaw(
        jsonEncode(<String, dynamic>{
          'version': BoardSnapshotStore.schemaVersion - 1,
          'savedAt': '2026-09-15T08:00:00.000Z',
          'board': boardJson(),
        }),
      );

      expect(await store.read(), isNull);
      expect(snapshotFile().existsSync(), isFalse);
    });

    test('a newer schema version, written by a build we downgraded from', () async {
      putRaw(
        jsonEncode(<String, dynamic>{
          'version': BoardSnapshotStore.schemaVersion + 1,
          'savedAt': '2026-09-15T08:00:00.000Z',
          'board': boardJson(),
        }),
      );

      expect(await store.read(), isNull);
    });

    test('the right version, but rows an older app wrote without isCurrent', () {
      // The case a version field cannot catch, because the field that changed
      // was added without anyone remembering to bump it. The parse has to fail
      // *and be caught*, which is why the read path uses the same model codec
      // as the HTTP path rather than a lenient one of its own.
      final legacyTask = taskJson(id: 'tsk_1')..remove('isCurrent');
      putRaw(
        jsonEncode(<String, dynamic>{
          'version': BoardSnapshotStore.schemaVersion,
          'savedAt': '2026-09-15T08:00:00.000Z',
          'board': <dynamic>[
            boardProjectJson(
              id: 'prj_1',
              name: 'Старая схема',
              tasks: <Map<String, dynamic>>[legacyTask],
            ),
          ],
        }),
      );

      expect(store.read(), completion(isNull));
    });

    test('a savedAt that is not a timestamp', () async {
      putRaw(
        jsonEncode(<String, dynamic>{
          'version': BoardSnapshotStore.schemaVersion,
          'savedAt': 'недавно',
          'board': boardJson(),
        }),
      );

      expect(await store.read(), isNull);
    });
  });

  group('a good snapshot round-trips', () {
    test('every field the board screen and the scheduler read', () async {
      final written = BoardProject.listFromJson(boardJson());
      final savedAt = DateTime.utc(2026, 9, 15, 8, 30);

      await store.write(written, savedAt: savedAt);
      final read = await store.read();

      expect(read, isNotNull);
      expect(read!.savedAt.toUtc(), savedAt);

      // Order is part of the contract: projects by createdAt, tasks by
      // position. A snapshot that reshuffles them would put a different task
      // under "current" than the server meant.
      expect(
        read.projects.map((entry) => entry.project.name),
        <String>['TaskRadar', 'Пустой'],
      );

      final first = read.projects.first;
      expect(first.tasks.map((task) => task.id), <String>['tsk_1', 'tsk_2', 'tsk_3']);
      expect(first.currentTask?.id, 'tsk_2', reason: 'isCurrent survived');

      final blocked = first.tasks.last;
      expect(blocked.status, TaskStatus.blocked);
      expect(
        blocked.remindAt,
        '2026-09-18T00:00:00.000Z',
        reason: 'the reminder date must survive byte-for-byte: it is the whole '
            'reason a phone with no network can still arm an alarm',
      );

      // An empty project stays a project with zero tasks, not a missing one.
      expect(read.projects.last.tasks, isEmpty);
    });

    test('an empty board is a real snapshot, distinguishable from no snapshot', () async {
      await store.write(const <BoardProject>[]);

      final read = await store.read();
      expect(read, isNotNull);
      expect(read!.projects, isEmpty);
    });

    test('a write replaces the previous snapshot', () async {
      await store.write(BoardProject.listFromJson(boardJson()));
      await store.write(
        BoardProject.listFromJson(<dynamic>[
          boardProjectJson(id: 'prj_9', name: 'Новее'),
        ]),
      );

      final read = await store.read();
      expect(read!.projects.single.project.name, 'Новее');
    });

    test('write leaves no temporary file behind', () async {
      await store.write(BoardProject.listFromJson(boardJson()));

      // The write goes to `<name>.tmp` and is renamed over the target, so that
      // a kill halfway through cannot leave a half-written file where the
      // reader looks. The rename must actually happen.
      expect(
        directory.listSync().map((entry) => entry.path.split(Platform.pathSeparator).last),
        <String>[BoardSnapshotStore.fileName],
      );
    });

    test('the file is plain, readable JSON with no credentials in it', () async {
      await store.write(BoardProject.listFromJson(boardJson()));

      final contents = snapshotFile().readAsStringSync();
      final decoded = jsonDecode(contents) as Map<String, dynamic>;

      expect(decoded['version'], BoardSnapshotStore.schemaVersion);
      expect(decoded['board'], isA<List<dynamic>>());

      // The token lives in flutter_secure_storage and nowhere else. This
      // assertion is what keeps it that way if somebody later decides it would
      // be convenient to cache "the session" rather than "the board".
      expect(contents, isNot(contains('token')));
      expect(decoded.keys, unorderedEquals(<String>['version', 'savedAt', 'board']));
    });

    test('the persisted rows are the same shape the server sends', () async {
      // Symmetry check: what `write` produces must be parseable by the *HTTP*
      // parser, not just by `read`. An asymmetry between BoardProject's
      // fromJson and toJson would only show up on a device, offline.
      await store.write(BoardProject.listFromJson(boardJson()));

      final decoded =
          jsonDecode(snapshotFile().readAsStringSync()) as Map<String, dynamic>;
      final reparsed = BoardProject.listFromJson(decoded['board'] as List<dynamic>);

      expect(reparsed.first.tasks.first.id, 'tsk_1');
      expect(
        (decoded['board'] as List<dynamic>).first,
        isA<Map<String, dynamic>>().having(
          (json) => json.containsKey('tasks'),
          'tasks alongside id, not nested',
          isTrue,
        ),
      );
    });
  });

  group('clear', () {
    test('removes the file', () async {
      await store.write(BoardProject.listFromJson(boardJson()));
      expect(snapshotFile().existsSync(), isTrue);

      await store.clear();

      expect(snapshotFile().existsSync(), isFalse);
      expect(await store.read(), isNull);
    });

    test('is safe when there is nothing to remove', () async {
      await expectLater(store.clear(), completes);
    });
  });

  test('a write into an unwritable location does not throw', () async {
    // A failed cache write must not turn a good `GET /board` into an error on
    // screen; the user loses the fast launch, not the data. The returned
    // snapshot is still valid so the caller can use its `savedAt`.
    final broken = BoardSnapshotStore(
      directory: () async => throw const FileSystemException('read-only volume'),
    );

    final snapshot = await broken.write(BoardProject.listFromJson(boardJson()));

    expect(snapshot.projects, hasLength(2));
    expect(await broken.read(), isNull);
  });
}
