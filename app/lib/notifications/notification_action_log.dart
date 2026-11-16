import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The last few presses of a notification button and what became of them,
/// for the notification bench.
///
/// A button press on Android runs in a background isolate with no UI and,
/// usually, with the app not running at all: when «Выполнено» "did nothing"
/// on the phone, this list is the only way to tell "the press never reached
/// the app" from "it reached it and the server said no". A plain file read
/// fresh every time, for the reason `GeofenceStore` gives -- the bench and the
/// background isolate must not each keep their own cached copy.
@immutable
class NotificationActionRecord {
  const NotificationActionRecord({
    required this.at,
    required this.action,
    required this.taskId,
    required this.outcome,
    required this.where,
  });

  factory NotificationActionRecord.fromJson(Map<String, dynamic> json) =>
      NotificationActionRecord(
        at: DateTime.parse(json['at'] as String),
        action: json['action'] as String? ?? '',
        taskId: json['taskId'] as String? ?? '',
        outcome: json['outcome'] as String? ?? '',
        where: json['where'] as String? ?? '',
      );

  final DateTime at;

  /// The button's id (`ReminderAction.id`).
  final String action;
  final String taskId;

  /// One line in Russian: «отправлено», «в очереди без сети», the reason it
  /// was ignored, or the error.
  final String outcome;

  /// «приложение» (the app was running and handled it) or «фон» (it ran
  /// with no app).
  final String where;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'at': at.toUtc().toIso8601String(),
    'action': action,
    'taskId': taskId,
    'outcome': outcome,
    'where': where,
  };
}

/// Where [NotificationActionRecord]s are kept.
abstract interface class NotificationActionLog {
  /// Newest first. Empty when there is nothing or it cannot be read.
  Future<List<NotificationActionRecord>> read();

  /// Adds one. Never throws: a diagnostic must not break the action.
  Future<void> add(NotificationActionRecord record);
}

/// [NotificationActionLog] as a small JSON file in app-support storage.
class FileNotificationActionLog implements NotificationActionLog {
  FileNotificationActionLog({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const String fileName = 'notification_actions.json';

  /// Enough to see what happened this week; small enough to rewrite whole.
  static const int keep = 20;

  final Future<Directory> Function() _directory;

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$fileName');

  @override
  Future<List<NotificationActionRecord>> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const <NotificationActionRecord>[];
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return const <NotificationActionRecord>[];
      return <NotificationActionRecord>[
        for (final entry in json)
          if (entry is Map)
            NotificationActionRecord.fromJson(entry.cast<String, dynamic>()),
      ];
    } catch (error) {
      debugPrint('Could not read the notification action log: $error');
      return const <NotificationActionRecord>[];
    }
  }

  @override
  Future<void> add(NotificationActionRecord record) async {
    try {
      final next = <NotificationActionRecord>[
        record,
        ...await read(),
      ].take(keep);
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode(<Object>[for (final entry in next) entry.toJson()]),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (error) {
      debugPrint('Could not write the notification action log: $error');
    }
  }
}

/// In memory -- for tests, and anywhere there is no file system.
class MemoryNotificationActionLog implements NotificationActionLog {
  final List<NotificationActionRecord> records = <NotificationActionRecord>[];

  @override
  Future<List<NotificationActionRecord>> read() async =>
      List<NotificationActionRecord>.unmodifiable(records);

  @override
  Future<void> add(NotificationActionRecord record) async =>
      records.insert(0, record);
}
