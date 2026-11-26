import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/navigation/review_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/focus_providers.dart';
import 'package:taskradar/providers/shell_providers.dart';
import 'package:taskradar/screens/review_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/theme/tokens.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';

/// The weekly review (today-history-spec §10): six steps, each skippable,
/// recorded with `POST /reviews`.
void main() {
  late FakeBackend backend;
  late FakeHistoryBackend server;
  late List<String> goalActions;
  late List<String> focusDrops;

  Map<String, dynamic> contour(String id, String name, double position) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'slots': 2,
        'windowDays': 7,
        'schedule': null,
        'position': position,
      };

  setUp(() {
    backend = FakeBackend();
    server = FakeHistoryBackend(backend);
    goalActions = <String>[];
    focusDrops = <String>[];
    final slotGoal = (server.draft['goals'] as List).first as Map;
    backend
      ..on('GET', '/board', (match) => jsonResponse(const <dynamic>[]))
      ..on('GET', '/goals', (match) => jsonResponse(<dynamic>[slotGoal]))
      ..on('POST', '/goals/:id/:action', (match) {
        goalActions.add('${match.params['id']}/${match.params['action']}');
        return jsonResponse(<String, dynamic>{
          ...slotGoal,
          'windowExpired': false,
          'windowEndsAt': server.iso(-7),
        });
      })
      ..on(
        'GET',
        '/contours',
        (match) => jsonResponse(<String, dynamic>{
          'contours': <dynamic>[
            contour('c_work', 'Работа', 1000),
            contour('c_home', 'Личное', 2000),
          ],
          'active': <String, dynamic>{'contourId': 'c_work', 'until': null},
        }),
      )
      ..on(
        'GET',
        '/focus',
        (match) => jsonResponse(<dynamic>[
          <String, dynamic>{
            'id': 'i1',
            'projectId': 'prj_1',
            'title': 'Собрать отзывы',
            'description': null,
            'status': 'pending',
            'position': 1000,
            'remindAt': null,
            'createdAt': server.iso(10),
            'updatedAt': server.iso(1),
            'focusedAt': server.iso(3),
            'project': <String, dynamic>{'id': 'prj_1', 'name': 'TaskRadar'},
            'focusContourId': 'c_work',
          },
        ]),
      )
      ..on('DELETE', '/tasks/:id/focus', (match) {
        focusDrops.add(match.params['id']!);
        return jsonResponse(<String, dynamic>{});
      });
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<ProviderContainer> pumpReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(backend.client),
        boardSnapshotStoreProvider.overrideWithValue(FakeBoardSnapshotStore()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return container;
  }

  Color segment(WidgetTester tester, int i) =>
      ((tester.widget<Container>(
                    find.byKey(ValueKey<String>('review-progress-$i')),
                  ).decoration
                  as BoxDecoration?)
              ?.color) ??
      Colors.transparent;

  testWidgets('step 1: what was done, by project, «Следом» on each', (
    tester,
  ) async {
    await pumpReview(tester);

    expect(find.text('ШАГ 1 ИЗ 6 · СДЕЛАНО'), findsOneWidget);
    expect(find.text('Что сделано'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Зарелизить 0.15'), findsOneWidget);
    expect(find.text('Купить лампочки'), findsOneWidget);
    expect(find.text('Следом'), findsNWidgets(3));
    expect(find.byKey(const ValueKey<String>('review-month')), findsNothing);
  });

  testWidgets('a monthly review has its month section', (tester) async {
    server.draft = server.draftJson(monthly: true);
    await pumpReview(tester);

    expect(find.byKey(const ValueKey<String>('review-month')), findsOneWidget);
    expect(find.text('ИТОГИ НОЯБРЯ'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);
  });

  testWidgets('«Дальше» and «Пропустить» move on and mark the progress', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.byKey(const ValueKey<String>('review-next')));
    await settle(tester);
    expect(find.text('Задумано, но не сделано'), findsOneWidget);
    expect(segment(tester, 0), AppColors.reviewStepDone);

    await tester.tap(find.byKey(const ValueKey<String>('review-skip')));
    await settle(tester);
    expect(find.text('ШАГ 3 ИЗ 6 · ЦЕЛИ'), findsOneWidget);
    expect(segment(tester, 1), AppColors.reviewSkipped);
  });

  testWidgets('step 2: intended by contour, then «С ДАТОЙ»; «В стопку» '
      'drops it from the set', (tester) async {
    final container = await pumpReview(tester);
    // The set is loaded where the review is opened from (the shell).
    container.listen(focusSetProvider, (_, _) {});
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('review-next')));
    await settle(tester);

    expect(find.text('РАБОТА'), findsOneWidget);
    expect(find.text('С ДАТОЙ'), findsOneWidget);
    expect(find.text('в наборе'), findsOneWidget);
    expect(find.textContaining('дата '), findsOneWidget);

    await tester.tap(find.text('В стопку').first);
    await settle(tester);
    expect(find.text('в стопке'), findsOneWidget);
    expect(focusDrops, <String>['i1']);
  });

  testWidgets('step 3: «Оставить» on an expired window extends it', (
    tester,
  ) async {
    await pumpReview(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('review-skip')));
      await settle(tester);
    }

    expect(find.text('Выпустить 0.16'), findsOneWidget);
    await tester.tap(find.text('Оставить'));
    await settle(tester);
    expect(goalActions, <String>['g_slot/extend']);
    expect(find.textContaining('Продлено до'), findsOneWidget);
    expect(find.text('Вернуть'), findsOneWidget);
  });

  testWidgets('step 4: a silent project, with its numbers', (tester) async {
    await pumpReview(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('review-skip')));
      await settle(tester);
    }

    expect(find.text('Ритм проектов'), findsOneWidget);
    expect(find.text('тишина 3 нед'), findsOneWidget);
    expect(find.text('закрыто 0,5 в неделю · норма 2'), findsOneWidget);
    expect(find.text('Поменять норму'), findsOneWidget);
  });

  testWidgets('step 6: «Записать пересмотр» records the summary and closes', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('review-skip')));
      await settle(tester);
    }
    expect(find.text('Итог недели'), findsOneWidget);
    expect(find.text('3 закрыто'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('review-summary')),
      'Дожал стенды',
    );
    await tester.tap(find.byKey(const ValueKey<String>('review-next')));
    await settle(tester);

    expect(server.savedReviews, hasLength(1));
    expect(server.savedReviews.single['summary'], 'Дожал стенды');
    expect(server.savedReviews.single['tzOffsetMinutes'], isA<int>());
    await settle(tester);
    expect(find.text('Пересмотр записан'), findsOneWidget);
    expect(find.text('Итог недели'), findsNothing);
    expect(find.text('Пересмотр записан'), findsOneWidget);

    await tester.tap(find.text('Недели'));
    await settle(tester);
    expect(container.read(historyTabProvider), HistoryTab.weeks);
  });

  testWidgets('closed midway, it opens on the same step', (tester) async {
    final container = await pumpReview(tester);
    await tester.tap(find.byKey(const ValueKey<String>('review-next')));
    await settle(tester);
    await tester.tap(find.byTooltip('Закрыть'));
    await settle(tester);
    expect(container.read(reviewProgressProvider).step, 1);

    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('Задумано, но не сделано'), findsOneWidget);
  });

  testWidgets('openReviewCard switches to «История», «Сделано»', (
    tester,
  ) async {
    final container = await pumpReview(tester);
    container.read(historyTabProvider.notifier).select(HistoryTab.weeks);
    openReviewCard(container);
    expect(container.read(historyTabProvider), HistoryTab.done);
    expect(container.read(shellModeProvider), AppMode.history);
  });
}
