import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/project_providers.dart';
import '../screens/note_editor_screen.dart';
import 'mutation_feedback.dart';
import 'note_markdown.dart';

/// The notes half of the project screen.
///
/// Port of `frontend/src/components/NoteList.tsx` + `NoteListItem.tsx`, with one
/// structural change: the React row was an editor *and* a viewer, toggling a
/// textarea against a rendered preview in place. On a phone that is the wrong
/// shape -- a list of five notes, any of which might be a 40-line textarea, is
/// unreadable and unscrollable. So the list renders notes and nothing else, and
/// editing happens on its own screen ([NoteEditorScreen]).
///
/// Why the notes exist at all is worth remembering while reading this: per
/// `../../README.md`, the thing that makes a project a first-class entity
/// rather than a list is that it has a **body**. These are that body.
class NoteListView extends ConsumerWidget {
  const NoteListView({required this.projectId, required this.notes, super.key});

  final String projectId;

  /// In `createdAt` ascending order, as the server sends them.
  final List<Note> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(projectNotesProvider(projectId).notifier).refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        // +1 for the composer, +1 for the empty-state footer when there is one.
        itemCount: notes.length + (notes.isEmpty ? 2 : 1),
        itemBuilder: (context, index) {
          if (index == 0) return _NoteComposer(projectId: projectId);
          if (notes.isEmpty) return const _NoNotesYet();

          final note = notes[index - 1];
          return _NoteCard(
            key: ValueKey<String>(note.id),
            projectId: projectId,
            note: note,
          );
        },
      ),
    );
  }
}

/// "New note" -- a title only.
///
/// The content is written in the editor, which is where a multi-line markdown
/// body belongs. Creating with an empty body is explicitly fine on the server
/// (`createNoteSchema` defaults `content` to `""`), so this is one field and one
/// Enter, not a form.
class _NoteComposer extends ConsumerStatefulWidget {
  const _NoteComposer({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends ConsumerState<_NoteComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    _controller.clear();

    await runMutation(
      context,
      () => ref
          .read(projectNotesProvider(widget.projectId).notifier)
          .create(title),
      failure: 'Не удалось создать заметку.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Новая заметка…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Создать заметку',
            onPressed: _submit,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _NoNotesYet extends StatelessWidget {
  const _NoNotesYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('Заметок пока нет', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Контекст проекта, ссылки, куда вернуться — всё, что нужно '
            'вспомнить через две недели.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.projectId, required this.note, super.key});

  final String projectId;
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unconfirmed = isOptimisticId(note.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: unconfirmed ? null : () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (unconfirmed)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Удалить заметку',
                      onPressed: () => _delete(context, ref),
                      icon: const Icon(Icons.close),
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                // Clipped rather than truncated: markdown cut off mid-source
                // renders as broken markup (an unclosed `**`, half a list), so
                // the preview renders the whole note and the *box* is what ends.
                child: ClipRect(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: Align(
                      alignment: Alignment.topLeft,
                      heightFactor: 1,
                      child: NoteMarkdown(content: note.content),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(projectId: projectId, note: note),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Удалить заметку?',
      message: '«${note.title}» будет удалена без возможности восстановления.',
    );
    if (!confirmed || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(projectNotesProvider(projectId).notifier).remove(note),
      failure: 'Не удалось удалить заметку.',
    );
  }
}
