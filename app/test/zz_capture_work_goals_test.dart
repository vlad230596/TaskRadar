import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/goal.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/shell_providers.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/theme/tokens.dart';
import 'package:taskradar/widgets/goals/duel_sheet.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_goals_backend.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';

/// Стенд приёмки для целей в режимах работы и планирования
/// (`design/goals-ideas-spec.md`, пп. 1–4): `Focus-Goals.html`, `Duel.html`,
/// `Project-Goals.html`, `Desk-Focus-Goals.html` и плашка «Цели» на
/// планировании. Как и соседние `zz_capture_*`, кладёт PNG в
/// `build/acceptance/` и падает на любом исключении рендера (переполнение
/// строки — тоже исключение).
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
        'g5',
        'Положение на рынке труда',
        contourId: 'c_home',
        taskIds: <String>['t4'],
      )
      ..focused['t2'] = 'c_work';
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
            captureQueueStoreProvider.overrideWithValue(
              FakeCaptureQueueStore(),
            ),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: home,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> openWork(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    await container.read(shellModeProvider.notifier).select(AppMode.work);
    await settle(tester);
  }

  testWidgets('Focus-Goals — блок целей над набором', (tester) async {
    await pump(tester, const ShellScreen());
    await openWork(tester);
    expect(find.text('Новое поколение TaskRadar'), findsWidgets);
    expect(find.text('Окно вышло вчера'), findsOneWidget);
    await shot(tester, 'Focus-Goals');
  });

  testWidgets('Plan-Goals — плашка «Цели» и переключатель', (tester) async {
    await pump(tester, const ShellScreen());
    expect(find.text('Цели'), findsOneWidget);
    await shot(tester, 'Plan-Goals');
  });

  testWidgets('Duel — «Что берём?»', (tester) async {
    await pump(
      tester,
      const Scaffold(
        backgroundColor: AppColors.background,
        body: SizedBox.expand(),
      ),
    );
    final step = GoalTask.fromJson(<String, dynamic>{
      'id': 't1',
      'title': 'Спроектировать экран целей',
      'status': 'pending',
      'projectId': 'prj_tr',
      'projectName': 'TaskRadar',
    });
    final goal = GoalView(
      id: 'g1',
      contourId: 'c_work',
      title: 'Новое поколение TaskRadar',
      why: 'Чтобы задачи выбирались по пользе, а не по свежести',
      state: GoalState.slot,
      position: 1000,
      createdAt: '2026-11-01T10:00:00.000Z',
      windowEndsAt: DateTime.now()
          .add(const Duration(days: 3, hours: 2))
          .toUtc()
          .toIso8601String(),
      tasks: <GoalTask>[
        step.copyWith(id: 't0', status: TaskStatus.done),
        step.copyWith(id: 't9', status: TaskStatus.done),
        step,
        step.copyWith(id: 't8'),
        step.copyWith(id: 't7'),
      ],
      nextStep: step,
      progress: const GoalProgress(done: 2, total: 5),
    );
    final context = tester.element(find.byType(SizedBox).last);
    showDuel(
      context,
      goals: <GoalView>[
        goal,
        goal.copyWith(id: 'g2', title: 'Первая публикация'),
      ],
      taskTitle: 'Купить лампочки и заодно посмотреть удлинитель',
      projectName: 'Дом',
    ).ignore();
    await settle(tester);
    expect(find.text('Что берём?'), findsOneWidget);
    await shot(tester, 'Duel');
  });

  testWidgets('Project-Goals — короны на строках', (tester) async {
    await pump(tester, const ProjectScreen(projectId: 'prj_tr'));
    await shot(tester, 'Project-Goals');
  });

  testWidgets('Desk-Focus-Goals — полоса целей на десктопе', (tester) async {
    await pump(tester, const ShellScreen(), w: 1440, h: 900);
    await openWork(tester);
    await shot(tester, 'Desk-Focus-Goals');
  });
}

final GlobalKey _root = GlobalKey();
