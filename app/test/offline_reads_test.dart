import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/domain/not_loaded.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/focus_providers.dart';
import 'package:taskradar/providers/project_providers.dart';
import 'package:taskradar/providers/read_cache_providers.dart';
import 'package:taskradar/providers/scope_providers.dart';
import 'package:taskradar/storage/read_cache_store.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_project_backend.dart';
import 'support/memory_read_cache_store.dart';

/// The offline read set beyond the board (offline QA pass, 16.10.2026): the
/// "in work" set, a project's notes and the scope list are read through a
/// local copy, and a write against a list that never loaded fails loudly
/// instead of completing as if it had worked.
///
/// The matrix these rows come from is `docs/offline-capabilities.md`.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late MemoryReadCacheStore cache;
  late String projectId;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    cache = MemoryReadCacheStore();
    projectId = server.addProject(name: 'Кухня', id: 'prj_kitchen');
    server.addTask(projectId: projectId, title: 'Плитка', focused: true);
    server.addNote(projectId: projectId, title: 'Размеры', content: '3,2 м');
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        boardSnapshotStoreProvider.overrideWithValue(FakeBoardSnapshotStore()),
        readCacheStoreProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// One online run, so the copy is written exactly as the app writes it.
  Future<void> warmUp() async {
    final online = makeContainer();
    await online.read(focusSetProvider.future);
    await online.read(projectNotesProvider(projectId).future);
    await online.read(scopesProvider.future);
    await pumpEventQueue();
  }

  group('a successful read leaves a copy', () {
    test('of the set, the notes and the scopes', () async {
      await warmUp();

      expect(
        cache.entries.keys,
        containsAll(<String>[
          ReadCacheKeys.focus,
          ReadCacheKeys.notes(projectId),
          ReadCacheKeys.scopes,
        ]),
      );
    });
  });

  group('no network', () {
    test('the set, the notes and the scopes come from the copy', () async {
      await warmUp();
      backend.alwaysFailToConnect();

      final offline = makeContainer();
      final set = await offline.read(focusSetProvider.future);
      final notes = await offline.read(projectNotesProvider(projectId).future);
      final scopes = await offline.read(scopesProvider.future);

      expect(set.single.title, 'Плитка');
      expect(notes.single.content, '3,2 м');
      expect(scopes, isNotEmpty);
      expect(
        offline.read(cachedReadsProvider).keys,
        containsAll(<String>[ReadCacheKeys.focus, ReadCacheKeys.scopes]),
        reason: 'the screen has to be able to say it is showing a copy',
      );
    });

    test('with no copy it is still an honest error, not an empty list', () async {
      backend.alwaysFailToConnect();

      final offline = makeContainer();
      await expectLater(
        offline.read(focusSetProvider.future),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('a server that does not answer', () {
    test('the copy is shown after the grace period, then replaced', () async {
      await warmUp();
      server.addTask(projectId: projectId, title: 'Затирка', focused: true);
      final gate = Completer<void>();
      backend.delay = (options) =>
          options.path == '/focus' ? gate.future : Future<void>.value();

      final slow = makeContainer();
      final shown = await slow
          .read(focusSetProvider.future)
          .timeout(readCacheGrace * 3);
      expect(shown.map((row) => row.title), <String>['Плитка']);
      expect(slow.read(cachedReadsProvider), contains(ReadCacheKeys.focus));

      gate.complete();
      await pumpEventQueue();

      expect(
        slow.read(focusSetProvider).value!.map((row) => row.title),
        <String>['Плитка', 'Затирка'],
      );
      expect(slow.read(cachedReadsProvider), isNot(contains(ReadCacheKeys.focus)));
    });
  });

  group('writes against a list that never loaded fail loudly', () {
    test('a task write rethrows the network error', () async {
      backend.alwaysFailToConnect();
      final offline = makeContainer();
      // Kept alive the way the project screen keeps it: by watching it.
      offline.listen(projectTasksProvider(projectId), (_, _) {});
      await offline
          .read(projectTasksProvider(projectId).future)
          .then<void>((_) {}, onError: (Object _) {});

      Object? failure;
      try {
        await offline
            .read(projectTasksProvider(projectId).notifier)
            .create('Новая');
      } catch (error) {
        failure = error;
      }
      // It used to complete normally, and the draft screen closed over the
      // lost text.
      expect(failure, isA<NetworkException>());
    });

    test('a set write while the read is still in flight', () async {
      final gate = Completer<void>();
      backend.delay = (_) => gate.future;
      final slow = makeContainer();
      slow.read(focusSetProvider);

      final task = Task.fromJson(<String, dynamic>{
        ...server.tasks.single,
        'isCurrent': true,
      });
      await expectLater(
        slow.read(focusSetProvider.notifier).drop(task.id),
        throwsA(isA<NotLoadedException>()),
      );
      gate.complete();
    });
  });
}
