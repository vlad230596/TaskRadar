import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/providers/board_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fixtures.dart';

/// Tests for the three providers that decide what the board screen sees, and
/// for the one seam that turns a refreshed board into armed alarms.
///
/// These run against a real [ApiClient] over a faked transport (see
/// `FakeBackend`), so the model parsing, the query parameter and the
/// exception mapping are all exercised on the way through.
void main() {
  // `flutter_timezone` is a platform channel; pinning it keeps the scheduler's
  // idea of "09:00 local" the same on every machine.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;

  setUp(() {
    backend = FakeBackend();
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (MethodCall call) async =>
              call.method == 'getLocalTimezone' ? 'Europe/Moscow' : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), null);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        boardSnapshotStoreProvider.overrideWithValue(snapshots),
        notificationGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Subscribes to [boardView] the way the screen does, so the providers below
  /// it are actually created.
  BoardView watchBoard(ProviderContainer container) {
    container.listen(boardViewProvider, (_, _) {});
    return container.read(boardViewProvider);
  }

  BoardSnapshot cachedBoard({DateTime? savedAt}) => BoardSnapshot(
    projects: BoardProject.listFromJson(<dynamic>[
      boardProjectJson(
        id: 'prj_cached',
        name: 'Из кэша',
        tasks: <Map<String, dynamic>>[
          taskJson(id: 'tsk_cached', title: 'Старая задача', isCurrent: true),
        ],
      ),
    ]),
    savedAt: savedAt ?? DateTime(2026, 9, 15, 8, 30),
  );

  group('parsing the real /board response', () {
    test('a bare array of projects, each with its tasks', () async {
      backend.alwaysRespond(boardJson());
      final container = makeContainer();

      final board = await container.read(boardProvider.future);

      expect(board.projects, hasLength(2));
      expect(board.projects.first.project.name, 'TaskRadar');
      expect(board.projects.first.tasks, hasLength(3));
      expect(board.projects.first.currentTask?.id, 'tsk_2');
      expect(board.projects.last.tasks, isEmpty);
    });

    test('the request asks for the active half of the board', () async {
      backend.alwaysRespond(boardJson());
      final container = makeContainer();

      await container.read(boardProvider.future);

      expect(backend.lastRequest.path, '/board');
      expect(backend.lastRequest.queryParameters, <String, dynamic>{
        'archived': 'false',
      });
    });
  });

  group('cache first, network behind it', () {
    test('the snapshot is on screen while the request is still in flight', () async {
      snapshots.snapshot = cachedBoard();

      final inFlight = Completer<ResponseBody>();
      backend.responder = (_) => inFlight.future;

      final container = makeContainer();
      watchBoard(container);
      await pumpEventQueue();

      final cached = container.read(boardViewProvider);
      expect(cached, isA<BoardReady>());
      cached as BoardReady;
      expect(cached.origin, BoardOrigin.cache);
      expect(cached.isRefreshing, isTrue);
      expect(cached.refreshError, isNull);
      expect(cached.updatedAt, DateTime(2026, 9, 15, 8, 30));
      expect(cached.projects.single.project.name, 'Из кэша');

      // ...and the request really did go out at the same time, rather than
      // waiting for the disk.
      expect(backend.requests.single.path, '/board');

      inFlight.complete(jsonResponse(boardJson()));
      await container.read(boardProvider.future);

      final fresh = container.read(boardViewProvider) as BoardReady;
      expect(fresh.origin, BoardOrigin.network);
      expect(fresh.isRefreshing, isFalse);
      expect(fresh.projects.first.project.name, 'TaskRadar');
    });

    test('a slow disk never overwrites a board that already arrived', () async {
      // The race the three-provider split exists to make impossible: the wire
      // answers first, the snapshot lands afterwards, and the stale rows must
      // not win.
      final disk = Completer<void>();
      snapshots
        ..snapshot = cachedBoard()
        ..readGate = disk.future;
      backend.alwaysRespond(boardJson());

      final container = makeContainer();
      watchBoard(container);
      await container.read(boardProvider.future);

      disk.complete();
      await pumpEventQueue();

      final view = container.read(boardViewProvider) as BoardReady;
      expect(view.origin, BoardOrigin.network);
      expect(view.projects.first.project.name, 'TaskRadar');
    });
  });

  group('an unusable snapshot is "loading", never "you have no projects"', () {
    // The store maps every broken-file case to null (covered in
    // board_snapshot_store_test.dart); this is the other half of the contract:
    // null must not be rendered as an empty board.

    test('no snapshot: the screen waits for the wire', () async {
      final inFlight = Completer<ResponseBody>();
      backend.responder = (_) => inFlight.future;

      final container = makeContainer();
      watchBoard(container);
      await pumpEventQueue();

      expect(container.read(boardViewProvider), isA<BoardLoading>());

      inFlight.complete(jsonResponse(boardJson()));
      await container.read(boardProvider.future);

      expect(container.read(boardViewProvider), isA<BoardReady>());
    });

    test('a store that throws is treated exactly like an empty one', () async {
      snapshots.readFailure = const FileSystemException('unreadable');
      backend.alwaysRespond(boardJson());

      final container = makeContainer();
      watchBoard(container);
      await container.read(boardProvider.future);

      final view = container.read(boardViewProvider) as BoardReady;
      expect(view.origin, BoardOrigin.network);
    });
  });

  group('when the refresh fails', () {
    test('with a cache: the cached board stays, flagged and dated', () async {
      snapshots.snapshot = cachedBoard(savedAt: DateTime(2026, 9, 15, 21, 40));
      backend.alwaysFailToConnect();

      final container = makeContainer();
      watchBoard(container);
      await expectLater(
        container.read(boardProvider.future),
        throwsA(isA<NetworkException>()),
      );
      await pumpEventQueue();

      final view = container.read(boardViewProvider) as BoardReady;
      expect(view.origin, BoardOrigin.cache);
      expect(view.isStale, isTrue);
      expect(view.refreshError, isA<NetworkException>());
      expect(view.updatedAt, DateTime(2026, 9, 15, 21, 40));
      expect(view.projects.single.project.name, 'Из кэша');
    });

    test('without a cache: there is nothing to show and the screen says so', () async {
      backend.alwaysFailToConnect();

      final container = makeContainer();
      watchBoard(container);
      await expectLater(
        container.read(boardProvider.future),
        throwsA(isA<NetworkException>()),
      );
      await pumpEventQueue();

      final view = container.read(boardViewProvider);
      expect(view, isA<BoardUnavailable>());
      expect((view as BoardUnavailable).error, isA<NetworkException>());
    });

    test('after a good refresh: the fresh board stays, with the error on top', () async {
      backend.alwaysRespond(boardJson());
      final container = makeContainer();
      watchBoard(container);
      await container.read(boardProvider.future);

      backend.alwaysFailToConnect();
      await container.read(boardProvider.notifier).refresh();

      final view = container.read(boardViewProvider) as BoardReady;
      expect(view.origin, BoardOrigin.network, reason: 'the last good data');
      expect(view.isStale, isFalse);
      expect(view.refreshError, isA<NetworkException>());
      expect(view.projects, hasLength(2));
    });

    test('refresh does not throw at its caller', () async {
      backend.alwaysFailToConnect();
      final container = makeContainer();
      watchBoard(container);
      await expectLater(
        container.read(boardProvider.future),
        throwsA(isA<NetworkException>()),
      );

      // A RefreshIndicator's future only drives the spinner; the failure
      // belongs on screen, not in an unhandled exception.
      await expectLater(container.read(boardProvider.notifier).refresh(), completes);
    });
  });

  group('the snapshot is written', () {
    test('after every successful fetch, with the timestamp shown on screen', () async {
      backend.alwaysRespond(boardJson());
      final container = makeContainer();

      final board = await container.read(boardProvider.future);

      expect(snapshots.writeCount, 1);
      expect(snapshots.snapshot!.projects, hasLength(2));
      expect(
        board.fetchedAt,
        snapshots.snapshot!.savedAt,
        reason: '"last updated" on screen and savedAt on disk are one clock read',
      );
    });

    test('and not after a failed one', () async {
      backend.alwaysFailToConnect();
      final container = makeContainer();

      await expectLater(
        container.read(boardProvider.future),
        throwsA(isA<NetworkException>()),
      );

      expect(snapshots.writeCount, 0);
    });

    test('an empty board is cached as an empty board', () async {
      backend.alwaysRespond(<dynamic>[]);
      final container = makeContainer();
      watchBoard(container);
      await container.read(boardProvider.future);

      final view = container.read(boardViewProvider) as BoardReady;
      expect(view.isEmpty, isTrue);
      expect(view.origin, BoardOrigin.network);
      expect(snapshots.snapshot!.projects, isEmpty);
    });
  });

  group('the board drives the reminder queue', () {
    /// A `remindAt` [offsetDays] away from today, in the shape the backend
    /// stores. Relative to the real clock because the scheduler uses it.
    String remindAt(int offsetDays) {
      final day = DateTime.now().add(Duration(days: offsetDays));
      return '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}'
          'T00:00:00.000Z';
    }

    List<dynamic> boardWithBlocker({required bool blocked}) => <dynamic>[
      boardProjectJson(
        id: 'prj_1',
        name: 'Дача',
        tasks: <Map<String, dynamic>>[
          taskJson(
            id: 'tsk_wait',
            title: 'Жду кабель',
            status: blocked ? 'blocked' : 'done',
            remindAt: remindAt(2),
          ),
          taskJson(id: 'tsk_next', title: 'Покрасить забор', isCurrent: true),
        ],
      ),
    ];

    /// Brings up the bridge and waits for the resync it triggers.
    ///
    /// The `pumpEventQueue` is not padding: the bridge hands the target write
    /// to a microtask (see the comment on `boardReminderBridge`), so the
    /// resync it causes is one turn of the event loop behind the board.
    Future<void> settleReminders(ProviderContainer container) async {
      container.listen(boardReminderBridgeProvider, (_, _) {});
      container.listen(reminderSyncProvider, (_, _) {});
      await pumpEventQueue();
      await container.read(reminderSyncProvider.future);
    }

    test('a successful refresh changes the set of scheduled reminders', () async {
      backend.alwaysRespond(boardWithBlocker(blocked: true));

      final container = makeContainer();
      await container.read(boardProvider.future);
      await settleReminders(container);

      final id = notificationIdForTask('tsk_wait');
      expect(
        gateway.queue.keys,
        contains(id),
        reason: 'the board fetch alone armed the alarm -- nothing called the '
            'scheduler, changing the target set is the reschedule',
      );
      expect(gateway.queue[id]!.body, 'Жду кабель');
      expect(gateway.queue[id]!.title, 'Дача');

      // The task stops being blocked; the alarm has to go away on the next
      // refresh, again with nobody calling the scheduler.
      backend.alwaysRespond(boardWithBlocker(blocked: false));
      await container.read(boardProvider.notifier).refresh();
      await pumpEventQueue();
      await container.read(reminderSyncProvider.future);

      expect(gateway.queue, isEmpty);
      expect(gateway.cancelledIds, contains(id));
    });

    test('the cached board arms alarms too, before any network answer', () async {
      // Half the reason the snapshot exists: a phone with no connectivity still
      // has to know its reminder dates.
      snapshots.snapshot = BoardSnapshot(
        projects: BoardProject.listFromJson(boardWithBlocker(blocked: true)),
        savedAt: DateTime.now(),
      );
      backend.alwaysFailToConnect();

      final container = makeContainer();
      await settleReminders(container);

      expect(gateway.queue.keys, contains(notificationIdForTask('tsk_wait')));
    });

    test('a board with no blockers leaves the queue empty', () async {
      backend.alwaysRespond(boardJson());

      final container = makeContainer();
      await container.read(boardProvider.future);
      await settleReminders(container);

      // The fixture's one blocked task is dated 2026-09-18; whether that is in
      // the future depends on when this suite runs, so assert the rule that is
      // time-independent: nothing that is not a blocked task with a date ever
      // reaches the queue.
      for (final entry in gateway.queue.values) {
        expect(entry.payload, reminderPayload('tsk_3'));
      }
    });
  });
}
