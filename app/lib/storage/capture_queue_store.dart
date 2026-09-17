import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A line captured on the device that the server has not acknowledged yet
/// (F8.1).
@immutable
class PendingCapture {
  const PendingCapture({
    required this.key,
    required this.text,
    required this.capturedAt,
    this.failed = false,
  });

  /// The idempotency key sent to `POST /inbox`, generated here.
  ///
  /// Its whole job is to survive a retry: a phone cannot tell "the request
  /// never arrived" from "it arrived and the answer was lost", and without a
  /// key the second case puts a twin of the line in the pile.
  final String key;

  final String text;

  /// When the user actually typed it -- which can be hours before it is sent.
  ///
  /// Not sent to the server (the contract change F8.1 asked for is the key and
  /// nothing else), and not used for ordering against server rows: it exists so
  /// the queue drains in the order things were thought of, and so a line that
  /// has been stuck for a suspiciously long time can be recognised as stuck.
  final DateTime capturedAt;

  /// Set when the last attempt was refused by the server rather than lost to
  /// the network.
  ///
  /// **Deliberately not persisted.** It is the client's read of a single
  /// attempt, not a fact about the line, and a fresh start deserves a fresh
  /// attempt -- carrying "this failed once in March" across a restart would
  /// leave a line permanently painted as broken for a reason nobody can see any
  /// more.
  final bool failed;

  PendingCapture copyWith({String? text, bool? failed}) => PendingCapture(
    key: key,
    text: text ?? this.text,
    capturedAt: capturedAt,
    failed: failed ?? this.failed,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'text': text,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };

  static PendingCapture fromJson(Map<String, dynamic> json) => PendingCapture(
    key: json['key'] as String,
    text: json['text'] as String,
    capturedAt: DateTime.parse(json['capturedAt'] as String),
  );

  /// A fresh 128-bit key, hex-encoded.
  ///
  /// Hand-rolled rather than a `uuid` dependency, and that is worth one line of
  /// justification: the server treats the key as an opaque string of 8..100
  /// characters, so nothing downstream cares whether it is formatted as a UUID.
  /// `Random.secure()` is the platform CSPRNG, which makes a collision between
  /// two devices about as likely as a v4 UUID collision -- the property that
  /// actually matters here.
  static String newKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  bool operator ==(Object other) =>
      other is PendingCapture &&
      other.key == key &&
      other.text == text &&
      other.capturedAt == capturedAt &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(key, text, capturedAt, failed);

  @override
  String toString() => 'PendingCapture($key, "$text")';
}

/// The on-device queue of captured lines waiting for a network (F8.1).
///
/// ## Why this file exists at all
///
/// It is the first deliberate exception to "every write requires the network"
/// (`../../../README.md`, and the long note in `providers/inbox_providers.dart`
/// that F8 wrote and F8.1 overturned). The sandbox has to work in a lift, on a
/// train, out of town -- that is precisely where "надо не забыть" arrives -- and
/// a screen answering "не удалось записать" fails in exactly the way the
/// sandbox exists to prevent.
///
/// The exception does not generalise, and the reason is about this data and no
/// other: a captured line has no order to be inserted into the wrong place in,
/// no state another device could change underneath it, and a lifetime measured
/// in hours. Two devices merging their queues is set union, with nothing to
/// choose between. Tasks, notes, positions and statuses have none of those
/// properties and stay online-only.
///
/// ## Why a JSON file and not `drift`
///
/// The plan named `drift` as the candidate, and the answer turned out to be no,
/// for reasons that are specific rather than stylistic:
///
/// - the queue is a handful of rows, appended and removed whole, and never
///   queried. There is no join, no index and no partial update here -- the
///   entire "query language" this needs is "give me the list";
/// - `drift` brings a second code generator into a project whose `pubspec.yaml`
///   already documents a delicate analyzer/meta lockstep between `freezed`,
///   `json_serializable` and `riverpod_generator`, plus native SQLite for
///   Android **and** Windows;
/// - the atomic-rename file pattern next door (`board_snapshot_store.dart`) is
///   already proven on both targets and already tested against a real
///   directory.
///
/// If real offline editing ever happens (an operation log with ordering and
/// conflicts), `drift` becomes the right answer and this file is a hundred
/// lines to throw away.
///
/// ## How it differs from the board snapshot, which matters
///
/// The snapshot is a *cache*: every failure mode collapses into "there is no
/// cache", and a failed write is swallowed because the data is still on the
/// server. This file is the **opposite**: for a line captured with no network,
/// it is the only copy that exists anywhere. So:
///
/// - [write] throws when it fails, and capture reports that to the user,
///   because a queue that silently did not save is worse than an error message;
/// - unreadable bytes are **kept**, renamed aside rather than deleted, on the
///   chance that a human can still read a thought out of them.
class CaptureQueueStore {
  /// [directory] is injected so tests can point the real store at a temp folder:
  /// `path_provider` is a platform channel and answers `MissingPluginException`
  /// in the `flutter test` VM, and faking the store wholesale would leave the
  /// actual file format untested.
  CaptureQueueStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const int schemaVersion = 1;

  /// The version is in the name as well as in the envelope, so a future bump
  /// leaves the old file behind rather than fighting over one name.
  static const String fileName = 'capture-queue.v1.json';

  final Future<Directory> Function() _directory;

  /// The queue as it was left, oldest first. Never throws.
  ///
  /// An unreadable file reads as an empty queue -- there is nothing else it
  /// could read as -- but the bytes are moved to `<name>.corrupt` instead of
  /// being deleted. That file is the last trace of something the user typed and
  /// nobody else has a copy of; the app has no use for it, and a person with a
  /// file manager might.
  Future<List<PendingCapture>> read() async {
    File file;
    try {
      file = await _file();
      if (!await file.exists()) return const <PendingCapture>[];
    } catch (error) {
      debugPrint('Capture queue unreadable (no directory): $error');
      return const <PendingCapture>[];
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('capture queue root is not an object');
      }

      final version = decoded['version'];
      if (version != schemaVersion) {
        throw FormatException('capture queue schema version $version');
      }

      final queue = decoded['queue'] as List<dynamic>;
      return List<PendingCapture>.unmodifiable(
        queue.map(
          (dynamic row) =>
              PendingCapture.fromJson(row as Map<String, dynamic>),
        ),
      );
    } catch (error) {
      debugPrint('Unusable capture queue, setting it aside: $error');
      await _setAside(file);
      return const <PendingCapture>[];
    }
  }

  /// Replaces the queue with [queue].
  ///
  /// **Throws** when the bytes did not reach the disk. Unlike the board
  /// snapshot, this is not a cache of something the server already has: losing
  /// this write loses the line. The caller turns the failure into an error the
  /// user can see and act on, with the text still in the field.
  Future<void> write(List<PendingCapture> queue) async {
    final file = await _file();
    await file.parent.create(recursive: true);

    // Write to a sibling and rename over the target. `File.writeAsString`
    // truncates first, so a kill halfway through would leave a half-written
    // file -- and here that is not a lost cache but a lost thought. A rename is
    // atomic on both NTFS and ext4/f2fs, so a reader only ever sees a complete
    // file: either the old queue or the new one.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, dynamic>{
        'version': schemaVersion,
        'queue': queue.map((entry) => entry.toJson()).toList(growable: false),
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  /// Drops the queue. For sign-out: lines captured by one account must not be
  /// sent under the next one's session.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Could not clear the capture queue: $error');
    }
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  Future<void> _setAside(File file) async {
    try {
      if (await file.exists()) await file.rename('${file.path}.corrupt');
    } catch (error) {
      debugPrint('Could not set the unusable capture queue aside: $error');
    }
  }
}
