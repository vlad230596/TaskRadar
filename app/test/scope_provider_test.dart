import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/scope.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/scope_providers.dart';

import 'support/fake_backend.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';
import 'support/fixtures.dart';

/// Scopes on the client (F7): the list, the selection, and the filter.
///
/// Run against a real `ApiClient` over the stateful fake, so the wire shapes --
/// the neighbour-based reorder body, the 409 on a scope that still holds
/// projects -- are exercised rather than assumed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeSettingsStore settings;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    settings = FakeSettingsStore();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        settingsStoreProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the list', () {
    test('reads GET /scopes in server order', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      final container = makeContainer();

      final scopes = await container.read(scopesProvider.future);

      expect(scopes.map((s) => s.name), <String>['Основной', 'Дача']);
      expect(backend.requests.single.path, '/scopes');
    });

    test('creating one appends it, and it comes back with a position', () async {
      final container = makeContainer();
      await container.read(scopesProvider.future);

      final created = await container.read(scopesProvider.notifier).create('  Дача  ');

      // Trimmed by the client before the server ever sees it, exactly as a
      // project name is.
      expect(created.name, 'Дача');
      expect(created.position, greaterThan(1000));
      expect(
        container.read(scopesProvider).requireValue.map((s) => s.name),
        <String>['Основной', 'Дача'],
      );
    });

    test('an empty name never reaches the server', () async {
      final container = makeContainer();
      await container.read(scopesProvider.future);
      final before = backend.requests.length;

      expect(
        () => container.read(scopesProvider.notifier).create('   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(backend.requests, hasLength(before));
    });

    test('renaming shows the new name immediately and keeps the server row', () async {
      final container = makeContainer();
      final scopes = await container.read(scopesProvider.future);

      await container.read(scopesProvider.notifier).rename(scopes.first, 'Работа');

      expect(container.read(scopesProvider).requireValue.first.name, 'Работа');
      expect(server.scopes.first['name'], 'Работа');
    });

    test('a failed rename is rolled back', () async {
      final container = makeContainer();
      final scopes = await container.read(scopesProvider.future);
      backend.failingPaths.add('/scopes/');

      await expectLater(
        container.read(scopesProvider.notifier).rename(scopes.first, 'Работа'),
        throwsA(isA<NetworkException>()),
      );

      // Back to what the server still has, not left showing a name that was
      // never saved.
      expect(container.read(scopesProvider).requireValue.first.name, 'Основной');
    });
  });

  group('reordering', () {
    test('moves by naming the neighbours, not an index', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      server.addScope(name: 'Личное', id: 's-home');
      final container = makeContainer();
      await container.read(scopesProvider.future);

      // Личное (index 2) to the very front.
      await container.read(scopesProvider.notifier).move(2, 0);

      expect(
        container.read(scopesProvider).requireValue.map((s) => s.id),
        <String>['s-home', 'scope_main', 's-dacha'],
      );

      final move = backend.requests.firstWhere(
        (request) => request.path.endsWith('/position'),
      );
      final body = move.data as Map<String, dynamic>;
      expect(body['beforeScopeId'], isNull);
      expect(body['afterScopeId'], 'scope_main');
    });

    test('moving down accounts for the row being removed first', () async {
      // `ReorderableListView` reports `newIndex` counted before the removal, so
      // a move downwards is off by one unless it is corrected. This is the case
      // that catches it.
      server.addScope(name: 'Дача', id: 's-dacha');
      server.addScope(name: 'Личное', id: 's-home');
      final container = makeContainer();
      await container.read(scopesProvider.future);

      await container.read(scopesProvider.notifier).move(0, 2);

      expect(
        container.read(scopesProvider).requireValue.map((s) => s.id),
        <String>['s-dacha', 'scope_main', 's-home'],
      );
    });

    test('a failed move puts the order back', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      final container = makeContainer();
      await container.read(scopesProvider.future);
      backend.failingPaths.add('/position');

      await expectLater(
        container.read(scopesProvider.notifier).move(1, 0),
        throwsA(isA<NetworkException>()),
      );

      expect(
        container.read(scopesProvider).requireValue.map((s) => s.id),
        <String>['scope_main', 's-dacha'],
      );
    });
  });

  group('deleting', () {
    test('removes an empty scope', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      final container = makeContainer();
      final scopes = await container.read(scopesProvider.future);

      await container.read(scopesProvider.notifier).delete(scopes.last);

      expect(
        container.read(scopesProvider).requireValue.map((s) => s.id),
        <String>['scope_main'],
      );
    });

    test('a scope holding a project is refused by the server, with its reason', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      server.addProject(name: 'Забор', scopeId: 's-dacha');
      final container = makeContainer();
      final scopes = await container.read(scopesProvider.future);

      await expectLater(
        container.read(scopesProvider.notifier).delete(scopes.last),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('projects')),
        ),
      );

      // And nothing was removed locally on the way to the refusal.
      expect(container.read(scopesProvider).requireValue, hasLength(2));
    });

    test('the last scope is refused too, with a different reason', () async {
      final container = makeContainer();
      final scopes = await container.read(scopesProvider.future);

      await expectLater(
        container.read(scopesProvider.notifier).delete(scopes.single),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('last scope'),
          ),
        ),
      );
    });
  });

  group('which scope the board shows', () {
    test('with nothing stored it is the first one', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      final container = makeContainer();
      await container.read(scopesProvider.future);
      await container.read(selectedScopeIdProvider.future);

      expect(container.read(activeScopeProvider)?.id, 'scope_main');
    });

    test('a stored id wins, and survives as the list reloads', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      settings.selectedScopeId = 's-dacha';
      final container = makeContainer();
      await container.read(scopesProvider.future);
      await container.read(selectedScopeIdProvider.future);

      expect(container.read(activeScopeProvider)?.id, 's-dacha');
    });

    test('a stored id that no longer names a scope falls back to the first', () async {
      // The scope was deleted on another device, or this database came back
      // from a backup. An empty board with no explanation would be the wrong
      // answer; the first scope is the same default the server uses.
      settings.selectedScopeId = 's-gone';
      final container = makeContainer();
      await container.read(scopesProvider.future);
      await container.read(selectedScopeIdProvider.future);

      expect(container.read(activeScopeProvider)?.id, 'scope_main');
    });

    test('selecting one shows it at once and persists it', () async {
      server.addScope(name: 'Дача', id: 's-dacha');
      final container = makeContainer();
      await container.read(scopesProvider.future);
      await container.read(selectedScopeIdProvider.future);

      await container.read(selectedScopeIdProvider.notifier).select('s-dacha');

      expect(container.read(activeScopeProvider)?.id, 's-dacha');
      expect(settings.scopeWrites, <String>['s-dacha']);
    });

    test('a store that cannot be written still switches the board', () async {
      // The choice being forgotten by tomorrow is a smaller lie than the board
      // jumping back to another scope under the user's finger.
      server.addScope(name: 'Дача', id: 's-dacha');
      settings.writeFailure = StateError('disk is full');
      final container = makeContainer();
      await container.read(scopesProvider.future);
      await container.read(selectedScopeIdProvider.future);

      await container.read(selectedScopeIdProvider.notifier).select('s-dacha');

      expect(container.read(activeScopeProvider)?.id, 's-dacha');
    });

    test('the switcher stays hidden while there is only one scope', () async {
      final container = makeContainer();
      await container.read(scopesProvider.future);

      expect(container.read(hasMultipleScopesProvider), isFalse);

      await container.read(scopesProvider.notifier).create('Дача');
      expect(container.read(hasMultipleScopesProvider), isTrue);
    });
  });

  group('projectsInScope', () {
    BoardProject row(String id, String scopeId) => BoardProject.fromJson(
      boardProjectJson(id: id, name: id, scopeId: scopeId),
    );

    const scope = Scope(
      id: 's-dacha',
      name: 'Дача',
      position: 2000,
      createdAt: '2026-08-01T09:00:00.000Z',
      updatedAt: '2026-08-01T09:00:00.000Z',
    );

    test('keeps only the projects of that scope, in order', () {
      final rows = <BoardProject>[
        row('a', 'scope_main'),
        row('b', 's-dacha'),
        row('c', 's-dacha'),
      ];

      expect(
        projectsInScope(rows, scope).map((e) => e.project.id),
        <String>['b', 'c'],
      );
    });

    test('an unresolved scope shows everything rather than nothing', () {
      // The one frame before the scope list lands. "All of them" is the honest
      // answer there; an empty board would read as "you have no projects".
      final rows = <BoardProject>[row('a', 'scope_main'), row('b', 's-dacha')];
      expect(projectsInScope(rows, null), hasLength(2));
    });
  });
}
