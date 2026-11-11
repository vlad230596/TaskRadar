import '../models/inbox_item.dart';
import '../models/note.dart';
import '../models/task.dart';

/// "Правил AI" on a task, a note or a sandbox line (14.10.2026).
///
/// The server keeps three things (backend `src/domain/aiMark.ts`): the words
/// before the first "Обработать" (`aiSource`), the kind of that first parse
/// (`aiKind`), and the fields as the last AI answer saved them (`aiResult`).
/// This file turns them into what the screens need: whether to show the mark,
/// whether the text was changed by hand since, what "Причесать" starts from,
/// and how the source goes back into the fields.
///
/// Nothing here forgets the source (25.10.2026). There used to be "Вернуть
/// исходник", which wrote the source back and cleared all three columns; next
/// to "Как надиктовано" on the AI screen it read as the same button, and one of
/// the two always looked broken. Now the mark opens the AI screen itself, and
/// text put back to the source simply shows no mark -- the source is still
/// there for the next "Причесать".
enum AiMarkState {
  /// AI never touched it, or the text is the source again.
  none,

  /// As the last AI answer left it.
  asAi,

  /// AI processed it, and it was edited by hand afterwards.
  editedAfter,
}

/// What a row says about AI, for the mark and the AI screen behind it.
class AiMark {
  const AiMark(this.state, this.source);

  static const AiMark none = AiMark(AiMarkState.none, null);

  final AiMarkState state;

  /// The words before the first processing; null with [AiMarkState.none].
  final String? source;

  bool get shown => state != AiMarkState.none;

  /// What "Причесать" sends for text that stands as [current]: the source
  /// while the text is as AI left it -- the model never works from its own
  /// answer -- and [current] otherwise. Edited by hand after AI, the edit is
  /// the newer word and is not thrown away for an older one.
  String tidySource(String current) =>
      state == AiMarkState.asAi ? source ?? current : current;
}

AiMark _mark(
  String? source,
  Map<String, dynamic>? result,
  Map<String, Object?> current,
  Map<String, Object?> asSource,
) {
  if (source == null) return AiMark.none;
  // Back to the source: nothing AI wrote is left to point at.
  bool same(Map<String, Object?> fields) => fields.entries.every(
    (field) => _norm(field.value) == _norm(current[field.key]),
  );
  if (same(asSource)) return AiMark.none;
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

/// [title] and [description] are the fields as they stand on the screen,
/// when they differ from the row's.
AiMark taskAiMark(Task task, {String? title, String? description}) {
  final source = task.aiSource == null ? null : taskSourceFields(task);
  return _mark(
    task.aiSource,
    task.aiResult,
    <String, Object?>{
      'title': title ?? task.title,
      'description': description ?? task.description,
    },
    <String, Object?>{
      'title': source?.title,
      'description': source?.description,
    },
  );
}

AiMark noteAiMark(Note note, {String? title, String? content}) => _mark(
  note.aiSource,
  note.aiResult,
  <String, Object?>{
    'title': title ?? note.title,
    'content': content ?? note.content,
  },
  // A note's source is its body; the title was never processed.
  <String, Object?>{'content': note.aiSource},
);

AiMark inboxAiMark(InboxItem item, {String? text}) => _mark(
  item.aiSource,
  item.aiResult,
  <String, Object?>{'text': text ?? item.text},
  <String, Object?>{'text': item.aiSource},
);

/// The source of [task] -- or [source], the same words corrected by hand on
/// the AI screen -- as the task's fields, by how the source was made.
///
/// - `note`: only the description was processed -- it gets the source back,
///   the title stays.
/// - `task_tidy`: the title and description were joined, title on the first
///   line (`task_editor_screen.dart`) -- split back the same way.
/// - `task`, `sandbox`: the source is speech or a sandbox line with no title
///   of its own -- split the way the server files a line ([splitSourceText]).
({String title, String? description}) taskSourceFields(
  Task task, [
  String? source,
]) {
  final text = (source ?? task.aiSource)?.trim() ?? '';
  switch (task.aiKind) {
    case 'note':
      return (title: task.title, description: text.isEmpty ? null : text);
    case 'task_tidy':
      final lines = text.split('\n');
      final rest = lines.skip(1).join('\n').trim();
      final title = lines.first.trim();
      return (
        title: title.isEmpty ? task.title : title,
        description: rest.isEmpty ? null : rest,
      );
    default:
      final parts = splitSourceText(text);
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
