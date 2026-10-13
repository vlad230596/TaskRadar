import '../models/inbox_item.dart';
import '../models/note.dart';
import '../models/task.dart';

/// "Правил AI" on a task, a note or a sandbox line (14.10.2026).
///
/// The server keeps three things (backend `src/domain/aiMark.ts`): the words
/// before the first "Обработать" (`aiSource`), the kind of that first parse
/// (`aiKind`), and the fields as the last AI answer saved them (`aiResult`).
/// This file turns them into what the screens need: whether to show the mark,
/// whether the text was changed by hand since, and what "вернуть исходник"
/// writes back.
enum AiMarkState {
  /// AI never touched it, or it was put back.
  none,

  /// As the last AI answer left it.
  asAi,

  /// AI processed it, and it was edited by hand afterwards.
  editedAfter,
}

/// What a row says about AI, for the mark and its sheet.
class AiMark {
  const AiMark(this.state, this.source);

  static const AiMark none = AiMark(AiMarkState.none, null);

  final AiMarkState state;

  /// The words before the first processing; null with [AiMarkState.none].
  final String? source;

  bool get shown => state != AiMarkState.none;
}

AiMark _mark(
  String? source,
  Map<String, dynamic>? result,
  Map<String, Object?> current,
) {
  if (source == null) return AiMark.none;
  // No snapshot to compare with is "as AI left it": the mark is what matters.
  final edited =
      result != null &&
      current.entries.any(
        (field) => _norm(result[field.key]) != _norm(field.value),
      );
  return AiMark(edited ? AiMarkState.editedAfter : AiMarkState.asAi, source);
}

/// Null, empty and surrounding spaces are one thing: the server trims too.
String _norm(Object? value) => (value as String? ?? '').trim();

AiMark taskAiMark(Task task) => _mark(
  task.aiSource,
  task.aiResult,
  <String, Object?>{'title': task.title, 'description': task.description},
);

AiMark noteAiMark(Note note) => _mark(
  note.aiSource,
  note.aiResult,
  <String, Object?>{'title': note.title, 'content': note.content},
);

AiMark inboxAiMark(InboxItem item) =>
    _mark(item.aiSource, item.aiResult, <String, Object?>{'text': item.text});

/// What "вернуть исходник" writes into a task, by how the source was made.
///
/// - `note`: only the description was processed -- it gets the source back,
///   the title stays.
/// - `task_tidy`: the title and description were joined, title on the first
///   line (`task_screen.dart`) -- split back the same way.
/// - `task`, `sandbox`: the source is speech or a sandbox line with no title
///   of its own -- split the way the server files a line ([splitSourceText]).
({String title, String? description}) taskSourceFields(Task task) {
  final source = task.aiSource?.trim() ?? '';
  switch (task.aiKind) {
    case 'note':
      return (title: task.title, description: source.isEmpty ? null : source);
    case 'task_tidy':
      final lines = source.split('\n');
      final rest = lines.skip(1).join('\n').trim();
      final title = lines.first.trim();
      return (
        title: title.isEmpty ? task.title : title,
        description: rest.isEmpty ? null : rest,
      );
    default:
      final parts = splitSourceText(source);
      return (
        title: parts.title.isEmpty ? task.title : parts.title,
        description: parts.description,
      );
  }
}

/// The server's `splitInboxText` (backend `src/domain/inboxSplit.ts`), word
/// for word: a short text is the title whole; a long one gives its first
/// sentence, or its first 120 characters cut at a word, to the title.
({String title, String? description}) splitSourceText(String text) {
  const limit = 120;
  const minTitle = 10;
  final trimmed = text.trim();
  if (trimmed.length <= limit) return (title: trimmed, description: null);

  ({String title, String? description}) withRest(String title, String rest) {
    final description = rest.trim();
    return (
      title: title,
      description: description.isEmpty ? null : description,
    );
  }

  for (final match in RegExp(r'[.!?…]+(?=\s)|\r?\n').allMatches(trimmed)) {
    if (match.end > limit) break;
    if (trimmed.substring(0, match.start).trim().length >= minTitle) {
      var title = trimmed.substring(0, match.end).trim();
      if (title.endsWith('.') && !title.endsWith('...')) {
        title = title.substring(0, title.length - 1);
      }
      return withRest(title, trimmed.substring(match.end));
    }
  }

  final window = trimmed.substring(0, limit + 1);
  final lastSpace = window.lastIndexOf(RegExp(r'\s\S*$'));
  if (lastSpace >= minTitle) {
    return withRest(
      '${trimmed.substring(0, lastSpace).trimRight()}…',
      trimmed.substring(lastSpace),
    );
  }
  return withRest(trimmed.substring(0, limit), trimmed.substring(limit));
}
