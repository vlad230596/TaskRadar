import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../api/dictation_api.dart';
import '../api/patch_field.dart';
import '../domain/ai_mark.dart';
import '../domain/smart_tokens.dart';
import '../domain/task_age.dart';
import '../models/board_project.dart';
import '../models/checklist_item.dart';
import '../models/history_task_event.dart';
import '../models/task.dart';
import '../models/task_category.dart';
import '../models/task_location.dart';
import '../models/task_status.dart';
import '../navigation/app_routes.dart';
import '../providers/board_providers.dart';
import '../providers/history_providers.dart';
import '../providers/project_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ai_source_mark.dart';
import '../widgets/ai_tidy.dart';
import '../widgets/category_sheets.dart';
import '../widgets/dictation.dart';
import '../widgets/editor/attribute_bar.dart';
import '../widgets/editor/editor_theme.dart';
import '../widgets/editor/link_cards.dart';
import '../widgets/editor/reminder_sheet.dart';
import '../widgets/editor/sections.dart';
import '../widgets/editor/smart_text_controller.dart';
import '../widgets/editor/task_draft.dart';
import '../widgets/focus_toggle.dart';
import '../widgets/history_charts.dart';
import '../widgets/move_task_sheet.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/unsaved_changes_guard.dart';
import 'dictation_screen.dart';

/// A task's text: what "Причесать" reads and what it gives back.
typedef TaskText = ({String title, String? description});

/// See [TaskEditor.onTidy].
typedef TidyText = Future<TaskText?> Function(TaskText current);

/// How tall the editor opens (task-editor spec, section 1).
enum EditorHeight {
  /// Quick-add: the title, the attribute row and "Добавить", in a sheet over
  /// the project's list. Dragged up or `⤢` -- the same widget, full height.
  compact,

  /// Everything: an existing task, a task from dictation, an expanded
  /// quick-add.
  full,
}

/// What the editor is drawn in.
enum EditorPresentation { page, sheet, dialog }

/// Opens a new task's editor over [projectId]'s list: the compact sheet on a
/// phone, a 560 px dialog on a wide window («+ Задача», spec section 9).
Future<void> showNewTaskEditor(
  BuildContext context, {
  required String projectId,
}) {
  if (isWideLayout(context)) {
    return showDialog<void>(
      context: context,
      builder: (_) => TaskEditorDialog(
        child: TaskEditor(
          projectId: projectId,
          presentation: EditorPresentation.dialog,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Dragging the sheet down would close it past the unsaved-changes guard
    // (a drag-dismiss is a pop, not a maybePop). The scrim and Back ask.
    enableDrag: false,
    backgroundColor: EditorColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.large)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => TaskEditor(
      projectId: projectId,
      presentation: EditorPresentation.sheet,
      initialHeight: EditorHeight.compact,
    ),
  );
}

/// The editor on a wide window: a 560 px dialog, as tall as it may be.
class TaskEditorDialog extends StatelessWidget {
  const TaskEditorDialog({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: EditorColors.background,
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: SizedBox(
        width: kEditorDialogWidth,
        height: (height - 48).clamp(320.0, 820.0),
        child: child,
      ),
    );
  }
}

/// One screen to create and to edit a task (task-editor spec): replaces the
/// old "Новая задача" and "Задача", which were two faces of one class with
/// different powers -- a reminder could only be set on a task that already
/// existed, so a task was "create, open, finish".
///
/// ## Two modes
///
/// [taskId] null is a **new** task: nothing is written until "Добавить",
/// then one create with every field. Otherwise an **existing** task: the
/// discrete controls (status, the reminder chip, the category chip, "Взять в
/// работу") write at once, as before; the text -- and what is recognised in
/// it -- waits for "Сохранить", which shows only while there is something to
/// save.
///
/// ## Recognition in the text
///
/// The title runs on a [SmartTextController]: «завтра в 10», `#Дом`,
/// `/покупки` light up as they are typed and fill the chips, which "come
/// alive" (a short pulse). The value lives in the chip; the text only
/// *writes* to it. A token's piece is cut from the title on save. Tapping the
/// highlight offers «Не дата» and «Изменить…»; Backspace right after it
/// un-recognises it first. An existing task's text is scanned once on
/// opening and every piece found is dismissed: "позвонить в пятницу" saved
/// before this feature must not quietly move a reminder.
///
/// The rule between text and chips, per kind (reminder, category, project):
///
/// - the chip shows the active token's value if there is one, else the
///   *manual* value (a new task's own state, an existing task's row);
/// - removing the token's text falls back to the manual value, untouched;
/// - changing the chip by hand dismisses the token;
/// - "Причесать" / dictation commit the tokens' values to the manual value
///   before replacing the text, so a token the model cut out keeps its
///   effect.
///
/// ## The look
///
/// The dictation review's dark family (`editor_theme.dart`): it is what the
/// owner pointed at -- "приятно и драйвово, а не скучно".
///
/// ## Where WP5–7 plug in
///
/// `widgets/editor/sections.dart`: [EditorSlots] for the chips and sections,
/// [EditorExtras] for the state they keep until a save.
class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({
    required this.projectId,
    this.taskId,
    this.prefill,
    this.initialHeight = EditorHeight.full,
    this.presentation = EditorPresentation.page,
    this.onTidy,
    this.clock,
    super.key,
  });

  /// The project the task is in -- or, for a new one, the project the editor
  /// opens on (the header chip and a `#проект` token can change it).
  final String projectId;

  /// Null for a new task.
  final String? taskId;

  /// A new task's starting text and reminder (from the dictation review).
  final TaskDraft? prefill;

  final EditorHeight initialHeight;
  final EditorPresentation presentation;

  /// "Причесать": the task's text -- title and description -- tidied. Null,
  /// as in the app, opens [AiTidyScreen] with [ParseKind.taskTidy]. A test
  /// puts its own answer here.
  final TidyText? onTidy;

  /// The wall clock the date tokens are read against. Tests fix it.
  final DateTime Function()? clock;

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

/// A value committed for an existing task but not saved yet: the value of a
/// token the model cut out, or AI's reminder. A box, because null is a value
/// here ("no reminder").
class _Held<T> {
  const _Held(this.value);
  final T value;
}

enum _TokenAction { dismiss, change }

enum _TaskAction { unfile, delete }

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final SmartTextController _title = SmartTextController(
    contextFor: _smartContext,
    clock: _now,
  );
  final SmartTextController _note = SmartTextController(recognise: false);
  final FocusNode _titleFocus = FocusNode(debugLabel: 'task title');
  final FocusNode _noteFocus = FocusNode(debugLabel: 'task description');
  final GlobalKey _titleKey = GlobalKey();
  final EditorExtras _extras = EditorExtras();

  /// Whether the field had the focus when the finger went down: a tap on a
  /// link in a field that is not being edited opens the link; in a field
  /// being edited it places the caret.
  bool _titleFocusedAtTap = false;
  bool _noteFocusedAtTap = false;

  /// The row the controllers were last filled from -- see the same field in
  /// the old task screen: the list under this screen is live, and filling
  /// only when the row's identity changes means the user's version wins while
  /// they are typing.
  String? _loadedFrom;

  /// The title as it was filled from the row: while the title still is
  /// exactly this, late-arriving context (the categories) re-dismisses
  /// instead of recognising.
  String? _openedTitle;

  late bool _noteOpen = _draft;
  late bool _expanded = widget.initialHeight == EditorHeight.full;

  /// The server's record of the AI text now in the fields, sent with the
  /// save (F15). Null once saved, and when the fields hold no answer.
  String? _tidyParseId;

  // -- A new task's own values (the "manual" side of each chip) -----------
  late String _projectId = widget.projectId;
  ReminderValue? _reminder;
  String? _categoryId;

  /// A new task's status: «Открыта» or «Блокер» -- a task is not created
  /// done.
  TaskStatus _newStatus = TaskStatus.pending;

  /// The project [_categoryId] was picked in: a category does not follow
  /// the task to another project.
  String? _categoryProject;

  // -- An existing task's committed, unsaved values -------------------------
  _Held<ReminderValue?>? _heldReminder;
  _Held<String?>? _heldCategory;

  /// The reminder in the chip came from AI (a dictation's answer).
  bool _reminderFromAi = false;

  /// Bumped each time a token of that kind gives its chip a new value: the
  /// chip's pulse.
  final Map<TokenKind, int> _flash = <TokenKind, int>{};
  final Map<TokenKind, String?> _lastValue = <TokenKind, String?>{};

  /// Categories by project, as they arrive: what `/категория` matches.
  final Map<String, List<SmartCategory>> _categories =
      <String, List<SmartCategory>>{};
  String _contextSignature = '';

  bool _creating = false;

  bool get _draft => widget.taskId == null;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  ProjectTasks _tasksOf(String projectId) =>
      ref.read(projectTasksProvider(projectId).notifier);

  ProjectTasks get _tasks => _tasksOf(widget.projectId);

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    if (prefill != null) {
      _title.reset(prefill.title);
      _note.reset(prefill.description ?? '');
      if (_note.text.trim().isNotEmpty) _noteOpen = true;
      if (prefill.remindAt case final date?) {
        _reminder = ReminderValue(date, prefill.remindTime);
        _reminderFromAi = true;
      }
      _tidyParseId = prefill.parseId;
    }
    _rememberValues();
    _title.addListener(_onTitleChanged);
    _note.addListener(_changed);
    _extras.addListener(_changed);
  }

  @override
  void dispose() {
    _title.removeListener(_onTitleChanged);
    _note.removeListener(_changed);
    _extras.removeListener(_changed);
    _title.dispose();
    _note.dispose();
    _titleFocus.dispose();
    _noteFocus.dispose();
    _extras.dispose();
    super.dispose();
  }

  // -- Recognition -----------------------------------------------------------

  List<BoardProject> _boardProjects() {
    final view = ref.read(boardViewProvider);
    return view is BoardReady ? view.projects : const <BoardProject>[];
  }

  SmartContext _smartContext() {
    final projects = _draft
        ? <SmartProject>[
            for (final entry in _boardProjects())
              SmartProject(
                id: entry.project.id,
                name: entry.project.name,
                categories: _categories[entry.project.id],
              ),
          ]
        : const <SmartProject>[];
    return SmartContext(
      projects: projects,
      categories: _categories[_draft ? _projectId : widget.projectId] ??
          const <SmartCategory>[],
    );
  }

  static String? _tokenValue(SmartToken? token) => switch (token) {
    null => null,
    SmartToken(kind: TokenKind.date) =>
      '${token.remindAt} ${token.remindTime}',
    SmartToken(kind: TokenKind.project) => token.projectId,
    SmartToken(kind: TokenKind.category) => token.categoryId,
  };

  void _rememberValues() {
    for (final kind in TokenKind.values) {
      _lastValue[kind] = _tokenValue(_title.activeOf(kind));
    }
  }

  /// Any change of the text or the extras: the chips, the save button and
  /// the guard follow it. Also called while this widget builds (filling the
  /// fields from the row), which `setState` allows for the widget itself.
  void _changed() {
    if (mounted) setState(() {});
  }

  /// The chips' pulse: a kind whose token now says something new.
  void _onTitleChanged() {
    for (final kind in TokenKind.values) {
      final value = _tokenValue(_title.activeOf(kind));
      if (value != null && value != _lastValue[kind]) {
        _flash[kind] = (_flash[kind] ?? 0) + 1;
        if (kind == TokenKind.date) _reminderFromAi = false;
      }
      _lastValue[kind] = value;
    }
    _changed();
  }

  /// Keeps what `/категория` and `#проект` match against current, and
  /// re-parses when it changes.
  void _syncContext() {
    final target = _targetProject;
    final ids = <String>{_draft ? _projectId : widget.projectId, target};
    for (final id in ids) {
      final rows = ref.watch(projectCategoriesProvider(id)).value;
      if (rows != null) {
        _categories[id] = <SmartCategory>[
          for (final row in rows) SmartCategory(id: row.id, name: row.name),
        ];
      }
    }
    final projects = _draft ? _boardProjects() : const <BoardProject>[];
    if (_draft) ref.watch(boardViewProvider);
    final signature = <String>[
      for (final entry in projects) '${entry.project.id}=${entry.project.name}',
      for (final entry in _categories.entries)
        '${entry.key}:${entry.value.map((c) => '${c.id}=${c.name}').join(',')}',
    ].join('|');
    if (signature == _contextSignature) return;
    _contextSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // An existing task's untouched text: what the context now recognises
      // was written before this session too, so it is dismissed, not applied.
      if (!_draft && _openedTitle != null && _title.text == _openedTitle) {
        _title.dismissAll();
      } else {
        _title.refresh();
      }
      _rememberValues();
    });
  }

  // -- The values the chips show -------------------------------------------

  /// Where a new task will be created: a `#проект` token, else the header
  /// chip. An existing task's own project.
  String get _targetProject {
    if (!_draft) return widget.projectId;
    return _title.activeOf(TokenKind.project)?.projectId ?? _projectId;
  }

  ReminderValue? _reminderOf(Task? task) {
    final token = _title.activeOf(TokenKind.date);
    if (token != null) return ReminderValue(token.remindAt!, token.remindTime);
    if (_draft) return _reminder;
    if (_heldReminder case final held?) return held.value;
    return ReminderValue.fromRow(task?.remindAt, task?.remindTime);
  }

  String? _categoryOf(Task? task) {
    final token = _title.activeOf(TokenKind.category);
    if (token != null) return token.categoryId;
    if (_draft) {
      return _categoryProject == _targetProject ? _categoryId : null;
    }
    if (_heldCategory case final held?) return held.value;
    return task?.categoryId;
  }

  /// Before the text is replaced by AI: what the tokens say becomes the
  /// manual value, so a piece the model cut out keeps its effect.
  void _commitTokens(Task? task) {
    final date = _title.activeOf(TokenKind.date);
    final category = _title.activeOf(TokenKind.category);
    final project = _title.activeOf(TokenKind.project);
    if (_draft) {
      if (project != null) _projectId = project.projectId!;
      if (date != null) {
        _reminder = ReminderValue(date.remindAt!, date.remindTime);
      }
      if (category != null) {
        _categoryId = category.categoryId;
        _categoryProject = _targetProject;
      }
    } else {
      if (date != null) {
        _heldReminder = _Held(ReminderValue(date.remindAt!, date.remindTime));
      }
      if (category != null) _heldCategory = _Held(category.categoryId);
    }
  }

  // -- Dirty ------------------------------------------------------------------

  bool _dirtyDraft() =>
      _title.text.trim().isNotEmpty ||
      _note.text.trim().isNotEmpty ||
      _reminder != null ||
      _categoryId != null ||
      _newStatus != TaskStatus.pending ||
      _extras.isDirty;

  bool _reminderDiffers(Task task) =>
      task.status != TaskStatus.done &&
      _reminderOf(task) != ReminderValue.fromRow(task.remindAt, task.remindTime);

  bool _editedAgainst(Task task) =>
      _loadedFrom == task.id &&
      (_title.strippedText != task.title ||
          _note.text.trim() != (task.description ?? '').trim() ||
          _tidyParseId != null ||
          _reminderDiffers(task) ||
          _categoryOf(task) != task.categoryId ||
          _extras.isDirty);

  // -- Rows -------------------------------------------------------------------

  static List<Task>? _rows(ProjectView view) =>
      view is ProjectReady ? view.tasks : null;

  Task? _find(List<Task>? rows) {
    final id = widget.taskId;
    if (rows == null || id == null) return null;
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// The task as the list has it now.
  Task? get _row =>
      _find(_rows(ref.read(projectViewProvider(widget.projectId))));

  void _fill(Task task) {
    if (_loadedFrom == task.id) return;
    _loadedFrom = task.id;
    _title.reset(task.title);
    _title.dismissAll();
    _openedTitle = task.title;
    _note.reset(task.description ?? '');
    _noteOpen = _note.text.trim().isNotEmpty;
    _extras.loadFrom(task);
    _rememberValues();
  }

  // -- Writing ----------------------------------------------------------------

  /// Creates the task in [projectId], which may not be the project whose
  /// list is open (`#проект`, the header chip) -- so the provider is kept
  /// alive for the length of the write, as the dictation screen does.
  Future<WriteOutcome> _createIn(
    String projectId,
    String title, {
    String? description,
    String? categoryId,
    TaskStatus? status,
    ReminderValue? reminder,
    String? dictationParseId,
  }) async {
    final provider = projectTasksProvider(projectId);
    final keepAlive = ref.listenManual(provider, (_, _) {});
    try {
      return await ref
          .read(provider.notifier)
          .create(
            title,
            description: description,
            categoryId: categoryId,
            status: status,
            remindAt: reminder?.date,
            remindTime: reminder?.time,
            checklist: _extras.checklistForSave,
            location: _extras.location,
            dictationParseId: dictationParseId,
          );
    } finally {
      keepAlive.close();
    }
  }

  /// "Добавить" ([more]: "Добавить и ещё").
  Future<void> _create({bool more = false}) async {
    if (_creating) return;
    final title = _title.strippedText;
    if (title.isEmpty) {
      if (!more) Navigator.of(context).pop();
      return;
    }

    final project = _targetProject;
    final note = _note.text.trim();
    final reminder = _reminderOf(null);
    final category = _categoryOf(null);
    final messenger = ScaffoldMessenger.of(context);
    final projectName = _projectName(project);

    _creating = true;
    final outcome = await runMutationFor<WriteOutcome>(
      context,
      () => _createIn(
        project,
        title,
        description: note.isEmpty ? null : note,
        categoryId: category,
        status: _newStatus == TaskStatus.pending ? null : _newStatus,
        reminder: reminder,
        dictationParseId: _tidyParseId,
      ),
      failure: 'Не удалось добавить задачу.',
    );
    _creating = false;
    if (outcome == null || !mounted) return;
    await _extras.afterCreate(projectId: project, outcome: outcome);
    if (!mounted) return;

    // Said only where the result is not in view: another project's list, or
    // the sheet staying open for the next one.
    if (more || project != widget.projectId) {
      final where = projectName == null ? '' : ' в «$projectName»';
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              outcome.isQueued
                  ? 'Задача$where сохранена на телефоне — уйдёт при связи.'
                  : 'Задача добавлена$where.',
            ),
          ),
        );
    }

    if (more) {
      setState(_clearForNext);
      _titleFocus.requestFocus();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// "Добавить и ещё": an empty editor in the same project -- the old "five
  /// sentences, five Enters".
  void _clearForNext() {
    _projectId = _targetProject;
    _title.reset('');
    _note.reset('');
    _reminder = null;
    _reminderFromAi = false;
    _categoryId = null;
    _categoryProject = null;
    _newStatus = TaskStatus.pending;
    _tidyParseId = null;
    _extras.clear();
    _rememberValues();
  }

  Future<void> _save(Task task) async {
    final title = _title.strippedText;
    final note = _note.text.trim();
    final reminder = _reminderOf(task);
    final category = _categoryOf(task);
    final reminderChanged = _reminderDiffers(task);
    final categoryChanged = category != task.categoryId;

    // One PATCH of what changed (`ProjectTasks.edit` drops every field equal
    // to the row's): the text, what was recognised in it, the extras' edits.
    // A tidied text goes first as its own PATCH of both fields with the
    // record of the answer -- sent even when nothing changed, because "the
    // answer was right as it came" is the most useful label there is.
    final parseId = _tidyParseId;
    final checklist = _extras.checklistChanged
        ? PatchField<List<ChecklistItem>>.toOrClear(_extras.checklistForSave)
        : const PatchField<List<ChecklistItem>>.keep();
    final location = _extras.locationChanged
        ? PatchField<TaskLocation>.toOrClear(_extras.location)
        : const PatchField<TaskLocation>.keep();
    final ok = await runMutation(context, () async {
      var base = task;
      if (parseId != null) {
        await _tasks.editText(
          task,
          title: title,
          description: note.isEmpty ? null : note,
          dictationParseId: parseId,
        );
        base = _row ?? task;
      }
      final remind = reminderChanged && base.status != TaskStatus.done;
      await _tasks.edit(
        base,
        title: title,
        description: PatchField<String>.toOrClear(note.isEmpty ? null : note),
        categoryId: categoryChanged
            ? PatchField<String>.toOrClear(category)
            : const PatchField<String>.keep(),
        remindAt: remind
            ? PatchField<String>.toOrClear(reminder?.date)
            : const PatchField<String>.keep(),
        remindTime: remind && reminder != null
            ? PatchField<String>.toOrClear(reminder.time)
            : const PatchField<String>.keep(),
        checklist: checklist,
        location: location,
      );
    }, failure: 'Не удалось сохранить задачу.');
    if (!ok || !mounted) return;
    _tidyParseId = null;
    _heldReminder = null;
    _heldCategory = null;
    Navigator.of(context).pop();
  }

  // -- Status, reminder, category, project ------------------------------------

  /// Changes the status, and -- when the change is *into* `blocked` on a task
  /// with no date yet -- offers the day immediately: "Блокер" and "жду до
  /// вторника" are one thought. Cancelling is a real answer ("blocked, and I
  /// do not know when").
  Future<void> _setStatus(Task task, TaskStatus status) async {
    final wasBlocked = task.status == TaskStatus.blocked;
    final hadDate = task.remindAt != null;

    final ok = await runMutation(
      context,
      () => _tasks.setStatus(task, status),
      failure: 'Не удалось изменить статус.',
    );
    if (!ok || !mounted) return;
    if (status != TaskStatus.blocked || wasBlocked || hadDate) return;

    // Read fresh: the row the caller holds is the one from before the
    // change, still `pending`.
    final fresh = _row;
    if (fresh == null) return;
    final value = await pickReminderDayAndTime(context, ref);
    if (value == null || !mounted) return;
    _title.dismissKind(TokenKind.date);
    _heldReminder = null;
    await runMutation(
      context,
      () => _tasks.setRemindAt(fresh, value.date, time: value.time),
      failure: 'Не удалось сохранить дату напоминания.',
    );
  }

  /// A reminder chosen by hand -- the chip, or «Изменить…» on a date token.
  /// Dismisses the token; a new task keeps the value, an existing task
  /// writes it at once (a discrete control, as the status).
  Future<void> _setReminderByHand(ReminderValue? value) async {
    _title.dismissKind(TokenKind.date);
    if (_draft) {
      setState(() {
        _reminder = value;
        _reminderFromAi = false;
      });
      return;
    }
    setState(() {
      _heldReminder = null;
      _reminderFromAi = false;
    });
    final task = _row;
    if (task == null || task.status == TaskStatus.done) return;
    // Clearing what is not there is nothing; a value picked is written even
    // when it is the same -- the user confirmed a day.
    if (value == null && task.remindAt == null) return;
    await runMutation(
      context,
      () => _tasks.setRemindAt(task, value?.date, time: value?.time),
      failure: value == null
          ? 'Не удалось убрать дату напоминания.'
          : 'Не удалось сохранить дату напоминания.',
    );
  }

  Future<void> _editReminder(Task? task) async {
    final choice = await showReminderSheet(
      context,
      ref,
      current: _reminderOf(task),
      now: _now(),
    );
    if (choice == null || !mounted) return;
    await _setReminderByHand(choice.value);
  }

  Future<void> _pickCategory(Task? task) async {
    final current = _categoryOf(task);
    final project = _targetProject;
    final choice = await pickTaskCategory(
      context,
      projectId: project,
      current: current,
    );
    if (choice == null || !mounted) return;
    _title.dismissKind(TokenKind.category);
    if (_draft) {
      setState(() {
        _categoryId = choice.categoryId;
        _categoryProject = project;
      });
      return;
    }
    setState(() => _heldCategory = null);
    final row = _row ?? task;
    if (row == null || row.categoryId == choice.categoryId) return;
    await runMutation(
      context,
      () => _tasks.setCategory(row, choice.categoryId),
      failure: 'Не удалось сменить категорию.',
    );
  }

  String? _projectName(String id) {
    for (final entry in _boardProjects()) {
      if (entry.project.id == id) return entry.project.name;
    }
    final header = ref.read(projectHeaderProvider(id)).value;
    return header?.name;
  }

  /// A new task's project: every project on the board.
  Future<void> _pickProject() async {
    final projects = _boardProjects();
    final current = _targetProject;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'В какой проект',
                  style: EditorText.header.copyWith(fontSize: 18),
                ),
              ),
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                    'Проекты ещё не загрузились.',
                    style: EditorText.note,
                  ),
                ),
              for (final entry in projects)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(entry.project.name),
                  trailing: entry.project.id == current
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(entry.project.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _title.dismissKind(TokenKind.project);
    setState(() => _projectId = picked);
  }

  /// "Перенести в проект…" -- the picker and the move live in
  /// `widgets/move_task_sheet.dart`. Leaving afterwards: every control here
  /// addresses a row that is now somewhere else.
  Future<void> _moveToProject(Task task) async {
    final navigator = Navigator.of(context);
    final moved = await moveTaskToAnotherProject(context, ref, task);
    if (moved && navigator.canPop()) navigator.pop();
  }

  /// Back to the sandbox: for a task filed into the wrong project.
  Future<void> _unfile(Task task) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Вернуть в песочницу?',
      message:
          '«${task.title}» снова станет строкой в песочнице. Статус, '
          'напоминание и история задачи не сохранятся.',
      confirmLabel: 'Вернуть',
    );
    if (!confirmed || !mounted) return;

    final navigator = Navigator.of(context);
    final ok = await runMutation(
      context,
      () => _tasks.unfile(task),
      failure: 'Не удалось вернуть задачу в песочницу.',
      success: 'Задача вернулась в песочницу.',
    );
    if (ok && navigator.canPop()) navigator.pop();
  }

  Future<void> _delete(Task task) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Удалить задачу?',
      message: '«${task.title}» будет удалена без возможности восстановления.',
    );
    if (!confirmed || !mounted) return;

    final navigator = Navigator.of(context);
    final ok = await runMutation(
      context,
      () => _tasks.remove(task),
      failure: 'Не удалось удалить задачу.',
    );
    if (ok && navigator.canPop()) navigator.pop();
  }

  // -- Tokens in the field ------------------------------------------------------

  /// A tap in the title: on a token, its menu; on a link in a field that was
  /// not being edited, the link.
  void _onTitleTap() {
    final selection = _title.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final offset = selection.baseOffset;
    final token = _title.tokenAt(offset);
    if (token != null) {
      unawaited(_tokenMenu(token));
      return;
    }
    if (!_titleFocusedAtTap) {
      final link = _title.linkAt(offset);
      if (link != null) {
        _titleFocus.unfocus();
        unawaited(ref.read(linkOpenerProvider)(context, link.url));
      }
    }
  }

  void _onNoteTap() {
    if (_noteFocusedAtTap) return;
    final selection = _note.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final link = _note.linkAt(selection.baseOffset);
    if (link == null) return;
    _noteFocus.unfocus();
    unawaited(ref.read(linkOpenerProvider)(context, link.url));
  }

  /// Where the caret at [offset] is drawn, in global coordinates.
  Rect? _caretRect(int offset) {
    final root = _titleKey.currentContext?.findRenderObject();
    if (root == null) return null;
    RenderEditable? editable;
    void visit(RenderObject child) {
      if (editable != null) return;
      if (child is RenderEditable) {
        editable = child;
        return;
      }
      child.visitChildren(visit);
    }

    visit(root);
    final found = editable;
    if (found == null || !found.attached) return null;
    final local = found.getLocalRectForCaret(TextPosition(offset: offset));
    return found.localToGlobal(local.bottomLeft) & const Size(1, 1);
  }

  String _tokenWord(TokenKind kind) => switch (kind) {
    TokenKind.date => 'Не дата',
    TokenKind.project => 'Не проект',
    TokenKind.category => 'Не категория',
  };

  /// The highlight, tapped: «Не дата» / «Изменить…», or for an ambiguous
  /// `#…` / `/…` the names it could be.
  Future<void> _tokenMenu(SmartToken token) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final caret =
        _caretRect(token.end) ??
        (_titleKey.currentContext?.findRenderObject() as RenderBox?)
            ?.paintBounds ??
        Rect.zero;
    final candidates = token.isResolved
        ? const <({String id, String name})>[]
        : _candidateNames(token);

    final picked = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(caret, Offset.zero & overlay.size),
      items: <PopupMenuEntry<Object>>[
        for (final candidate in candidates)
          PopupMenuItem<Object>(
            value: candidate,
            child: Text(
              '${token.kind == TokenKind.project ? '#' : '/'}${candidate.name}',
            ),
          ),
        PopupMenuItem<Object>(
          value: _TokenAction.dismiss,
          child: Text(_tokenWord(token.kind)),
        ),
        if (token.isResolved)
          const PopupMenuItem<Object>(
            value: _TokenAction.change,
            child: Text('Изменить…'),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case _TokenAction.dismiss:
        _title.dismiss(token);
      case _TokenAction.change:
        switch (token.kind) {
          case TokenKind.date:
            final choice = await showReminderSheet(
              context,
              ref,
              current: ReminderValue(token.remindAt!, token.remindTime),
              now: _now(),
            );
            if (choice == null || !mounted) return;
            await _setReminderByHand(choice.value);
          case TokenKind.project:
            await _pickProject();
          case TokenKind.category:
            await _pickCategory(_row);
        }
      case final ({String id, String name}) candidate:
        _chooseCandidate(token, candidate.name);
    }
  }

  /// Writes the full name in place of an ambiguous prefix, so the text says
  /// exactly which one: `#до` → `#Дом`, a name with spaces in quotes.
  void _chooseCandidate(SmartToken token, String name) {
    final mark = token.kind == TokenKind.project ? '#' : '/';
    final written = name.contains(' ') ? '$mark"$name"' : '$mark$name';
    _title.replaceRange(token.start, token.end, written);
  }

  List<({String id, String name})> _candidateNames(SmartToken token) {
    final names = <String, String>{
      if (token.kind == TokenKind.project)
        for (final entry in _boardProjects())
          entry.project.id: entry.project.name
      else
        for (final category
            in _categories[_targetProject] ?? const <SmartCategory>[])
          category.id: category.name,
    };
    return <({String id, String name})>[
      for (final id in token.candidates)
        if (names[id] case final name?) (id: id, name: name),
    ];
  }

  // -- AI: tidy, dictation ----------------------------------------------------

  /// The fields' AI mark, against the text as it stands on the screen.
  AiMark _markOf(Task task) =>
      taskAiMark(task, title: _title.text, description: _note.text);

  /// Replaces the title and the description with an AI answer: the tokens'
  /// values are kept (committed), the new text is read as new.
  void _replaceText(String title, String? description, {Task? task}) {
    _commitTokens(task);
    _title.reset(title);
    _note.reset(description ?? '');
    if (_note.text.isNotEmpty) _noteOpen = true;
    _rememberValues();
  }

  /// A reminder AI proposed (a dictation's answer): into the chip, marked.
  void _setAiReminder(ReminderValue value) {
    if (_draft) {
      _reminder = value;
    } else {
      _heldReminder = _Held(value);
    }
    _reminderFromAi = true;
  }

  Future<void> _tidy() async {
    final note = _note.text.trim();
    final current = (
      title: _title.text.trim(),
      description: note.isEmpty ? null : note,
    );
    if (current.title.isEmpty && current.description == null) return;

    final tidied = await (widget.onTidy ?? _tidyWithModel)(current);
    if (tidied == null || !mounted) return;
    setState(() => _replaceText(tidied.title, tidied.description, task: _row));
  }

  /// "Причесать" in the app: [AiTidyScreen], from the title and the
  /// description as they stand -- one source, the title on its first line.
  /// Text AI processed whole and nobody touched since goes from the source
  /// the server kept instead: the model never works from its own answer.
  Future<TaskText?> _tidyWithModel(TaskText current) async {
    final joined = _joinedSource(current);
    final task = _row;
    final source = task == null || task.aiKind == 'note'
        ? joined
        : _markOf(task).tidySource(joined);
    final outcome = await openAiTidy(
      context,
      kind: ParseKind.taskTidy,
      source: source,
      destination: _projectName(_targetProject),
    );
    switch (outcome) {
      case TidyAccepted(
        result: TidiedTask(:final title, :final description, :final parseId),
      ):
        _tidyParseId = parseId;
        return (title: title, description: description);
      case TidyKeptSource(source: final kept) when kept != joined:
        _tidyParseId = null;
        if (task != null && source != joined) {
          return taskSourceFields(task, kept);
        }
        final lines = kept.split('\n');
        final rest = lines.skip(1).join('\n').trim();
        return (
          title: lines.first.trim(),
          description: rest.isEmpty ? null : rest,
        );
      default:
        return null;
    }
  }

  static String _joinedSource(TaskText text) => <String>[
    text.title,
    ?text.description,
  ].where((part) => part.isNotEmpty).join('\n');

  /// The "AI" mark: [AiTidyScreen] on the answer in the fields and the source
  /// the server kept -- compare, keep the source, or run the model again.
  Future<void> _openAiMark(Task task) async {
    final title = _title.text.trim();
    final note = _note.text.trim();
    final noteOnly = task.aiKind == 'note';
    final outcome = await openAiTidy(
      context,
      kind: noteOnly ? ParseKind.note : ParseKind.taskTidy,
      source: task.aiSource ?? '',
      result: noteOnly
          ? TidiedNote(content: note)
          : TidiedTask(title: title, description: note.isEmpty ? null : note),
      noteTitle: noteOnly && title.isNotEmpty ? title : null,
      destination: noteOnly ? null : _projectName(widget.projectId),
    );
    if (!mounted) return;
    switch (outcome) {
      case TidyAccepted(
        result: TidiedTask(:final title, :final description, :final parseId),
      ):
        setState(() {
          _replaceText(title, description, task: task);
          _tidyParseId = parseId ?? _tidyParseId;
        });
      case TidyAccepted(result: TidiedNote(:final content, :final parseId)):
        setState(() {
          _note.reset(content);
          _tidyParseId = parseId ?? _tidyParseId;
        });
      case TidyKeptSource(:final source):
        final fields = taskSourceFields(task, source);
        setState(() {
          _replaceText(fields.title, fields.description, task: task);
          _tidyParseId = null;
        });
      default:
        return;
    }
    if (_note.text.isNotEmpty) setState(() => _noteOpen = true);
  }

  /// Dictation into the task. A new, empty task asks for a whole task
  /// ([ParseKind.task]: the answer carries a reminder, which goes into the
  /// chip, marked AI); a task with text asks for the text and the words
  /// tidied together ([ParseKind.taskTidy]), as before. "Как надиктовано"
  /// appends the words to the title.
  Future<void> _dictate() async {
    final note = _note.text.trim();
    final title = _title.text.trim();
    final fresh = _draft && title.isEmpty && note.isEmpty;
    final result = await AppRoutes.openDictation(
      context,
      destination: FieldDestination(
        _draft ? 'в новую задачу' : 'в задачу',
        kind: fresh ? ParseKind.task : ParseKind.taskTidy,
        task: fresh
            ? null
            : (title: title, description: note.isEmpty ? null : note),
      ),
    );
    if (!mounted) return;
    switch (result) {
      case FieldWords(:final text) when text.isNotEmpty:
        appendDictated(_title, text: text);
      case FieldTaskText(
        :final title,
        :final description,
        :final parseId,
        :final remindAt,
        :final remindTime,
      ):
        setState(() {
          _replaceText(title, description, task: _row);
          _tidyParseId = parseId;
          if (remindAt != null) {
            _setAiReminder(ReminderValue(remindAt, remindTime));
          }
        });
      default:
        break;
    }
  }

  /// "Причесать" on the description alone: [ParseKind.note], with the title
  /// as the note's title so the model leaves it be.
  Future<void> _tidyNote() async {
    final current = _note.text.trim();
    if (current.isEmpty) return;
    final title = _title.text.trim();
    final task = _row;
    final source = task != null && task.aiKind == 'note'
        ? _markOf(task).tidySource(current)
        : current;
    final outcome = await openAiTidy(
      context,
      kind: ParseKind.note,
      source: source,
      noteTitle: title.isEmpty ? null : title,
    );
    if (!mounted) return;
    switch (outcome) {
      case TidyAccepted(result: TidiedNote(:final content, :final parseId)):
        setState(() {
          _note.reset(content);
          _tidyParseId = parseId;
        });
      case TidyKeptSource(:final source) when source != _note.text.trim():
        setState(() {
          _note.reset(source);
          _tidyParseId = null;
        });
      default:
        break;
    }
  }

  /// Dictation into the description: the words, as said or tidied as a
  /// note, on a new line after what it holds.
  Future<void> _dictateNote() async {
    final result = await AppRoutes.openDictation(
      context,
      destination: const FieldDestination('в описание'),
    );
    if (!mounted) return;
    final text = switch (result) {
      FieldWords(:final text) => text,
      FieldTaskText(:final title, :final description) => <String>[
        title,
        ?description,
      ].join('\n'),
      null => '',
    };
    if (text.isEmpty) return;
    setState(() {
      _noteOpen = true;
      appendDictated(_note, text: text, separator: '\n');
    });
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Read above any Scaffold, which strips the inset from its body.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    _syncContext();

    if (_draft) {
      return _guarded(
        isDirty: _dirtyDraft,
        message: 'Новая задача не будет создана.',
        onSave: () async {
          // `_create` leaves the editor itself when the task is created.
          await _create();
          return false;
        },
        child: _frame(task: null, keyboard: keyboard),
      );
    }

    // Through the project fold, not the network list alone: opened from a
    // project drawn out of the board snapshot (no network, or a reminder tap
    // on a cold start), the network list holds only an error.
    final view = ref.watch(projectViewProvider(widget.projectId));
    final task = _find(_rows(view));
    if (task == null) return _missing(view);

    _fill(task);
    return _guarded(
      isDirty: () => _editedAgainst(task),
      message: 'Правка задачи «${task.title}» будет потеряна.',
      onSave: () async {
        await _save(task);
        return false;
      },
      child: _frame(task: task, keyboard: keyboard),
    );
  }

  Widget _guarded({
    required bool Function() isDirty,
    required String message,
    required Future<bool> Function() onSave,
    required Widget child,
  }) {
    return UnsavedChangesGuard(
      listenable: Listenable.merge(<Listenable>[_title, _note, _extras]),
      isDirty: isDirty,
      message: message,
      onSave: onSave,
      child: child,
    );
  }

  Widget _missing(ProjectView view) {
    return _themed(
      Scaffold(
        backgroundColor: EditorColors.background,
        appBar: AppBar(
          backgroundColor: EditorColors.background,
          foregroundColor: EditorColors.ink,
          title: Text('Задача', style: EditorText.header),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  switch (view) {
                    ProjectUnavailable(:final error) =>
                      'Не удалось открыть задачу. ${describeApiError(error)}',
                    ProjectReady() || ProjectMissing() =>
                      'Задача не найдена — её могли удалить или перенести.',
                    ProjectLoading() => 'Загружаем задачу…',
                  },
                  textAlign: TextAlign.center,
                  style: EditorText.body.copyWith(color: EditorColors.muted),
                ),
                if (view is ProjectUnavailable) ...<Widget>[
                  const SizedBox(height: 16),
                  EditorSecondaryButton(
                    label: 'Повторить',
                    onPressed: () => ref
                        .read(projectTasksProvider(widget.projectId).notifier)
                        .refresh(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _themed(Widget child) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: editorOverlayStyle,
      child: Theme(data: editorTheme, child: child),
    );
  }

  /// The editor in its frame: a page, a sheet (compact or expanded), a
  /// dialog. Rebuilt with every keystroke (see [_changed]) -- the chips
  /// follow the text.
  Widget _frame({required Task? task, required bool keyboard}) {
    // The attribute row rides above the keyboard while typing, as Todoist's
    // toolbar does.
    final pinBar = keyboard;
    final header = _header(task);
    final body = _body(task, pinBar: pinBar);
    final bottom = _bottom(task, keyboard: keyboard, pinBar: pinBar);
    final content = switch (widget.presentation) {
      EditorPresentation.sheet => _sheetFrame(header, body, bottom),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          Expanded(child: body),
          bottom,
        ],
      ),
    };

    return _themed(switch (widget.presentation) {
      EditorPresentation.page => Scaffold(
        backgroundColor: EditorColors.background,
        body: SafeArea(child: content),
      ),
      EditorPresentation.dialog => Material(
        color: EditorColors.background,
        child: content,
      ),
      EditorPresentation.sheet => Material(
        color: EditorColors.background,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: content,
        ),
      ),
    });
  }

  /// Compact: as tall as its content; expanded: the whole height the sheet
  /// may take. Dragging the handle up (or `⤢`) expands -- the same state,
  /// nothing lost.
  Widget _sheetFrame(Widget header, Widget body, Widget bottom) {
    final handle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200 && !_expanded) setState(() => _expanded = true);
        if (velocity > 200 && _expanded) setState(() => _expanded = false);
      },
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: EditorColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final column = Column(
          mainAxisSize: _expanded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            handle,
            header,
            if (_expanded) Expanded(child: body) else Flexible(child: body),
            bottom,
          ],
        );
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _expanded && constraints.hasBoundedHeight
              ? SizedBox(height: constraints.maxHeight, child: column)
              : column,
        );
      },
    );
  }

  Widget _header(Task? task) {
    final projectId = _targetProject;
    final projectName =
        _projectName(projectId) ??
        ref.watch(projectHeaderProvider(projectId)).value?.name;
    final compactSheet =
        widget.presentation == EditorPresentation.sheet && !_expanded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, size: 22),
            color: EditorColors.muted,
          ),
          Expanded(
            child: Text(
              _draft ? 'Новая задача' : 'Задача',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorText.header,
            ),
          ),
          if (projectName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AttributeChip(
                icon: Icons.folder_outlined,
                label: projectName,
                filled: true,
                flash: _flash[TokenKind.project],
                // A new task's project is switchable; an existing task's
                // chip is the way to move it to another project.
                tooltip: _draft ? 'Проект задачи' : 'Перенести в проект…',
                onTap: _draft
                    ? () => unawaited(_pickProject())
                    : () => unawaited(_moveToProject(task!)),
              ),
            ),
          if (compactSheet)
            IconButton(
              tooltip: 'Развернуть',
              onPressed: () => setState(() => _expanded = true),
              icon: const Icon(Icons.open_in_full, size: 20),
              color: EditorColors.bright,
            ),
          if (task != null)
            PopupMenuButton<_TaskAction>(
              tooltip: 'Ещё',
              icon: const Icon(Icons.more_horiz, color: EditorColors.bright),
              onSelected: (action) => switch (action) {
                _TaskAction.unfile => unawaited(_unfile(task)),
                _TaskAction.delete => unawaited(_delete(task)),
              },
              itemBuilder: (_) => const <PopupMenuEntry<_TaskAction>>[
                PopupMenuItem<_TaskAction>(
                  value: _TaskAction.unfile,
                  child: Text('Вернуть в песочницу'),
                ),
                PopupMenuItem<_TaskAction>(
                  value: _TaskAction.delete,
                  child: Text('Удалить задачу'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _body(Task? task, {required bool pinBar}) {
    final full = widget.presentation != EditorPresentation.sheet || _expanded;
    final scope = EditorSectionScope(
      projectId: _targetProject,
      task: task,
      extras: _extras,
      expanded: full,
    );
    final links = <LinkSpan>[..._title.links, ..._note.links];
    final ambiguous = _title.tokens
        .where((token) => !token.isResolved)
        .toList(growable: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        4,
        Insets.gutter,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _titleCard(task),
          for (final token in ambiguous) _candidateRow(token),
          if (!pinBar) ...<Widget>[
            const SizedBox(height: 8),
            _attributeBar(task, scope),
          ],
          if (full) ...<Widget>[
            const SizedBox(height: 14),
            _descriptionSection(),
            if (links.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              LinkCards(links: links),
            ],
            _slot(EditorSlots.checklist(scope)),
            _slot(EditorSlots.attachments(scope)),
            _slot(EditorSlots.location(scope)),
            if (task == null) ...<Widget>[
              const SizedBox(height: 18),
              _statusSegments(
                statuses: const <TaskStatus>[
                  TaskStatus.pending,
                  TaskStatus.blocked,
                ],
                current: _newStatus,
                onTap: (status) => setState(() => _newStatus = status),
              ),
            ],
            if (task != null) ...<Widget>[
              const SizedBox(height: 18),
              _statusRow(task),
              const SizedBox(height: Insets.gap),
              // The set's rows carry the project's name; until the header
              // has loaded the optimistic row goes without it.
              FocusToggleButton(
                task: task,
                projectName: _projectName(widget.projectId) ?? '',
                onDark: true,
              ),
              const SizedBox(height: Insets.gap),
              _LifeOfTask(task: task),
            ],
          ],
        ],
      ),
    );
  }

  Widget _slot(Widget section) => AnimatedSize(
    duration: const Duration(milliseconds: 200),
    alignment: Alignment.topCenter,
    child: section,
  );

  /// The title, and under it the two things done *to* the text.
  Widget _titleCard(Task? task) {
    final hasText =
        _title.text.trim().isNotEmpty || _note.text.trim().isNotEmpty;
    return ListenableBuilder(
      listenable: _titleFocus,
      builder: (context, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: EditorColors.well,
          border: Border.all(
            color: _titleFocus.hasFocus
                ? EditorColors.focus
                : EditorColors.line,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(Radii.row),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Listener(
              onPointerDown: (_) => _titleFocusedAtTap = _titleFocus.hasFocus,
              child: TextField(
                key: _titleKey,
                controller: _title,
                focusNode: _titleFocus,
                autofocus: _draft && widget.prefill == null,
                // Two lines at least -- an empty field still reads as a
                // place to write (F12) -- and no upper bound: the screen
                // scrolls, the field does not.
                minLines: 2,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: EditorText.title,
                cursorColor: EditorColors.bright,
                onTap: _onTitleTap,
                decoration: InputDecoration(
                  filled: false,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: _draft
                      ? 'Что надо сделать — «завтра в 10», #проект, /категория'
                      : 'Что надо сделать',
                  hintMaxLines: 2,
                  hintStyle: EditorText.title.copyWith(
                    color: EditorColors.line,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: task == null
                      ? const SizedBox.shrink()
                      // Shrunk rather than overflowing when the pills
                      // beside it take the row.
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AiSourceMark(
                              mark: _markOf(task),
                              onOpen: () => unawaited(_openAiMark(task)),
                            ),
                          ),
                        ),
                ),
                // Only with text to tidy -- the title or the description.
                if (hasText)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: EditorPill(
                      icon: Icons.auto_awesome,
                      label: 'Причесать',
                      onTap: () => unawaited(_tidy()),
                    ),
                  ),
                EditorPill(
                  icon: Icons.mic_none,
                  accent: true,
                  tooltip: _draft ? 'Продиктовать' : 'Дописать голосом',
                  onTap: () => unawaited(_dictate()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// An ambiguous `#до` / `/по`: the names it could be, one tap each.
  Widget _candidateRow(SmartToken token) {
    final names = _candidateNames(token);
    if (names.isEmpty) return const SizedBox.shrink();
    final mark = token.kind == TokenKind.project ? '#' : '/';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            token.kind == TokenKind.project ? 'Проект:' : 'Категория:',
            style: EditorText.note,
          ),
          for (final candidate in names)
            ActionChip(
              label: Text('$mark${candidate.name}'),
              labelStyle: EditorText.chip,
              backgroundColor: EditorColors.well,
              side: const BorderSide(color: EditorColors.line),
              shape: const StadiumBorder(),
              onPressed: () => _chooseCandidate(token, candidate.name),
            ),
        ],
      ),
    );
  }

  Widget _attributeBar(Task? task, EditorSectionScope scope) {
    final now = _now();
    final showReminder = task == null || task.status != TaskStatus.done;
    final reminder = _reminderOf(task);
    final categoryId = _categoryOf(task);
    final categories =
        ref.watch(projectCategoriesProvider(_targetProject)).value ??
        const <TaskCategory>[];
    String? categoryName;
    for (final category in categories) {
      if (category.id == categoryId) categoryName = category.name;
    }
    final past = reminder != null && reminderIsPast(reminder, now: now);

    return AttributeBar(
      chips: <Widget>[
        if (showReminder)
          AttributeChip(
            icon: reminder == null ? Icons.alarm_add : Icons.alarm,
            label: reminder == null
                ? '+ Напомнить'
                : reminderChipLabel(reminder, now: now),
            filled: reminder != null,
            alarm: past,
            note: past ? 'уже прошло' : null,
            aiMark: _reminderFromAi && reminder != null,
            flash: _flash[TokenKind.date],
            tooltip: 'Напоминание',
            onTap: () => unawaited(_editReminder(task)),
            onClear: reminder == null
                ? null
                : () => unawaited(_setReminderByHand(null)),
            clearTooltip: 'Убрать напоминание',
          ),
        ...EditorSlots.chips(
          scope,
          onOpen: () => setState(() => _expanded = true),
        ),
        AttributeChip(
          icon: Icons.label_outline,
          label: categoryName ?? 'Без категории',
          filled: categoryName != null,
          flash: _flash[TokenKind.category],
          tooltip: 'Категория',
          onTap: () => unawaited(_pickCategory(task)),
        ),
      ],
    );
  }

  /// The description: open from the start on a new task, folded away on an
  /// existing one until it has text or is asked for -- the screen that
  /// matters is the text and what to do with it.
  Widget _descriptionSection() {
    if (!_noteOpen) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            setState(() => _noteOpen = true);
            _noteFocus.requestFocus();
          },
          icon: const Icon(Icons.notes, size: 18),
          label: const Text('+ Описание'),
          style: TextButton.styleFrom(
            foregroundColor: EditorColors.bright,
            minimumSize: const Size(0, Targets.minimum),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ),
      );
    }

    final hasNote = _note.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EditorSectionLabel(
          'ОПИСАНИЕ',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (hasNote)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: EditorPill(
                    icon: Icons.auto_awesome,
                    label: 'Причесать',
                    onTap: () => unawaited(_tidyNote()),
                  ),
                ),
              EditorPill(
                icon: Icons.mic_none,
                tooltip: 'Дописать в описание голосом',
                onTap: () => unawaited(_dictateNote()),
              ),
            ],
          ),
        ),
        Listener(
          onPointerDown: (_) => _noteFocusedAtTap = _noteFocus.hasFocus,
          child: TextField(
            controller: _note,
            focusNode: _noteFocus,
            minLines: 1,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            style: EditorText.body,
            cursorColor: EditorColors.bright,
            onTap: _onNoteTap,
            decoration: InputDecoration(
              filled: false,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Кто, что, к какому сроку…',
              hintStyle: EditorText.body.copyWith(color: EditorColors.line),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusRow(Task task) => _statusSegments(
    statuses: _statusOrder,
    current: task.status,
    onTap: (status) => unawaited(_setStatus(task, status)),
  );

  Widget _statusSegments({
    required List<TaskStatus> statuses,
    required TaskStatus current,
    required ValueChanged<TaskStatus> onTap,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: EditorColors.well,
        border: Border.all(color: EditorColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final status in statuses) ...<Widget>[
            Expanded(
              child: _StatusSegment(
                status: status,
                selected: current == status,
                onTap: () => onTap(status),
              ),
            ),
            if (status != statuses.last) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }

  Widget _bottom(Task? task, {required bool keyboard, required bool pinBar}) {
    final scope = EditorSectionScope(
      projectId: _targetProject,
      task: task,
      extras: _extras,
      expanded: widget.presentation != EditorPresentation.sheet || _expanded,
    );
    final Widget? button;
    if (task == null) {
      button = Row(
        children: <Widget>[
          Expanded(
            child: EditorPrimaryButton(
              label: 'Добавить',
              icon: Icons.add,
              compact: keyboard,
              onPressed: () => unawaited(_create()),
              onLongPress: () => unawaited(_create(more: true)),
            ),
          ),
          const SizedBox(width: 10),
          EditorSecondaryButton(
            icon: Icons.playlist_add,
            tooltip: 'Добавить и ещё',
            height: keyboard ? 56 : Targets.finishDictation,
            width: keyboard ? 56 : Targets.finishDictation,
            onPressed: () => unawaited(_create(more: true)),
          ),
        ],
      );
    } else {
      // "Сохранить" only while there is something to save: everything else
      // on this screen writes at once.
      button = _editedAgainst(task)
          ? EditorPrimaryButton(
              label: 'Сохранить',
              compact: keyboard,
              onPressed: () => unawaited(_save(task)),
            )
          : null;
    }

    // Not animated: a button that slides in while it is being reached for is
    // a button the tap misses.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (pinBar)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              6,
              Insets.gutter,
              0,
            ),
            child: _attributeBar(task, scope),
          ),
        if (button != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              Insets.gutter,
              10,
              Insets.gutter,
              keyboard ? 10 : 18,
            ),
            child: button,
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

/// `pending -> blocked -> done`: the order a task travels in, with the
/// final-feeling "done" at the far end.
const List<TaskStatus> _statusOrder = <TaskStatus>[
  TaskStatus.pending,
  TaskStatus.blocked,
  TaskStatus.done,
];

/// One segment of the status control. "Открыта", not "В очереди": a task
/// nobody has taken is simply open.
class _StatusSegment extends StatelessWidget {
  const _StatusSegment({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final TaskStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      TaskStatus.pending => 'Открыта',
      TaskStatus.blocked => 'Блокер',
      TaskStatus.done => 'Сделано',
    };
    final foreground = !selected
        ? EditorColors.muted
        : switch (status) {
            TaskStatus.pending => EditorColors.ink,
            TaskStatus.blocked => EditorColors.blocked,
            TaskStatus.done => EditorColors.done,
          };

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.railActive : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorText.chip.copyWith(
                fontSize: 13.5,
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Жизнь задачи»: куда ушло время, по журналу (F13). Одна строка — полоска и
/// «открыта 11 дней · с 17.09»; тап раскрывает разбивку по фазам. Журнал
/// грузится отдельным запросом (`GET /tasks/:id/events`); пока он едет или
/// если не доехал, блок показывает общий срок из `createdAt` и говорит, почему
/// разбивки нет. Перенесено из старого экрана задачи без изменений смысла,
/// только в тёмной гамме редактора.
class _LifeOfTask extends ConsumerStatefulWidget {
  const _LifeOfTask({required this.task});

  final Task task;

  @override
  ConsumerState<_LifeOfTask> createState() => _LifeOfTaskState();
}

class _LifeOfTaskState extends ConsumerState<_LifeOfTask> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final journal = ref.watch(taskEventsProvider(task.id));
    final totalDays = daysSince(task.createdAt);

    final life = switch (journal.value) {
      final List<TaskEvent> events => replayTaskLife(
        createdAt: task.createdAt,
        status: task.status,
        // `focusedAt` is the set row's, not the task's; it is only the
        // fallback for a task with no journal at all.
        focusedAt: null,
        events: events,
      ),
      null => null,
    };

    if (life == null && totalDays == null) return const SizedBox.shrink();

    if (!_expanded) return _line(life, totalDays, journal.hasError);

    return Container(
      decoration: BoxDecoration(
        color: EditorColors.well,
        border: Border.all(color: EditorColors.line),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: _toggle,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  'ЖИЗНЬ ЗАДАЧИ',
                  style: AppText.sectionLabel.copyWith(
                    color: EditorColors.muted,
                  ),
                ),
                const Spacer(),
                Text(
                  life == null
                      ? formatDays(totalDays!)
                      : formatSpanLong(life.totalMs),
                  style: AppText.numberSmall.copyWith(color: EditorColors.ink),
                ),
              ],
            ),
          ),
          if (life == null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              journal.hasError
                  ? 'Журнал переходов не прочитался — разбивки по статусам '
                        'не будет. Остальное на экране работает.'
                  : 'Считаем по журналу переходов…',
              style: EditorText.note.copyWith(fontSize: 12),
            ),
          ] else
            ..._breakdown(life),
        ],
      ),
    );
  }

  Widget _line(TaskLife? life, int? totalDays, bool failed) {
    final String text;
    if (life == null) {
      text =
          'живёт ${formatDays(totalDays!)} · '
          '${failed ? 'журнал не прочитался' : 'считаем…'}';
    } else {
      final current = DateTime.now().toUtc().difference(life.since);
      text =
          '${_currentPhrase(life.phase)} '
          '${formatSpanLong(current.inMilliseconds)} · '
          'с ${_shortDate(life.since)}';
    }

    return Semantics(
      button: true,
      hint: 'Показать жизнь задачи',
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: <Widget>[
                Expanded(
                  child: SpanBar(
                    height: 6,
                    segments: <SpanSegment>[
                      if (life != null)
                        for (final phase in _order)
                          if (life[phase] > 0)
                            SpanSegment(life[phase], phaseColour(phase)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.75,
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EditorText.note,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const List<TaskLifePhase> _order = <TaskLifePhase>[
    TaskLifePhase.queued,
    TaskLifePhase.working,
    TaskLifePhase.blocked,
    TaskLifePhase.done,
  ];

  List<Widget> _breakdown(TaskLife life) {
    final shown = <TaskLifePhase>[
      for (final phase in _order)
        if (life[phase] > 0) phase,
    ];

    return <Widget>[
      const SizedBox(height: 12),
      SpanBar(
        height: 16,
        segments: <SpanSegment>[
          for (final phase in shown)
            SpanSegment(life[phase], phaseColour(phase)),
        ],
      ),
      const SizedBox(height: 12),
      for (final phase in shown) ...<Widget>[
        if (phase != shown.first) const SizedBox(height: 9),
        _LifeRow(
          phase: phase,
          label: phase == life.phase
              ? '${_currentPhrase(phase)} с ${_shortDate(life.since)}'
              : phaseLabel(phase),
          ms: life[phase],
          emphasised: phase == TaskLifePhase.blocked,
        ),
      ],
    ];
  }

  static String _currentPhrase(TaskLifePhase phase) => switch (phase) {
    TaskLifePhase.queued => 'открыта',
    TaskLifePhase.working => 'в работе',
    TaskLifePhase.blocked => 'ждёт',
    TaskLifePhase.done => 'закрыта',
  };

  static String _shortDate(DateTime at) {
    final local = at.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}';
  }
}

class _LifeRow extends StatelessWidget {
  const _LifeRow({
    required this.phase,
    required this.label,
    required this.ms,
    this.emphasised = false,
  });

  final TaskLifePhase phase;
  final String label;
  final int ms;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        PhaseDot(phase: phase),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EditorText.body.copyWith(fontSize: 13.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatSpanShort(ms),
          maxLines: 1,
          softWrap: false,
          style: EditorText.chip.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: emphasised ? EditorColors.blocked : EditorColors.ink,
          ),
        ),
      ],
    );
  }
}
