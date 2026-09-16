import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/board_project.dart';

/// The last successful `GET /board` response, as it came off disk.
@immutable
class BoardSnapshot {
  const BoardSnapshot({required this.projects, required this.savedAt});

  /// The board rows, in the order the server sent them.
  final List<BoardProject> projects;

  /// When the response this snapshot was built from actually arrived.
  ///
  /// ## Why this one *is* a `DateTime` when every wire timestamp is a `String`
  ///
  /// The rule the models follow (see the long note on `Project`) is about
  /// *calendar dates disguised as instants* -- `remindAt` above all. This field
  /// is the opposite kind of value: a genuine instant, produced by this app's
  /// own clock, never compared to a calendar date, and used for exactly one
  /// thing -- telling the user "you are looking at data from 09:12 yesterday".
  /// That is arithmetic on a moment in time, which is what `DateTime` is for.
  /// It is serialised as an ISO-8601 UTC string, so the file stays readable.
  final DateTime savedAt;
}

/// Persists the board as a JSON file, for reading only.
///
/// ## Why a cache exists at all, given the product says "online only"
///
/// `../README.md` and the migration plan both reject offline *editing* -- no
/// operation queue, no conflict resolution. This is the one deliberate
/// exception, and it is a read cache for two concrete reasons:
///
/// 1. the board screen must be on screen instantly on launch, not after a
///    round trip to a VPS over mobile data;
/// 2. to schedule a local alarm the app has to know `remindAt` at a moment when
///    there may be no network at all.
///
/// So: the last good response is written here verbatim, and nothing is ever
/// written back to the server from it. Writes (F3/F4) will require the network
/// and fail loudly without it.
///
/// **The token is not in here.** It lives in `TokenStorage`
/// (Keystore/DPAPI) and nowhere else; this file holds only what `GET /board`
/// returned, which is why the snapshot can sit in plain application-support
/// storage without being a credential leak.
///
/// ## Why every read failure is "there is no snapshot"
///
/// A cache file is the least trustworthy input the app has. It can be absent
/// (first launch, cleared app data), truncated (killed mid-write), corrupted,
/// or -- the interesting one -- perfectly valid JSON written by an older
/// version of the app whose `Task` had no `isCurrent` yet. Every one of those
/// has the same correct answer: pretend there is no cache, show "loading", and
/// let the network be the source of truth. What must never happen is a crash,
/// or an empty board presented as a fact. See `BoardView` for the second half
/// of that contract.
class BoardSnapshotStore {
  /// [directory] is injected so tests can point the real store at a temp
  /// folder: `path_provider` is a platform channel and answers
  /// `MissingPluginException` in the `flutter test` VM, and faking the store
  /// wholesale would leave the actual file format untested.
  BoardSnapshotStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  /// Bumped whenever the shape inside `board` changes incompatibly.
  ///
  /// This is the cheap half of schema handling: a file whose `version` is not
  /// this number is discarded unread. The expensive half -- a file that claims
  /// the right version but whose rows no longer parse -- is handled by catching
  /// the parse failure, because no version field can protect against a field
  /// that was added without anyone remembering to bump it.
  static const int schemaVersion = 1;

  /// The version is in the filename as well as in the envelope so that a future
  /// bump leaves the old file behind rather than fighting over one name.
  static const String fileName = 'board-snapshot.v1.json';

  final Future<Directory> Function() _directory;

  /// Reads the snapshot, or returns null if there is nothing usable.
  ///
  /// Never throws -- see the class comment.
  Future<BoardSnapshot?> read() async {
    File file;
    try {
      file = await _file();
      if (!await file.exists()) return null;
    } catch (error) {
      debugPrint('Board snapshot unreadable (no directory): $error');
      return null;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('snapshot root is not an object');
      }

      final version = decoded['version'];
      if (version != schemaVersion) {
        throw FormatException('snapshot schema version $version');
      }

      final savedAt = DateTime.parse(decoded['savedAt'] as String);
      final board = decoded['board'] as List<dynamic>;

      return BoardSnapshot(
        // The same parser the HTTP layer uses, on purpose: if the snapshot were
        // read by a laxer codec, a shape that the network path rejects could
        // still reach the UI from disk, and the bug would only ever reproduce
        // on a device that had been offline.
        projects: BoardProject.listFromJson(board),
        savedAt: savedAt,
      );
    } catch (error) {
      // Corrupt, truncated, or from an older schema. Delete it: leaving it in
      // place would mean paying the same failed parse on every single launch,
      // and the next successful refresh would overwrite it anyway.
      debugPrint('Discarding unusable board snapshot: $error');
      await _delete(file);
      return null;
    }
  }

  /// Replaces the snapshot with [projects].
  ///
  /// Returns the [BoardSnapshot] that was written so the caller can use the
  /// very same `savedAt` it persisted, instead of reading the clock twice.
  ///
  /// Never throws: a cache write that fails must not turn a perfectly good
  /// board response into an error on screen. The user loses the fast launch,
  /// not the data.
  Future<BoardSnapshot> write(
    List<BoardProject> projects, {
    DateTime? savedAt,
  }) async {
    final snapshot = BoardSnapshot(
      projects: projects,
      savedAt: savedAt ?? DateTime.now(),
    );

    try {
      final file = await _file();
      await file.parent.create(recursive: true);

      // Write to a sibling and rename over the target. `File.writeAsString`
      // truncates first, so a kill (or a low-battery shutdown) halfway through
      // leaves a half-written JSON file that the next launch has to detect and
      // throw away. A rename is atomic on both NTFS and ext4/f2fs, so the
      // reader only ever sees a complete file -- either the old one or the new
      // one.
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': schemaVersion,
          'savedAt': snapshot.savedAt.toUtc().toIso8601String(),
          // Exactly the `GET /board` body, re-encoded by the models' own
          // `toJson`. `BoardProject.toJson` is deliberately symmetric with its
          // `fromJson` (flat, `tasks` alongside `id`) -- an asymmetry there
          // would produce a file that only fails to load later, on a device,
          // with no network to fall back on.
          'board': projects
              .map((project) => project.toJson())
              .toList(growable: false),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (error) {
      debugPrint('Could not write the board snapshot: $error');
    }

    return snapshot;
  }

  /// Drops the snapshot. For a future sign-out: the board of the account that
  /// just logged out must not be the first thing the next account sees.
  Future<void> clear() async {
    try {
      await _delete(await _file());
    } catch (error) {
      debugPrint('Could not clear the board snapshot: $error');
    }
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Could not delete the board snapshot: $error');
    }
  }
}
