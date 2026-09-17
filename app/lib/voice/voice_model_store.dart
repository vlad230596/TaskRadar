import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'voice_model.dart';

/// Where the speech model lives on disk, and how it gets there (F9).
///
/// ## The three jobs
///
/// **Find it.** [installed] answers "is dictation possible right now", and does
/// it by *looking at the files* rather than by trusting a flag in preferences:
/// a half-finished unpack, an app-data wipe or a user with a file manager all
/// produce a state where a flag would say yes and the recogniser would fail
/// with an FFI error nobody can read.
///
/// **Fetch it.** 163 MB over whatever connection is available, resumable only
/// in the sense that a failed attempt leaves nothing behind and can be started
/// again. The archive is unpacked in a background isolate: `extractFileToDisk`
/// streams through it (so memory stays flat) but it is still tens of seconds of
/// solid CPU, and doing that on the UI isolate would freeze the app.
///
/// **Delete it.** Quarter of a gigabyte is worth being able to take back.
///
/// ## Why application-support and not the documents directory
///
/// Same reason as the board snapshot: on Android the documents directory is
/// visible in the file manager and is backed up, and neither is right for a
/// redownloadable blob of model weights. Application support is
/// `/data/data/<pkg>/files` on Android and `%APPDATA%\<app>` on Windows.
class VoiceModelStore {
  VoiceModelStore({
    Dio? downloader,
    Future<Directory> Function()? directory,
    Future<void> Function(String archivePath, String destination)? unpack,
  }) : _downloader = downloader ?? Dio(),
       _directory = directory ?? getApplicationSupportDirectory,
       _unpack = unpack ?? _unpackInIsolate;

  final Dio _downloader;
  final Future<Directory> Function() _directory;
  final Future<void> Function(String archivePath, String destination) _unpack;

  /// The folder all models live under, so that deleting dictation entirely is
  /// one `rm -r` and a future second model does not have to invent a layout.
  static const String folderName = 'voice-models';

  /// The model on disk, or null if it is not there (or not whole).
  Future<InstalledVoiceModel?> installed(VoiceModel model) async {
    try {
      final directory = await _modelDirectory(model);
      if (!await directory.exists()) return null;

      final files = await directory
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      // Discovered rather than hard-coded, because the file names are the
      // archive's business and not the contract: every published export so far
      // is `model.int8.onnx` + `tokens.txt`, and a build that named the graph
      // differently would otherwise be a crash instead of a shrug.
      final graph = files.where((f) => f.path.endsWith('.onnx')).toList()
        ..sort((a, b) => a.path.length.compareTo(b.path.length));
      final tokens = files.where((f) => f.path.endsWith('tokens.txt')).toList();
      if (graph.isEmpty || tokens.isEmpty) return null;

      var bytes = 0;
      for (final file in files) {
        bytes += await file.length();
      }

      return InstalledVoiceModel(
        model: model,
        modelPath: graph.first.path,
        tokensPath: tokens.first.path,
        bytesOnDisk: bytes,
      );
    } catch (error) {
      debugPrint('Could not inspect the voice model: $error');
      return null;
    }
  }

  /// Downloads and unpacks [model], reporting progress.
  ///
  /// [onProgress] receives `(received, total)` in bytes while downloading;
  /// `total` is -1 until the server says how long the body is. [onUnpacking] is
  /// called once, when the bytes are all there and the slow silent part starts.
  ///
  /// Throws on failure, leaving nothing half-installed behind: the archive goes
  /// to a temporary name and the destination is wiped first, so a failed
  /// attempt can simply be repeated.
  Future<InstalledVoiceModel> install(
    VoiceModel model, {
    void Function(int received, int total)? onProgress,
    void Function()? onUnpacking,
    CancelToken? cancelToken,
  }) async {
    final directory = await _modelDirectory(model);
    final archive = File('${directory.path}.tar.bz2');

    // A previous attempt that died mid-unpack would otherwise leave files that
    // `installed` counts as a model and the recogniser cannot load.
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.parent.create(recursive: true);
    if (await archive.exists()) await archive.delete();

    try {
      await _downloader.download(
        model.archiveUrl,
        archive.path,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );

      onUnpacking?.call();
      await _unpack(archive.path, directory.path);
    } catch (error) {
      await _cleanUp(directory, archive);
      rethrow;
    }

    // The archive holds a top-level folder of its own, so the files land one
    // level deeper than the destination. Nothing here flattens them: `installed`
    // searches recursively for exactly that reason.
    await _delete(archive);

    final result = await installed(model);
    if (result == null) {
      await _cleanUp(directory, archive);
      throw StateError(
        'the downloaded archive did not contain a model and tokens.txt',
      );
    }
    return result;
  }

  /// Removes the model from disk. Never throws: the worst case is that the
  /// quarter-gigabyte is still there, and the settings screen will say so on
  /// its next read.
  Future<void> remove(VoiceModel model) async {
    try {
      final directory = await _modelDirectory(model);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      debugPrint('Could not remove the voice model: $error');
    }
  }

  Future<Directory> _modelDirectory(VoiceModel model) async {
    final root = await _directory();
    final separator = Platform.pathSeparator;
    return Directory('${root.path}$separator$folderName$separator${model.id}');
  }

  Future<void> _cleanUp(Directory directory, File archive) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      debugPrint('Could not clean up a failed model install: $error');
    }
    await _delete(archive);
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Could not delete the model archive: $error');
    }
  }
}

/// Unpacks off the UI isolate.
///
/// `extractFileToDisk` is pure Dart over file paths, so it moves to another
/// isolate with no ceremony at all -- and it has to, because bzip2 over 160 MB
/// is tens of seconds during which the app would not paint a frame.
Future<void> _unpackInIsolate(String archivePath, String destination) {
  return Isolate.run(() => extractFileToDisk(archivePath, destination));
}
