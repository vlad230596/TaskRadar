import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/note.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/note_editor_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/theme/app_theme.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_ideas_backend.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';

/// Стенд приёмки идей — близнец `zz_capture_work_test.dart`: экраны
/// `design/reference/Ideas.html` и `Idea-Edit.html` при 390×844 настоящими
/// шрифтами, PNG в `build/acceptance/`. И тест: раскладка без переполнений.
void main() {
  const double width = 390;
  const double height = 844;

  final Directory out = Directory(
    '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}acceptance',
  );

  late FakeIdeasBackend server;

  setUpAll(() async {
    out.createSync(recursive: true);
    await loadAcceptanceFonts();
  });

  setUp(() => server = FakeIdeasBackend());

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

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _root,
        child: ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(server.backend.client),
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

  testWidgets('Ideas — вкладка идей проекта', (tester) async {
    await pump(
      tester,
      const ProjectScreen(projectId: FakeIdeasBackend.projectId),
    );
    await tester.tap(find.text('Идеи · 3'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await shot(tester, 'Ideas');
  });

  testWidgets('Ideas-Empty — идей нет', (tester) async {
    server.notes.clear();
    await pump(
      tester,
      const ProjectScreen(projectId: FakeIdeasBackend.projectId),
    );
    await tester.tap(find.textContaining('Идеи'));
    await settle(tester);
    expect(find.text('Идей пока нет'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'Ideas-Empty');
  });

  testWidgets('Idea-Edit — экран идеи', (tester) async {
    final json = server.notes.last;
    await pump(
      tester,
      NoteEditorScreen(
        projectId: FakeIdeasBackend.projectId,
        projectName: 'Публикации',
        note: Note.fromJson(<String, dynamic>{
          ...json,
          'content':
              'Whisper на телефоне, гонка моделей, почему аудио не уходит '
              'на сервер.\n— сравнить с Google Recorder\n— показать '
              '«Причесать» до и после',
        }),
      ),
    );
    expect(tester.takeException(), isNull);
    await shot(tester, 'Idea-Edit');
  });
}

final GlobalKey _root = GlobalKey();
