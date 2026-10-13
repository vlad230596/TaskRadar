import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/voice/dictation_archive.dart';

/// The debug copies of dictations: kept with their text, newest first, never
/// more than the limit.
void main() {
  late Directory root;
  late DictationArchive archive;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('archive_test');
    archive = DictationArchive(directory: () async => root, limit: 3);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> recording(String name, int bytes) async {
    final file = File('${root.path}${Platform.pathSeparator}$name.wav');
    await file.writeAsBytes(List<int>.filled(bytes, 0));
    return file.path;
  }

  test('keeps a copy with the text, and leaves the original alone', () async {
    final path = await recording('rec', 44 + 32000);
    await archive.keep(
      path,
      text: 'купить хлеб',
      at: DateTime.utc(2026, 10, 14, 9),
    );

    expect(await File(path).exists(), isTrue);
    final items = await archive.list();
    expect(items, hasLength(1));
    expect(items.single.text, 'купить хлеб');
    expect(items.single.length, const Duration(seconds: 1));
    expect(items.single.recordedAt, DateTime.utc(2026, 10, 14, 9));
  });

  test('lists newest first and drops the oldest past the limit', () async {
    final path = await recording('rec', 100);
    for (var i = 0; i < 5; i++) {
      await archive.keep(
        path,
        text: 'запись $i',
        at: DateTime.utc(2026, 10, 14, 9, i),
      );
    }

    final items = await archive.list();
    expect(items.map((item) => item.text), <String>[
      'запись 4',
      'запись 3',
      'запись 2',
    ]);
  });

  test('silence and a failed recognition are told apart', () async {
    final path = await recording('rec', 100);
    await archive.keep(path, text: '', at: DateTime.utc(2026, 10, 14, 9));
    await archive.keep(path, at: DateTime.utc(2026, 10, 14, 10));

    final items = await archive.list();
    expect(items.map((item) => item.text), <String?>[null, '']);
  });

  test('a missing file is no error, and clear empties the archive', () async {
    await archive.keep('${root.path}/nope.wav', text: 'x');
    expect(await archive.list(), isEmpty);

    await archive.keep(await recording('rec', 100), text: 'x');
    await archive.clear();
    expect(await archive.list(), isEmpty);
  });
}
