import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/goal.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/history_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';

/// История → «Недели»: «Достигнутые цели» (design/goals-ideas-spec.md, п. 8;
/// today-history-spec §9.4 -- the same section, filtered to the 12 weeks).
void main() {
  late FakeBackend backend;
  late FakeHistoryBackend server;
  late List<Map<String, dynamic>> achieved;

  Map<String, dynamic> goal(
    String id,
    String title, {
    required num achievedDaysAgo,
    num createdDaysAgo = 20,
    int done = 3,
    String contourId = 'c_work',
    String? why,
  }) => <String, dynamic>{
    'id': id,
    'contourId': contourId,
    'title': title,
    'why': why,
    'state': 'achieved',
    'windowDays': 7,
    'achievedAt': server.iso(achievedDaysAgo),
    'position': 1000,
    'createdAt': server.iso(createdDaysAgo),
    'tasks': <dynamic>[],
    'ideas': <dynamic>[],
    'progress': <String, dynamic>{'done': done, 'total': done},
  };

  setUp(() {
    backend = FakeBackend();
    server = FakeHistoryBackend(backend);
    achieved = <Map<String, dynamic>>[];
    backend
      ..on('GET', '/board', (match) => jsonResponse(const <dynamic>[]))
      ..on('GET', '/goals', (match) => jsonResponse(achieved))
      ..on(
        'GET',
        '/contours',
        (match) => jsonResponse(<String, dynamic>{
          'contours': <dynamic>[
            <String, dynamic>{
              'id': 'c_work',
              'name': 'Работа',
              'slots': 2,
              'windowDays': 7,
              'schedule': null,
              'position': 1000,
            },
            <String, dynamic>{
              'id': 'c_home',
              'name': 'Личное',
              'slots': 2,
              'windowDays': 14,
              'schedule': null,
              'position': 2000,
            },
          ],
          'active': <String, dynamic>{'contourId': null, 'until': null},
        }),
      );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> openWeeks(WidgetTester tester) async {
    server.weeks = server.sampleWeeks();
    tester.view.physicalSize = const Size(412, 2400);
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
    await tester.tap(find.text('Недели'));
    await settle(tester);
  }

  testWidgets('the newest goal is large, the rest are rows, above the week '
      'records', (tester) async {
    achieved
      ..add(goal('g1', 'Перевезти фото в облако', achievedDaysAgo: 3))
      ..add(
        goal(
          'g2',
          'Голос без сети',
          achievedDaysAgo: 1,
          createdDaysAgo: 13,
          done: 5,
          why: 'Диктовка не должна зависеть от сервера',
        ),
      );

    await openWeeks(tester);

    expect(find.text('ДОСТИГНУТЫЕ ЦЕЛИ · 2'), findsOneWidget);
    // Newest first, as the large card: its numbers and its «зачем».
    expect(find.text('Голос без сети'), findsOneWidget);
    expect(find.text('Диктовка не должна зависеть от сервера'), findsOneWidget);
    expect(find.text('задач закрыто'), findsOneWidget);
    expect(find.text('дней от начала'), findsOneWidget);
    // The older one is a row with date, tasks and contour.
    expect(find.textContaining('3 задачи · Работа'), findsOneWidget);

    final section = tester.getTopLeft(find.text('ДОСТИГНУТЫЕ ЦЕЛИ · 2'));
    final records = tester.getTopLeft(find.text('ПО НЕДЕЛЯМ'));
    expect(section.dy, lessThan(records.dy));
  });

  testWidgets('no achieved goals: no section', (tester) async {
    await openWeeks(tester);

    expect(find.textContaining('ДОСТИГНУТЫЕ ЦЕЛИ'), findsNothing);
    expect(find.text('ПО НЕДЕЛЯМ'), findsOneWidget);
  });

  testWidgets('a failed goals read leaves the weeks as they were', (
    tester,
  ) async {
    backend.failingPaths.add('/goals');
    await openWeeks(tester);

    expect(find.textContaining('ДОСТИГНУТЫЕ ЦЕЛИ'), findsNothing);
    expect(find.text('ПО НЕДЕЛЯМ'), findsOneWidget);
  });

  testWidgets('goals achieved before the twelve weeks are left out', (
    tester,
  ) async {
    achieved.add(goal('old', 'Давняя цель', achievedDaysAgo: 120));
    await openWeeks(tester);

    expect(find.textContaining('ДОСТИГНУТЫЕ ЦЕЛИ'), findsNothing);
  });

  test('achievedSince filters by achievedAt in local time, newest first', () {
    GoalView at(DateTime when) => GoalView(
      id: when.toIso8601String(),
      contourId: 'c',
      title: 't',
      state: GoalState.achieved,
      achievedAt: when.toUtc().toIso8601String(),
      position: 1,
      createdAt: when.toUtc().toIso8601String(),
    );
    final goals = <GoalView>[
      at(DateTime(2026, 11, 18, 0, 5)),
      at(DateTime(2026, 11, 17, 23, 55)),
      at(DateTime(2026, 10, 1)),
    ];

    expect(achievedSince(goals, DateTime(2026, 11, 18)), hasLength(1));
    final all = achievedSince(goals, null);
    expect(all, hasLength(3));
    expect(all.first.achievedAt, goals.first.achievedAt);
  });
}
