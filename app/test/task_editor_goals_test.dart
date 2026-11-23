import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/goal.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/task_editor_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/editor/goals_section.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';
import 'support/fake_outbox_store.dart';
import 'support/fake_project_backend.dart';

/// The task editor's «Цели» (design/goals-ideas-spec.md, п. 6): the chip
/// second in the attribute row, the section of the task's goals, and the
/// unlink that is sent at once.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late String projectId;
  late List<Map<String, dynamic>> goals;
  final List<String> deletes = <String>[];

  Map<String, dynamic> goal(
    String id,
    String contourId,
    String title,
    List<String> taskIds, {
    String? nextStepId,
  }) {
    final tasks = <Map<String, dynamic>>[
      for (final taskId in taskIds)
        <String, dynamic>{
          'id': taskId,
          'title': 'Задача $taskId',
          'status': taskId == nextStepId ? 'pending' : 'done',
          'projectId': projectId,
          'projectName': 'Дом',
          'focusedAt': null,
          'focusContourId': null,
        },
    ];
    return <String, dynamic>{
      'id': id,
      'contourId': contourId,
      'title': title,
      'why': null,
      'state': 'slot',
      'slottedAt': '2026-11-20T10:00:00.000Z',
      'windowDays': 7,
      'ownWindowDays': null,
      'windowEndsAt': '2026-12-20T10:00:00.000Z',
      'windowExpired': false,
      'achievedAt': null,
      'position': 1000,
      'createdAt': '2026-11-01T10:00:00.000Z',
      'tasks': tasks,
      'nextStep': nextStepId == null
          ? null
          : tasks.firstWhere((task) => task['id'] == nextStepId),
      'ideas': <dynamic>[],
      'progress': <String, dynamic>{'done': 0, 'total': tasks.length},
    };
  }

  setUp(() {
    deletes.clear();
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    FakeHistoryBackend(backend);
    projectId = server.addProject(name: 'Дом', id: 'prj_dom');
    server.addTask(projectId: projectId, title: 'Купить лампочки', id: 't1');
    server.addTask(projectId: projectId, title: 'Без целей', id: 't2');
    server.addTask(projectId: projectId, title: 'Одна цель', id: 't3');
    goals = <Map<String, dynamic>>[
      goal('g1', 'c_work', 'Первая публикация', <String>[
        't1',
        'x2',
      ], nextStepId: 't1'),
      goal('g2', 'c_home', 'Положение на рынке труда', <String>[
        'x1',
        't1',
        'x3',
        'x4',
      ], nextStepId: 'x3'),
      goal('g3', 'c_work', 'Порядок дома', <String>['t3'], nextStepId: 't3'),
    ];
    backend
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
              'windowDays': 7,
              'schedule': null,
              'position': 2000,
            },
          ],
          'active': <String, dynamic>{'contourId': null, 'until': null},
        }),
      )
      ..on('GET', '/goals', (match) => jsonResponse(goals))
      ..on('DELETE', '/goals/:id/tasks/:taskId', (match) {
        final id = match.params['id']!;
        final taskId = match.params['taskId']!;
        deletes.add('$id/$taskId');
        final row = goals.firstWhere((g) => g['id'] == id);
        final kept = <Map<String, dynamic>>[
          for (final task in row['tasks'] as List<Map<String, dynamic>>)
            if (task['id'] != taskId) task,
        ];
        final updated = <String, dynamic>{
          ...row,
          'tasks': kept,
          'nextStep': null,
          'progress': <String, dynamic>{'done': 0, 'total': kept.length},
        };
        goals = <Map<String, dynamic>>[
          for (final g in goals)
            if (g['id'] == id) updated else g,
        ];
        return jsonResponse(updated);
      });
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpTask(WidgetTester tester, String taskId) async {
    tester.view.physicalSize = const Size(375, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
          outboxStoreProvider.overrideWithValue(FakeOutboxStore()),
          deviceTimeZoneNameProvider.overrideWith(
            (ref) async => 'Europe/Moscow',
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TaskEditor(projectId: projectId, taskId: taskId),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  test('the chip says «+ Цель», the goal, or how many', () {
    const a = TaskGoalRef(id: 'a', title: 'Первая публикация', contourId: 'c');
    const b = TaskGoalRef(id: 'b', title: 'Другая', contourId: 'c');
    expect(goalChipLabel(const <TaskGoalRef>[]), '+ Цель');
    expect(goalChipLabel(const <TaskGoalRef>[a]), 'Первая публикация');
    expect(goalChipLabel(const <TaskGoalRef>[a, b]), '2 цели');
  });

  testWidgets('a task with no goals: «+ Цель», and no section', (
    tester,
  ) async {
    await pumpTask(tester, 't2');
    expect(find.text('+ Цель'), findsOneWidget);
    expect(find.text('ЦЕЛИ'), findsNothing);
  });

  testWidgets('one goal: the chip carries its title', (tester) async {
    await pumpTask(tester, 't3');
    // The chip and the section row both name it.
    expect(find.text('Порядок дома'), findsNWidgets(2));
    expect(find.text('ЦЕЛИ'), findsOneWidget);
  });

  testWidgets('two goals: «2 цели», a row each, the step marked', (
    tester,
  ) async {
    await pumpTask(tester, 't1');
    expect(find.text('2 цели'), findsOneWidget);
    expect(find.text('ЦЕЛИ'), findsOneWidget);
    expect(find.text('Первая публикация'), findsOneWidget);
    expect(find.text('Положение на рынке труда'), findsOneWidget);
    expect(
      find.text('Работа · следующий шаг', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Личное · шаг 2 из 4', findRichText: true), findsOneWidget);
  });

  testWidgets('× unlinks at once: DELETE /goals/:id/tasks/:taskId', (
    tester,
  ) async {
    await pumpTask(tester, 't1');
    await tester.tap(find.byTooltip('Отвязать').first);
    await settle(tester);
    expect(deletes, <String>['g1/t1']);
    expect(find.text('Первая публикация'), findsNothing);
    // One goal left: the chip names it.
    expect(find.text('Положение на рынке труда'), findsNWidgets(2));
  });
}
