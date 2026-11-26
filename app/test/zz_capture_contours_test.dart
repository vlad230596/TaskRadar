import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/contour_edit_screen.dart';
import 'package:taskradar/screens/contours_screen.dart';
import 'package:taskradar/screens/history_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_backend.dart';
import 'support/fake_history_backend.dart';

/// Стенд приёмки для контуров и «Достигнутых целей» — близнец
/// `zz_capture_history_test.dart`: каждый экран при 390×844 настоящими
/// шрифтами в `build/acceptance/`, для сличения с
/// `design/reference/Contours.html`, `Contour-Edit.html` и
/// `History-Goals.html`. Заодно это тест: переполнение строки или исключение
/// при раскладке валят его, как любой другой.
void main() {
  const double width = 390;
  const double height = 844;

  final Directory out = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance',
  );

  late FakeBackend backend;
  late FakeHistoryBackend history;

  setUpAll(() async {
    out.createSync(recursive: true);
    await loadAcceptanceFonts();
  });

  setUp(() {
    backend = FakeBackend();
    history = FakeHistoryBackend(backend);
    history
      ..done = history.sampleDone()
      ..weeks = history.sampleWeeks();
    backend.on('GET', '/board', (match) => jsonResponse(const <dynamic>[]));
    final achieved = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'g_voice',
        'contourId': 'c_work',
        'title': 'Голос, который работает без сети',
        'why': 'Диктовка не должна зависеть от сервера',
        'state': 'achieved',
        'achievedAt': history.iso(3),
        'position': 1000,
        'createdAt': history.iso(15),
        'progress': <String, dynamic>{'done': 5, 'total': 5},
      },
      <String, dynamic>{
        'id': 'g_photo',
        'contourId': 'c_home',
        'title': 'Перевезти семейные фото в облако',
        'state': 'achieved',
        'achievedAt': history.iso(16),
        'position': 2000,
        'createdAt': history.iso(30),
        'progress': <String, dynamic>{'done': 3, 'total': 3},
      },
    ];
    backend
      ..on('GET', '/goals', (match) {
        final state = match.options.queryParameters['state'] as String?;
        return jsonResponse(
          state == 'achieved'
              ? achieved
              : <dynamic>[
                  <String, dynamic>{
                    'id': 'g_next',
                    'contourId': 'c_work',
                    'title': 'Новое поколение TaskRadar',
                    'state': 'slot',
                    'position': 1000,
                    'createdAt': history.iso(5),
                  },
                ],
        );
      })
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
              'schedule': <String, dynamic>{
                'days': <int>[1, 2, 3, 4, 5],
                'from': '09:00',
                'to': '19:00',
              },
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
          'active': <String, dynamic>{'contourId': 'c_work', 'until': null},
        }),
      );
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
    double w = width,
    double h = height,
  }) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _root,
        child: ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(backend.client)],
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

  const historyHome = Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          HistoryHeader(),
          Expanded(child: HistoryScreen()),
        ],
      ),
    ),
  );

  testWidgets('Contours — список контуров', (tester) async {
    await pump(tester, const ContoursScreen());
    expect(find.text('сейчас'), findsOneWidget);
    await shot(tester, 'Contours');
  });

  testWidgets('Contour-Edit — контур с целями', (tester) async {
    await pump(tester, const ContourEditScreen(contourId: 'c_work'));
    expect(find.textContaining('Нельзя удалить'), findsOneWidget);
    await shot(tester, 'Contour-Edit');
  });

  testWidgets('History-Goals — достигнутые цели', (tester) async {
    await pump(tester, historyHome);
    // On a phone the goals are on «Недели»; on a desktop both columns show.
    await tester.tap(find.text('Недели'));
    await settle(tester);
    expect(find.text('ДОСТИГНУТЫЕ ЦЕЛИ · 2'), findsOneWidget);
    await shot(tester, 'History-Goals');
  });

  testWidgets('Desk-History-Goals — широкое окно', (tester) async {
    await pump(tester, historyHome, w: 1440, h: 900);
    expect(find.text('ДОСТИГНУТЫЕ ЦЕЛИ · 2'), findsOneWidget);
    await shot(tester, 'Desk-History-Goals');
  });
}

final GlobalKey _root = GlobalKey();
