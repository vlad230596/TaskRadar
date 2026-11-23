import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../api/dictation_api.dart';
import '../domain/ai_mark.dart';
import '../models/goal.dart';
import '../models/note.dart';
import '../navigation/app_routes.dart';
import '../navigation/goal_routes.dart';
import '../providers/goal_providers.dart';
import '../providers/project_providers.dart';
import '../theme/tokens.dart';
import '../widgets/ai_source_mark.dart';
import '../widgets/ai_tidy.dart';
import '../widgets/dictation.dart';
import '../widgets/editor/editor_theme.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/goals/goal_picker_sheet.dart';
import '../widgets/ime_text_controller.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/note_list.dart';
import '../widgets/note_markdown.dart';
import '../widgets/unsaved_changes_guard.dart';
import 'dictation_screen.dart';

/// One idea (`design/reference/Idea-Edit.html`): the task editor's dark
/// family -- a title, a markdown text, its goals, and «Сделать задачей».
///
/// ## Why saving is explicit
///
/// Markdown is written in passes, and a save-per-keystroke would be both a
/// request per keystroke and an undo history the server owns. So the screen
/// holds a draft, «Сохранить» writes it (it replaces the idea's actions while
/// there is something to save), and leaving with unsaved text asks first.
///
/// ## Edit and view by focus
///
/// The text shows rendered while the field is not being written in; a tap on
/// it opens the field. An empty text is always the field.
///
/// [note] null is a new idea: the first save creates it ([initialTitle] and
/// [initialContent] come from dictation or are empty).
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    required this.projectId,
    required this.note,
    this.projectName,
    this.initialTitle = '',
    this.initialContent = '',
    super.key,
  });

  final String projectId;
  final Note? note;

  /// For the project chip in the header; looked up when not given.
  final String? projectName;
  final String initialTitle;
  final String initialContent;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  /// The idea as saved; null until a new one is created.
  late Note? _note = widget.note;

  late final TextEditingController _title = ImeTextController(
    text: widget.note?.title ?? widget.initialTitle,
  );
  late final TextEditingController _content = ImeTextController(
    text: widget.note?.content ?? widget.initialContent,
  );
  final FocusNode _contentFocus = FocusNode();

  /// The text field is open (rather than the rendered markdown).
  late bool _editing = (widget.note?.content ?? widget.initialContent)
      .trim()
      .isEmpty;
  bool _saving = false;
  bool _converting = false;

  late String _savedTitle = widget.note?.title ?? '';
  late String _savedContent = widget.note?.content ?? '';

  /// The server's record of the "Причесать" answer now in the draft, sent
  /// with the next save so it learns what was kept (F15).
  String? _tidyParseId;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
    _content.addListener(_onChanged);
    _contentFocus.addListener(() {
      if (!_contentFocus.hasFocus && _content.text.trim().isNotEmpty) {
        setState(() => _editing = false);
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _dirty =>
      _title.text.trim() != _savedTitle || _content.text != _savedContent;

  bool get _titleValid => _title.text.trim().isNotEmpty;

  Future<bool> _save() async {
    if (!_dirty || !_titleValid) return true;

    setState(() => _saving = true);
    final title = _title.text.trim();
    final content = _content.text;
    final notes = ref.read(projectNotesProvider(widget.projectId).notifier);
    final current = _note;

    final ok = await runMutation(
      context,
      () async {
        if (current == null) {
          final created = await notes.create(title, content: content);
          if (created != null && mounted) setState(() => _note = created);
        } else {
          await notes.edit(
            current,
            title: title,
            content: content,
            dictationParseId: _tidyParseId,
          );
        }
      },
      failure: current == null
          ? 'Не удалось создать идею.'
          : 'Не удалось сохранить идею.',
    );

    if (!mounted) return ok;
    setState(() {
      _saving = false;
      if (ok) {
        _savedTitle = title;
        _savedContent = content;
        _tidyParseId = null;
      }
    });
    return ok;
  }

  /// "Причесать" (F15): into the draft, not saved.
  Future<void> _tidy({bool shown = false}) async {
    final current = _content.text.trim();
    if (current.isEmpty && !shown) return;
    final title = _title.text.trim();
    final mark = _markOf(_row);

    final outcome = await openAiTidy(
      context,
      kind: ParseKind.note,
      source: shown ? mark.source ?? current : mark.tidySource(current),
      result: shown ? TidiedNote(content: current) : null,
      noteTitle: title.isEmpty ? null : title,
    );
    if (!mounted) return;
    switch (outcome) {
      case TidyAccepted(
        result: TidiedNote(:final title, :final content, :final parseId),
      ):
        _content.text = content;
        if (title != null && _title.text.trim().isEmpty) _title.text = title;
        _tidyParseId = parseId ?? _tidyParseId;
        setState(() => _editing = true);
      case TidyKeptSource(:final source) when source != _content.text.trim():
        _content.text = source;
        _tidyParseId = null;
        setState(() => _editing = true);
      default:
        break;
    }
  }

  AiMark _markOf(Note? note) => note == null
      ? AiMark.none
      : noteAiMark(note, title: _title.text, content: _content.text);

  Note? get _current =>
      _find(ref.watch(projectNotesProvider(widget.projectId)).value);

  Note? get _row =>
      _find(ref.read(projectNotesProvider(widget.projectId)).value);

  Note? _find(List<Note>? rows) {
    final id = _note?.id;
    if (id == null) return null;
    for (final row in rows ?? const <Note>[]) {
      if (row.id == id) return row;
    }
    return _note;
  }

  Future<void> _dictateIntoText() async {
    final result = await AppRoutes.openDictation(
      context,
      destination: const FieldDestination('в текст идеи'),
    );
    final text = switch (result) {
      FieldWords(:final text) => text,
      FieldTaskText(:final title, :final description) => <String>[
        title,
        ?description,
      ].join('\n'),
      null => '',
    };
    if (text.isEmpty || !mounted) return;
    appendDictated(_content, text: text, separator: '\n');
    setState(() => _editing = true);
  }

  Future<void> _toTask() async {
    final note = _note;
    if (note == null || _converting) return;
    setState(() => _converting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = _projectName;
    try {
      final task = await ref
          .read(projectNotesProvider(widget.projectId).notifier)
          .toTask(note);
      // The idea is gone; there is nothing left to edit.
      _savedTitle = _title.text.trim();
      _savedContent = _content.text;
      navigator.pop();
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
      if (mounted) setState(() => _converting = false);
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

  Future<void> _delete() async {
    final note = _note;
    if (note == null) return;
    final confirmed = await confirmDestructive(
      context,
      title: 'Удалить идею?',
      message: '«${note.title}» будет удалена без возможности восстановления.',
    );
    if (!confirmed || !mounted) return;
    final navigator = Navigator.of(context);
    final ok = await runMutation(
      context,
      () => ref
          .read(projectNotesProvider(widget.projectId).notifier)
          .remove(note),
      failure: 'Не удалось удалить идею.',
    );
    if (!ok) return;
    _savedTitle = _title.text.trim();
    _savedContent = _content.text;
    navigator.pop();
  }

  Future<void> _linkGoals(List<GoalView> goals) async {
    final note = _note;
    if (note == null) return;
    await linkIdeaToGoals(
      context,
      ref,
      noteId: note.id,
      current: <String>{for (final goal in goals) goal.id},
    );
  }

  String? get _projectName {
    if (widget.projectName != null) return widget.projectName;
    final header = ref.read(projectHeaderProvider(widget.projectId)).value;
    return header?.name;
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    final goals = note == null
        ? const <GoalView>[]
        : goalsOfIdea(ref.watch(goalListProvider), note.id);
    final active = ref.watch(activeContourIdProvider);
    final projectName =
        widget.projectName ??
        ref.watch(projectHeaderProvider(widget.projectId)).value?.name;
    final mark = _markOf(_current);

    return UnsavedChangesGuard(
      isDirty: () => _dirty,
      message: note == null
          ? 'Новая идея не будет создана.'
          : 'Изменения в идее «${note.title}» будут потеряны.',
      onSave: () async => _titleValid && await _save(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: editorOverlayStyle,
        child: Theme(
          data: editorTheme,
          child: Scaffold(
            backgroundColor: AppColors.voiceBackground,
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Header(
                    title: _dirty ? 'Идея · не сохранено' : 'Идея',
                    projectName: projectName,
                    saving: _saving,
                    onDelete: note == null ? null : () => unawaited(_delete()),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: <Widget>[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(4, 16, 0, 12),
                            child: _DarkBulbTile(),
                          ),
                        ),
                        _Well(
                          child: TextField(
                            controller: _title,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.sentences,
                            minLines: 1,
                            maxLines: null,
                            autofocus: note == null && _title.text.isEmpty,
                            style: EditorText.title.copyWith(
                              color: AppColors.onInk,
                            ),
                            cursorColor: AppColors.voiceBright,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Название идеи',
                              hintStyle: EditorText.title.copyWith(
                                color: AppColors.voiceMuted,
                              ),
                              errorText: _titleValid || note == null
                                  ? null
                                  : 'Название не может быть пустым',
                            ),
                          ),
                        ),
                        if (mark.shown) ...<Widget>[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AiSourceMark(
                              mark: mark,
                              onOpen: () => unawaited(_tidy(shown: true)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _textWell(),
                        if (note != null) ...<Widget>[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 18, 0, 8),
                            child: Text('ЦЕЛИ', style: _tidyLabel),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              for (final goal in goals)
                                _DarkGoalChip(
                                  goal: goal,
                                  bright:
                                      active == null ||
                                      goal.contourId == active,
                                  onOpen: () =>
                                      unawaited(openGoal(context, goal.id)),
                                  onRemove: () => unawaited(
                                    runMutation(
                                      context,
                                      () => ref
                                          .read(goalsProvider.notifier)
                                          .unlinkIdea(goal.id, note.id),
                                      failure: 'Не удалось отвязать идею.',
                                    ),
                                  ),
                                ),
                              _AddGoalChip(
                                onPressed: () => unawaited(_linkGoals(goals)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                    child: _dirty || note == null
                        ? EditorPrimaryButton(
                            label: note == null ? 'Создать' : 'Сохранить',
                            onPressed: _dirty && _titleValid && !_saving
                                ? () => unawaited(_save())
                                : null,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SizedBox(
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed: () => unawaited(_linkGoals(goals)),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: AppColors.voiceBright,
                                    side: const BorderSide(
                                      color: AppColors.voiceLine,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: const TextStyle(
                                      fontFamily: AppFonts.text,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  icon: const CrownIcon(
                                    size: 16,
                                    color: AppColors.crownMuted,
                                  ),
                                  label: const Text('Связать с целью'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 64,
                                child: FilledButton(
                                  onPressed: _converting
                                      ? null
                                      : () => unawaited(_toTask()),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.onInk,
                                    foregroundColor: AppColors.voiceBackground,
                                    disabledBackgroundColor:
                                        AppColors.voiceLine,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    textStyle: const TextStyle(
                                      fontFamily: AppFonts.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Text('Сделать задачей'),
                                      SizedBox(width: 10),
                                      Icon(Icons.arrow_forward, size: 22),
                                    ],
                                  ),
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

  /// The text: rendered, or the field while it is written in.
  Widget _textWell() {
    final editing = _editing || _content.text.trim().isEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.voiceWell,
        borderRadius: BorderRadius.circular(Radii.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 150),
            child: editing
                ? TextField(
                    controller: _content,
                    focusNode: _contentFocus,
                    minLines: 6,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: EditorText.body.copyWith(color: AppColors.voiceInk),
                    cursorColor: AppColors.voiceBright,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Текст идеи',
                      hintStyle: EditorText.body.copyWith(
                        color: AppColors.voiceMuted,
                      ),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _editing = true);
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _contentFocus.requestFocus(),
                      );
                    },
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: NoteMarkdown(content: _content.text, onDark: true),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (_content.text.trim().isNotEmpty) ...<Widget>[
                _SquareButton(
                  tooltip: 'Причесать',
                  outlined: true,
                  icon: Icons.auto_awesome_outlined,
                  onPressed: _saving ? null : () => unawaited(_tidy()),
                ),
                const SizedBox(width: 8),
              ],
              _SquareButton(
                tooltip: 'Продиктовать',
                outlined: false,
                icon: Icons.mic_none,
                onPressed: () => unawaited(_dictateIntoText()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.projectName,
    required this.saving,
    required this.onDelete,
  });

  final String title;
  final String? projectName;
  final bool saving;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => unawaited(Navigator.of(context).maybePop()),
            icon: const Icon(Icons.close, color: AppColors.voiceMuted),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorText.header.copyWith(fontSize: 16),
            ),
          ),
          if (saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.voiceBright,
                ),
              ),
            ),
          if (projectName != null)
            Container(
              height: 32,
              constraints: const BoxConstraints(maxWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.railActive,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                projectName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.voiceBright,
                ),
              ),
            ),
          if (onDelete != null)
            PopupMenuButton<String>(
              tooltip: 'Ещё',
              icon: const Icon(Icons.more_vert, color: AppColors.voiceMuted),
              onSelected: (_) => onDelete!(),
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Удалить идею'),
                ),
              ],
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Well extends StatelessWidget {
  const _Well({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.voiceWell,
        borderRadius: BorderRadius.circular(Radii.panel),
      ),
      child: child,
    );
  }
}

class _DarkBulbTile extends StatelessWidget {
  const _DarkBulbTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.ideaTileOnDark,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const BulbIcon(size: 22, color: AppColors.ideaOnDark),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.tooltip,
    required this.outlined,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool outlined;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: outlined ? Colors.transparent : AppColors.indigo,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: outlined
              ? const BorderSide(color: AppColors.voiceLine)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: Targets.minimum,
            height: Targets.minimum,
            child: Icon(
              icon,
              size: 20,
              color: outlined ? AppColors.voiceBright : AppColors.onInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// A goal on the dark idea screen: 32 high, r 16; bright on `goalEnd`.
class _DarkGoalChip extends StatelessWidget {
  const _DarkGoalChip({
    required this.goal,
    required this.bright,
    required this.onOpen,
    required this.onRemove,
  });

  final GoalView goal;
  final bool bright;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bright ? AppColors.goalEnd : AppColors.voiceLine,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 32,
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.only(left: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CrownIcon(
                size: 13,
                color: bright ? AppColors.crown : AppColors.crownMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.onInk,
                  ),
                ),
              ),
              Tooltip(
                message: 'Отвязать',
                child: InkResponse(
                  onTap: onRemove,
                  radius: 16,
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.voiceMuted,
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
}

class _AddGoalChip extends StatelessWidget {
  const _AddGoalChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.voiceBright,
          side: const BorderSide(color: AppColors.voiceLine),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Цель'),
      ),
    );
  }
}

/// «ЦЕЛИ»: the editor's section label (`TidyLabel`'s look).
const TextStyle _tidyLabel = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 12,
  letterSpacing: 0.72,
  color: AppColors.voiceMuted,
);
