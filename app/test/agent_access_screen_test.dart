import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/agent_access_screen.dart';

import 'support/fake_backend.dart';

/// «Доступ для агентов (MCP)»: the token list, creating one (shown once, with
/// the command to paste), and revoking.
void main() {
  late FakeBackend backend;
  late List<Map<String, dynamic>> rows;
  late List<Map<String, dynamic>> creates;
  late List<String> revoked;
  late List<String> clipboard;

  const plainToken = 'trk_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';

  setUp(() {
    backend = FakeBackend(baseUrl: 'https://tr.example.test/');
    rows = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'tok-1',
        'name': 'ноутбук',
        'prefix': 'trk_Xy12ab',
        'createdAt': '2026-11-01T10:00:00.000Z',
        'lastUsedAt': null,
      },
    ];
    creates = <Map<String, dynamic>>[];
    revoked = <String>[];
    clipboard = <String>[];

    backend.on('GET', '/agent-tokens', (match) => jsonResponse(rows));
    backend.on('POST', '/agent-tokens', (match) {
      creates.add(match.body);
      final row = <String, dynamic>{
        'id': 'tok-2',
        'name': match.body['name'],
        'prefix': plainToken.substring(0, 10),
        'createdAt': '2026-11-11T10:00:00.000Z',
        'lastUsedAt': null,
      };
      rows = <Map<String, dynamic>>[row, ...rows];
      return jsonResponse(<String, dynamic>{
        ...row,
        'token': plainToken,
      }, statusCode: 201);
    });
    backend.on('DELETE', '/agent-tokens/:id', (match) {
      revoked.add(match.params['id']!);
      rows = rows.where((r) => r['id'] != match.params['id']).toList();
      return jsonResponse(null, statusCode: 204);
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(backend.client)],
        child: const MaterialApp(home: AgentAccessScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the command points at /mcp of the API origin', () {
    expect(
      mcpUrlFor('https://tr.example.test/'),
      'https://tr.example.test/mcp',
    );
    expect(
      claudeMcpAddCommand('https://tr.example.test/mcp', 'trk_x'),
      'claude mcp add --transport http taskradar https://tr.example.test/mcp '
      '--header "Authorization: Bearer trk_x"',
    );
  });

  testWidgets('lists tokens by name and prefix, never the token', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text(AgentAccessScreen.title), findsOneWidget);
    expect(find.text('ноутбук'), findsOneWidget);
    expect(find.textContaining('trk_Xy12ab…'), findsOneWidget);
    expect(find.textContaining('ещё не использовался'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    rows = <Map<String, dynamic>>[];
    await pumpScreen(tester);
    expect(find.text('Токенов пока нет.'), findsOneWidget);
  });

  testWidgets(
    'creating shows the token once with a ready command, and copies it',
    (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Создать токен'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Claude Code');
      await tester.tap(find.text('Создать'));
      await tester.pumpAndSettle();

      expect(creates, <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Claude Code'},
      ]);
      expect(find.text('Токен создан'), findsOneWidget);
      expect(find.text(plainToken), findsOneWidget);
      const command =
          'claude mcp add --transport http taskradar '
          'https://tr.example.test/mcp '
          '--header "Authorization: Bearer $plainToken"';
      expect(find.text(command), findsOneWidget);

      await tester.tap(find.text('Скопировать команду'));
      await tester.pumpAndSettle();
      expect(clipboard, <String>[command]);
      await tester.tap(find.text('Скопировать токен'));
      await tester.pumpAndSettle();
      expect(clipboard.last, plainToken);

      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      // Gone for good once the dialog closes: the list shows the prefix only.
      expect(find.text(plainToken), findsNothing);
      expect(find.text('Claude Code'), findsOneWidget);
      expect(
        find.textContaining('${plainToken.substring(0, 10)}…'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a token without a name is sent without one', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Создать токен'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    expect(creates, <Map<String, dynamic>>[<String, dynamic>{}]);
  });

  testWidgets('revoking asks first, then removes the row', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Отозвать'));
    await tester.pumpAndSettle();
    expect(find.text('Отозвать токен?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(revoked, isEmpty);

    await tester.tap(find.byTooltip('Отозвать'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Отозвать'));
    await tester.pumpAndSettle();

    expect(revoked, <String>['tok-1']);
    expect(find.text('ноутбук'), findsNothing);
    expect(find.text('Токенов пока нет.'), findsOneWidget);
  });

  testWidgets('no network is said plainly', (tester) async {
    backend.alwaysFailToConnect();
    await pumpScreen(tester);
    expect(find.text('Нет связи с сервером.'), findsOneWidget);
  });
}
