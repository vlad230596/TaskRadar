import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/pick_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';

/// Не тест, а стенд приёмки для F13-A — близнец `zz_capture_screens_test.dart`,
/// который остался за F12 и не трогается.
///
/// Приёмка итерации — буквальное сличение с `design/reference/*.html` при
/// 390×844. Здесь каждый мой экран рисуется ровно в этом размере, настоящими
/// шрифтами из `assets/fonts`, и кладётся PNG в `build/acceptance/`.
///
/// Почему не в браузере — см. длинную заметку в соседнем файле: превью
/// пересчитывает пиксели дважды, и чип высотой 22 px перестаёт быть 22 px.
/// `toImage` по дереву рендера — те же виджеты, те же шрифты, те же 390×844 и
/// никакой передискретизации.
void main() {
  const double width = 390;
  const double height = 844;

  final Directory out = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance',
  );

  late FakeBackend backend;

  setUpAll(() async {
    out.createSync(recursive: true);
    await loadAcceptanceFonts();
  });

  setUp(() {
    _resetFocus();
    backend = FakeBackend()..responder = _respond;
  });

  /// Кодирование внутри `runAsync`: `toImage` заканчивается на растровом потоке
  /// движка, а поддельные часы виджет-теста завершения этого потока не видят —
  /// будущее разрешается, и тест стоит до десятиминутного таймаута.
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
          overrides: [
            apiClientProvider.overrideWithValue(backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
            ),
            captureQueueStoreProvider.overrideWithValue(FakeCaptureQueueStore()),
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

  /// Режим работы целиком, с оболочкой: шапка и нижняя панель — часть эталона.
  Future<void> openWork(WidgetTester tester) async {
    await tester.tap(find.text('Работа'));
    await settle(tester);
  }

  testWidgets('Focus — работа, набор из трёх', (tester) async {
    await pump(tester, const ShellScreen());
    await openWork(tester);
    await shot(tester, 'Focus');
  });

  testWidgets('Focus-Empty — пустой набор', (tester) async {
    _focused.clear();
    await pump(tester, const ShellScreen());
    await openWork(tester);
    await shot(tester, 'Focus-Empty');
  });

  testWidgets('Pick — сбор набора', (tester) async {
    await pump(tester, const PickScreen());
    await shot(tester, 'Pick');
  });

  testWidgets('Project — строка задачи с «взять в работу»', (tester) async {
    await pump(tester, const ProjectScreen(projectId: 'prj_dom'));
    await shot(tester, 'Project-Focus');
  });

  testWidgets('Desk-Focus — широкое окно', (tester) async {
    await pump(tester, const ShellScreen(), w: 1440, h: 900);
    await openWork(tester);
    await shot(tester, 'Desk-Focus');
  });
}

final GlobalKey _root = GlobalKey();

// --- данные приёмки, из спецификации ---------------------------------------

String _iso(int daysAgo) => DateTime.now()
    .toUtc()
    .subtract(Duration(days: daysAgo, hours: 9))
    .toIso8601String();

String _day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}T00:00:00.000Z';
}

/// «в работе с 9:40» на снимке — то же самое время, что на эталонной странице.
///
/// Сегодняшняя дата с фиксированным часом: подпись показывает время только для
/// сегодняшнего набора, а снимок должен быть одинаковым в любой день.
String _focusedAt(int minutesAfter) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 9, 40 + minutesAfter)
      .toUtc()
      .toIso8601String();
}

Map<String, dynamic> _task(
  String id,
  String pid,
  String title, {
  String status = 'pending',
  num position = 1000,
  bool isCurrent = false,
  String? remindAt,
  int age = 2,
}) => <String, dynamic>{
  'id': id,
  'projectId': pid,
  'title': title,
  'description': null,
  'status': status,
  'position': position,
  'remindAt': remindAt,
  'createdAt': _iso(age + 6),
  'updatedAt': _iso(age),
  'isCurrent': isCurrent,
};

final List<Map<String, dynamic>> _board = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'prj_dom',
    'name': 'Дом',
    'scopeId': 'scope_main',
    'archivedAt': null,
    'createdAt': _iso(40),
    'updatedAt': _iso(2),
    'tasks': <Map<String, dynamic>>[
      _task(
        't1',
        'prj_dom',
        'Вызвать курьера из Яндекс Маркета.',
        isCurrent: true,
      ),
      _task('t2', 'prj_dom', 'Купить лампочки', position: 2000, age: 5),
      _task(
        't3',
        'prj_dom',
        'Заказать крючки для полок в ванной',
        position: 3000,
        age: 5,
      ),
      _task(
        't4',
        'prj_dom',
        'Посмотреть, почему не работает вентилятор в туалете',
        status: 'blocked',
        position: 4000,
        remindAt: _day(2),
        age: 3,
      ),
      _task(
        't5',
        'prj_dom',
        'Заменить болт на кухне в раковине.',
        position: 5000,
      ),
    ],
  },
  <String, dynamic>{
    'id': 'prj_tr',
    'name': 'TaskRadar',
    'scopeId': 'scope_main',
    'archivedAt': null,
    'createdAt': _iso(60),
    'updatedAt': _iso(4),
    'tasks': <Map<String, dynamic>>[
      _task(
        't7',
        'prj_tr',
        'Потестить диктовку на телефоне',
        isCurrent: true,
        age: 4,
      ),
      _task(
        't8',
        'prj_tr',
        'Адаптировать кнопку распознавания, размер шрифта, взаимное '
            'расположение',
        position: 2000,
        age: 4,
      ),
    ],
  },
  <String, dynamic>{
    'id': 'prj_fam',
    'name': 'Семья',
    'scopeId': 'scope_main',
    'archivedAt': null,
    'createdAt': _iso(30),
    'updatedAt': _iso(2),
    'tasks': <Map<String, dynamic>>[
      _task(
        't9',
        'prj_fam',
        'Посмотреть статус Мишиной сим карточки.',
        isCurrent: true,
      ),
    ],
  },
];

/// Набор: id задачи и когда её взяли. Ровно тот, что на `Focus.html`.
final Map<String, String> _focused = <String, String>{};

void _resetFocus() {
  _focused
    ..clear()
    ..addAll(<String, String>{
      't1': _focusedAt(0),
      't7': _focusedAt(20),
      't8': _focusedAt(35),
    });
}

Map<String, dynamic> _taskById(String id) {
  for (final project in _board) {
    for (final task in project['tasks'] as List<Map<String, dynamic>>) {
      if (task['id'] == id) {
        return <String, dynamic>{
          ...task,
          'focusedAt': _focused[id],
          'project': <String, dynamic>{
            'id': project['id'],
            'name': project['name'],
          },
        };
      }
    }
  }
  throw StateError('unknown task $id');
}

ResponseBody _respond(RequestOptions options) {
  final path = options.path.split('?').first;

  Object? body;
  if (path == '/board') {
    body = _board;
  } else if (path == '/focus') {
    final ids = _focused.keys.toList()
      ..sort((a, b) => _focused[a]!.compareTo(_focused[b]!));
    body = <dynamic>[for (final id in ids) _taskById(id)];
  } else if (path == '/scopes') {
    body = <dynamic>[
      <String, dynamic>{
        'id': 'scope_main',
        'name': 'Основной',
        'position': 1000,
        'createdAt': _iso(90),
        'updatedAt': _iso(90),
      },
    ];
  } else if (path == '/inbox') {
    body = <dynamic>[];
  } else if (path.endsWith('/notes')) {
    body = <dynamic>[];
  } else if (path.endsWith('/tasks')) {
    final id = path.split('/')[2];
    body = _board.firstWhere((p) => p['id'] == id)['tasks'];
  } else if (path.startsWith('/projects/')) {
    final id = path.split('/')[2];
    final project = Map<String, dynamic>.from(
      _board.firstWhere((p) => p['id'] == id),
    )..remove('tasks');
    body = project;
  } else {
    body = <dynamic>[];
  }

  return ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}
