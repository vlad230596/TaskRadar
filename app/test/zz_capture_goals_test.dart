import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/goal_providers.dart';
import 'package:taskradar/screens/goal_screen.dart';
import 'package:taskradar/screens/goals_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/goals/goal_link_sheet.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_goals_backend.dart';

/// Стенд приёмки экрана целей — близнец `zz_capture_work_test.dart`: экраны
/// `Goals.html`, `Goal-Edit.html`, `Goal-Link.html` и `Desk-Goals.html`
/// рисуются в их размерах настоящими шрифтами и кладутся PNG в
/// `build/acceptance/`. Заодно — проверка, что ничего не переполняется.
void main() {
  final Directory out = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance',
  );

  late FakeGoalsBackend fake;

  setUpAll(() async {
    out.createSync(recursive: true);
    await loadAcceptanceFonts();
  });

  setUp(() {
    fake = FakeGoalsBackend()
      ..addGoal(
        'g1',
        'Новое поколение TaskRadar',
        why: 'Чтобы задачи выбирались по пользе, а не по свежести',
        taskIds: <String>['t3', 't1', 't2'],
      )
      ..addGoal(
        'g2',
        'Первая публикация',
        why: 'Без публикаций меня как инженера не видно',
        taskIds: <String>['t4'],
        expired: true,
        position: 2000,
      )
      ..addGoal(
        'g3',
        'Бэкапы, которым можно верить',
        why: 'Проверить восстановление с нуля',
        state: 'bench',
        position: 3000,
      )
      ..addGoal('g4', 'Лендинг TaskRadar', state: 'bench', position: 4000)
      ..addGoal('g5', 'Сад', contourId: 'c_home');
  });

  Future<void> shot(WidgetTester tester, String name) async {
    final boundary =
        tester.renderObject(find.byKey(_root)) as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File(
        '${out.path}${Platform.pathSeparator}$name.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    double w = 390,
    double h = 844,
  }) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _root,
        child: ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(fake.backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: home,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('Goals — слоты и скамейка', (tester) async {
    await pump(tester, const GoalsScreen());
    expect(tester.takeException(), isNull);
    await shot(tester, 'Goals');
  });

  testWidgets('Goal-Edit — цель в слоте', (tester) async {
    await pump(tester, const GoalScreen(goalId: 'g1'));
    expect(tester.takeException(), isNull);
    await shot(tester, 'Goal-Edit');
  });

  testWidgets('Goal-New — новая цель', (tester) async {
    await pump(tester, const GoalScreen(newInContourId: 'c_work'));
    expect(tester.takeException(), isNull);
    await shot(tester, 'Goal-New');
  });

  testWidgets('Goal-Link — задачи в цель', (tester) async {
    await pump(tester, const _SheetHost());
    await tester.tap(find.text('открыть'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await shot(tester, 'Goal-Link');
  });

  testWidgets('Desk-Goals — широкое окно', (tester) async {
    await pump(tester, const GoalsScreen(), w: 1440, h: 900);
    expect(tester.takeException(), isNull);
    await shot(tester, 'Desk-Goals');
  });
}

final GlobalKey _root = GlobalKey();

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
