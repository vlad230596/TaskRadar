import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Pictures already fetched, by attachment id.
///
/// An attachment never changes after upload (`ETag` = sha256, `immutable`),
/// so a copy is good forever and its id is the whole key: no revalidation,
/// no expiry -- only a size cap, oldest first, so a phone does not fill up
/// with full-size photos looked at once.
abstract class AttachmentCache {
  Future<Uint8List?> read(String attachmentId, {required bool thumb});

  /// Best effort: a failure costs a later re-download, nothing else.
  Future<void> write(
    String attachmentId,
    Uint8List bytes, {
    required bool thumb,
  });
}

/// `<support>/attachment_cache/<id>` and `<id>.thumb`.
class IoAttachmentCache implements AttachmentCache {
  IoAttachmentCache({
    Future<Directory> Function()? directory,
    this.maxBytes = 300 * 1024 * 1024,
  }) : _directory = directory ?? getApplicationSupportDirectory;

  static const String folder = 'attachment_cache';

  final Future<Directory> Function() _directory;

  /// What the folder may hold before the oldest files go.
  final int maxBytes;

  Future<Directory> _folder() async {
    final root = await _directory();
    return Directory('${root.path}${Platform.pathSeparator}$folder');
  }

  Future<File> _file(String id, bool thumb) async {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dir = await _folder();
    return File(
      '${dir.path}${Platform.pathSeparator}$safe${thumb ? '.thumb' : ''}',
    );
  }

  @override
  Future<Uint8List?> read(String attachmentId, {required bool thumb}) async {
    try {
      final file = await _file(attachmentId, thumb);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (error) {
      debugPrint('Attachment cache unreadable: $error');
      return null;
    }
  }

  @override
  Future<void> write(
    String attachmentId,
    Uint8List bytes, {
    required bool thumb,
  }) async {
    try {
      final file = await _file(attachmentId, thumb);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      await _trim(file.parent);
    } catch (error) {
      debugPrint('Could not cache attachment $attachmentId: $error');
    }
  }

  Future<void> _trim(Directory dir) async {
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      files.add((entity, stat));
      total += stat.size;
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= maxBytes) break;
      try {
        await file.delete();
        total -= stat.size;
      } catch (_) {
        // In use, or gone already; the next write tries again.
      }
    }
  }
}

/// In memory, for the browser (whose own HTTP cache sees these requests
/// anyway) and for tests.
class MemoryAttachmentCache implements AttachmentCache {
  final Map<String, Uint8List> entries = <String, Uint8List>{};

  String _key(String id, bool thumb) => thumb ? '$id.thumb' : id;

  @override
  Future<Uint8List?> read(String attachmentId, {required bool thumb}) async =>
      entries[_key(attachmentId, thumb)];

  @override
  Future<void> write(
    String attachmentId,
    Uint8List bytes, {
    required bool thumb,
  }) async {
    entries[_key(attachmentId, thumb)] = bytes;
  }
}
