import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/screens/task_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';
import 'support/fake_project_backend.dart';

/// Не тест: сверка F13 с эталоном.
///
/// Близнец `zz_capture_screens_test.dart`, отдельным файлом по той же причине,
/// по которой у F13 отдельные экраны: тот снимает F12 и правиться не должен.
/// Здесь рендерятся история (телефон и широкое окно) и экран задачи с
/// «жизнью задачи» — ровно в 390x844 (и 1440x900), настоящими шрифтами, — и
/// кладутся в `build/acceptance/`, чтобы положить рядом с
/// `design/reference/History.html`, `Edit.html` и `Desk-History.html`.
///
/// Почему снимается здесь, а не в браузере, разобрано в комментарии
/// `zz_capture_screens_test.dart`: у `toImage` на дереве рендера нет
/// пересэмплирования, без которого сравнение с `height: 22px` ничего не значит.
void main() {
  const double width = 390;
  const double height = 844;

  final Directory out = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance',
  );

  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeHistoryBackend history;
  late String taskId;

  setUpAll(() async {
    out.createSync(recursive: true);
    await loadAcceptanceFonts();
  });

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    history = FakeHistoryBackend(backend);

    final projectId = server.addProject(name: 'Дом', id: 'prj_dom');
    taskId = server.addTask(
      projectId: projectId,
      id: 'tsk_vent',
      title:
          'Посмотреть, почему не работает вентилятор в туалете. Позвонить в '
          'УК и спросить, чей это участок.',
      status: 'blocked',
      remindAt: _day(1),
    );
    history.events[taskId] = history.sampleJournal(taskId);
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
          overrides: [
            apiClientProvider.overrideWithValue(backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
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

  /// Режим истории целиком, с оболочкой.
  ///
  /// Через `ShellScreen`, а не `HistoryHeader + HistoryScreen` в голом
  /// `Scaffold`, как было: нижняя панель — часть эталона `History.html`, и без
  /// неё снимок получал лишние 82 px высоты. Сверка именно этого экрана шла на
  /// другой площади, чем у страницы, с которой её сравнивают, — то есть значила
  /// не то, что должна. `Focus` снимается так с самого начала.
  ///
  /// Ищется по обеим подписям: на телефоне пункт зовётся «История», а на
  /// рельсе — «Итоги» (`AppModeChrome.railLabel`: «История» не влезает в 56 px
  /// кеглем 9.5). Один литерал здесь ронял бы ровно широкий снимок.
  Future<void> openHistory(WidgetTester tester) async {
    final phone = find.text('История');
    await tester.tap(phone.evaluate().isNotEmpty ? phone : find.text('Итоги'));
    await settle(tester);
  }

  testWidgets('History — неделя, долгожители, проекты', (tester) async {
    await pump(tester, const ShellScreen());
    await openHistory(tester);
    await shot(tester, 'History');
  });

  testWidgets('History — пусто, и это сказано словами', (tester) async {
    history.history = history.emptyWeek();
    await pump(tester, const ShellScreen());
    await openHistory(tester);
    await shot(tester, 'History-empty');
  });

  testWidgets('Edit — задача с настоящей «жизнью задачи»', (tester) async {
    await pump(tester, TaskScreen(projectId: 'prj_dom', taskId: taskId));
    await shot(tester, 'Edit-life');
  });

  testWidgets('Desk-History — широкое окно', (tester) async {
    await pump(tester, const ShellScreen(), w: 1440, h: 900);
    await openHistory(tester);
    await shot(tester, 'Desk-History');
  });
}

final GlobalKey _root = GlobalKey();

String _day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}T00:00:00.000Z';
}
