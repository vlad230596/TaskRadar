import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The last few dictations, kept on this device for debugging (14.10.2026).
///
/// ## Why it exists
///
/// When a dictated word comes out wrong there are two suspects -- the speech
/// recogniser and the person -- and only the recording can tell them apart.
/// So each recording is copied here before the recorder deletes it, next to
/// the text it was recognised as, and the debug screen plays it back.
///
/// ## What it is not
///
/// Not a backup and not a feature: [limit] recordings, the oldest dropped
/// first, in the app's private support folder. Nothing here is ever sent to
/// the server -- the user decided that the audio stays on the device.
///
/// Every failure is swallowed with a log line: a debug copy that could not
/// be written must never cost the dictation itself.
class DictationArchive {
  DictationArchive({Future<Directory> Function()? directory, this.limit = 10})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  /// How many recordings are kept.
  final int limit;

  Future<Directory> _folder() async {
    final base = await _directory();
    final folder = Directory('${base.path}${Platform.pathSeparator}dictations');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  /// Copies the recording at [wavPath] in, with [text] as recognised (empty
  /// for "ничего не расслышали", null when recognition failed), and drops
  /// the oldest beyond [limit].
  Future<void> keep(String wavPath, {String? text, DateTime? at}) async {
    try {
      final source = File(wavPath);
      // Synchronous on purpose: a widget test's fake clock never completes
      // real file I/O, and its fake recorders hand over paths that do not
      // exist -- this way they stop here instead of hanging the test.
      if (!source.existsSync()) return;
      final folder = await _folder();
      final when = (at ?? DateTime.now()).toUtc();
      final stem = when.toIso8601String().replaceAll(RegExp('[:.]'), '-');
      final base = '${folder.path}${Platform.pathSeparator}$stem';
      await source.copy('$base.wav');
      await File('$base.json').writeAsString(
        jsonEncode(<String, Object?>{
          'recordedAt': when.toIso8601String(),
          'text': text,
        }),
      );
      await _prune(folder);
    } catch (error) {
      debugPrint('Could not keep the dictation for debugging: $error');
    }
  }

  /// The kept recordings, newest first.
  Future<List<ArchivedDictation>> list() async {
    try {
      final folder = await _folder();
      final wavs = await _wavs(folder);
      final out = <ArchivedDictation>[];
      for (final wav in wavs.reversed) {
        out.add(await _read(wav));
      }
      return out;
    } catch (error) {
      debugPrint('Could not list the kept dictations: $error');
      return const <ArchivedDictation>[];
    }
  }

  /// Deletes every kept recording.
  Future<void> clear() async {
    try {
      final folder = await _folder();
      await for (final entry in folder.list()) {
        if (entry is File) await entry.delete();
      }
    } catch (error) {
      debugPrint('Could not clear the kept dictations: $error');
    }
  }

  /// Oldest first: the names are timestamps, so the name order is the time order.
  Future<List<File>> _wavs(Directory folder) async {
    final wavs = <File>[
      await for (final entry in folder.list())
        if (entry is File && entry.path.endsWith('.wav')) entry,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return wavs;
  }

  Future<void> _prune(Directory folder) async {
    final wavs = await _wavs(folder);
    for (final wav in wavs.take(
      wavs.length - limit < 0 ? 0 : wavs.length - limit,
    )) {
      await wav.delete();
      final meta = File(_metaPath(wav.path));
      if (await meta.exists()) await meta.delete();
    }
  }

  static String _metaPath(String wavPath) =>
      '${wavPath.substring(0, wavPath.length - 4)}.json';

  Future<ArchivedDictation> _read(File wav) async {
    String? text;
    DateTime? at;
    try {
      final meta = File(_metaPath(wav.path));
      if (await meta.exists()) {
        final json =
            jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        text = json['text'] as String?;
        at = DateTime.tryParse(json['recordedAt'] as String? ?? '');
      }
    } catch (error) {
      debugPrint('Could not read ${wav.path}: $error');
    }
    return ArchivedDictation(
      path: wav.path,
      recordedAt: at ?? await wav.lastModified(),
      text: text,
      bytes: await wav.length(),
    );
  }
}

/// One kept recording.
@immutable
class ArchivedDictation {
  const ArchivedDictation({
    required this.path,
    required this.recordedAt,
    required this.text,
    required this.bytes,
  });

  final String path;
  final DateTime recordedAt;

  /// As recognised: empty for silence, null when recognition failed.
  final String? text;
  final int bytes;

  /// 16 kHz mono 16-bit WAV: 32 000 bytes a second, less the header.
  Duration get length =>
      Duration(milliseconds: ((bytes - 44).clamp(0, bytes) / 32).round());
}
