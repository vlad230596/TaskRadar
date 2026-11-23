import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/focus_providers.dart';
import 'package:taskradar/providers/goal_providers.dart';
import 'package:taskradar/screens/work_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/goals/contour_switcher.dart';
import 'package:taskradar/widgets/goals/duel_sheet.dart';

import 'support/fake_board_snapshot_store.dart';
import 'support/fake_goals_backend.dart';

/// The work mode's goal block and the duel
/// (design/goals-ideas-contract.md, «Блок целей», «Дуэль»).
void main() {
  late FakeGoalsBackend fake;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(fake.backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: body),
        ),
      ),
    );
    await settle(tester);
  }

  const work = Column(
    children: <Widget>[
      WorkHeader(),
      Expanded(child: WorkScreen()),
    ],
  );

  group('goal block', () {
    testWidgets('a goal in a slot: title, why, count, step and its button', (
      tester,
    ) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal(
          'g1',
          'Новое поколение TaskRadar',
          why: 'Чтобы задачи выбирались по пользе',
          taskIds: <String>['t3', 't1', 't2'],
        )
        ..focused['t4'] = 'c_work';
      await pump(tester, work);

      expect(find.text('Новое поколение TaskRadar'), findsOneWidget);
      expect(find.text('Чтобы задачи выбирались по пользе'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('ШАГ'), findsOneWidget);
      expect(find.text('Спроектировать экран целей'), findsOneWidget);
      expect(find.text('ещё 3 д'), findsOneWidget);
      // One contour: no switcher.
      expect(find.text('Работа'), findsOneWidget);

      await tester.tap(find.byTooltip('Взять шаг в работу'));
      await settle(tester);

      expect(fake.writes, contains('POST /tasks/t1/focus c_work'));
      expect(find.text('в работе'), findsOneWidget);
    });

    testWidgets('no step: «Обсудить, что дальше», all blocked', (tester) async {
      (fake = FakeGoalsBackend(
        twoContours: false,
      )).board.first['tasks'] = <Map<String, dynamic>>[
        for (final task
            in fake.board.first['tasks'] as List<Map<String, dynamic>>)
          <String, dynamic>{
            ...task,
            if (task['id'] == 't1') 'status': 'blocked',
          },
      ];
      fake.addGoal('g1', 'Цель', taskIds: <String>['t1', 't3']);
      await pump(tester, work);

      expect(find.text('Обсудить, что дальше'), findsOneWidget);
      expect(find.text('всё заблокировано'), findsOneWidget);
      expect(find.byTooltip('Добавить задачу в цель'), findsOneWidget);
    });

    testWidgets('an expired window: the three answers, no step', (
      tester,
    ) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Цель', taskIds: <String>['t1'], expired: true);
      await pump(tester, work);

      expect(find.text('Окно вышло вчера'), findsOneWidget);
      expect(find.text('Оставить'), findsOneWidget);
      expect(find.text('На скамейку'), findsOneWidget);
      expect(find.text('Достигнута'), findsOneWidget);
      expect(find.text('ШАГ'), findsNothing);

      await tester.tap(find.text('Оставить'));
      await settle(tester);
      expect(fake.writes, contains('POST /goals/g1/extend'));
    });

    testWidgets('no goals in the contour: no block, a small entry', (
      tester,
    ) async {
      fake = FakeGoalsBackend(twoContours: false);
      await pump(tester, work);

      expect(find.text('ШАГ'), findsNothing);
      expect(find.text('Слоты свободны'), findsNothing);
      expect(find.text('Цели'), findsOneWidget);
    });

    testWidgets('only the bench: «Слоты свободны · Поставить цель»', (
      tester,
    ) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Цель', state: 'bench');
      await pump(tester, work);

      expect(find.text('Слоты свободны'), findsOneWidget);
      expect(find.text('Поставить цель'), findsOneWidget);
    });

    testWidgets('two contours: switcher, other contours folded, own set', (
      tester,
    ) async {
      fake = FakeGoalsBackend()
        ..addGoal('g1', 'Рабочая цель', taskIds: <String>['t1'])
        ..addGoal(
          'g2',
          'Личная цель',
          contourId: 'c_home',
          taskIds: <String>['t4'],
        )
        ..focused['t2'] = 'c_work'
        ..focused['t4'] = 'c_home';
      await pump(tester, work);

      // The switcher shows the active contour.
      expect(find.text('Работа'), findsNWidgets(2));
      expect(find.text('Рабочая цель'), findsOneWidget);
      // The other contour's goal: one folded line.
      expect(find.text('Личное'), findsOneWidget);
      expect(find.text(' · Личная цель'), findsOneWidget);
      // The set is the active contour's only.
      expect(find.text('Шаги целей в виджете'), findsOneWidget);
      expect(find.text('Купить лампочки'), findsNothing);

      // Switch by hand.
      await tester.tap(find.byType(ContourSwitcher));
      await settle(tester);
      await tester.tap(find.text('Личное').last);
      await settle(tester);

      expect(fake.writes, contains('PUT /contours/active c_home'));
      // In «Личное»'s set, and its goal's step (already «в работе»).
      expect(find.text('Купить лампочки'), findsNWidgets(2));
      expect(find.text('в работе'), findsOneWidget);
      expect(find.text('Шаги целей в виджете'), findsNothing);
    });
  });

  group('duel', () {
    Task task(String id, String title) => Task(
      id: id,
      projectId: 'prj_dom',
      title: title,
      description: null,
      status: TaskStatus.pending,
      position: 1000,
      remindAt: null,
      createdAt: '2026-11-01T10:00:00.000Z',
      updatedAt: '2026-11-01T10:00:00.000Z',
      isCurrent: false,
    );

    final outcomes = <TakeOutcome>[];

    Widget taker(Task target) => Consumer(
      builder: (context, ref, _) {
        // Keep the set and the goals alive, as the shell does.
        ref.watch(activeFocusSetProvider);
        ref.watch(goalListProvider);
        return Center(
          child: FilledButton(
            onPressed: () => unawaited(
              takeIntoWork(
                context,
                ref,
                task: target,
                projectName: 'Дом',
              ).then(outcomes.add),
            ),
            child: const Text('Взять'),
          ),
        );
      },
    );

    setUp(outcomes.clear);

    testWidgets('a task outside the goals meets the step; the step wins', (
      tester,
    ) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal(
          'g1',
          'Новое поколение TaskRadar',
          why: 'Чтобы задачи выбирались по пользе',
          taskIds: <String>['t1'],
        );
      await pump(tester, taker(task('t4', 'Купить лампочки')));
      await tester.tap(find.text('Взять'));
      await settle(tester);

      expect(find.text('Что берём?'), findsOneWidget);
      expect(find.text('Спроектировать экран целей'), findsOneWidget);
      expect(find.text('Купить лампочки'), findsOneWidget);
      expect(find.text('Чтобы задачи выбирались по пользе'), findsOneWidget);

      await tester.tap(find.text('Беру шаг цели'));
      await settle(tester);

      expect(fake.writes, contains('POST /tasks/t1/focus c_work'));
      expect(fake.writes, isNot(contains('POST /tasks/t4/focus c_work')));
      expect(outcomes, <TakeOutcome>[TakeOutcome.step]);
      expect(find.text('В работе: Спроектировать экран целей'), findsOneWidget);
    });

    testWidgets('«Всё равно эту» takes the task', (tester) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Цель', taskIds: <String>['t1']);
      await pump(tester, taker(task('t4', 'Купить лампочки')));
      await tester.tap(find.text('Взять'));
      await settle(tester);
      await tester.tap(find.text('Всё равно эту'));
      await settle(tester);

      expect(fake.writes, contains('POST /tasks/t4/focus c_work'));
      expect(outcomes, <TakeOutcome>[TakeOutcome.task]);
    });

    testWidgets('the cross takes nothing', (tester) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Цель', taskIds: <String>['t1']);
      await pump(tester, taker(task('t4', 'Купить лампочки')));
      await tester.tap(find.text('Взять'));
      await settle(tester);
      await tester.tap(find.byTooltip('Отмена'));
      await settle(tester);

      expect(fake.writes.where((w) => w.contains('/focus')), isEmpty);
      expect(outcomes, <TakeOutcome>[TakeOutcome.none]);
    });

    testWidgets('a crowned task of the active contour: no duel', (
      tester,
    ) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Цель', taskIds: <String>['t1', 't2']);
      await pump(tester, taker(task('t2', 'Шаги целей в виджете')));
      await tester.tap(find.text('Взять'));
      await settle(tester);

      expect(find.text('Что берём?'), findsNothing);
      expect(fake.writes, contains('POST /tasks/t2/focus c_work'));
    });

    testWidgets('the step already in the set: no duel', (tester) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Цель', taskIds: <String>['t1'])
        ..focused['t1'] = 'c_work';
      await pump(tester, taker(task('t4', 'Купить лампочки')));
      await tester.tap(find.text('Взять'));
      await settle(tester);

      expect(find.text('Что берём?'), findsNothing);
      expect(fake.writes, contains('POST /tasks/t4/focus c_work'));
    });

    testWidgets('two goals: «Другая цель» cycles the card', (tester) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Первая', taskIds: <String>['t1'])
        ..addGoal('g2', 'Вторая', taskIds: <String>['t2'], position: 2000);
      await pump(tester, taker(task('t4', 'Купить лампочки')));
      await tester.tap(find.text('Взять'));
      await settle(tester);

      expect(find.text('Спроектировать экран целей'), findsOneWidget);
      await tester.tap(find.text('Другая цель: Вторая →'));
      await settle(tester);
      expect(find.text('Шаги целей в виджете'), findsOneWidget);
      await tester.tap(find.text('Беру шаг цели'));
      await settle(tester);
      expect(fake.writes, contains('POST /tasks/t2/focus c_work'));
    });
  });
}
