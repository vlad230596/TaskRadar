import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_handler/share_handler.dart';
import 'package:taskradar/attachments/clipboard_image.dart';
import 'package:taskradar/attachments/compress.dart';
import 'package:taskradar/attachments/pick.dart';
import 'package:taskradar/attachments/share_intake.dart';

/// WP6's plain logic: the compression rules, image headers, the picker's
/// limit, pasted and shared files (`design/task-editor-spec.md` §6).
void main() {
  Uint8List png(int width, int height, {int padTo = 0}) {
    final bytes = Uint8List(padTo > 33 ? padTo : 33);
    bytes.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    bytes.setAll(8, <int>[0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
    final data = ByteData.sublistView(bytes);
    data.setUint32(16, width);
    data.setUint32(20, height);
    return bytes;
  }

  Uint8List jpeg(int width, int height) {
    final b = BytesBuilder()
      ..add(<int>[0xFF, 0xD8])
      // APP0, 16 bytes long.
      ..add(<int>[0xFF, 0xE0, 0x00, 0x10])
      ..add(List<int>.filled(14, 0))
      // SOF0: length 17, precision 8, height, width.
      ..add(<int>[0xFF, 0xC0, 0x00, 0x11, 0x08])
      ..add(<int>[height >> 8, height & 0xFF, width >> 8, width & 0xFF])
      ..add(List<int>.filled(12, 0));
    return b.toBytes();
  }

  Uint8List webpX(int width, int height) {
    final bytes = Uint8List(40);
    bytes.setAll(0, ascii.encode('RIFF'));
    bytes.setAll(8, ascii.encode('WEBPVP8X'));
    void u24(int at, int v) {
      bytes[at] = v & 0xFF;
      bytes[at + 1] = (v >> 8) & 0xFF;
      bytes[at + 2] = (v >> 16) & 0xFF;
    }

    u24(24, width - 1);
    u24(27, height - 1);
    return bytes;
  }

  group('image headers', () {
    test('reads PNG, JPEG and WebP sizes', () {
      expect(imageDimensions(png(1080, 2400)), (1080, 2400));
      expect(imageDimensions(jpeg(4032, 3024)), (4032, 3024));
      expect(imageDimensions(webpX(5000, 100)), (5000, 100));
      expect(imageDimensions(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    });
  });

  group('the compression rules', () {
    test('a screenshot under the limits goes as it is', () {
      expect(
        planCompression(
          mime: 'image/png',
          width: 1080,
          height: 2400,
          sizeBytes: 900000,
        ),
        isNull,
      );
    });

    test('a long PNG is shrunk as a PNG, WebP only if still too big', () {
      expect(
        planCompression(
          mime: 'image/png',
          width: 1440,
          height: 9000,
          sizeBytes: 3000000,
        ),
        const CompressionStep(
          format: ImageEncoding.png,
          width: 480,
          height: 3000,
          webpIfLarger: true,
        ),
      );
    });

    test('a heavy PNG within the pixels becomes WebP q85', () {
      expect(
        planCompression(
          mime: 'image/png',
          width: 2000,
          height: 2000,
          sizeBytes: pngKeepBytes + 1,
        ),
        const CompressionStep(
          format: ImageEncoding.webp,
          width: 2000,
          height: 2000,
        ),
      );
    });

    test('a photo is always re-encoded as JPEG q85, the long side ≤ 3000', () {
      expect(
        planCompression(
          mime: 'image/jpeg',
          width: 4000,
          height: 3000,
          sizeBytes: 5000000,
        ),
        const CompressionStep(
          format: ImageEncoding.jpeg,
          width: 3000,
          height: 2250,
        ),
      );
      expect(
        planCompression(
          mime: 'image/jpeg',
          width: 800,
          height: 600,
          sizeBytes: 90000,
        )?.format,
        ImageEncoding.jpeg,
      );
    });

    test('a WebP is touched only when too large in pixels', () {
      expect(
        planCompression(
          mime: 'image/webp',
          width: 1000,
          height: 1000,
          sizeBytes: 9000000,
        ),
        isNull,
      );
      expect(
        planCompression(
          mime: 'image/webp',
          width: 6000,
          height: 3000,
          sizeBytes: 100,
        ),
        const CompressionStep(
          format: ImageEncoding.webp,
          width: 3000,
          height: 1500,
        ),
      );
    });
  });

  group('compressForUpload', () {
    test('without an encoder (Windows, web) the file goes unchanged', () async {
      final file = XFile.fromData(png(5000, 5000), name: 'a.png');
      expect(await compressForUpload(file, null), same(file));
    });

    test(
      'a long PNG over 4 MB after shrinking is encoded again as WebP',
      () async {
        final encoder = _FakeEncoder(
          (format) => format == ImageEncoding.png
              ? Uint8List(pngKeepBytes + 10)
              : Uint8List(1000),
        );
        final out = await compressForUpload(
          XFile.fromData(png(1500, 6000), path: 'Screenshot_1.png'),
          encoder,
        );
        expect(encoder.calls, <String>['png 750x3000', 'webp 750x3000']);
        expect(out.name, 'Screenshot_1.webp');
        expect(await out.length(), 1000);
      },
    );

    test(
      'a re-encode that comes out bigger at the same size is dropped',
      () async {
        final original = jpeg(800, 600);
        final encoder = _FakeEncoder((_) => Uint8List(original.length + 100));
        final file = XFile.fromData(original, name: 'p.jpg');
        expect(await compressForUpload(file, encoder), same(file));
      },
    );

    test('an encoder failure sends the original', () async {
      final encoder = _FakeEncoder((_) => throw StateError('boom'));
      final file = XFile.fromData(jpeg(4000, 3000), name: 'p.jpg');
      expect(await compressForUpload(file, encoder), same(file));
    });
  });

  group('picking', () {
    test('never more than 30 in all; the rest are counted', () async {
      final source = _FakeSource(<XFile>[
        for (var i = 0; i < 5; i++) XFile.fromData(png(10, 10), path: '$i.png'),
      ]);
      final picked = await pickPictures(source, null, current: 27);
      expect(source.limits, <int?>[3]);
      expect(picked.files.map((f) => f.name), <String>[
        '0.png',
        '1.png',
        '2.png',
      ]);
      expect(picked.dropped, 2);
      expect(droppedPicturesMessage(picked.dropped), contains('30'));
    });

    test('a full task does not open the picker', () async {
      final source = _FakeSource(const <XFile>[]);
      final picked = await pickPictures(source, null, current: 30);
      expect(picked.isEmpty, isTrue);
      expect(source.limits, isEmpty);
    });
  });

  group('pasting', () {
    test('clipboard bytes become a named file of their type', () async {
      final file = pastedPicture(png(2, 2))!;
      expect(file.name, endsWith('.png'));
      expect(file.mimeType, 'image/png');
      expect(pastedPicture(Uint8List.fromList(utf8.encode('text'))), isNull);
    });

    test('a keyboard insertion with bytes is a picture, a bare URI is not', () {
      expect(
        keyboardPicture(
          KeyboardInsertedContent(
            mimeType: 'image/png',
            uri: 'content://x',
            data: png(4, 4),
          ),
        )?.mimeType,
        'image/png',
      );
      expect(
        keyboardPicture(
          const KeyboardInsertedContent(
            mimeType: 'image/png',
            uri: 'content://x',
          ),
        ),
        isNull,
      );
    });
  });

  group('sharing in', () {
    test('only image attachments are taken', () {
      final media = SharedMedia(
        content: 'https://example.org',
        attachments: <SharedAttachment?>[
          SharedAttachment(path: '/a.png', type: SharedAttachmentType.image),
          SharedAttachment(path: '/b.pdf', type: SharedAttachmentType.file),
          null,
          SharedAttachment(path: '', type: SharedAttachmentType.image),
        ],
      );
      expect(sharedPictures(media).map((f) => f.path), <String>['/a.png']);
      expect(sharedPictures(null), isEmpty);
    });

    test('the closing sentence says what did not go in', () {
      expect(
        shareDeliveryMessage(
          const ShareDelivery(projectId: 'p', taskId: 't', added: 2),
        ),
        isNull,
      );
      expect(
        shareDeliveryMessage(
          const ShareDelivery(
            projectId: 'p',
            taskId: 'local:outbox:k',
            added: 1,
            refused: 1,
          ),
        ),
        allOf(contains('когда будет сеть'), contains('PNG, JPEG или WebP')),
      );
    });
  });
}

class _FakeEncoder implements ImageEncoder {
  _FakeEncoder(this.result);

  final Uint8List Function(ImageEncoding format) result;
  final List<String> calls = <String>[];

  @override
  Future<Uint8List> encode(
    Uint8List bytes, {
    required int width,
    required int height,
    required ImageEncoding format,
    required int quality,
  }) async {
    calls.add('${format.name} ${width}x$height');
    return result(format);
  }
}

class _FakeSource implements PictureSource {
  _FakeSource(this.files);

  final List<XFile> files;
  final List<int?> limits = <int?>[];

  @override
  Future<List<XFile>> pickImages({int? limit}) async {
    limits.add(limit);
    return files;
  }
}
