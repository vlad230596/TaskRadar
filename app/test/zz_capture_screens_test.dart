import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/dictation_screen.dart';
import 'package:taskradar/screens/inbox_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/screens/task_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_voice.dart';

/// Not a test: the acceptance harness for F12.
///
/// The iteration's acceptance step is a literal side-by-side against
/// `design/reference/*.html` at 390x844. This renders each redrawn screen at
/// exactly that size, with the real bundled fonts, and writes a PNG per screen
/// into `build/acceptance/`.
///
/// ## Why it renders here rather than in the browser
///
/// The web bundle was built and opened, and it draws correctly with the fonts
/// coming out of `assets/fonts` (no network). What the browser cannot give is a
/// *measurable* capture: the preview pane emulates a device pixel ratio over
/// CanvasKit's own surface, so the image that comes back is a rescale of a
/// rescale and a 22 px chip is no longer 22 px in it. `toImage` on the render
/// tree is the same widgets, the same fonts and the same 390x844, with no
/// resampling in between -- which is the only way a comparison against a page
/// that specifies `height: 22px` means anything.
///
/// Run it on demand; it is excluded from the suite by the `zz_` prefix only by
/// convention, so delete it (or keep it and accept ~1 s) as you prefer.
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
    await _loadFonts();
  });

  setUp(() {
    backend = FakeBackend()..responder = _respond;
  });

  /// Encoding runs inside `runAsync`: `toImage` and `toByteData` finish on the
  /// engine's raster thread, and the fake clock a widget test runs on never
  /// lets that thread's completion be observed -- the future resolves and the
  /// test then sits there until the ten-minute timeout.
  Future<void> shot(WidgetTester tester, String name) async {
    final boundary =
        tester.renderObject(find.byKey(_root)) as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${out.path}${Platform.pathSeparator}$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
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
            captureQueueStoreProvider.overrideWithValue(
              FakeCaptureQueueStore(),
            ),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            voiceRecorderProvider.overrideWithValue(
              FakeVoiceRecorder()
                ..levelSamples = const <double>[
                  0.05, 0.12, 0.34, 0.21, 0.52, 0.71, 0.38, 0.19, 0.46,
                  0.78, 0.57, 0.28, 0.09, 0.36, 0.66, 0.92, 0.6, 0.41,
                  0.24, 0.49, 0.86, 0.54, 0.31, 0.14, 0.43, 0.68, 0.33,
                  0.07,
                ],
            ),
            speechRecognizerProvider.overrideWithValue(FakeSpeechRecognizer()),
            voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
            deviceTimeZoneNameProvider.overrideWith(
              (ref) async => 'Europe/Moscow',
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

  testWidgets('Main — planning, as a list', (tester) async {
    await pump(tester, const ShellScreen());
    await shot(tester, 'Main');
  });

  testWidgets('Main-Tiles — planning, as tiles', (tester) async {
    await pump(tester, const ShellScreen());
    await tester.tap(find.byTooltip('Значками'));
    await settle(tester);
    await shot(tester, 'Main-Tiles');
  });

  testWidgets('Project — one project', (tester) async {
    await pump(tester, const ProjectScreen(projectId: 'prj_dom'));
    await shot(tester, 'Project');
  });

  testWidgets('Edit — one task', (tester) async {
    await pump(
      tester,
      const TaskScreen(projectId: 'prj_dom', taskId: 't4'),
    );
    await shot(tester, 'Edit');
  });

  testWidgets('Inbox — the sandbox', (tester) async {
    await pump(tester, const InboxScreen());
    await shot(tester, 'Inbox');
  });

  testWidgets('Dictate — recording', (tester) async {
    await pump(tester, const DictationScreen());
    await tester.pump(const Duration(seconds: 12));
    await shot(tester, 'Dictate');
  });

  testWidgets('Dictate — recognised, editable', (tester) async {
    await pump(tester, const DictationScreen());
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Готово'));
    await settle(tester);
    await shot(tester, 'Dictate-Text');
  });

  // F14: into a project, "Разобрать" is offered under the words; pressed, the
  // proposal replaces them for correction; and with the keyboard up the words
  // keep most of what is left of the screen. The keyboard itself is not drawn
  // -- the bottom 330 px are simply what it would cover.
  const dom = ProjectDestination(projectId: 'prj_dom', name: 'Дом');

  testWidgets('Dictate-Project — "Разобрать" offered', (tester) async {
    await pump(tester, const DictationScreen(destination: dom));
    await tester.tap(find.text('Готово'));
    await settle(tester);
    await shot(tester, 'Dictate-Project');
  });

  testWidgets('Dictate-Proposal — the proposal, editable', (
    tester,
  ) async {
    await pump(tester, const DictationScreen(destination: dom));
    await tester.tap(find.text('Готово'));
    await settle(tester);
    await tester.tap(find.text('Разобрать'));
    await settle(tester);
    await shot(tester, 'Dictate-Proposal');
  });

  testWidgets('Dictate-Keyboard — editing on a phone', (tester) async {
    await pump(tester, const DictationScreen(destination: dom));
    await tester.tap(find.text('Готово'));
    await settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await settle(tester);
    await shot(tester, 'Dictate-Keyboard');
  });

  testWidgets('Desk-Plan — the wide window', (tester) async {
    await pump(tester, const ShellScreen(), w: 1440, h: 900);
    await shot(tester, 'Desk-Plan');
  });

  // Снимков «работы» и «истории» здесь больше нет: в F12 это были заглушки,
  // которые нечего было сверять, а с F13 у обоих режимов свои стенды --
  // `zz_capture_work_test.dart` и `zz_capture_history_test.dart`, каждый со
  // своим фейком сервера. Снимать их этим, чей фейк не знает ни `/focus`, ни
  // `/history`, значило бы фотографировать экран ошибки.
}

final GlobalKey _root = GlobalKey();

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

/// The fonts the app bundles, registered into the test's font collection.
///
/// `flutter test` ships one font and it is not either of these, so without this
/// every capture would be set in the fallback face at the fallback metrics --
/// i.e. it would be a picture of the layout with the typography removed, which
/// is half of what the comparison is about.
Future<void> _loadFonts() async {
  final assets = '${Directory.current.path}${Platform.pathSeparator}assets'
      '${Platform.pathSeparator}fonts';

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('$assets${Platform.pathSeparator}$file')
          .readAsBytesSync();
      loader.addFont(
        Future<ByteData>.value(ByteData.view(bytes.buffer)),
      );
    }
    await loader.load();
  }

  await load('Golos Text', <String>[
    'GolosText-Regular.ttf',
    'GolosText-Medium.ttf',
    'GolosText-SemiBold.ttf',
    'GolosText-Bold.ttf',
  ]);
  await load('Unbounded', <String>[
    'Unbounded-SemiBold.ttf',
    'Unbounded-Bold.ttf',
  ]);

  // The icon font too, from the SDK's own artifact cache. Without it every
  // glyph in the capture is a tofu box, and half of what these screens say
  // ("меньше текста, больше графики") is said with icons.
  // The Flutter SDK's own copy, found by walking up from whatever binary is
  // running this test (`flutter_tester` lives in
  // <sdk>/bin/cache/artifacts/engine/<platform>/) and falling back to the
  // machine's known SDK. Hard-coding one path only would make this harness
  // silently produce tofu on any other machine, which is the failure it exists
  // to catch.
  File? icons;
  var probe = Directory(File(Platform.resolvedExecutable).parent.path);
  for (var i = 0; i < 8; i++) {
    final candidate = File(
      '${probe.path}${Platform.pathSeparator}material_fonts'
      '${Platform.pathSeparator}materialicons-regular.otf',
    );
    if (candidate.existsSync()) {
      icons = candidate;
      break;
    }
    final artifacts = File(
      '${probe.path}${Platform.pathSeparator}artifacts'
      '${Platform.pathSeparator}material_fonts'
      '${Platform.pathSeparator}materialicons-regular.otf',
    );
    if (artifacts.existsSync()) {
      icons = artifacts;
      break;
    }
    if (probe.parent.path == probe.path) break;
    probe = probe.parent;
  }
  icons ??= File(
    'C:/FlutterSdk/flutter/bin/cache/artifacts/material_fonts/'
    'materialicons-regular.otf',
  );

  if (icons.existsSync()) {
    final bytes = icons.readAsBytesSync();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  } else {
    // Loud, because a capture full of tofu boxes looks like a layout bug and
    // is not one.
    // ignore: avoid_print
    print('WARNING: MaterialIcons not found — icons will render as boxes.');
  }
}

// --- the acceptance data, from the spec -----------------------------------

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

Map<String, dynamic> _task(
  String id,
  String pid,
  String title, {
  String status = 'pending',
  num position = 1000,
  bool isCurrent = false,
  String? remindAt,
  String? description,
  int age = 2,
}) => <String, dynamic>{
  'id': id,
  'projectId': pid,
  'title': title,
  'description': description,
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
      _task('t1', 'prj_dom', 'Вызвать курьера из Яндекс Маркета.',
          isCurrent: true, age: 2),
      _task('t2', 'prj_dom', 'Купить лампочки', position: 2000, age: 5),
      _task('t3', 'prj_dom', 'Заказать крючки для полок в ванной',
          position: 3000, age: 5),
      _task(
        't4',
        'prj_dom',
        'Посмотреть, почему не работает вентилятор в туалете. Позвонить в УК '
            'и спросить, чей это участок.',
        status: 'blocked',
        position: 4000,
        remindAt: _day(2),
        age: 3,
      ),
      _task('t5', 'prj_dom', 'Обеспечить доступ к полке в кладовке.',
          position: 5000, age: 2),
      _task('t6', 'prj_dom', 'Заменить болт на кухне в раковине.',
          position: 6000, age: 2),
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
      _task('t7', 'prj_tr', 'Потестить диктовку на телефоне',
          isCurrent: true, age: 4),
      _task('t8', 'prj_tr',
          'Адаптировать кнопку распознавания, размер шрифта и взаимное '
              'расположение полей',
          position: 2000, age: 4),
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
      _task('t9', 'prj_fam', 'Посмотреть статус Мишиной сим карточки.',
          isCurrent: true, age: 2),
      _task('t10', 'prj_fam', 'Записать Мишу к врачу', position: 2000, age: 2),
    ],
  },
  <String, dynamic>{
    'id': 'prj_avo',
    'name': 'Авоська',
    'scopeId': 'scope_main',
    'archivedAt': null,
    'createdAt': _iso(20),
    'updatedAt': _iso(1),
    'tasks': <Map<String, dynamic>>[
      _task('t11', 'prj_avo',
          'По наведению на штрих-код, выводить, что это, где ещё можно купить…',
          isCurrent: true, age: 1),
    ],
  },
];

final List<Map<String, dynamic>> _inbox = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'i1',
    'text': 'В проекте TaskRadar надо увеличить размер полей для ввода данных.',
    'createdAt': _iso(3),
    'updatedAt': _iso(3),
  },
  <String, dynamic>{
    'id': 'i2',
    'text': 'На общем экране не работает запись с первого раза.',
    'createdAt': _iso(3),
    'updatedAt': _iso(3),
  },
  <String, dynamic>{
    'id': 'i3',
    'text': 'Почему-то не работает знак, значок громкости.',
    'createdAt': _iso(3),
    'updatedAt': _iso(3),
  },
];

ResponseBody _respond(RequestOptions options) {
  final path = options.path.split('?').first;

  Object? body;
  if (path == '/board') {
    body = _board;
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
    body = _inbox;
  } else if (path == '/dictation/parse') {
    body = <String, dynamic>{
      'title': 'Купить кабель USB-C для монитора',
      'description': 'Длина около двух метров. Проверить, пришёл ли.',
      'remindDate': '2026-09-25',
      'remindTime': null,
    };
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
    body = <String, dynamic>{'ok': true};
  }

  return ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}
