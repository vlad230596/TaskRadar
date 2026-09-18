/// The browser versions of the two on-disk stores.
///
/// ## Why they exist at all
///
/// `BoardSnapshotStore` and `CaptureQueueStore` are files: `path_provider` plus
/// `dart:io`, an atomic rename, a `.corrupt` sibling. A browser tab has none of
/// that. `getApplicationSupportDirectory` answers `MissingPluginException` on
/// web, and the consequences are not symmetric between the two:
///
/// - the board snapshot swallows its own failures, so on web it would silently
///   degrade into "no cache, ever" -- survivable, but it would also log a
///   platform exception on every board refresh;
/// - the capture queue **throws** by design, because the queue is the only copy
///   of a line captured with no network. On web that turns every single capture
///   into "не удалось записать", which is exactly the failure F8.1 exists to
///   prevent.
///
/// So the browser gets its own pair, with the same two interfaces and the same
/// JSON envelopes (same `version` field, same row shapes), and
/// `providers/dependencies.dart` picks between them with `kIsWeb`.
///
/// ## Why `shared_preferences` and not IndexedDB
///
/// `shared_preferences` is `localStorage` on web, it is already a dependency of
/// this app, and both payloads are a few kilobytes of JSON read and written
/// whole. IndexedDB would buy transactions and megabytes, and cost a package, a
/// schema and an upgrade path -- for a value that is replaced in one write.
///
/// What `localStorage` does *not* give is the file stores' atomic rename, and
/// that is a real difference rather than an oversight: a write is one string
/// assignment inside the browser, so there is no torn write to recover from,
/// but "clear site data" takes the queue with it. That is the browser's
/// bargain, and it is why the phone stays the client for capture away from a
/// network.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/board_project.dart';
import 'board_snapshot_store.dart';
import 'capture_queue_store.dart';

/// The key/value half of the two stores below, so they can be tested without a
/// platform channel and without `SharedPreferences.setMockInitialValues` -- a
/// global on a channel, which leaks between tests in one file and cannot
/// express a failing write.
abstract interface class WebKeyValueStore {
  Future<String?> read(String key);

  /// Persists [value]. May throw -- `localStorage` refuses writes when the
  /// origin's quota is full or when the browser blocks site data, and
  /// [WebCaptureQueueStore] has to report that rather than hide it.
  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

/// [WebKeyValueStore] on top of `shared_preferences` (`localStorage` on web).
class PreferencesKeyValueStore implements WebKeyValueStore {
  PreferencesKeyValueStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;

  @override
  Future<String?> read(String key) async {
    final preferences = await _preferences();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final preferences = await _preferences();
    final saved = await preferences.setString(key, value);
    // `setString` reports failure by returning false rather than by throwing,
    // and the one caller that must not lose data is the capture queue. Turning
    // it into an exception here is what lets that store keep its "throws when
    // the bytes did not land" contract unchanged.
    if (!saved) {
      throw StateError('Could not write "$key" to browser storage');
    }
  }

  @override
  Future<void> remove(String key) async {
    final preferences = await _preferences();
    await preferences.remove(key);
  }
}

/// [BoardSnapshotStore] for the browser. Same contract: never throws, and every
/// unusable value reads as "there is no snapshot".
class WebBoardSnapshotStore implements BoardSnapshotStore {
  WebBoardSnapshotStore({WebKeyValueStore? storage})
    : _storage = storage ?? PreferencesKeyValueStore();

  /// Deliberately the file store's name, version suffix and all: the two never
  /// share a device, and one name means a grep for the snapshot finds both
  /// halves.
  static const String key = BoardSnapshotStore.fileName;

  final WebKeyValueStore _storage;

  @override
  Future<BoardSnapshot?> read() async {
    String? raw;
    try {
      raw = await _storage.read(key);
    } catch (error) {
      debugPrint('Board snapshot unreadable (browser storage): $error');
      return null;
    }
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('snapshot root is not an object');
      }
      final version = decoded['version'];
      if (version != BoardSnapshotStore.schemaVersion) {
        throw FormatException('snapshot schema version $version');
      }
      return BoardSnapshot(
        projects: BoardProject.listFromJson(decoded['board'] as List<dynamic>),
        savedAt: DateTime.parse(decoded['savedAt'] as String),
      );
    } catch (error) {
      // Same reasoning as the file store: a value that failed to parse once
      // will fail on every launch, and the next successful refresh replaces it
      // anyway.
      debugPrint('Discarding unusable board snapshot: $error');
      await clear();
      return null;
    }
  }

  @override
  Future<BoardSnapshot> write(
    List<BoardProject> projects, {
    DateTime? savedAt,
  }) async {
    final snapshot = BoardSnapshot(
      projects: projects,
      savedAt: savedAt ?? DateTime.now(),
    );

    try {
      await _storage.write(
        key,
        jsonEncode(<String, dynamic>{
          'version': BoardSnapshotStore.schemaVersion,
          'savedAt': snapshot.savedAt.toUtc().toIso8601String(),
          'board': projects
              .map((project) => project.toJson())
              .toList(growable: false),
        }),
      );
    } catch (error) {
      // A failed cache write must not turn a good board response into an error
      // on screen. The user loses the fast reload, not the data.
      debugPrint('Could not write the board snapshot: $error');
    }

    return snapshot;
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.remove(key);
    } catch (error) {
      debugPrint('Could not clear the board snapshot: $error');
    }
  }
}

/// [CaptureQueueStore] for the browser. Same contract, including the one that
/// matters: [write] throws when the value did not reach storage.
class WebCaptureQueueStore implements CaptureQueueStore {
  WebCaptureQueueStore({WebKeyValueStore? storage})
    : _storage = storage ?? PreferencesKeyValueStore();

  static const String key = CaptureQueueStore.fileName;

  /// Where an unparseable queue is moved instead of being deleted. The file
  /// store renames the bytes to `<name>.corrupt` for the same reason: they are
  /// the last trace of something the user typed and nobody else has a copy of.
  /// Nobody can open this one with a file manager, but the developer console
  /// can, which is more than deleting it would leave.
  static const String corruptKey = '$key.corrupt';

  final WebKeyValueStore _storage;

  @override
  Future<List<PendingCapture>> read() async {
    String? raw;
    try {
      raw = await _storage.read(key);
    } catch (error) {
      debugPrint('Capture queue unreadable (browser storage): $error');
      return const <PendingCapture>[];
    }
    if (raw == null) return const <PendingCapture>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('capture queue root is not an object');
      }
      final version = decoded['version'];
      if (version != CaptureQueueStore.schemaVersion) {
        throw FormatException('capture queue schema version $version');
      }
      final queue = decoded['queue'] as List<dynamic>;
      return List<PendingCapture>.unmodifiable(
        queue.map(
          (dynamic row) => PendingCapture.fromJson(row as Map<String, dynamic>),
        ),
      );
    } catch (error) {
      debugPrint('Unusable capture queue, setting it aside: $error');
      await _setAside(raw);
      return const <PendingCapture>[];
    }
  }

  @override
  Future<void> write(List<PendingCapture> queue) async {
    await _storage.write(
      key,
      jsonEncode(<String, dynamic>{
        'version': CaptureQueueStore.schemaVersion,
        'queue': queue.map((entry) => entry.toJson()).toList(growable: false),
      }),
    );
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.remove(key);
    } catch (error) {
      debugPrint('Could not clear the capture queue: $error');
    }
  }

  Future<void> _setAside(String raw) async {
    try {
      await _storage.write(corruptKey, raw);
      await _storage.remove(key);
    } catch (error) {
      debugPrint('Could not set the unusable capture queue aside: $error');
    }
  }
}
