import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/today_history.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/today_providers.dart';
import 'package:taskradar/screens/history_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';

/// «История» (today-history-spec §9): «Сделано» and «Недели», «Вернуть»,
/// the review card.
void main() {
  late FakeBackend backend;
  late FakeHistoryBackend server;

  setUp(() {
    backend = FakeBackend();
    server = FakeHistoryBackend(backend);
    server.done = server.sampleDone();
    server.weeks = server.sampleWeeks();
    backend
      ..on('GET', '/board', (match) => jsonResponse(const <dynamic>[]))
      ..on('GET', '/goals', (match) => jsonResponse(const <dynamic>[]))
      ..on('GET', '/focus', (match) => jsonResponse(const <dynamic>[]))
      ..on(
        'GET',
        '/projects/:id/tasks',
        (match) => jsonResponse(const <dynamic>[]),
      );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpHistory(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                HistoryHeader(),
                Expanded(child: HistoryScreen()),
              ],
            ),
          ),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  group('«Сделано»', () {
    testWidgets('opens on «Сделано» with day groups, project and time', (
      tester,
    ) async {
      await pumpHistory(tester);

      expect(find.text('Сделано'), findsOneWidget);
      expect(find.text('Недели'), findsOneWidget);
      expect(find.text('СЕГОДНЯ · 2'), findsOneWidget);
      expect(find.text('ВЧЕРА · 2'), findsOneWidget);
      expect(find.text('Зарелизить 0.15'), findsOneWidget);
      expect(find.textContaining('Дом · '), findsOneWidget);
      expect(find.text('Следом'), findsNWidgets(5));
      expect(find.text('Раньше закрытого нет'), findsOneWidget);
      // The old screen's charts are gone.
      expect(find.text('ВИСИТ ДОЛЬШЕ ВСЕГО'), findsNothing);
    });

    testWidgets('empty: said in words', (tester) async {
      server.done = <Map<String, dynamic>>[];
      await pumpHistory(tester);

      expect(find.text('Пока ничего не закрыто'), findsOneWidget);
    });

    testWidgets('pages: the next one is asked for near the end', (
      tester,
    ) async {
      server.done = <Map<String, dynamic>>[
        for (var i = 0; i < 60; i++)
          server.doneJson(id: 't$i', title: 'Задача $i', hoursAgo: i * 3),
      ];
      await pumpHistory(tester, size: const Size(412, 900));
      await tester.dragUntilVisible(
        find.text('Задача 49'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await settle(tester);
      final pages = backend.requests
          .where((r) => r.path == '/history/done')
          .toList();
      expect(pages.length, greaterThanOrEqualTo(2));
      expect(pages.last.queryParameters['before'], isNotNull);
    });

    testWidgets('«Вернуть» reopens at once and offers «Отменить»', (
      tester,
    ) async {
      await pumpHistory(tester);

      await tester.tap(find.bySemanticsLabel('Вернуть').first);
      await settle(tester);

      expect(server.reopened, <String>['d1']);
      expect(find.text('Зарелизить 0.15'), findsNothing);
      expect(find.text('Вернули в «TaskRadar»'), findsOneWidget);
      expect(find.text('Отменить'), findsOneWidget);
    });

    testWidgets('«Вернуть» with no network says so and sends nothing', (
      tester,
    ) async {
      await pumpHistory(tester);
      backend.failingPaths.add('/tasks/');

      await tester.tap(find.bySemanticsLabel('Вернуть').first);
      await settle(tester);

      expect(find.text('Вернуть можно с сетью'), findsOneWidget);
      expect(server.reopened, isEmpty);
      expect(find.text('Зарелизить 0.15'), findsOneWidget);
    });
  });

  group('the review card', () {
    testWidgets('not there while the review is not due', (tester) async {
      await pumpHistory(tester);
      expect(find.text('Пересмотр недели'), findsNothing);
    });

    testWidgets('due: «пора», the period and «Начать»', (tester) async {
      server.status = <String, dynamic>{
        'due': true,
        'nextAt': server.iso(0.1),
        'lastAt': server.iso(7),
      };
      await pumpHistory(tester);

      expect(find.text('Пересмотр недели'), findsOneWidget);
      expect(find.text('пора'), findsOneWidget);
      expect(find.textContaining('закрыто'), findsWidgets);
      expect(find.text('Начать'), findsOneWidget);
      expect(find.text('≈ 5 мин'), findsOneWidget);
    });

    testWidgets('skipped for more than a day: «пропущен с …»', (tester) async {
      server.status = <String, dynamic>{
        'due': true,
        'nextAt': server.iso(3),
        'lastAt': server.iso(10),
      };
      await pumpHistory(tester);

      expect(find.textContaining('пропущен с '), findsOneWidget);
    });
  });

  group('«Недели»', () {
    testWidgets('bars, this week, records with and without a review', (
      tester,
    ) async {
      await pumpHistory(tester, size: const Size(412, 2400));
      await tester.tap(find.text('Недели'));
      await settle(tester);

      expect(find.text('на этой неделе'), findsOneWidget);
      expect(find.text('эта'), findsOneWidget);
      expect(find.textContaining('в среднем'), findsOneWidget);
      expect(find.text('ПО НЕДЕЛЯМ'), findsOneWidget);
      expect(
        find.text('Дожал стенды, дом стоял. Следующая — отзывы по 0.15.'),
        findsOneWidget,
      );
      expect(find.text('Релиз 0.15'), findsOneWidget);
      expect(find.textContaining('без пересмотра'), findsNWidgets(11));
      // Four projects shown of five; a tap shows all.
      expect(find.text('и ещё 1'), findsOneWidget);
      await tester.tap(find.text('и ещё 1'));
      await settle(tester);
      expect(find.text('Работа'), findsOneWidget);
    });
  });

  testWidgets('wide: «Сделано» and «Недели» side by side, no tabs', (
    tester,
  ) async {
    await pumpHistory(tester, size: const Size(1440, 900));

    expect(find.byType(HistoryTabs), findsNothing);
    expect(find.text('Зарелизить 0.15'), findsOneWidget);
    expect(find.text('на этой неделе'), findsOneWidget);
  });

  group('helpers', () {
    test('day labels', () {
      expect(doneDayLabel('2026-11-27', '2026-11-27'), 'Сегодня');
      expect(doneDayLabel('2026-11-26', '2026-11-27'), 'Вчера');
      expect(doneDayLabel('2026-11-24', '2026-11-27'), 'вт 24.11');
      expect(doneDayLabel('2025-11-25', '2026-11-27'), 'вт 25.11.2025');
    });

    test('a review is «пропущен» only a day after it fell due', () {
      final now = DateTime(2026, 11, 27, 12);
      final fresh = ReviewStatus(
        due: true,
        nextAt: now.subtract(const Duration(hours: 3)).toUtc().toIso8601String(),
      );
      expect(reviewDueLabel(fresh, now), ('пора', false));
      final old = ReviewStatus(
        due: true,
        nextAt: DateTime(2026, 11, 23, 9).toUtc().toIso8601String(),
      );
      expect(reviewDueLabel(old, now), ('пропущен с пн 23.11', true));
    });

    test('the first review of a month carries «+ итоги …»', () {
      final now = DateTime(2026, 12, 7, 9);
      expect(
        monthlyCaption(DateTime(2026, 11, 30, 9).toUtc().toIso8601String(), now),
        '+ итоги ноября',
      );
      expect(
        monthlyCaption(DateTime(2026, 12, 1).toUtc().toIso8601String(), now),
        isNull,
      );
      expect(monthlyCaption(null, now), isNull);
    });

    test('week range', () {
      expect(weekRange('2026-11-30'), '30.11 – 6.12');
    });
  });

  test('a failed reopen keeps nothing in the feed changed', () async {
    // The provider level: a reopen that the server refused throws, and the
    // row stays (it is removed only after the answer).
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(backend.client)],
    );
    addTearDown(container.dispose);
    await container.read(doneFeedStateProvider.future);
    backend.responder = (options) => throw DioException.connectionError(
      requestOptions: options,
      reason: 'down',
    );
    final item = container.read(doneFeedStateProvider).value!.items.first;
    await expectLater(
      reopenTask(container, item.task.task),
      throwsA(isA<Object>()),
    );
    expect(container.read(doneFeedStateProvider).value!.items, hasLength(5));
  });
}
