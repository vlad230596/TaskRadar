import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'web_stores.dart';

/// The last good answer to a read, kept so a screen has something true to
/// show with no network: the "in work" set, a project's notes, the scope list.
///
/// The board has its own, older store (`board_snapshot_store.dart`) because
/// reminders depend on it and its shape is load-bearing; everything added to
/// the offline read set afterwards goes here instead of growing a file class
/// per screen. Same rules as the board snapshot, and for the same reasons:
///
/// - **read-only cache.** Nothing is ever *written* from it; every edit still
///   needs the network (`../../flutter-migration-plan.md`, "Про локальный кэш
///   и офлайн"). It only decides what the screen draws before the network has
///   answered, or instead of an answer that is not coming;
/// - **never throws.** Absent, truncated, foreign-schema -- all of it is "no
///   cache", which every caller already handles as "wait for the network";
/// - **per user.** `Session.signIn` clears it with the other per-user files
///   when a different person signs in.
///
/// Entries are the server's own JSON (re-encoded from the models), so a cached
/// list goes through exactly the parser a fresh one does.
abstract interface class ReadCacheStore {
  Future<CachedRead?> read(String key);

  Future<void> write(String key, Object? json);

  Future<void> clear();
}

@immutable
class CachedRead {
  const CachedRead({required this.json, required this.savedAt});

  final Object? json;
  final DateTime savedAt;
}

/// Keys used by the app, in one place so `clear` and the docs agree.
abstract final class ReadCacheKeys {
  static const String focus = 'focus';
  static const String scopes = 'scopes';
  static String notes(String projectId) => 'notes.$projectId';
}

const int _schemaVersion = 1;

String? _encode(Object? json) {
  try {
    return jsonEncode(<String, dynamic>{
      'version': _schemaVersion,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'data': json,
    });
  } catch (error) {
    debugPrint('Read cache: cannot encode entry: $error');
    return null;
  }
}

CachedRead? _decode(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic> || decoded['version'] != _schemaVersion) {
    throw const FormatException('foreign read-cache entry');
  }
  return CachedRead(
    json: decoded['data'],
    savedAt: DateTime.parse(decoded['savedAt'] as String),
  );
}

/// One file per key under the application-support directory (the same place
/// the board snapshot lives, and for the same reason: not user-visible).
class FileReadCacheStore implements ReadCacheStore {
  FileReadCacheStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const String folder = 'read-cache.v1';

  final Future<Directory> Function() _directory;

  Future<Directory> _root() async {
    final base = await _directory();
    return Directory('${base.path}${Platform.pathSeparator}$folder');
  }

  Future<File> _file(String key) async {
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${(await _root()).path}${Platform.pathSeparator}$safe.json');
  }

  @override
  Future<CachedRead?> read(String key) async {
    File? file;
    try {
      file = await _file(key);
      if (!await file.exists()) return null;
      return _decode(await file.readAsString());
    } catch (error) {
      debugPrint('Read cache: discarding "$key": $error');
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? json) async {
    final encoded = _encode(json);
    if (encoded == null) return;
    try {
      final file = await _file(key);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    } catch (error) {
      debugPrint('Read cache: cannot write "$key": $error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final root = await _root();
      if (await root.exists()) await root.delete(recursive: true);
    } catch (error) {
      debugPrint('Read cache: cannot clear: $error');
    }
  }
}

/// The browser twin: `localStorage` through [WebKeyValueStore], with an index
/// entry so [clear] knows which keys are its own.
class WebReadCacheStore implements ReadCacheStore {
  WebReadCacheStore({WebKeyValueStore? storage})
    : _storage = storage ?? PreferencesKeyValueStore();

  static const String _prefix = 'read-cache.v1.';
  static const String _index = 'read-cache.v1.__keys';

  final WebKeyValueStore _storage;

  @override
  Future<CachedRead?> read(String key) async {
    try {
      final raw = await _storage.read('$_prefix$key');
      return raw == null ? null : _decode(raw);
    } catch (error) {
      debugPrint('Read cache: discarding "$key": $error');
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? json) async {
    final encoded = _encode(json);
    if (encoded == null) return;
    try {
      await _storage.write('$_prefix$key', encoded);
      final keys = await _keys();
      if (keys.add(key)) await _storage.write(_index, jsonEncode(keys.toList()));
    } catch (error) {
      debugPrint('Read cache: cannot write "$key": $error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      for (final key in await _keys()) {
        await _storage.remove('$_prefix$key');
      }
      await _storage.remove(_index);
    } catch (error) {
      debugPrint('Read cache: cannot clear: $error');
    }
  }

  Future<Set<String>> _keys() async {
    try {
      final raw = await _storage.read(_index);
      if (raw == null) return <String>{};
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }
}
