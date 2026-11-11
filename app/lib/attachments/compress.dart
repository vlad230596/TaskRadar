import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/attachment_api.dart' show extensionForMime, sniffImageMime;

/// Shrinking a picture on the phone before it goes up
/// (`design/task-editor-spec.md` §6).
///
/// Nine pictures in ten are screenshots, so the rules protect text:
///
/// - the long side is at most [maxLongSide] px;
/// - a PNG stays a PNG while it is at most [pngKeepBytes] -- a screenshot
///   re-encoded as JPEG smears its letters -- and becomes WebP q85 above that;
/// - a photo (JPEG) is re-encoded as JPEG q85 without EXIF (no GPS leaves the
///   phone; the server strips it again anyway);
/// - a WebP is only touched when it is too large in pixels.
///
/// The decision ([planCompression]) is plain Dart and tested; the encoding is
/// behind [ImageEncoder], which only Android and iOS have (the plugin). On
/// Windows and the web the picked file goes as it is -- the server keeps its
/// own limits and strips metadata itself.

/// The long side a picture is shrunk to.
const int maxLongSide = 3000;

/// The largest PNG that is sent as a PNG.
const int pngKeepBytes = 4 * 1024 * 1024;

/// The quality of every lossy re-encode.
const int uploadQuality = 85;

/// The formats an [ImageEncoder] writes.
enum ImageEncoding {
  png('image/png'),
  jpeg('image/jpeg'),
  webp('image/webp');

  const ImageEncoding(this.mime);

  final String mime;
}

/// One re-encode: to [format], at [width] x [height].
@immutable
class CompressionStep {
  const CompressionStep({
    required this.format,
    required this.width,
    required this.height,
    this.quality = uploadQuality,
    this.webpIfLarger = false,
  });

  final ImageEncoding format;
  final int width;
  final int height;
  final int quality;

  /// A PNG shrunk in pixels may still be over [pngKeepBytes]; then it is
  /// encoded once more, as WebP.
  final bool webpIfLarger;

  @override
  bool operator ==(Object other) =>
      other is CompressionStep &&
      other.format == format &&
      other.width == width &&
      other.height == height &&
      other.quality == quality &&
      other.webpIfLarger == webpIfLarger;

  @override
  int get hashCode => Object.hash(format, width, height, quality, webpIfLarger);

  @override
  String toString() =>
      'CompressionStep(${format.name} ${width}x$height q$quality'
      '${webpIfLarger ? ', webp if larger' : ''})';
}

/// [width] x [height] scaled so that the long side is at most [maxLongSide].
(int, int) fitLongSide(int width, int height, {int limit = maxLongSide}) {
  final long = width > height ? width : height;
  if (long <= limit) return (width, height);
  final scale = limit / long;
  int side(int value) {
    final scaled = (value * scale).round();
    return scaled < 1 ? 1 : scaled;
  }

  return (side(width), side(height));
}

/// What to do with a picture of [mime], [width] x [height], [sizeBytes]
/// long: null means send it as it is.
CompressionStep? planCompression({
  required String mime,
  required int width,
  required int height,
  required int sizeBytes,
}) {
  if (width <= 0 || height <= 0) return null;
  final (w, h) = fitLongSide(width, height);
  final shrink = w != width || h != height;
  switch (mime) {
    case 'image/png':
      if (shrink) {
        return CompressionStep(
          format: ImageEncoding.png,
          width: w,
          height: h,
          webpIfLarger: true,
        );
      }
      if (sizeBytes <= pngKeepBytes) return null;
      return CompressionStep(format: ImageEncoding.webp, width: w, height: h);
    case 'image/jpeg':
      return CompressionStep(format: ImageEncoding.jpeg, width: w, height: h);
    case 'image/webp':
      if (!shrink) return null;
      return CompressionStep(format: ImageEncoding.webp, width: w, height: h);
  }
  return null;
}

/// The pixel size of a PNG, JPEG or WebP, read from its header; null when it
/// is none of those or the header is cut short.
(int, int)? imageDimensions(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int u8(int i) => bytes[i];
  bool has(int length) => bytes.length >= length;

  // PNG: IHDR is the first chunk, width and height big-endian at 16 and 20.
  if (has(24) &&
      u8(0) == 0x89 &&
      u8(1) == 0x50 &&
      u8(2) == 0x4E &&
      u8(3) == 0x47) {
    return (data.getUint32(16), data.getUint32(20));
  }

  // JPEG: walk the markers to the first SOFn.
  if (has(4) && u8(0) == 0xFF && u8(1) == 0xD8) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (u8(i) != 0xFF) {
        i++;
        continue;
      }
      final marker = u8(i + 1);
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final length = data.getUint16(i + 2);
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        return (data.getUint16(i + 7), data.getUint16(i + 5));
      }
      i += 2 + length;
    }
    return null;
  }

  // WebP: RIFF....WEBP, then VP8 / VP8L / VP8X.
  if (has(30) &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    switch (chunk) {
      case 'VP8 ':
        return (
          data.getUint16(26, Endian.little) & 0x3FFF,
          data.getUint16(28, Endian.little) & 0x3FFF,
        );
      case 'VP8L':
        final b0 = u8(21), b1 = u8(22), b2 = u8(23), b3 = u8(24);
        final w = 1 + (((b1 & 0x3F) << 8) | b0);
        final h = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6));
        return (w, h);
      case 'VP8X':
        int u24(int at) => u8(at) | (u8(at + 1) << 8) | (u8(at + 2) << 16);
        return (1 + u24(24), 1 + u24(27));
    }
  }
  return null;
}

/// Re-encodes pictures. [encode] scales to exactly [width] x [height]
/// (aspect kept by the caller) and drops metadata.
abstract interface class ImageEncoder {
  Future<Uint8List> encode(
    Uint8List bytes, {
    required int width,
    required int height,
    required ImageEncoding format,
    required int quality,
  });
}

/// [ImageEncoder] over `flutter_image_compress` (Android, iOS).
class PluginImageEncoder implements ImageEncoder {
  const PluginImageEncoder();

  @override
  Future<Uint8List> encode(
    Uint8List bytes, {
    required int width,
    required int height,
    required ImageEncoding format,
    required int quality,
  }) {
    // The plugin scales by max(1, min(w / minWidth, h / minHeight)), so
    // passing the target size itself lands exactly on it.
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: width,
      minHeight: height,
      quality: quality,
      format: switch (format) {
        ImageEncoding.png => CompressFormat.png,
        ImageEncoding.jpeg => CompressFormat.jpeg,
        ImageEncoding.webp => CompressFormat.webp,
      },
      keepExif: false,
    );
  }
}

/// The encoder of this platform, or null where pictures go as they are.
final imageEncoderProvider = Provider<ImageEncoder?>((ref) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => const PluginImageEncoder(),
    _ => null,
  };
});

/// [file], made ready to upload by the rules above. Anything that cannot be
/// read as a picture, or fails to encode, is returned unchanged -- the
/// queue refuses what is not a picture, and a big picture beats no picture.
Future<XFile> compressForUpload(XFile file, ImageEncoder? encoder) async {
  if (encoder == null) return file;
  try {
    final bytes = await file.readAsBytes();
    final mime = sniffImageMime(bytes);
    final size = imageDimensions(bytes);
    if (mime == null || size == null) return file;
    final step = planCompression(
      mime: mime,
      width: size.$1,
      height: size.$2,
      sizeBytes: bytes.length,
    );
    if (step == null) return file;

    var format = step.format;
    var out = await encoder.encode(
      bytes,
      width: step.width,
      height: step.height,
      format: format,
      quality: step.quality,
    );
    if (step.webpIfLarger && out.length > pngKeepBytes) {
      format = ImageEncoding.webp;
      out = await encoder.encode(
        bytes,
        width: step.width,
        height: step.height,
        format: format,
        quality: step.quality,
      );
    }
    final resized = step.width != size.$1 || step.height != size.$2;
    // Re-encoding at the same size only to come out bigger is no gain.
    if (!resized && format.mime == mime && out.length >= bytes.length) {
      return file;
    }
    final name = '${_baseName(file.name)}.${extensionForMime(format.mime)}';
    // `path` too: on io `XFile.name` is read from the path, not `name`.
    return XFile.fromData(
      out,
      path: name,
      name: name,
      mimeType: format.mime,
      length: out.length,
    );
  } catch (error) {
    debugPrint('Picture not compressed (${file.name}): $error');
    return file;
  }
}

/// [compressForUpload] for each of [files], in order.
Future<List<XFile>> compressAllForUpload(
  List<XFile> files,
  ImageEncoder? encoder,
) async => <XFile>[for (final f in files) await compressForUpload(f, encoder)];

String _baseName(String name) {
  final slash = name.lastIndexOf(RegExp(r'[/\\]'));
  final bare = slash >= 0 ? name.substring(slash + 1) : name;
  final dot = bare.lastIndexOf('.');
  final base = dot > 0 ? bare.substring(0, dot) : bare;
  return base.isEmpty ? 'picture' : base;
}
