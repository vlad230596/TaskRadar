import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/project_providers.dart';
import '../widgets/dictation.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/note_markdown.dart';

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
      _title.text.trim() != _savedTitle || _content.text != _savedContent;

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
          .edit(widget.note, title: title, content: content),
      failure: 'Не удалось сохранить заметку.',
    );

    if (!mounted) return ok;
    setState(() {
      _saving = false;
      if (ok) {
        _savedTitle = title;
        _savedContent = content;
      }
    });
    return ok;
  }

  /// Intercepts the back gesture / button.
  Future<void> _onPopInvoked(bool didPop, void result) async {
    if (didPop) return;

    final leave = await confirmDestructive(
      context,
      title: 'Выйти без сохранения?',
      message: 'Изменения в заметке «${widget.note.title}» будут потеряны.',
      confirmLabel: 'Выйти',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope<void>(
      // `canPop: false` only while there is something to lose -- an unconditional
      // interception would put a confirmation dialog in front of every back tap,
      // including the read-only ones, which trains people to dismiss it.
      canPop: !_dirty,
      onPopInvokedWithResult: _onPopInvoked,
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
              DictatedField(
                onText: (text) => appendDictated(_title, text: text),
                field: TextField(
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
                DictatedField(
                  // A new line, not a space. The body is Markdown and is
                  // dictated in chunks -- one thought, then the next -- and
                  // running them together into one paragraph is the one thing
                  // that would make the result worse than typing it.
                  onText: (text) =>
                      appendDictated(_content, text: text, separator: '\n'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
