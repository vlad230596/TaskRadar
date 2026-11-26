import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/today_history.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/notification_link_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/review_push_providers.dart';
import 'package:taskradar/providers/today_providers.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_today_backend.dart';
import 'support/fixtures.dart';

/// The weekly review's one push (today-history-spec §10.8).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reviewPushFor', () {
    final now = DateTime.utc(2026, 11, 27, 12);

    test('ahead and not due: armed at nextAt with the count', () {
      final push = reviewPushFor(
        const ReviewStatus(due: false, nextAt: '2026-11-30T06:00:00.000Z'),
        now: now,
        closed: 23,
      );
      expect(push?.fireAt, DateTime.utc(2026, 11, 30, 6));
      expect(push?.body, 'Закрыто 23 · 5 минут на неделю вперёд');
    });

    test('a due (missed) review gets no push -- only the History dot', () {
      expect(
        reviewPushFor(
          const ReviewStatus(due: true, nextAt: '2026-11-23T06:00:00.000Z'),
          now: now,
        ),
        isNull,
      );
    });

    test('a moment gone by, or unknown, arms nothing', () {
      expect(
        reviewPushFor(
          const ReviewStatus(due: false, nextAt: '2026-11-27T11:00:00.000Z'),
          now: now,
        ),
        isNull,
      );
      expect(reviewPushFor(const ReviewStatus(due: false), now: now), isNull);
    });

    test('no count: the second half alone', () {
      expect(reviewPushBody(null), '5 минут на неделю вперёд');
    });
  });

  test('closedOnBoardSince counts done tasks closed after the last review', () {
    final json = boardJson();
    final tasks =
        (json.first as Map<String, dynamic>)['tasks'] as List<dynamic>;
    (tasks[0] as Map<String, dynamic>)['doneAt'] = '2026-11-25T10:00:00.000Z';
    final board = BoardProject.listFromJson(json);
    expect(closedOnBoardSince(board, '2026-11-23T06:00:00.000Z'), 1);
    expect(closedOnBoardSince(board, '2026-11-26T06:00:00.000Z'), 0);
    expect(closedOnBoardSince(board, null), 1);
  });

  group('the bridge', () {
    late FakeBackend backend;
    late FakeTodayServer server;
    late FakeNotificationGateway gateway;

    setUp(() {
      backend = FakeBackend();
      backend.on('GET', '/board', (_) => jsonResponse(boardJson()));
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
          .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'),
            null,
          );
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          notificationGatewayProvider.overrideWithValue(gateway),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen<void>(reviewPushBridgeProvider, (_, _) {});
      return container;
    }

    Future<void> settle(ProviderContainer container) async {
      await container.read(reviewStatusStateProvider.future);
      for (var i = 0; i < 20; i++) {
        await pumpEventQueue();
      }
    }

    test('arms one push with its own id and payload; recording cancels '
        'it until the next week', () async {
      server = FakeTodayServer(
        backend,
        initialStatus: const ReviewStatus(
          due: false,
          nextAt: '2030-06-03T06:00:00.000Z',
        ),
      );
      final container = makeContainer();
      await settle(container);

      final push = gateway.queue[reviewNotificationId];
      expect(push, isNotNull);
      expect(push!.payload, reviewPayload);
      expect(push.title, 'Пересмотр недели');
      expect(push.body, contains('5 минут на неделю вперёд'));
      expect(push.fireAt.toUtc(), DateTime.utc(2030, 6, 3, 6));

      // The review becomes due (missed): the push goes, nothing repeats.
      server.status = const ReviewStatus(
        due: true,
        nextAt: '2026-11-23T06:00:00.000Z',
      );
      await container.read(reviewStatusStateProvider.notifier).refresh();
      await settle(container);
      expect(gateway.queue[reviewNotificationId], isNull);
    });

    test('a due review arms nothing at all', () async {
      server = FakeTodayServer(
        backend,
        initialStatus: const ReviewStatus(
          due: true,
          nextAt: '2026-11-23T06:00:00.000Z',
        ),
      );
      final container = makeContainer();
      await settle(container);
      expect(gateway.queue, isEmpty);
    });
  });

  test('a tap on the review push is a review link, not a task', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(notificationLinkProvider.notifier)
        .requestFromPayload(reviewPayload);
    expect(
      container.read(notificationLinkProvider),
      isA<NotificationLinkReview>(),
    );
  });
}
