import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminders.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/today/date_sheet.dart';
import 'package:taskradar/widgets/today/next_sheet.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';

/// The acceptance stand of «Сегодня» (`design/today-history-spec.md`): each
/// screen drawn at the reference's 412 dp phone (or 1440x900), real fonts,
/// a PNG in `build/acceptance/` to put beside `design/reference/*.html`.
/// The checks below are what the screen must hold whatever it looks like.
void main() {
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
    _tail = 2;
    backend = FakeBackend()..responder = _respond;
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
    double w = 412,
    double h = 915,
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
            captureQueueStoreProvider.overrideWithValue(
              FakeCaptureQueueStore(),
            ),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            settingsStoreProvider.overrideWithValue(
              FakeSettingsStore()..uiNotes['hint.swipeDate'] = '1',
            ),
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
    await tester.tap(find.text('Работа').first);
    await settle(tester);
  }

  testWidgets('Focus-Today — хвост, «Сегодня», набор', (tester) async {
    await pump(tester, const ShellScreen(), h: 1500);
    await openWork(tester);

    expect(find.text('С прошлых дней'), findsOneWidget);
    expect(find.text('Все в сегодня'), findsOneWidget);
    // M = open today (5) + closed today (3); N = 3.
    expect(find.text('3 из 8'), findsOneWidget);
    expect(find.text('РАБОТА'), findsOneWidget);
    expect(find.text('ДОМ'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('проверить'), findsOneWidget);
    expect(find.text('Разблокировать'), findsOneWidget);
    // In the set and dated today: once, in «Сегодня».
    expect(find.text('Спроектировать экран «Сегодня»'), findsOneWidget);
    expect(find.text('Собрать стенд для демо в среду'), findsOneWidget);
    await shot(tester, 'Focus-Today');
  });

  testWidgets('Focus-Tail — день миграции, 14 в хвосте', (tester) async {
    _tail = 14;
    await pump(tester, const ShellScreen(), h: 1100);
    await openWork(tester);
    expect(find.text('Ещё 11'), findsOneWidget);
    await shot(tester, 'Focus-Tail');
  });

  testWidgets('Desk-Focus-Today — колонка дня слева', (tester) async {
    await pump(tester, const ShellScreen(), w: 1440, h: 900);
    await openWork(tester);
    expect(find.text('С прошлых дней'), findsOneWidget);
    await shot(tester, 'Desk-Focus-Today');
  });

  testWidgets('Project-Later — метки даты и «Позже»', (tester) async {
    await pump(tester, const ProjectScreen(projectId: 'prj_dom'), h: 1000);
    expect(find.text('Позже · '), findsOneWidget);
    await shot(tester, 'Project-Later');

    await tester.tap(find.text('Позже · '));
    await settle(tester);
    await tester.drag(find.text('Купить лампочки'), const Offset(-150, 0));
    await settle(tester);
    expect(find.text('Завтра'), findsWidgets);
    await shot(tester, 'Project-Later-Open');
  });

  testWidgets('Date-Sheet — лист даты', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showTaskDateSheet(context, current: _day(1), time: '15:00'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('Время 15:00 сохранится'), findsOneWidget);
    await shot(tester, 'Date-Sheet');
  });

  testWidgets('Next-Sheet — снекбар и лист «Следом»', (tester) async {
    await pump(tester, const ShellScreen(), h: 1500);
    await openWork(tester);
    // Close a task in «Сегодня».
    await tester.tap(find.byTooltip('Отметить сделанной').first);
    await settle(tester);
    expect(find.text('Следом…'), findsOneWidget);
    await shot(tester, 'Next-Snack');

    await tester.tap(find.byKey(const ValueKey<String>('snack-next')));
    await settle(tester);
    expect(find.byType(NextSheet), findsOneWidget);
    await shot(tester, 'Next-Sheet');
  });
}

final GlobalKey _root = GlobalKey();

/// How many tasks the tail holds: 2 as on `Focus-Today.html`, 14 on the
/// migration day.
int _tail = 2;

String _iso(int daysAgo, {int hour = 9}) => DateTime.now()
    .toUtc()
    .subtract(Duration(days: daysAgo, hours: hour))
    .toIso8601String();

String _day(int offset) =>
    calendarDateForApi(DateTime.now().add(Duration(days: offset)));

String _stored(int offset) => '${_day(offset)}T00:00:00.000Z';

/// A closing today at [hhmm] local.
String _doneAt(String hhmm) {
  final now = DateTime.now();
  final p = hhmm.split(':').map(int.parse).toList();
  return DateTime(
    now.year,
    now.month,
    now.day,
    p[0],
    p[1],
  ).toUtc().toIso8601String();
}

Map<String, dynamic> _task(
  String id,
  String pid,
  String title, {
  String status = 'pending',
  num position = 1000,
  bool isCurrent = false,
  int? date,
  String? time,
  String? doneAt,
  int age = 2,
}) => <String, dynamic>{
  'id': id,
  'projectId': pid,
  'title': title,
  'description': null,
  'status': status,
  'position': position,
  'remindAt': date == null ? null : _stored(date),
  'remindTime': time,
  'doneAt': doneAt,
  'createdAt': _iso(age + 6),
  'updatedAt': _iso(age),
  'isCurrent': isCurrent,
};

List<Map<String, dynamic>> _board() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'prj_st',
    'name': 'Стенды',
    'scopeId': 'scope_work',
    'archivedAt': null,
    'createdAt': _iso(60),
    'updatedAt': _iso(2),
    'tasks': <Map<String, dynamic>>[
      _task('tw0', 'prj_st', 'Собрать стенд для демо в среду', isCurrent: true),
      _task(
        'tw1',
        'prj_st',
        'Ответить Пете про стенды',
        date: 0,
        position: 2000,
      ),
      _task(
        'tw2',
        'prj_st',
        'Поговорить с Васей — ждём ответа',
        status: 'blocked',
        date: 0,
        position: 3000,
      ),
      _task('tw3', 'prj_st', 'Обновить прошивку на стенде №2', position: 4000),
      _task(
        'tw4',
        'prj_st',
        'Скинуть Лене презентацию стендов',
        date: -1,
        position: 5000,
      ),
      _task(
        'tw5',
        'prj_st',
        'Отправить акт за ноябрь',
        status: 'done',
        date: 0,
        doneAt: _doneAt('09:05'),
        position: 6000,
      ),
      _task(
        'tw6',
        'prj_st',
        'Созвон 5 мин с Олегом',
        status: 'done',
        date: 0,
        doneAt: _doneAt('10:12'),
        position: 7000,
      ),
    ],
  },
  <String, dynamic>{
    'id': 'prj_tr',
    'name': 'TaskRadar',
    'scopeId': 'scope_work',
    'archivedAt': null,
    'createdAt': _iso(50),
    'updatedAt': _iso(4),
    'tasks': <Map<String, dynamic>>[
      _task(
        'tt1',
        'prj_tr',
        'Спроектировать экран «Сегодня»',
        isCurrent: true,
        date: 0,
      ),
    ],
  },
  <String, dynamic>{
    'id': 'prj_dom',
    'name': 'Дом',
    'scopeId': 'scope_home',
    'archivedAt': null,
    'createdAt': _iso(40),
    'updatedAt': _iso(2),
    'tasks': <Map<String, dynamic>>[
      _task('th1', 'prj_dom', 'Встретить курьера', date: 0, time: '15:00'),
      _task(
        'th2',
        'prj_dom',
        'Записать Мишу к стоматологу',
        date: 0,
        position: 2000,
        isCurrent: true,
      ),
      _task(
        'th3',
        'prj_dom',
        'Купить батарейки для пульта',
        status: 'done',
        date: 0,
        doneAt: _doneAt('11:41'),
        position: 3000,
      ),
      _task('th4', 'prj_dom', 'Купить лампочки', position: 4000, date: 1),
      _task(
        'th5',
        'prj_dom',
        'Заказать крючки для полок в ванной',
        position: 5000,
        date: 4,
      ),
      _task(
        'th6',
        'prj_dom',
        'Посмотреть, почему не работает вентилятор',
        status: 'blocked',
        position: 6000,
        date: 2,
      ),
      _task(
        'th7',
        'prj_dom',
        'Поменять зимнюю резину',
        position: 7000,
        date: 90,
      ),
      _task(
        'th8',
        'prj_dom',
        'Продлить страховку квартиры',
        position: 8000,
        date: 40,
      ),
      for (var i = 0; i < _tail - 1; i++)
        _task(
          'tail$i',
          'prj_dom',
          i == 0 ? 'Позвонить в ЖЭК про счётчики' : 'Старое дело №$i',
          position: 9000 + i * 1000,
          date: -3 - i,
        ),
    ],
  },
];

Map<String, dynamic>? _row(String id) {
  for (final project in _board()) {
    for (final task in project['tasks'] as List<Map<String, dynamic>>) {
      if (task['id'] == id) {
        return <String, dynamic>{
          ...task,
          'focusedAt': _iso(0, hour: 3),
          'project': <String, dynamic>{
            'id': project['id'],
            'name': project['name'],
          },
        };
      }
    }
  }
  return null;
}

ResponseBody _respond(RequestOptions options) {
  final path = options.path.split('?').first;

  Object? body;
  if (path == '/board') {
    body = _board();
  } else if (path == '/focus') {
    body = <dynamic>[_row('tw0'), _row('tt1'), _row('tw3')];
  } else if (path == '/scopes') {
    body = <dynamic>[
      <String, dynamic>{
        'id': 'scope_work',
        'name': 'Работа',
        'position': 1000,
        'createdAt': _iso(90),
        'updatedAt': _iso(90),
      },
      <String, dynamic>{
        'id': 'scope_home',
        'name': 'Дом',
        'position': 2000,
        'createdAt': _iso(90),
        'updatedAt': _iso(90),
      },
    ];
  } else if (path == '/settings') {
    body = <String, dynamic>{
      'laterHorizonDays': 10,
      'reviewWeekday': 1,
      'reviewTime': '09:00',
    };
  } else if (path == '/reviews/status') {
    body = <String, dynamic>{'due': false, 'nextAt': null, 'lastAt': null};
  } else if (path.endsWith('/notes') || path.endsWith('/categories')) {
    body = <dynamic>[];
  } else if (path.endsWith('/tasks')) {
    final id = path.split('/')[2];
    body = _board().firstWhere((p) => p['id'] == id)['tasks'];
  } else if (path.startsWith('/projects/')) {
    final id = path.split('/')[2];
    final project = Map<String, dynamic>.from(
      _board().firstWhere((p) => p['id'] == id),
    )..remove('tasks');
    body = project;
  } else if (path.startsWith('/tasks/') && options.method == 'GET') {
    body = _row(path.split('/')[2]);
  } else if (options.method == 'PATCH' && path.startsWith('/tasks/')) {
    final row = _row(path.split('/')[2])!;
    body = <String, dynamic>{...row, ...(options.data as Map)};
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
