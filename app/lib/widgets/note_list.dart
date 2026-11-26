import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../models/goal.dart';
import '../models/note.dart';
import '../navigation/app_routes.dart';
import '../providers/goal_providers.dart';
import '../providers/project_providers.dart';
import '../screens/dictation_screen.dart';
import '../screens/note_editor_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'goals/goal_icons.dart';
import 'goals/goal_picker_sheet.dart';
import 'mode_navigation.dart';
import 'mutation_feedback.dart';

/// The ideas half of the project screen (`design/goals-ideas-spec.md`, §7).
///
/// Ideas are the former notes: what may become a task, with no age and no
/// status. The model, the table and the routes stay `Note` / `/notes` (the
/// contract keeps them), only the interface says «идеи».
///
/// The list renders cards and nothing else; an idea is written on its own
/// screen ([NoteEditorScreen]). The inline composer is gone: «+ Идея» and the
/// microphone are pinned under the list, as the tasks' bar is.
class NoteListView extends ConsumerWidget {
  const NoteListView({
    required this.projectId,
    required this.notes,
    this.projectName,
    super.key,
  });

  final String projectId;

  /// For «Теперь это задача в «…»». Optional: the snackbar reads without it.
  final String? projectName;

  /// In `createdAt` ascending order, as the server sends them; drawn newest
  /// first.
  final List<Note> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordered = <Note>[...notes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      children: <Widget>[
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(projectNotesProvider(projectId).notifier).refresh(),
            child: ordered.isEmpty
                ? _NoIdeasYet(projectId: projectId)
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      Insets.gutter,
                      12,
                      Insets.gutter,
                      16,
                    ),
                    children: <Widget>[
                      if (ordered.length < 3)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
                          child: Text(
                            'Мысль, которая может стать задачей. Без срока и '
                            'возраста.',
                            style: _hint,
                          ),
                        ),
                      for (final note in ordered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Insets.gap),
                          child: IdeaCard(
                            key: ValueKey<String>(note.id),
                            projectId: projectId,
                            projectName: projectName,
                            note: note,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        _IdeaBar(projectId: projectId, projectName: projectName),
      ],
    );
  }
}

/// «+ Идея» (56, ink) and the microphone (56, indigo), pinned under the list.
class _IdeaBar extends StatelessWidget {
  const _IdeaBar({required this.projectId, required this.projectName});

  final String projectId;
  final String? projectName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 8, Insets.gutter, 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: Targets.microphone,
              child: FilledButton.icon(
                onPressed: () => unawaited(openNewIdea(context, projectId)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: AppColors.onInk,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.stub),
                  ),
                  textStyle: AppText.action.copyWith(fontSize: 16),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Идея'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MicrophoneSquare(
            tooltip: 'Продиктовать идею',
            onPressed: () => unawaited(dictateNewIdea(context, projectId)),
          ),
        ],
      ),
    );
  }
}

/// A new idea's screen, empty or with [title] / [content] already in it.
Future<void> openNewIdea(
  BuildContext context,
  String projectId, {
  String title = '',
  String content = '',
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => NoteEditorScreen(
        projectId: projectId,
        note: null,
        initialTitle: title,
        initialContent: content,
      ),
    ),
  );
}

/// The microphone of the ideas tab: dictation, then the new idea's screen
/// with the words in it.
///
/// Tidied ("Разобрать"), the answer names the idea itself and its text goes
/// in whole. As dictated, the words are split by [splitIdeaText].
Future<void> dictateNewIdea(BuildContext context, String projectId) async {
  final result = await AppRoutes.openDictation(
    context,
    destination: const FieldDestination('новая идея'),
  );
  final (String title, String content) = switch (result) {
    FieldTaskText(:final title, :final description) => (
      title,
      description ?? '',
    ),
    FieldWords(:final text, title: final title?) => (title, text.trim()),
    FieldWords(:final text) => splitIdeaText(text),
    null => ('', ''),
  };
  if (title.trim().isEmpty && content.trim().isEmpty) return;
  if (!context.mounted) return;
  await openNewIdea(context, projectId, title: title, content: content);
}

/// Dictated words as an idea, never with a sentence torn across the two
/// fields:
///
/// - one short line: the title, no text;
/// - several lines, the first short: the first line is the title, the rest
///   the text -- the lines were said or edited that way on purpose;
/// - a long first line that starts with a short sentence: that sentence is
///   the title, everything after it the text;
/// - otherwise (one long thought): the title is its first words cut at a word
///   and marked `…`, and the text is the *whole* thing -- the title is only a
///   name for it. Moving the rest of the sentence into the text, as this used
///   to, left «…отпуск в…» over «приложении. И сразу…» (the «Зерно» idea).
(String, String) splitIdeaText(String text) {
  const limit = 120;
  const minTitle = 10;
  final trimmed = text.trim();
  final newline = trimmed.indexOf('\n');
  final first = newline < 0 ? trimmed : trimmed.substring(0, newline).trim();
  final rest = newline < 0 ? '' : trimmed.substring(newline + 1).trim();
  if (first.length <= limit) return (first, rest);

  final sentence = RegExp(r'[.!?…]+(?=\s)')
      .allMatches(first)
      .where(
        (match) => first.substring(0, match.start).trim().length >= minTitle,
      );
  if (sentence.isNotEmpty && sentence.first.end <= limit) {
    var title = first.substring(0, sentence.first.end).trim();
    if (title.endsWith('.') && !title.endsWith('...')) {
      title = title.substring(0, title.length - 1);
    }
    final after = first.substring(sentence.first.end).trim();
    return (
      title,
      <String>[after, rest].where((part) => part.isNotEmpty).join('\n'),
    );
  }

  final cut = first.lastIndexOf(' ', limit);
  final at = cut > 40 ? cut : limit;
  final title = first
      .substring(0, at)
      .trim()
      .replaceAll(RegExp(r'[\s,;:—–-]+$'), '');
  return ('$title…', trimmed);
}

/// The goals [noteId] is kept next to, from the goals list.
List<GoalView> goalsOfIdea(List<GoalView> goals, String noteId) => <GoalView>[
  for (final goal in goals)
    if (goal.ideas.any((idea) => idea.id == noteId)) goal,
];

/// The idea's text as a two-line preview: markdown marks stripped, links
/// shown as their text.
String ideaPreview(String markdown) {
  final lines = <String>[];
  for (var line in markdown.split('\n')) {
    line = line
        .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '')
        .replaceFirst(RegExp(r'^\s*([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?'), '')
        .replaceFirst(RegExp(r'^\s*>\s?'), '');
    line = line
        .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'(\*\*|__|~~|`)'), '')
        .replaceAllMapped(
          RegExp(r'(^|\W)[*_]([^*_]+)[*_]'),
          (m) => '${m[1]}${m[2]}',
        )
        .trim();
    if (line.isNotEmpty) lines.add(line);
  }
  return lines.join(' ');
}

/// One idea (`Ideas.html`): the bulb, the title, two lines of text, and a
/// foot with its goals and «Сделать задачей».
class IdeaCard extends ConsumerStatefulWidget {
  const IdeaCard({
    required this.projectId,
    required this.note,
    this.projectName,
    super.key,
  });

  final String projectId;
  final String? projectName;
  final Note note;

  @override
  ConsumerState<IdeaCard> createState() => _IdeaCardState();
}

class _IdeaCardState extends ConsumerState<IdeaCard>
    with SingleTickerProviderStateMixin {
  /// 1 while the card is there; run down to 0 (200 ms) when the idea leaves
  /// for the task list, and back up if that fails.
  late final AnimationController _size = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  bool _busy = false;

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  Note get note => widget.note;

  Future<void> _toTask() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(projectNotesProvider(widget.projectId).notifier);
    final name = widget.projectName;

    await _size.reverse();
    try {
      final task = await notifier.toTask(note);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              name == null
                  ? 'Теперь это задача'
                  : 'Теперь это задача в «$name»',
            ),
            persist: false,
            action: SnackBarAction(
              label: 'Открыть',
              onPressed: () => unawaited(
                AppRoutes.openTask(
                  navigator.context,
                  projectId: task.projectId,
                  taskId: task.id,
                ),
              ),
            ),
          ),
        );
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        unawaited(_size.forward());
      }
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error is NetworkException
                  ? 'Нужна сеть: сделать задачей можно только онлайн.'
                  : 'Не удалось сделать задачей. ${describeApiError(error)}',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unconfirmed = isOptimisticId(note.id);
    final goals = goalsOfIdea(ref.watch(goalListProvider), note.id);
    final active = ref.watch(activeContourIdProvider);
    final preview = ideaPreview(note.content);

    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _size, curve: Curves.easeInOut),
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _size,
        child: Material(
          color: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.panel),
            side: const BorderSide(color: AppColors.line),
          ),
          shadowColor: const Color(0x0D1B2050),
          elevation: 0.5,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: unconfirmed ? null : () => _open(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: preview.isEmpty
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: <Widget>[
                      const IdeaTile(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              note.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.ideaTitle,
                            ),
                            if (preview.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.ideaPreview,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (unconfirmed)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.lineFaint),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: Targets.minimum,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: goals.isEmpty
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: _LinkButton(
                                    onPressed: unconfirmed
                                        ? null
                                        : () => unawaited(_link(goals)),
                                  ),
                                )
                              : _GoalChips(
                                  goals: goals,
                                  activeContourId: active,
                                  onTap: unconfirmed
                                      ? null
                                      : () => unawaited(_link(goals)),
                                ),
                        ),
                        const SizedBox(width: 8),
                        // At a large system font on a narrow phone the
                        // button would push the row past the edge: it gets
                        // at most 60 % and scales its label down instead.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.55,
                          ),
                          child: _MakeTaskButton(
                            onPressed: unconfirmed || _busy
                                ? null
                                : () => unawaited(_toTask()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _link(List<GoalView> goals) => linkIdeaToGoals(
    context,
    ref,
    noteId: note.id,
    current: <String>{for (final goal in goals) goal.id},
  );

  void _open(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NoteEditorScreen(
            projectId: widget.projectId,
            note: note,
            projectName: widget.projectName,
          ),
        ),
      ),
    );
  }
}

/// The bulb on its 34x34 tile.
class IdeaTile extends StatelessWidget {
  const IdeaTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.ideaFill,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const BulbIcon(size: 19, color: AppColors.ideaInk),
    );
  }
}

class _GoalChips extends StatelessWidget {
  const _GoalChips({
    required this.goals,
    required this.activeContourId,
    required this.onTap,
  });

  final List<GoalView> goals;
  final String? activeContourId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: Targets.minimum,
        child: ClipRect(
          child: Row(
            children: <Widget>[
              for (final goal in goals) ...<Widget>[
                Flexible(
                  child: IdeaGoalChip(
                    title: goal.title,
                    bright:
                        activeContourId == null ||
                        goal.contourId == activeContourId,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A goal on an idea card: 24 high, r 12, crown 11 and the title.
class IdeaGoalChip extends StatelessWidget {
  const IdeaGoalChip({required this.title, required this.bright, super.key});

  final String title;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.fromLTRB(7, 0, 9, 0),
      decoration: BoxDecoration(
        color: bright ? AppColors.crownChip : AppColors.crownMutedChip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CrownIcon(
            size: 11,
            color: bright ? AppColors.crown : AppColors.crownMuted,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: bright ? AppColors.onInk : AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: const SizedBox(
        height: Targets.minimum,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CrownIcon(size: 13, color: AppColors.crownMuted),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Связать с целью',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Сделать задачей →»: 36 high in a 44 target, r 12, `ideaLine` border.
class _MakeTaskButton extends StatelessWidget {
  const _MakeTaskButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Targets.minimum,
      child: Center(
        widthFactor: 1,
        child: SizedBox(
          height: 36,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.card,
              foregroundColor: AppColors.ideaInk,
              side: const BorderSide(color: AppColors.ideaLine),
              padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.padded,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Сделать задачей', maxLines: 1, softWrap: false),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 15),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// No ideas: the bulb on its tile, two lines and «+ Идея».
class _NoIdeasYet extends StatelessWidget {
  const _NoIdeasYet({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
      children: <Widget>[
        Center(
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ideaFill,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const BulbIcon(size: 28, color: AppColors.ideaInk),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Идей пока нет',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.text,
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Сюда — то, что может стать задачей, когда дойдут руки. Идеи не '
          'стареют и не висят.',
          textAlign: TextAlign.center,
          style: _hint,
        ),
      ],
    );
  }
}

const TextStyle _hint = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w500,
  fontSize: 13,
  height: 1.4,
  color: AppColors.muted,
);

/// Kept for the delete in the idea's own screen.
Future<void> deleteIdea(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required Note note,
}) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Удалить идею?',
    message: '«${note.title}» будет удалена без возможности восстановления.',
  );
  if (!confirmed || !context.mounted) return;

  await runMutation(
    context,
    () => ref.read(projectNotesProvider(projectId).notifier).remove(note),
    failure: 'Не удалось удалить идею.',
  );
}
