import 'package:flutter/foundation.dart';

/// What the editor of a new task opens with, when it is not opened empty --
/// «Дополнить…» on the dictation review hands over the proposal it shows
/// (task-editor spec, section 4).
@immutable
class TaskDraft {
  const TaskDraft({
    required this.title,
    this.description,
    this.remindAt,
    this.remindTime,
    this.parseId,
  });

  final String title;
  final String? description;

  /// `YYYY-MM-DD`, as the dictation's answer proposed it.
  final String? remindAt;

  /// `HH:MM`, read only together with [remindAt].
  final String? remindTime;

  /// The server's record of the parse the text came from: sent with the
  /// create as `dictationParseId` (F15).
  final String? parseId;
}
