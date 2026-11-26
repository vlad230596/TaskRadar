import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/today_history.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/read_cache_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/settings_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/storage/read_cache_store.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fixtures.dart';
import 'support/memory_read_cache_store.dart';

/// Стенд приёмки «Даты и пересмотр» и меток ритма: настройки
/// (`design/reference/Settings-Today.html`) и планирование с метками
/// «тишина» / «перебор» (`Rhythm-Sheet.html`), 412 dp, настоящими шрифтами,
/// в `build/acceptance/`. Это ещё и тест: переполнение валит его.
void main() {
  const double width = 412;
  const double height = 915;

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
    double w = width,
    double h = height,
    MemoryReadCacheStore? readCache,
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
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            if (readCache != null)
              readCacheStoreProvider.overrideWithValue(readCache),
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

  testWidgets('Settings-Today — «Даты и пересмотр»', (tester) async {
    await pump(tester, const SettingsScreen());
    expect(find.text('ДАТЫ И ПЕРЕСМОТР'), findsOneWidget);
    expect(find.text('10 дн.'), findsOneWidget);
    expect(find.text('пн 9:00'), findsOneWidget);
    await shot(tester, 'Settings-Today');
  });

  testWidgets('Settings-Today-Horizon — лист горизонта', (tester) async {
    await pump(tester, const SettingsScreen());
    await tester.tap(find.text('Горизонт «Позже»'));
    await settle(tester);
    expect(find.text('Своё'), findsOneWidget);
    await shot(tester, 'Settings-Today-Horizon');
  });

  testWidgets('Settings-Today-Review — лист пересмотра', (tester) async {
    await pump(tester, const SettingsScreen());
    await tester.tap(find.text('Пересмотр'));
    await settle(tester);
    expect(find.text('вс'), findsOneWidget);
    await shot(tester, 'Settings-Today-Review');
  });

  testWidgets('Settings-Today-Offline — без сети', (tester) async {
    backend.responder = (options) => throw DioException.connectionError(
      requestOptions: options,
      reason: 'offline',
    );
    final cache = MemoryReadCacheStore()
      ..seed(
        ReadCacheKeys.ownerSettings,
        const OwnerSettings(
          laterHorizonDays: 14,
          reviewWeekday: 1,
          reviewTime: '09:00',
        ).toJson(),
      );
    await pump(tester, const SettingsScreen(), readCache: cache);
    expect(find.textContaining('нужна сеть'), findsNWidgets(2));
    await shot(tester, 'Settings-Today-Offline');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Rhythm-Plan — метки ритма в списке', (tester) async {
    await pump(tester, const ShellScreen());
    expect(find.text('тишина 3 нед'), findsOneWidget);
    expect(find.text('перебор 24/20'), findsOneWidget);
    await shot(tester, 'Rhythm-Plan');
  });

  testWidgets('Rhythm-Plan-Tiles — метки ритма на плитках', (tester) async {
    await pump(tester, const ShellScreen());
    await tester.tap(find.byTooltip('Значками'));
    await settle(tester);
    expect(find.text('тишина 3 нед'), findsOneWidget);
    await shot(tester, 'Rhythm-Plan-Tiles');
  });
}

final GlobalKey _root = GlobalKey();

String _ago(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

Map<String, dynamic> _task(
  String id,
  String projectId,
  String title, {
  String status = 'pending',
  bool current = false,
  double position = 1000,
}) => <String, dynamic>{
  'id': id,
  'projectId': projectId,
  'title': title,
  'description': null,
  'status': status,
  'position': position,
  'remindAt': null,
  'createdAt': _ago(20),
  'updatedAt': _ago(3),
  'isCurrent': current,
};

Map<String, dynamic> _project(
  String id,
  String name, {
  Map<String, dynamic>? rhythm,
  required List<Map<String, dynamic>> tasks,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'scopeId': defaultScopeId,
  'archivedAt': null,
  'createdAt': _ago(60),
  'updatedAt': _ago(2),
  'rhythmClosedPerWeek': rhythm?['closedPerWeek'],
  'rhythmMaxOpen': rhythm?['maxOpen'],
  'rhythm': rhythm,
  'noteCount': 0,
  'tasks': tasks,
};

List<dynamic> _board() => <dynamic>[
  _project(
    'p_radar',
    'TaskRadar',
    rhythm: <String, dynamic>{
      'closedPerWeek': null,
      'maxOpen': 20,
      'closedAvg': 4,
      'open': 24,
      'lastClosedAt': _ago(1),
      'silentWeeks': 0,
      'signal': 'overflow',
    },
    tasks: <Map<String, dynamic>>[
      _task('t1', 'p_radar', 'Сегодня и История в приложении', current: true),
      _task('t2', 'p_radar', 'Виджет: строка «Сегодня»', position: 2000),
      _task('t3', 'p_radar', 'Пересмотр недели', position: 3000),
    ],
  ),
  _project(
    'p_dom',
    'Дом',
    rhythm: <String, dynamic>{
      'closedPerWeek': 2,
      'maxOpen': null,
      'closedAvg': 0.5,
      'open': 6,
      'lastClosedAt': _ago(24),
      'silentWeeks': 3,
      'signal': 'silence',
    },
    tasks: <Map<String, dynamic>>[
      _task('t4', 'p_dom', 'Позвонить мастеру по окнам', current: true),
      _task('t5', 'p_dom', 'Купить фильтры', position: 2000),
    ],
  ),
  _project(
    'p_dacha',
    'Дача',
    tasks: <Map<String, dynamic>>[
      _task('t6', 'p_dacha', 'Закрыть воду на зиму', current: true),
    ],
  ),
];

Future<ResponseBody> _respond(RequestOptions options) async {
  final path = options.path;
  if (path.startsWith('/board')) return jsonResponse(_board());
  if (path.startsWith('/scopes')) return jsonResponse(defaultScopesJson());
  if (path == '/settings') {
    return jsonResponse(const OwnerSettings().toJson());
  }
  if (path == '/reviews/status') {
    return jsonResponse(<String, dynamic>{'due': false, 'nextAt': null});
  }
  if (path.startsWith('/contours')) {
    return jsonResponse(<String, dynamic>{
      'contours': <dynamic>[],
      'active': <String, dynamic>{'contourId': null, 'until': null},
    });
  }
  if (path.startsWith('/dictation/models')) {
    return jsonResponse(<String, dynamic>{
      'models': <dynamic>[],
      'defaultModel': null,
    });
  }
  return jsonResponse(const <dynamic>[]);
}
