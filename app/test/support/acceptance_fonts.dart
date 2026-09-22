import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

/// Шрифты приложения, зарегистрированные в шрифтовой коллекции теста.
///
/// `flutter test` несёт один шрифт, и это не Golos и не Unbounded: без этой
/// загрузки каждый снимок был бы набран запасной гарнитурой с её метриками — то
/// есть картинкой раскладки без типографики, а это половина того, ради чего
/// снимки и делаются.
///
/// Живёт в `support/`, потому что снимающих тестов уже два (`zz_capture_*`), и
/// второй копией этой функции отличались бы не картинки, а способ их получить.
Future<void> loadAcceptanceFonts() async {
  final assets =
      '${Directory.current.path}${Platform.pathSeparator}assets'
      '${Platform.pathSeparator}fonts';

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File(
        '$assets${Platform.pathSeparator}$file',
      ).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
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

  // И шрифт значков, из артефактов самого SDK. Без него каждый глиф на снимке —
  // квадратик, а половина того, что говорят эти экраны («меньше текста, больше
  // графики»), сказана значками.
  //
  // Путь ищется вверх от работающего бинаря (`flutter_tester` лежит в
  // <sdk>/bin/cache/artifacts/engine/<platform>/) с запасным вариантом на
  // известный SDK этой машины: жёстко прописанный единственный путь означал бы
  // молчаливые квадратики на любой другой.
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
    // Громко: снимок в квадратиках выглядит как ошибка вёрстки, а это не она.
    // ignore: avoid_print
    print('WARNING: MaterialIcons not found — icons will render as boxes.');
  }
}
