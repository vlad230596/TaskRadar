import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The bytes of pictures waiting in the outbox (`OutboxKind.uploadAttachment`).
///
/// The picture is copied here the moment it is queued, not read from where
/// the picker left it: a gallery URI, a share-intent temp file or a cache
/// file can be gone by the time the network comes back, and for a picture
/// taken offline this copy is the only one the app can still reach. It is
/// deleted once the upload is `sent`, or when the entry is thrown away.
abstract class OutboxFileStore {
  /// Stores [bytes] as `<key>.<extension>` and returns the path to put in the
  /// entry's `localPath`. **Throws** when it could not -- then the picture is
  /// not queued, and the caller says so.
  Future<String> put(String key, Uint8List bytes, String extension);

  /// The bytes at [path], or null when they are gone.
  Future<Uint8List?> read(String path);

  /// Best effort.
  Future<void> delete(String path);
}

/// `<support>/outbox_files/<key>.<ext>` -- next to `outbox.v1.json`, in the
/// directory the user never sees.
class IoOutboxFileStore implements OutboxFileStore {
  IoOutboxFileStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const String folder = 'outbox_files';

  final Future<Directory> Function() _directory;

  @override
  Future<String> put(String key, Uint8List bytes, String extension) async {
    final root = await _directory();
    final dir = Directory('${root.path}${Platform.pathSeparator}$folder');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$key.$extension');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    return file.path;
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (error) {
      debugPrint('Outbox file $path unreadable: $error');
      return null;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Could not delete outbox file $path: $error');
    }
  }
}

/// In memory: the browser (no file system to copy into -- a picture queued
/// there survives until the tab is closed, not a reload) and tests.
class MemoryOutboxFileStore implements OutboxFileStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<String> put(String key, Uint8List bytes, String extension) async {
    final path = 'memory:$key.$extension';
    files[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<void> delete(String path) async => files.remove(path);
}
