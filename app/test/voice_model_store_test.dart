import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/voice/voice_model.dart';
import 'package:taskradar/voice/voice_model_store.dart';

/// Where the speech model lives, and how it gets there (F9).
///
/// Run against a **real directory**, with only two things faked: the HTTP
/// transport (163 MB is not a unit test) and the unpacking step, which is
/// `archive`'s job rather than this class's. What is left is exactly what this
/// class is responsible for and what can actually go wrong on a phone: deciding
/// whether a model is present by looking at the files, leaving nothing behind
/// when an install fails halfway, and refusing an archive that turned out not to
/// contain a model.
void main() {
  late Directory directory;
  late _FakeDownloads downloads;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('taskradar_voice_test');
    downloads = _FakeDownloads();
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  /// A store whose unpack step writes [files] into the destination, as the real
  /// archive would.
  VoiceModelStore storeThatUnpacks(
    Map<String, String> files, {
    Object? unpackFailure,
  }) {
    return VoiceModelStore(
      downloader: downloads.dio,
      directory: () async => directory,
      unpack: (archivePath, destination) async {
        if (unpackFailure != null) throw unpackFailure;
        // The real archive holds a folder of its own, so files land one level
        // below the destination. Reproduced here because it is precisely what
        // `installed` has to cope with.
        final inner = Directory('$destination/inner')..createSync(recursive: true);
        files.forEach((name, contents) {
          File('${inner.path}/$name').writeAsStringSync(contents);
        });
      },
    );
  }

  final model = VoiceModel.gigaAmV3Punct;

  group('is the model there', () {
    test('no, when nothing has been downloaded', () async {
      final store = storeThatUnpacks(const <String, String>{});

      expect(await store.installed(model), isNull);
    });

    test('yes, with the graph and the tokens found by looking', () async {
      final store = storeThatUnpacks(const <String, String>{
        'model.int8.onnx': 'weights',
        'tokens.txt': 'а б в',
      });

      final installed = await store.install(model);

      // Discovered rather than assumed: the names are the archive's business,
      // and a build that spelled them differently should be a shrug, not a
      // crash inside FFI.
      expect(installed.modelPath, endsWith('model.int8.onnx'));
      expect(installed.tokensPath, endsWith('tokens.txt'));
      expect(installed.bytesOnDisk, greaterThan(0));
      expect(await store.installed(model), isNotNull);
    });

    test('no, when the folder holds files but not a model', () async {
      // The state a half-finished unpack leaves behind. A flag in preferences
      // would say "installed" here and the recogniser would fail with an FFI
      // error nobody can read.
      final store = storeThatUnpacks(const <String, String>{'README.md': 'hi'});

      await expectLater(store.install(model), throwsA(isA<StateError>()));
      expect(await store.installed(model), isNull);
    });
  });

  group('installing', () {
    test('asks for the pinned archive and reports progress', () async {
      final store = storeThatUnpacks(const <String, String>{
        'model.int8.onnx': 'weights',
        'tokens.txt': 'а б в',
      });
      final seen = <int>[];

      await store.install(model, onProgress: (received, _) => seen.add(received));

      expect(downloads.requested.single, model.archiveUrl);
      expect(seen, isNotEmpty);
    });

    test('says when the slow silent part starts', () async {
      // Unpacking reports no progress of its own and takes tens of seconds; a
      // bar sitting at 100% in silence looks exactly like a hang.
      final store = storeThatUnpacks(const <String, String>{
        'model.int8.onnx': 'weights',
        'tokens.txt': 'а б в',
      });
      var unpacking = false;

      await store.install(model, onUnpacking: () => unpacking = true);

      expect(unpacking, isTrue);
    });

    test('leaves nothing behind when the download fails', () async {
      downloads.failure = DioException.connectionError(
        requestOptions: RequestOptions(path: '/'),
        reason: 'no network',
      );
      final store = storeThatUnpacks(const <String, String>{});

      await expectLater(store.install(model), throwsA(isA<DioException>()));

      // Nothing half-installed and no 163 MB archive sitting in app storage: a
      // failed attempt has to be repeatable, not something to clean up by hand.
      expect(await store.installed(model), isNull);
      expect(_leftovers(directory), isEmpty);
    });

    test('leaves nothing behind when the unpack fails', () async {
      final store = storeThatUnpacks(
        const <String, String>{},
        unpackFailure: const FileSystemException('no space left on device'),
      );

      await expectLater(store.install(model), throwsA(isA<FileSystemException>()));

      expect(await store.installed(model), isNull);
      expect(_leftovers(directory), isEmpty);
    });

    test('a retry after a broken install starts from nothing', () async {
      final broken = storeThatUnpacks(const <String, String>{'README.md': 'hi'});
      await expectLater(broken.install(model), throwsA(isA<StateError>()));

      final good = storeThatUnpacks(const <String, String>{
        'model.int8.onnx': 'weights',
        'tokens.txt': 'а б в',
      });
      final installed = await good.install(model);

      expect(installed.modelPath, endsWith('model.int8.onnx'));
    });
  });

  test('removing takes the quarter of a gigabyte back', () async {
    final store = storeThatUnpacks(const <String, String>{
      'model.int8.onnx': 'weights',
      'tokens.txt': 'а б в',
    });
    await store.install(model);

    await store.remove(model);

    expect(await store.installed(model), isNull);
  });
}

/// Everything under the store's folder, so a test can assert that a failed
/// install left no archive and no partial directory.
List<String> _leftovers(Directory root) {
  final folder = Directory('${root.path}/${VoiceModelStore.folderName}');
  if (!folder.existsSync()) return const <String>[];
  return folder.listSync(recursive: true).map((e) => e.path).toList();
}

/// A `Dio` whose transport answers every download with a few bytes.
class _FakeDownloads {
  _FakeDownloads() {
    dio.httpClientAdapter = _Adapter(this);
  }

  final Dio dio = Dio();
  final List<String> requested = <String>[];
  Object? failure;

  ResponseBody answer(RequestOptions options) {
    requested.add(options.uri.toString());
    final failure = this.failure;
    if (failure != null) throw failure;

    final bytes = Uint8List.fromList(List<int>.filled(2048, 7));
    return ResponseBody(
      Stream<Uint8List>.value(bytes),
      200,
      headers: <String, List<String>>{
        Headers.contentLengthHeader: <String>['${bytes.length}'],
      },
    );
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this._downloads);

  final _FakeDownloads _downloads;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => _downloads.answer(options);

  @override
  void close({bool force = false}) {}
}
