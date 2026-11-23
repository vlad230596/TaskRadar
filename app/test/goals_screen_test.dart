import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/goal_providers.dart';
import 'package:taskradar/screens/goal_screen.dart';
import 'package:taskradar/screens/goals_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/goals/goal_link_sheet.dart';

import 'support/fake_board_snapshot_store.dart';
import 'support/fake_goals_backend.dart';

/// The goals screen, the goal screen and «Задачи в цель»
/// (design/goals-ideas-spec.md, п. 5).
void main() {
  late FakeGoalsBackend fake;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(420, 1500);
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
        child: MaterialApp(theme: buildAppTheme(), home: home),
      ),
    );
    await settle(tester);
  }

  group('goals screen', () {
    testWidgets('one contour: no tabs; slots counted', (tester) async {
      fake = FakeGoalsBackend(twoContours: false)
        ..addGoal('g1', 'Новое поколение TaskRadar', taskIds: <String>['t1'])
        ..addGoal('g2', 'Бэкапы', state: 'bench');
      await pump(tester, const GoalsScreen());

      expect(find.text('Личное'), findsNothing);
      expect(find.text('В СЛОТАХ · 1 из 2'), findsOneWidget);
      expect(find.text('СКАМЕЙКА · 1'), findsOneWidget);
      expect(find.text('Новое поколение TaskRadar'), findsOneWidget);
      expect(find.text('Свободный слот'), findsOneWidget);
    });

    testWidgets('two contours: tabs with used/total', (tester) async {
      fake = FakeGoalsBackend()
        ..addGoal('g1', 'Работа-цель')
        ..addGoal('g3', 'Личная цель', contourId: 'c_home');
      await pump(tester, const GoalsScreen());

      expect(find.text('Работа'), findsOneWidget);
      expect(find.text('Личное'), findsOneWidget);
      expect(find.text('Работа-цель'), findsOneWidget);
      expect(find.text('Личная цель'), findsNothing);

      await tester.tap(find.text('Личное'));
      await settle(tester);
      expect(find.text('Личная цель'), findsOneWidget);
    });

    testWidgets('«В слот» on the bench slots the goal', (tester) async {
      fake = FakeGoalsBackend()..addGoal('g2', 'Бэкапы', state: 'bench');
      await pump(tester, const GoalsScreen());

      await tester.tap(find.text('В слот'));
      await settle(tester);

      expect(fake.writes, contains('POST /goals/g2/slot'));
      expect(find.text('В СЛОТАХ · 1 из 2'), findsOneWidget);
    });

    testWidgets('a 409 slots_full says the spec sentence', (tester) async {
      fake = FakeGoalsBackend()..addGoal('g2', 'Бэкапы', state: 'bench');
      fake.slotsFullOn.add('slot');
      await pump(tester, const GoalsScreen());

      await tester.tap(find.text('В слот'));
      await settle(tester);

      expect(find.text(slotsFullText), findsOneWidget);
    });

    testWidgets('full slots: the bench says «Слоты заняты» and why', (
      tester,
    ) async {
      fake = FakeGoalsBackend()
        ..addGoal('g1', 'Первая')
        ..addGoal('g2', 'Вторая', position: 2000)
        ..addGoal('g3', 'Ждёт', state: 'bench');
      await pump(tester, const GoalsScreen());

      expect(find.text('В слот'), findsNothing);
      await tester.tap(find.text('Слоты заняты'));
      await settle(tester);
      expect(find.text(slotsFullText), findsOneWidget);
      expect(fake.writes, isEmpty);
    });

    testWidgets('expired window: three buttons; «Оставить» extends', (
      tester,
    ) async {
      fake = FakeGoalsBackend()..addGoal('g1', 'Просрочена', expired: true);
      await pump(tester, const GoalsScreen());

      expect(find.text('Окно вышло вчера'), findsOneWidget);
      expect(find.text('Оставить'), findsOneWidget);
      expect(find.text('На скамейку'), findsOneWidget);
      expect(find.text('Достигнута'), findsOneWidget);

      await tester.tap(find.text('Оставить'));
      await settle(tester);
      expect(fake.writes, contains('POST /goals/g1/extend'));
      expect(find.textContaining('Продлено до'), findsOneWidget);
    });

    testWidgets('«На скамейку» offers «Вернуть»', (tester) async {
      fake = FakeGoalsBackend()..addGoal('g1', 'Просрочена', expired: true);
      await pump(tester, const GoalsScreen());

      await tester.tap(find.text('На скамейку'));
      await settle(tester);
      expect(fake.writes, contains('POST /goals/g1/bench'));
      expect(find.text('Цель на скамейке'), findsOneWidget);

      await tester.tap(find.text('Вернуть'));
      await settle(tester);
      expect(fake.writes.last, 'POST /goals/g1/slot');
    });
  });

  group('goal screen', () {
    testWidgets('a new goal sends POST with the slot flag', (tester) async {
      fake = FakeGoalsBackend();
      await pump(tester, const GoalScreen(newInContourId: 'c_work'));

      expect(find.text('Сразу в слот'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Новая цель');
      await tester.pump();
      await tester.tap(find.text('Создать'));
      await settle(tester);

      expect(fake.writes, contains('POST /goals true'));
      expect(fake.goals.single['title'], 'Новая цель');
    });

    testWidgets('full slots: «Сразу в слот» is off and says so', (
      tester,
    ) async {
      fake = FakeGoalsBackend(workSlots: 1)..addGoal('g1', 'Занимает слот');
      await pump(tester, const GoalScreen(newInContourId: 'c_work'));

      expect(find.text('слоты заняты'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'На скамейку');
      await tester.pump();
      await tester.tap(find.text('Создать'));
      await settle(tester);
      expect(fake.writes, contains('POST /goals false'));
    });

    testWidgets('tasks in order, the step marked; × unlinks', (tester) async {
      fake = FakeGoalsBackend()
        ..addGoal(
          'g1',
          'Новое поколение',
          why: 'Чтобы по пользе',
          taskIds: <String>['t3', 't1', 't2'],
        );
      await pump(tester, const GoalScreen(goalId: 'g1'));

      expect(find.text('ЗАДАЧИ · 1/3'), findsOneWidget);
      expect(find.text('ШАГ'), findsOneWidget);
      expect(find.text('Достигнута'), findsOneWidget);

      await tester.tap(find.byTooltip('Отвязать').at(1));
      await settle(tester);
      expect(fake.writes, contains('DELETE /goals/g1/tasks/t1'));
      expect(find.text('Отвязана'), findsOneWidget);
      expect(find.text('ЗАДАЧИ · 1/2'), findsOneWidget);
    });

    testWidgets('an edited title turns the actions into «Сохранить»', (
      tester,
    ) async {
      fake = FakeGoalsBackend()..addGoal('g1', 'Старое название');
      await pump(tester, const GoalScreen(goalId: 'g1'));

      await tester.enterText(find.byType(TextField).first, 'Новое название');
      await tester.pump();
      expect(find.text('Достигнута'), findsNothing);
      await tester.tap(find.text('Сохранить'));
      await settle(tester);
      expect(fake.writes, contains('PATCH /goals/g1'));
      expect(find.text('Достигнута'), findsOneWidget);
    });

    testWidgets('an achieved goal is read by id', (tester) async {
      fake = FakeGoalsBackend()..addGoal('g9', 'Сделано', state: 'achieved');
      await pump(tester, const GoalScreen(goalId: 'g9'));

      expect(find.text('Вернуть на скамейку'), findsOneWidget);
      await tester.tap(find.text('Вернуть на скамейку'));
      await settle(tester);
      expect(fake.writes, contains('POST /goals/g9/reopen'));
      expect(find.text('Поставить в слот'), findsOneWidget);
    });
  });

  group('«Задачи в цель»', () {
    testWidgets('links the ticked tasks in order', (tester) async {
      fake = FakeGoalsBackend()..addGoal('g1', 'Цель', taskIds: <String>['t1']);
      await pump(tester, const _SheetHost());
      await tester.tap(find.text('открыть'));
      await settle(tester);

      expect(find.text('Задачи в цель'), findsOneWidget);
      expect(find.text('уже в цели'), findsOneWidget);
      // Done tasks are hidden by «Открытые».
      expect(find.text('Старая сделанная'), findsNothing);
      expect(find.text('Выберите задачи'), findsOneWidget);

      await tester.tap(find.text('Купить лампочки'));
      await tester.tap(find.text('Шаги целей в виджете'));
      await tester.pump();
      expect(find.text('Связать · 2'), findsOneWidget);

      await tester.tap(find.text('Связать · 2'));
      await settle(tester);
      expect(fake.writes, <String>[
        'PUT /goals/g1/tasks/t4',
        'PUT /goals/g1/tasks/t2',
      ]);
      expect(find.text('Задачи в цель'), findsNothing);
    });

    testWidgets('search is a flat list across projects', (tester) async {
      fake = FakeGoalsBackend()..addGoal('g1', 'Цель');
      await pump(tester, const _SheetHost());
      await tester.tap(find.text('открыть'));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'лампоч');
      await tester.pump();
      expect(find.text('Купить лампочки'), findsOneWidget);
      expect(find.text('Шаги целей в виджете'), findsNothing);
    });
  });
}

/// Opens the sheet for goal `g1` once the goals list is loaded.
class _SheetHost extends ConsumerWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final goals = await ref.read(goalsProvider.future);
            if (!context.mounted) return;
            await showGoalLinkSheet(context, ref, goal: goals.first);
          },
          child: const Text('открыть'),
        ),
      ),
    );
  }
}
