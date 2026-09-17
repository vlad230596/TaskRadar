import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/models/inbox_item.dart';
import 'package:taskradar/providers/board_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/inbox_providers.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';

/// The sandbox on the client (F8): the pile the server holds, and what can
/// happen to a line in it.
///
/// Capture moved out of this provider at F8.1 -- it goes through the on-device
/// queue now, and its tests live in `capture_queue_provider_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeCaptureQueueStore queue;
  late FakeNotificationGateway gateway;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    snapshots = FakeBoardSnapshotStore();
    queue = FakeCaptureQueueStore();
    gateway = FakeNotificationGateway();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        boardSnapshotStoreProvider.overrideWithValue(snapshots),
        captureQueueStoreProvider.overrideWithValue(queue),
        notificationGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the pile', () {
    test('reads GET /inbox in the server order, oldest first', () async {
      server.addInboxItem(text: 'Спросить про кабель');
      server.addInboxItem(text: 'Посмотреть налоги');
      final container = makeContainer();

      final items = await container.read(inboxProvider.future);

      expect(items.map((i) => i.text), <String>[
        'Спросить про кабель',
        'Посмотреть налоги',
      ]);
      expect(backend.requests.single.path, '/inbox');
    });

    test('the count is null until it has loaded, then the length', () async {
      server.addInboxItem(text: 'Спросить про кабель');
      final container = makeContainer();

      // Nothing has been read yet, so there is no honest number to show -- the
      // board draws a badge from this, and "0" would be a lie on every cold
      // start.
      expect(container.read(inboxCountProvider), isNull);

      await container.read(inboxProvider.future);
      expect(container.read(inboxCountProvider), 1);
    });
  });

  group('taking in what the queue sent', () {
    test('adds the rows without a second request', () async {
      final container = makeContainer();
      await container.read(inboxProvider.future);
      final before = backend.requests.length;

      container.read(inboxProvider.notifier).adoptAll(<InboxItem>[
        const InboxItem(
          id: 'inb-sent',
          text: 'Купить кабель',
          createdAt: '2026-08-01T12:00:00.000Z',
          updatedAt: '2026-08-01T12:00:00.000Z',
        ),
      ]);

      expect(
        container.read(inboxProvider).requireValue.map((i) => i.text),
        <String>['Купить кабель'],
      );
      // The row came from `POST /inbox` in the shape `GET /inbox` sends; asking
      // the server to repeat what this client is holding would be a request
      // spent on nothing.
      expect(backend.requests, hasLength(before));
    });

    test('ignores a row the pile already has', () async {
      // A flush can re-send a line whose first attempt did reach the server --
      // that is what the idempotency key is for -- and get back a row this list
      // is already showing.
      server.addInboxItem(text: 'Купить кабель', id: 'inb-1');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);

      container.read(inboxProvider.notifier).adoptAll(items);

      expect(container.read(inboxProvider).requireValue, hasLength(1));
    });

    test('does nothing while the pile has not loaded', () async {
      // Splicing into an absent list would turn "not loaded yet" into "this one
      // line is everything there is", and the board badge would report it as
      // fact.
      backend.failingPaths.add('/inbox');
      final container = makeContainer();
      await expectLater(container.read(inboxProvider.future), throwsA(anything));

      container.read(inboxProvider.notifier).adoptAll(<InboxItem>[
        const InboxItem(
          id: 'inb-sent',
          text: 'Купить кабель',
          createdAt: '2026-08-01T12:00:00.000Z',
          updatedAt: '2026-08-01T12:00:00.000Z',
        ),
      ]);

      expect(container.read(inboxProvider).hasValue, isFalse);
    });
  });

  group('editing and discarding', () {
    test('editing writes the new text', () async {
      server.addInboxItem(text: 'Спросить про кабель', id: 'inb-1');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);

      await container
          .read(inboxProvider.notifier)
          .edit(items.single, 'Спросить про кабель у Пети');

      expect(
        container.read(inboxProvider).requireValue.single.text,
        'Спросить про кабель у Пети',
      );
      expect(server.inbox.single['text'], 'Спросить про кабель у Пети');
    });

    test('editing to the same text asks nothing', () async {
      server.addInboxItem(text: 'Спросить про кабель');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);
      final before = backend.requests.length;

      await container.read(inboxProvider.notifier).edit(items.single, '  Спросить про кабель  ');

      expect(backend.requests, hasLength(before));
    });

    test('discarding removes the line', () async {
      server.addInboxItem(text: 'Спросить про кабель');
      server.addInboxItem(text: 'Посмотреть налоги');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);

      await container.read(inboxProvider.notifier).discard(items.first);

      expect(
        container.read(inboxProvider).requireValue.map((i) => i.text),
        <String>['Посмотреть налоги'],
      );
      expect(server.inbox.single['text'], 'Посмотреть налоги');
    });
  });

  group('filing', () {
    late String projectId;

    setUp(() {
      projectId = server.addProject(name: 'Дача');
      server.addTask(projectId: projectId, title: 'Уже есть');
    });

    test('creates the task, removes the line, and asks for a fresh board', () async {
      server.addInboxItem(text: 'Спросить про кабель');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);
      // The board has to be alive for the invalidation to be observable.
      await container.read(boardProvider.future);
      final boardReadsBefore = backend.requests
          .where((request) => request.path == '/board')
          .length;

      final task = await container
          .read(inboxProvider.notifier)
          .file(items.single, projectId: projectId);

      expect(task.title, 'Спросить про кабель');
      expect(task.projectId, projectId);
      expect(container.read(inboxProvider).requireValue, isEmpty);
      expect(server.titlesInOrder(projectId), contains('Спросить про кабель'));

      // Invalidated rather than spliced: the response is one raw row with no
      // `isCurrent`, and the board needs the project's settled list.
      await container.read(boardProvider.future);
      expect(
        backend.requests.where((request) => request.path == '/board').length,
        boardReadsBefore + 1,
      );
    });

    test('appends to the end of the project', () async {
      server.addInboxItem(text: 'Спросить про кабель');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);

      await container
          .read(inboxProvider.notifier)
          .file(items.single, projectId: projectId);

      // The line has no order of its own; dropping it into the middle would be
      // inventing one.
      expect(server.titlesInOrder(projectId), <String>[
        'Уже есть',
        'Спросить про кабель',
      ]);
    });

    test('a refused filing leaves the line where it was', () async {
      server.addInboxItem(text: 'Спросить про кабель');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);

      await expectLater(
        container
            .read(inboxProvider.notifier)
            .file(items.single, projectId: 'prj-does-not-exist'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );

      // Losing the line *and* not creating the task is the one outcome the
      // whole feature cannot afford.
      expect(container.read(inboxProvider).requireValue, hasLength(1));
      expect(server.inbox, hasLength(1));
    });

    test('the filed task carries no isCurrent guess into the list', () async {
      // The server answers a raw row; the client fills `isCurrent: false` in to
      // satisfy the model and never splices it anywhere. This pins that the
      // value is not taken for a fact about the project.
      server.addInboxItem(text: 'Спросить про кабель');
      final container = makeContainer();
      final items = await container.read(inboxProvider.future);

      final task = await container
          .read(inboxProvider.notifier)
          .file(items.single, projectId: projectId);

      expect(task.isCurrent, isFalse);
      // ...while the server, asked properly, says it *is* the current one --
      // which is why the board is re-read rather than patched with that row.
      expect(server.currentTaskId(projectId), isNot(task.id));
    });
  });

  group('InboxItem', () {
    test('parses exactly what the server sends', () {
      final item = InboxItem.fromJson(<String, dynamic>{
        'id': 'inb_1',
        'text': 'Спросить про кабель',
        'createdAt': '2026-09-17T08:00:00.000Z',
        'updatedAt': '2026-09-17T08:00:00.000Z',
      });

      expect(item.id, 'inb_1');
      expect(item.text, 'Спросить про кабель');
      // Timestamps stay strings, like every other model here.
      expect(item.createdAt, isA<String>());
    });
  });
}
