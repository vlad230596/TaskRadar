import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dictation_api.dart';
import '../domain/ai_mark.dart';
import '../models/note.dart';
import '../providers/project_providers.dart';
import '../widgets/ai_source_mark.dart';
import '../widgets/ai_tidy.dart';
import '../widgets/dictate_into.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/note_markdown.dart';
import '../widgets/unsaved_changes_guard.dart';

/// Editing one note: a title, a markdown body, and a preview of it.
///
/// ## Why this is a screen and not an in-place editor
///
/// `frontend/src/components/NoteListItem.tsx` toggled a `<textarea>` against a
/// rendered preview inside the list row. That works at desktop width with three
/// notes; on a phone it means a list where any item might be forty lines of
/// text area. A note is the project's *body* (see `../../README.md` on why a
/// project has one at all), so editing it gets the whole screen.
///
/// ## Why saving is explicit
///
/// Everywhere else in F3 a change is written the moment it is made. Not here:
/// markdown is written in passes, and a save-per-keystroke would be both a
/// request per keystroke and an undo history the server owns. So the editor
/// holds a draft, the save button writes it, and leaving with unsaved text asks
/// first -- the one thing that must never happen is silently discarding prose
/// somebody typed.
///
/// The preview always renders **the draft**, not the saved note. That is the
/// opposite of the React version, which deliberately previewed only
/// server-confirmed content so that a failed save could not be mistaken for a
/// successful one. The trade is different here because the draft is visibly
/// unsaved (the button is enabled, the app bar says so), and previewing text
/// other than what is in the editor is confusing in the moment you most need the
/// preview -- while writing.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    required this.projectId,
    required this.note,
    super.key,
  });

  final String projectId;
  final Note note;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.note.title,
  );
  late final TextEditingController _content = TextEditingController(
    text: widget.note.content,
  );

  bool _preview = false;
  bool _saving = false;

  /// The last state written to the server, so "is there anything to save" does
  /// not depend on the provider re-reading the note back to us.
  late String _savedTitle = widget.note.title;
  late String _savedContent = widget.note.content;

  /// The server's record of the "Причесать" answer now in the draft, sent
  /// with the next save so it learns what was kept (F15). Null once saved, or
  /// when the draft holds no answer.
  String? _tidyParseId;

  /// "Вернуть исходник" was picked: the draft holds the source again, and the
  /// save tells the server to forget AI touched the note (`domain/ai_mark.dart`).
  bool _aiClear = false;

  @override
  void initState() {
    super.initState();
    // The preview has to re-render as the draft changes, and the save button has
    // to enable itself -- both are `setState` on every keystroke, which is cheap
    // for one screen with two fields and avoids a listenable indirection.
    _title.addListener(_onChanged);
    _content.addListener(_onChanged);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _dirty =>
      _title.text.trim() != _savedTitle ||
      _content.text != _savedContent ||
      _aiClear;

  /// A title cannot be emptied: `updateNoteSchema` rejects `""` with a 400, and
  /// a note with no title is unfindable in the list anyway.
  bool get _titleValid => _title.text.trim().isNotEmpty;

  Future<bool> _save() async {
    if (!_dirty || !_titleValid) return true;

    setState(() => _saving = true);
    final title = _title.text.trim();
    final content = _content.text;

    final ok = await runMutation(
      context,
      () => ref
          .read(projectNotesProvider(widget.projectId).notifier)
          .edit(
            widget.note,
            title: title,
            content: content,
            dictationParseId: _aiClear ? null : _tidyParseId,
            aiClear: _aiClear,
          ),
      failure: 'Не удалось сохранить заметку.',
    );

    if (!mounted) return ok;
    setState(() {
      _saving = false;
      if (ok) {
        _savedTitle = title;
        _savedContent = content;
        _tidyParseId = null;
        _aiClear = false;
      }
    });
    return ok;
  }

  /// "Причесать": the body as paragraphs and lists, filler and repetition
  /// gone, every fact kept (F15). Into the draft, not saved: the answer is
  /// text like any other edit, and "Сохранить" writes it.
  ///
  /// The title goes along so the model knows the note has one and leaves it
  /// alone; it proposes one only for a note whose title was emptied.
  Future<void> _tidy() async {
    final source = _content.text.trim();
    if (source.isEmpty) return;
    final title = _title.text.trim();

    final outcome = await openAiTidy(
      context,
      kind: ParseKind.note,
      source: source,
      noteTitle: title.isEmpty ? null : title,
    );
    if (!mounted) return;
    switch (outcome) {
      case TidyAccepted(
        result: TidiedNote(:final title, :final content, :final parseId),
      ):
        _content.text = content;
        if (title != null && _title.text.trim().isEmpty) _title.text = title;
        _tidyParseId = parseId;
        _aiClear = false;
      // "Как надиктовано" after correcting the source by hand keeps the
      // correction.
      case TidyKeptSource(:final source) when source != _content.text.trim():
        _content.text = source;
        _tidyParseId = null;
      default:
        break;
    }
  }

  /// "Вернуть исходник" from the AI mark: into the draft, saved by
  /// "Сохранить" like any edit.
  void _revertToSource(String source) {
    setState(() {
      _content.text = source;
      _tidyParseId = null;
      _aiClear = true;
    });
  }

  /// The note as the list has it now -- the mark follows saves made here.
  Note get _current {
    final rows = ref.watch(projectNotesProvider(widget.projectId)).value;
    for (final row in rows ?? const <Note>[]) {
      if (row.id == widget.note.id) return row;
    }
    return widget.note;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Asks only while there is something to lose -- an unconditional
    // interception would put a dialog in front of every read-only Back, which
    // trains people to dismiss it. The same guard as every other screen with
    // typed text, so Back means one thing across the app.
    return UnsavedChangesGuard(
      isDirty: () => _dirty,
      message: 'Изменения в заметке «${widget.note.title}» будут потеряны.',
      onSave: () async => _titleValid && await _save(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_dirty ? 'Заметка · не сохранено' : 'Заметка'),
          bottom: _saving
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              : null,
          actions: [
            IconButton(
              tooltip: 'Причесать',
              onPressed: _content.text.trim().isEmpty || _saving ? null : _tidy,
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
            IconButton(
              tooltip: _preview ? 'Редактировать' : 'Просмотр',
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit_note : Icons.visibility),
            ),
            IconButton(
              tooltip: 'Сохранить',
              onPressed: (_dirty && _titleValid && !_saving) ? _save : null,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _title,
                      textInputAction: TextInputAction.next,
                      style: theme.textTheme.titleMedium,
                      decoration: InputDecoration(
                        labelText: 'Заголовок',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: _titleValid
                            ? null
                            : 'Заголовок не может быть пустым',
                      ),
                    ),
                  ),
                  DictateInto(controller: _title, label: 'в заголовок'),
                ],
              ),
              if (!_aiClear && noteAiMark(_current).shown) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AiSourceMark(
                    mark: noteAiMark(_current),
                    onRevert: () =>
                        _revertToSource(noteAiMark(_current).source ?? ''),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _preview
                    ? SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: NoteMarkdown(
                            content: _content.text,
                            selectable: true,
                          ),
                        ),
                      )
                    : TextField(
                        controller: _content,
                        // Unbounded lines plus `expands` is what makes this fill
                        // the remaining height instead of growing the layout: a
                        // `maxLines: null` field inside an Expanded without this
                        // sizes to its content and then overflows.
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Markdown…',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
              ),
              // The body's microphone sits under the text area rather than
              // beside it: the field fills the rest of the screen, so there is
              // no edge to pin a button to. Hidden in preview mode, where
              // there is nothing to dictate into.
              if (!_preview)
                Align(
                  alignment: Alignment.centerRight,
                  child: DictateInto(
                    controller: _content,
                    label: 'в текст заметки',
                    separator: '\n',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
