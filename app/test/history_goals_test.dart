import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/goal.dart';
import 'package:taskradar/models/history_snapshot.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/history_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';
import 'support/fake_history_backend.dart';

/// История: «Достигнутые цели» (design/goals-ideas-spec.md, п. 8).
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

  Future<void> pumpHistory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(backend.client)],
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

  testWidgets('the newest goal is large, the rest are rows, above the stale '
      'list', (tester) async {
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

    await pumpHistory(tester);

    expect(find.text('ДОСТИГНУТЫЕ ЦЕЛИ · 2'), findsOneWidget);
    // Newest first, as the large card: its numbers and its «зачем».
    expect(find.text('Голос без сети'), findsOneWidget);
    expect(find.text('Диктовка не должна зависеть от сервера'), findsOneWidget);
    expect(find.text('задач закрыто'), findsOneWidget);
    expect(find.text('дней от начала'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    // The older one is a row with date, tasks and contour.
    expect(find.textContaining('3 задачи · Работа'), findsOneWidget);
    // The summary counts them beside «сделано».
    expect(find.text('цели достигнуты'), findsOneWidget);

    final section = tester.getTopLeft(find.text('ДОСТИГНУТЫЕ ЦЕЛИ · 2'));
    final stale = tester.getTopLeft(find.text('ВИСИТ ДОЛЬШЕ ВСЕГО'));
    expect(section.dy, lessThan(stale.dy));
  });

  testWidgets('no achieved goals: no section and no count', (tester) async {
    await pumpHistory(tester);

    expect(find.textContaining('ДОСТИГНУТЫЕ ЦЕЛИ'), findsNothing);
    expect(find.textContaining('достигнут'), findsNothing);
  });

  testWidgets('a failed goals read leaves the history as it was', (
    tester,
  ) async {
    backend.failingPaths.add('/goals');
    await pumpHistory(tester);

    expect(find.textContaining('ДОСТИГНУТЫЕ ЦЕЛИ'), findsNothing);
    expect(find.text('ВИСИТ ДОЛЬШЕ ВСЕГО'), findsOneWidget);
  });

  test('the range filters by achievedAt in local days', () {
    final now = DateTime(2026, 11, 24, 12);
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
      at(DateTime(2026, 11, 18, 0, 5)), // the 7th day back: in the week
      at(DateTime(2026, 11, 17, 23, 55)), // the 8th: out
      at(DateTime(2026, 10, 1)),
    ];

    expect(achievedInRange(goals, HistoryRange.week, now: now), hasLength(1));
    expect(achievedInRange(goals, HistoryRange.month, now: now), hasLength(2));
    final all = achievedInRange(goals, HistoryRange.all, now: now);
    expect(all, hasLength(3));
    expect(all.first.achievedAt, goals.first.achievedAt);
  });
}
