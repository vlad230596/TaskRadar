import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What an [OutboxEntry] asks the server to do.
enum OutboxKind {
  /// `POST /projects/:id/tasks`, with the entry's key as `createKey`.
  createTask,

  /// `PATCH /tasks/:id`, with the values the edit was made against as
  /// `expected`.
  editTask,
}

/// Where an [OutboxEntry] is in its life.
enum OutboxState {
  /// Not sent yet: no network, or not tried yet.
  waiting,

  /// The server took it. Kept as history -- the green line that says "it
  /// went" is the whole point of keeping the history at all.
  sent,

  /// The server said the field had been changed elsewhere since this edit
  /// was made, and the edit was not applied. Waits for a decision.
  skipped,

  /// The server answered and said no (the project is gone, a 400, a 500).
  /// Waits for a decision: send again or throw away.
  refused,

  /// A skipped edit the user chose to leave as the server has it.
  resolved,
}

/// One task write made on this device that the server has not acknowledged,
/// or has answered recently enough to still be shown.
///
/// ## Why the wire body is stored, not the user's intent
///
/// An entry is replayed hours later by code that knows nothing about the
/// screen it came from. Storing `{ "status": "done", "remindAt": null }` --
/// exactly what the online path would have sent -- means the replay cannot
/// drift from it: there is one place that turns a tap into a request, and the
/// queue only postpones that request.
@immutable
class OutboxEntry {
  const OutboxEntry({
    required this.key,
    required this.kind,
    required this.projectId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.taskId,
    this.expected = const <String, Object?>{},
    this.state = OutboxState.waiting,
    this.settledAt,
    this.conflictFields = const <String>[],
    this.serverTask,
    this.message,
  });

  /// The idempotency key: `createKey` of a create, and the entry's identity
  /// everywhere else. Generated the same way as a capture key.
  final String key;
  final OutboxKind kind;
  final String projectId;

  /// The task's title as it was when the write was made, for the history
  /// line. A create's title is also in [body]; an edit's is the row's.
  final String title;

  /// The request body, exactly as the online path would have sent it.
  final Map<String, Object?> body;

  /// The task an edit applies to; for a create, the id the server gave it
  /// once it is [OutboxState.sent].
  final String? taskId;

  /// What the edited fields held when the edit was made (`PATCH`'s
  /// `expected`). Empty for a create.
  final Map<String, Object?> expected;

  final OutboxState state;
  final DateTime createdAt;

  /// When the entry stopped waiting: sent, skipped, refused or resolved.
  final DateTime? settledAt;

  /// For a skipped edit: the fields that had been changed elsewhere.
  final List<String> conflictFields;

  /// For a skipped edit: the task as the server had it, in the server's JSON.
  final Map<String, Object?>? serverTask;

  /// For a refused entry: what the server said.
  final String? message;

  /// The id an unsent create's row carries in the task list. Prefixed like
  /// every client-invented id (`isOptimisticId`), so nothing tries to edit or
  /// move a row the server has never heard of.
  String get localTaskId => 'local:outbox:$key';

  bool get isWaiting => state == OutboxState.waiting;

  /// Skipped or refused: the user has something to decide.
  bool get needsDecision =>
      state == OutboxState.skipped || state == OutboxState.refused;

  OutboxEntry copyWith({
    OutboxState? state,
    DateTime? settledAt,
    String? taskId,
    List<String>? conflictFields,
    Map<String, Object?>? serverTask,
    String? message,
  }) => OutboxEntry(
    key: key,
    kind: kind,
    projectId: projectId,
    title: title,
    body: body,
    createdAt: createdAt,
    taskId: taskId ?? this.taskId,
    expected: expected,
    state: state ?? this.state,
    settledAt: settledAt ?? this.settledAt,
    conflictFields: conflictFields ?? this.conflictFields,
    serverTask: serverTask ?? this.serverTask,
    message: message ?? this.message,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'kind': kind.name,
    'projectId': projectId,
    'title': title,
    'body': body,
    'taskId': ?taskId,
    'expected': expected,
    'state': state.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'settledAt': ?settledAt?.toUtc().toIso8601String(),
    'conflictFields': conflictFields,
    'serverTask': ?serverTask,
    'message': ?message,
  };

  static OutboxEntry fromJson(Map<String, dynamic> json) => OutboxEntry(
    key: json['key'] as String,
    kind: OutboxKind.values.byName(json['kind'] as String),
    projectId: json['projectId'] as String,
    title: json['title'] as String,
    body: Map<String, Object?>.from(json['body'] as Map),
    taskId: json['taskId'] as String?,
    expected: Map<String, Object?>.from(
      (json['expected'] as Map?) ?? const <String, Object?>{},
    ),
    state: OutboxState.values.byName(json['state'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    settledAt: json['settledAt'] == null
        ? null
        : DateTime.parse(json['settledAt'] as String),
    conflictFields: List<String>.from(
      (json['conflictFields'] as List?) ?? const <String>[],
    ),
    serverTask: json['serverTask'] == null
        ? null
        : Map<String, Object?>.from(json['serverTask'] as Map),
    message: json['message'] as String?,
  );

  @override
  String toString() => 'OutboxEntry($key, ${kind.name}, ${state.name})';
}

/// The on-device outbox of task writes (offline creates and edits), and the
/// last week of what became of them.
///
/// ## How it relates to the capture queue
///
/// `CaptureQueueStore` explains why "every write requires the network" was
/// right for tasks *without* a way to resolve conflicts. This file is that
/// way, in its gentlest form: a create is idempotent by key, and an edit
/// carries the values it was made against, so the server can refuse one that
/// would overwrite a change made elsewhere (`PATCH`'s `expected`). Nothing is
/// merged and nothing is silently overwritten -- a refused edit is shown to
/// the user, who decides.
///
/// Same file pattern as the capture queue (JSON, atomic rename, unreadable
/// bytes set aside), and the same strictness: for an entry made with no
/// network this file is the only copy, so [write] throws.
class OutboxStore {
  OutboxStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const int schemaVersion = 1;
  static const String fileName = 'outbox.v1.json';

  final Future<Directory> Function() _directory;

  /// How long a settled entry is kept as history.
  static const Duration keepHistory = Duration(days: 7);

  Future<List<OutboxEntry>> read() async {
    File file;
    try {
      file = await _file();
      if (!await file.exists()) return const <OutboxEntry>[];
    } catch (error) {
      debugPrint('Outbox unreadable (no directory): $error');
      return const <OutboxEntry>[];
    }

    try {
      return decode(await file.readAsString());
    } catch (error) {
      debugPrint('Unusable outbox, setting it aside: $error');
      try {
        if (await file.exists()) await file.rename('${file.path}.corrupt');
      } catch (error) {
        debugPrint('Could not set the unusable outbox aside: $error');
      }
      return const <OutboxEntry>[];
    }
  }

  /// Replaces the outbox with [entries]. **Throws** when the bytes did not
  /// reach the disk -- see the class comment.
  Future<void> write(List<OutboxEntry> entries) async {
    final file = await _file();
    await file.parent.create(recursive: true);

    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(encode(entries), flush: true);
    await temporary.rename(file.path);
  }

  /// Drops the outbox. For sign-out, like the capture queue.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Could not clear the outbox: $error');
    }
  }

  Future<File> _file() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  /// The envelope, shared with the browser store.
  static String encode(List<OutboxEntry> entries) =>
      jsonEncode(<String, dynamic>{
        'version': schemaVersion,
        'entries': entries
            .map((entry) => entry.toJson())
            .toList(growable: false),
      });

  static List<OutboxEntry> decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('outbox root is not an object');
    }
    final version = decoded['version'];
    if (version != schemaVersion) {
      throw FormatException('outbox schema version $version');
    }
    final entries = decoded['entries'] as List<dynamic>;
    return List<OutboxEntry>.unmodifiable(
      entries.map(
        (dynamic row) => OutboxEntry.fromJson(row as Map<String, dynamic>),
      ),
    );
  }
}
