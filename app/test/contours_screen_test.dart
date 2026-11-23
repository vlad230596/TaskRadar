import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/contour_edit_screen.dart';
import 'package:taskradar/screens/contours_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/fake_backend.dart';

/// Настройки → Контуры (design/goals-ideas-spec.md, п. 9).
void main() {
  late FakeBackend backend;
  late List<Map<String, dynamic>> contours;
  late List<Map<String, dynamic>> goals;
  late List<Map<String, dynamic>> achieved;
  late List<Map<String, dynamic>> patches;
  late int deletes;

  Map<String, dynamic> contour(
    String id,
    String name, {
    int slots = 2,
    int windowDays = 7,
    Map<String, dynamic>? schedule,
    num position = 1000,
  }) => <String, dynamic>{
    'id': id,
    'name': name,
    'slots': slots,
    'windowDays': windowDays,
    'schedule': schedule,
    'position': position,
  };

  Map<String, dynamic> goal(String id, String contourId, String state) =>
      <String, dynamic>{
        'id': id,
        'contourId': contourId,
        'title': 'Цель $id',
        'state': state,
        'position': 1000,
        'createdAt': '2026-11-01T10:00:00.000Z',
        if (state == 'slot') 'slottedAt': '2026-11-20T10:00:00.000Z',
        if (state == 'achieved') 'achievedAt': '2026-11-21T10:00:00.000Z',
      };

  setUp(() {
    backend = FakeBackend();
    contours = <Map<String, dynamic>>[
      contour(
        'c_work',
        'Работа',
        schedule: <String, dynamic>{
          'days': <int>[1, 2, 3, 4, 5],
          'from': '09:00',
          'to': '19:00',
        },
      ),
      contour('c_home', 'Личное', windowDays: 14, position: 2000),
    ];
    goals = <Map<String, dynamic>>[];
    achieved = <Map<String, dynamic>>[];
    patches = <Map<String, dynamic>>[];
    deletes = 0;
    backend
      ..on(
        'GET',
        '/contours',
        (match) => jsonResponse(<String, dynamic>{
          'contours': contours,
          'active': <String, dynamic>{'contourId': null, 'until': null},
        }),
      )
      ..on('GET', '/goals', (match) {
        final state = match.options.queryParameters['state'] as String?;
        return jsonResponse(state == 'achieved' ? achieved : goals);
      })
      ..on('PATCH', '/contours/:id', (match) {
        patches.add(match.body);
        final row = contours.firstWhere((c) => c['id'] == match.params['id']);
        row.addAll(match.body);
        return jsonResponse(row);
      })
      ..on('DELETE', '/contours/:id', (match) {
        deletes++;
        return jsonResponse(null, statusCode: 204);
      });
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(backend.client)],
        child: MaterialApp(theme: buildAppTheme(), home: home),
      ),
    );
    await settle(tester);
  }

  group('the list', () {
    testWidgets('names, summary, the active and the default', (tester) async {
      await pump(tester, const ContoursScreen());

      expect(find.text('Работа'), findsOneWidget);
      expect(find.text('Личное'), findsOneWidget);
      expect(find.text('2 слота · окно 7 д · пн–пт 9:00–19:00'), findsOneWidget);
      expect(find.text('2 слота · окно 14 д · без расписания'), findsOneWidget);
      expect(find.text('по умолчанию'), findsOneWidget);
      // One contour is active, whatever the clock says.
      expect(find.text('сейчас'), findsOneWidget);
      expect(find.text('Контур'), findsOneWidget);
    });
  });

  group('one contour', () {
    testWidgets('changing the slots enables «Сохранить» and sends a PATCH', (
      tester,
    ) async {
      await pump(tester, const ContourEditScreen(contourId: 'c_home'));

      final save = find.widgetWithText(TextButton, 'Сохранить');
      expect(tester.widget<TextButton>(save).onPressed, isNull);

      await tester.tap(find.bySemanticsLabel('3 слота'));
      await tester.pump();
      expect(tester.widget<TextButton>(save).onPressed, isNotNull);

      await tester.tap(save);
      await settle(tester);

      expect(patches, hasLength(1));
      expect(patches.single['slots'], 3);
      expect(patches.single['name'], 'Личное');
      expect(patches.single['windowDays'], 14);
      expect(patches.single.containsKey('schedule'), isTrue);
      expect(patches.single['schedule'], isNull);
    });

    testWidgets('an end before the start is refused', (tester) async {
      contours[1]['schedule'] = <String, dynamic>{
        'days': <int>[6, 7],
        'from': '19:00',
        'to': '09:00',
      };
      contours[1]['name'] = 'Выходные';
      await pump(tester, const ContourEditScreen(contourId: 'c_home'));

      await tester.enterText(find.byType(TextField).first, 'Дом');
      await tester.pump();

      expect(
        find.text('Конец раньше начала — через полночь нельзя.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Сохранить'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('a contour with goals explains the 409 before it is pressed', (
      tester,
    ) async {
      goals.add(goal('g1', 'c_home', 'bench'));
      achieved.add(goal('g2', 'c_home', 'achieved'));
      await pump(tester, const ContourEditScreen(contourId: 'c_home'));

      expect(
        find.textContaining('Нельзя удалить: в контуре 2 цели (с достигнутыми)'),
        findsOneWidget,
      );
      expect(find.text('К целям контура →'), findsOneWidget);
      final delete = find.widgetWithText(TextButton, 'Удалить контур');
      expect(tester.widget<TextButton>(delete).onPressed, isNull);
    });

    testWidgets('the last contour cannot go', (tester) async {
      contours.removeAt(1);
      await pump(tester, const ContourEditScreen(contourId: 'c_work'));

      expect(find.textContaining('Это единственный контур'), findsOneWidget);
    });

    testWidgets('an empty contour is deleted after a confirmation', (
      tester,
    ) async {
      await pump(tester, const ContourEditScreen(contourId: 'c_home'));

      await tester.tap(find.widgetWithText(TextButton, 'Удалить контур'));
      await settle(tester);
      expect(find.text('Удалить «Личное»?'), findsOneWidget);
      expect(find.textContaining('перейдут в набор «Работа»'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
      await settle(tester);
      expect(deletes, 1);
    });

    testWidgets('slots below the goals in them warn, not refuse', (
      tester,
    ) async {
      goals
        ..add(goal('g1', 'c_home', 'slot'))
        ..add(goal('g2', 'c_home', 'slot'));
      await pump(tester, const ContourEditScreen(contourId: 'c_home'));

      await tester.tap(find.bySemanticsLabel('1 слот'));
      await tester.pump();

      expect(find.textContaining('Сейчас в слотах 2'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Сохранить'))
            .onPressed,
        isNotNull,
      );
    });
  });
}
