import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/review_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_goals_backend.dart';
import 'support/fake_history_backend.dart';

/// Сверка пересмотра с `design/reference/Review.html`: шаги 1 (с месячным
/// разделом), 2, 3 и 6 на телефоне 412 dp, в `build/acceptance/`.
void main() {
  final Directory out = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance',
  );

  late FakeGoalsBackend fake;
  late FakeHistoryBackend history;

  setUpAll(() async {
    out.createSync(recursive: true);
    await loadAcceptanceFonts();
  });

  setUp(() {
    fake = FakeGoalsBackend()
      ..addGoal(
        'g1',
        'Новое поколение TaskRadar',
        why: 'Чтобы задачи выбирались по пользе',
        taskIds: <String>['t3', 't1', 't2'],
      )
      ..addGoal(
        'g2',
        'Первая публикация',
        taskIds: <String>['t4'],
        expired: true,
        position: 2000,
      )
      ..focused['t2'] = 'c_work';
    history = FakeHistoryBackend(fake.backend);
    history.draft = <String, dynamic>{
      ...history.draftJson(monthly: true),
      'goals': fake.goals,
    };
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

  Future<void> openAt(WidgetTester tester, int step) async {
    tester.view.physicalSize = const Size(412, 915);
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
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => openReview(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    for (var i = 0; i < step; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('review-next')));
      await settle(tester);
    }
  }

  testWidgets('Review — шаг 1, сделано и итоги месяца', (tester) async {
    await openAt(tester, 0);
    expect(find.text('ИТОГИ НОЯБРЯ'), findsOneWidget);
    await shot(tester, 'Review-1');
  });

  testWidgets('Review — шаг 2, задумано', (tester) async {
    await openAt(tester, 1);
    expect(find.text('Задумано, но не сделано'), findsOneWidget);
    await shot(tester, 'Review-2');
  });

  testWidgets('Review — шаг 3, цели', (tester) async {
    await openAt(tester, 2);
    expect(find.text('Первая публикация'), findsOneWidget);
    await shot(tester, 'Review-3');
  });

  testWidgets('Review — шаг 6, итог', (tester) async {
    await openAt(tester, 5);
    await tester.enterText(
      find.byKey(const ValueKey<String>('review-summary')),
      'Дожал стенды, дом стоял',
    );
    await settle(tester);
    expect(find.text('Записать пересмотр'), findsOneWidget);
    await shot(tester, 'Review-6');
  });
}

final GlobalKey _root = GlobalKey();
