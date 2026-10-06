import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dictation_api.dart';
import '../domain/reminders.dart';
import '../domain/task_age.dart';
import '../models/history_task_event.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../navigation/app_routes.dart';
import '../providers/history_providers.dart';
import '../providers/project_providers.dart';
import 'dictation_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ai_tidy.dart';
import '../widgets/dictation.dart';
import '../widgets/focus_toggle.dart';
import '../widgets/history_charts.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/reminder_time_picker.dart';

/// One task, large enough to read and edit (F12; compact blocks, variant A).
///
/// ## The field sizes to its text
///
/// Complaint number one was "в композере видно два-три слова, продиктованную
/// фразу нельзя ни прочитать, ни поправить". F12 answered it with a fixed
/// 252 px box at 20 px type, and the answer overshot: a one-line task opened
/// onto a screen that was mostly an empty frame, and everything below it --
/// status, focus, the note -- was pushed out of reach. Now the field is two
/// lines at least and grows with what is in it (`AppText.taskField`, 16.5 px),
/// so a long dictated sentence is still read whole and a short one does not
/// cost half the screen.
///
/// Under the text, inside the same card, sit the two things done *to* the
/// text: "Причесать" (the model tidying the title and the note, see
/// [TaskScreen.onTidy]) and the microphone, which appends. Then one full-width "Взять в работу", the
/// three statuses as a 38 px segmented control, the note, and the life of the
/// task folded into one line.
///
/// ## Why the whole screen scrolls
///
/// The reference page is exactly 844 px tall and everything fits. A real phone
/// is not: a 360x640 device, a system font scaled up, or the keyboard taking
/// two thirds of the display all make the same content taller than the window.
/// The save bar is pinned outside the scrollable, because the one control that
/// must never be scrolled away is the one that commits what was typed.
class TaskScreen extends ConsumerStatefulWidget {
  const TaskScreen({
    required this.projectId,
    required this.taskId,
    this.onTidy,
    super.key,
  });

  /// The screen for a task that does not exist yet.
  ///
  /// ## Why a new task gets the whole screen rather than a field on the list
  ///
  /// Because the brief says so -- *"инлайн-композеров с однострочным полем в
  /// новых экранах быть не должно"* -- and because the composer it replaces was
  /// complaint number one. The old project screen opened with a one-line field
  /// at the top of the list, which is exactly the field a dictated sentence
  /// could not be read in.
  ///
  /// The cost is one navigation per task, and it is smaller than it looks: the
  /// gesture that used to justify the inline field ("empty my head into the
  /// list", five sentences and five Enters) is now the microphone, which files
  /// straight into a project without opening anything at all.
  const TaskScreen.draft({required this.projectId, this.onTidy, super.key})
    : taskId = null;

  final String projectId;

  /// Null on [TaskScreen.draft]: there is no row yet, and "Сохранить" creates
  /// one.
  final String? taskId;

  /// "Причесать": the task's text -- title and note -- tidied into a title and
  /// a description: punctuation, filler words, misheard words, the shape of a
  /// dictated sentence, and nothing added. Returns null to leave the text as
  /// it is.
  ///
  /// Null, as in the app, opens [AiTidyScreen] with [ParseKind.taskTidy] and
  /// the text as its source. A test puts its own answer here.
  final TidyText? onTidy;

  @override
  ConsumerState<TaskScreen> createState() => _TaskScreenState();
}

/// A task's text: what "Причесать" reads and what it gives back.
typedef TaskText = ({String title, String? description});

/// See [TaskScreen.onTidy].
typedef TidyText = Future<TaskText?> Function(TaskText current);

class _TaskScreenState extends ConsumerState<TaskScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();

  /// The row the controllers were last filled from.
  ///
  /// The list underneath this screen is live -- an optimistic write, a refresh,
  /// a change made on another device -- and every rebuild would otherwise
  /// overwrite what is being typed. Filling only when the *identity* of the row
  /// changes means the server's version wins on arrival and the user's version
  /// wins while they are holding the keyboard.
  String? _loadedFrom;

  bool _noteOpen = false;

  /// The server's record of the tidied text now in the fields -- "Причесать",
  /// or a dictation "Разобрать" into this task -- sent with the save so the
  /// record learns what was kept (F15). Null once saved, and when the fields
  /// hold no answer.
  String? _tidyParseId;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  ProjectTasks get _tasks =>
      ref.read(projectTasksProvider(widget.projectId).notifier);

  bool get _draft => widget.taskId == null;

  Task? _find(List<Task>? rows) {
    final id = widget.taskId;
    if (rows == null || id == null) return null;
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// Creates the row this screen was opened to write.
  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final note = _note.text.trim();
    final ok = await runMutation(
      context,
      () => _tasks.create(
        title,
        description: note.isEmpty ? null : note,
        dictationParseId: _tidyParseId,
      ),
      failure: 'Не удалось добавить задачу.',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop();
  }

  void _fill(Task task) {
    if (_loadedFrom == task.id) return;
    _loadedFrom = task.id;
    _title.text = task.title;
    _note.text = task.description ?? '';
    _noteOpen = _note.text.trim().isNotEmpty;
  }

  Future<void> _save(Task task) async {
    final title = _title.text.trim();
    final note = _note.text.trim();

    // Both writes, but only the ones that changed: `editTitle` and
    // `editDescription` each short-circuit on an unchanged value, so this is
    // one PATCH in the common case and zero when nothing was touched. A
    // tidied text is one PATCH of both, with the record of the answer.
    final parseId = _tidyParseId;
    final ok = await runMutation(context, () async {
      if (parseId != null) {
        await _tasks.editText(
          task,
          title: title,
          description: note.isEmpty ? null : note,
          dictationParseId: parseId,
        );
        return;
      }
      await _tasks.editTitle(task, title);
      await _tasks.editDescription(task, note.isEmpty ? null : note);
    }, failure: 'Не удалось сохранить задачу.');
    if (!ok || !mounted) return;
    _tidyParseId = null;
    Navigator.of(context).pop();
  }

  /// Changes the status, and -- when the change is *into* `blocked` on a task
  /// with no date yet -- offers the date picker immediately.
  ///
  /// "Блокер" and "жду до вторника" are one thought. Left as two gestures the
  /// app fills up with dateless blockers, i.e. with tasks that are stuck and
  /// will never say so again, which is the failure the whole product exists to
  /// prevent. Cancelling the picker is a real answer, not a mistake: "blocked,
  /// and I do not know when" is a legitimate state and the row says so.
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

    await _pickReminder();
  }

  /// A new reminder: the day, then the time of day.
  Future<void> _pickReminder() async {
    // Read fresh rather than taken from the caller: this is reached straight
    // after a status change, and the row the caller is holding is the one from
    // before it -- still `pending`, which `setRemindAt` refuses.
    final task = _find(ref.read(projectTasksProvider(widget.projectId)).value);
    if (task == null) return;

    final picked = await _pickDay(task);
    if (picked == null || !mounted) return;

    // Then the time of day; dismissing it means "the day only".
    final time = await pickReminderTime(context, ref, task);
    if (!mounted) return;

    await runMutation(
      context,
      () => _tasks.setRemindAt(task, picked, time: time),
      failure: 'Не удалось сохранить дату напоминания.',
    );
  }

  /// An existing reminder, tapped: one menu for what can be changed in it --
  /// the day, the time, or taking the time off. Removing the whole reminder
  /// is the red cross on the row itself, one tap away, not in here.
  Future<void> _editReminder(Task task) async {
    final remindAt = task.remindAt;
    if (remindAt == null) return _pickReminder();
    final hasTime = task.remindTime != null;

    final choice = await showModalBottomSheet<_ReminderEdit>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                'Напомнить ${formatReminderDate(remindAt, task.remindTime)}',
                style: AppText.action,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Изменить дату'),
              onTap: () => Navigator.of(context).pop(_ReminderEdit.date),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(hasTime ? 'Изменить время' : 'Добавить время'),
              onTap: () => Navigator.of(context).pop(_ReminderEdit.time),
            ),
            if (hasTime)
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: const Text('Убрать время'),
                subtitle: const Text('Напомню в час из настроек'),
                onTap: () => Navigator.of(context).pop(_ReminderEdit.noTime),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final day = reminderCalendarDate(remindAt);
    switch (choice) {
      case _ReminderEdit.date:
        final picked = await _pickDay(task);
        if (picked == null || !mounted) return;
        await runMutation(
          context,
          // The time stays: changing the day of "в 14:30" keeps "в 14:30".
          () => _tasks.setRemindAt(task, picked, time: task.remindTime),
          failure: 'Не удалось изменить дату напоминания.',
        );
      case _ReminderEdit.time:
        if (day == null) return;
        // "Отмена" here, not "Без времени": this menu has its own line for
        // that, and dismissing a picker opened to change a time should change
        // nothing.
        final time = await pickReminderTime(
          context,
          ref,
          task,
          cancelText: 'Отмена',
        );
        if (time == null || !mounted) return;
        await runMutation(
          context,
          () => _tasks.setRemindAt(task, day, time: time),
          failure: 'Не удалось изменить время напоминания.',
        );
      case _ReminderEdit.noTime:
        if (day == null) return;
        await runMutation(
          context,
          () => _tasks.setRemindAt(task, day),
          failure: 'Не удалось убрать время напоминания.',
        );
    }
  }

  /// The day picker, as `YYYY-MM-DD`, or null when dismissed.
  Future<String?> _pickDay(Task task) async {
    final picked = await showDatePicker(
      context: context,
      // Re-assembled from its calendar parts rather than parsed as an instant;
      // `remindAtAsLocalDay` is where that distinction lives, and getting it
      // wrong opens the picker a day early for anyone west of UTC.
      initialDate: task.remindAt == null
          ? DateTime.now()
          : remindAtAsLocalDay(task.remindAt!) ?? DateTime.now(),
      // Today, not "no lower bound": a reminder in the past can never fire, so
      // offering one would be offering a button that silently does nothing.
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Когда напомнить',
      cancelText: 'Отмена',
      confirmText: 'Готово',
    );
    return picked == null ? null : calendarDateForApi(picked);
  }

  Future<void> _clearReminder(Task task) async {
    await runMutation(
      context,
      () => _tasks.setRemindAt(task, null),
      failure: 'Не удалось убрать дату напоминания.',
    );
  }

  /// Back to the sandbox: for a task filed into the wrong project, typically
  /// one whose right project does not exist yet.
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
      // The task disappears from here, so say where it went.
      success: 'Задача вернулась в песочницу.',
    );
    // Leaving, as after a delete: every control here addresses a row that is
    // gone.
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
    // Leaving on success, because staying would mean sitting on a screen whose
    // every control now addresses a row that is gone.
    if (ok && navigator.canPop()) navigator.pop();
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
    setState(() {
      _title.text = tidied.title;
      _note.text = tidied.description ?? '';
      // The description is half of the answer: folded away, it would look
      // as if the model had dropped it.
      if (_note.text.isNotEmpty) _noteOpen = true;
    });
  }

  /// "Причесать" in the app: [AiTidyScreen], from the title and the note as
  /// they stand -- one source, the title on its first line.
  Future<TaskText?> _tidyWithModel(TaskText current) async {
    final source = <String>[
      current.title,
      ?current.description,
    ].where((part) => part.isNotEmpty).join('\n');
    final outcome = await openAiTidy(
      context,
      kind: ParseKind.taskTidy,
      source: source,
      destination: ref
          .read(projectHeaderProvider(widget.projectId))
          .value
          ?.name,
    );
    switch (outcome) {
      case TidyAccepted(
        result: TidiedTask(:final title, :final description, :final parseId),
      ):
        _tidyParseId = parseId;
        return (title: title, description: description);
      // "Как надиктовано" after correcting the source by hand: the corrected
      // text is what the user asked for, split back the way it was joined.
      case TidyKeptSource(:final source) when source != _joinedSource(current):
        _tidyParseId = null;
        final lines = source.split('\n');
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

  /// Dictation into the task.
  ///
  /// As said, the words are appended to the title -- a phrase said in two
  /// goes is one thought continued. "Разобрать" on the dictation screen
  /// tidies the task's text and the words together (the screen is handed the
  /// text for that, see [FieldDestination.task]), and its answer replaces
  /// both fields, as "Причесать" does.
  Future<void> _dictate() async {
    final note = _note.text.trim();
    final result = await AppRoutes.openDictation(
      context,
      destination: FieldDestination(
        'в задачу',
        kind: ParseKind.taskTidy,
        task: (
          title: _title.text.trim(),
          description: note.isEmpty ? null : note,
        ),
      ),
    );
    if (!mounted) return;
    switch (result) {
      case FieldWords(:final text) when text.isNotEmpty:
        appendDictated(_title, text: text);
      case FieldTaskText(:final title, :final description, :final parseId):
        setState(() {
          _title.text = title;
          _note.text = description ?? '';
          if (_note.text.isNotEmpty) _noteOpen = true;
          _tidyParseId = parseId;
        });
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(projectTasksProvider(widget.projectId)).value;
    final header = ref.watch(projectHeaderProvider(widget.projectId)).value;
    final task = _find(rows);

    if (_draft) return _draftScaffold();

    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Задача')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              rows == null
                  ? 'Загружаем задачу…'
                  : 'Задача не найдена — её могли удалить или перенести.',
              textAlign: TextAlign.center,
              style: AppText.hint,
            ),
          ),
        ),
      );
    }

    _fill(task);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(task, header?.name),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Insets.gutter,
                  0,
                  Insets.gutter,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _textField(dictateTooltip: 'Дописать голосом'),
                    const SizedBox(height: Insets.gap),
                    // The set's rows carry the project's name; until the
                    // header has loaded the optimistic row goes without it,
                    // and the re-read after `take` fills it in.
                    FocusToggleButton(
                      task: task,
                      projectName: header?.name ?? '',
                    ),
                    const SizedBox(height: Insets.gap),
                    _statusRow(task),
                    if (task.status != TaskStatus.done) ...<Widget>[
                      const SizedBox(height: Insets.gap),
                      _reminderRow(task),
                    ],
                    const SizedBox(height: Insets.gap),
                    _noteSection(),
                    const SizedBox(height: Insets.gap),
                    _LifeOfTask(task: task),
                  ],
                ),
              ),
            ),
            _saveBar(task),
          ],
        ),
      ),
    );
  }

  /// The draft screen: the same field, and nothing that would be a lie
  /// about a row that does not exist yet -- no status (a new task is in the
  /// queue by definition), no reminder, no history, no delete.
  Widget _draftScaffold() {
    final header = ref.watch(projectHeaderProvider(widget.projectId)).value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 22),
                    color: AppColors.ink,
                  ),
                  Expanded(
                    child: Text('Новая задача', style: AppText.screenTight),
                  ),
                  if (header != null)
                    Text(
                      header.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.chip.copyWith(fontSize: 13),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _textField(dictateTooltip: 'Продиктовать'),
                    // Only once there is a note to show -- "Причесать" can
                    // give a new task its description before it exists.
                    if (_noteOpen) ...<Widget>[
                      const SizedBox(height: Insets.gap),
                      _noteSection(),
                    ],
                  ],
                ),
              ),
            ),
            _bottomButton('Добавить', () => unawaited(_create())),
          ],
        ),
      ),
    );
  }

  Widget _header(Task task, String? projectName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 22),
            color: AppColors.ink,
          ),
          Expanded(child: Text('Задача', style: AppText.screenTight)),
          if (projectName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                height: 26,
                constraints: const BoxConstraints(maxWidth: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.indigoFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.chip.copyWith(
                          color: AppColors.indigoInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            tooltip: 'Вернуть в песочницу',
            onPressed: () => unawaited(_unfile(task)),
            icon: const Icon(Icons.move_to_inbox_outlined, size: 21),
          ),
          IconButton(
            tooltip: 'Удалить задачу',
            onPressed: () => unawaited(_delete(task)),
            icon: const Icon(Icons.delete_outline, size: 21),
          ),
        ],
      ),
    );
  }

  /// The title, and under it the two things done *to* the title.
  Widget _textField({required String dictateTooltip}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.indigo, width: 1.5),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      // 1 at the bottom rather than 8, because the chips carry 7 px of hit area
      // above and below their 30 px -- see [_FieldChip].
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _title,
            // Sizes to its text: two lines at least, so an empty field still
            // reads as a place to write, and no upper bound -- the screen
            // scrolls, the field does not.
            minLines: 2,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            style: AppText.taskField,
            decoration: const InputDecoration(
              filled: false,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Что надо сделать',
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _FieldChip(
                icon: Icons.auto_awesome,
                label: 'Причесать',
                onTap: () => unawaited(_tidy()),
              ),
              const SizedBox(width: 4),
              _FieldChip(
                icon: Icons.mic_none,
                tooltip: dictateTooltip,
                onTap: () => unawaited(_dictate()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusRow(Task task) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.lineFaint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final status in _statusOrder) ...<Widget>[
            Expanded(
              child: _StatusSegment(
                status: status,
                selected: task.status == status,
                onTap: () => unawaited(_setStatus(task, status)),
              ),
            ),
            if (status != _statusOrder.last) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }

  Widget _reminderRow(Task task) {
    final remindAt = task.remindAt;
    final due =
        remindAt != null &&
        isReminderDue(remindAt, remindTime: task.remindTime);
    // A blocker keeps its amber; a plain open task's reminder is neutral.
    final blocked = task.status == TaskStatus.blocked;
    final ink = blocked ? AppColors.waitingInk : AppColors.indigoLink;

    return Material(
      color: blocked ? AppColors.waitingFill : AppColors.card,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        onTap: () => unawaited(_editReminder(task)),
        borderRadius: BorderRadius.circular(Radii.card),
        child: Container(
          height: 52,
          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
          decoration: BoxDecoration(
            border: Border.all(
              color: blocked ? AppColors.waitingLine : AppColors.line,
            ),
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                due
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none,
                size: 20,
                color: ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  remindAt == null
                      ? 'Напомнить когда-нибудь…'
                      : 'Напомнить '
                            '${formatReminderDate(remindAt, task.remindTime)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.action.copyWith(color: ink),
                ),
              ),
              if (remindAt == null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.chevron_right, size: 18, color: ink),
                )
              else
                // The one thing done to a reminder from the row: removing it,
                // date and time together. Everything else is in its menu.
                IconButton(
                  tooltip: 'Убрать напоминание',
                  onPressed: () => unawaited(_clearReminder(task)),
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.alarm,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The description.
  ///
  /// ## Why this is not in the reference and is here anyway
  ///
  /// `design/reference/Edit.html` draws one text area, because in the sketch a
  /// task *is* one sentence. The model has two fields -- `title` and
  /// `description` -- and the second one already holds text on eleven existing
  /// tasks. A screen that edited only the title would quietly make that text
  /// unreachable from the app, which is a data loss dressed up as a redesign.
  ///
  /// Folded away when empty, so the screen that matters (the text and what to
  /// do with it) is the screen you get unless you asked for more.
  Widget _noteSection() {
    if (!_noteOpen) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _noteOpen = true),
          icon: const Icon(Icons.notes, size: 18),
          label: const Text('Заметка к задаче'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.muted,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'ЗАМЕТКА',
            style: AppText.caption.copyWith(fontSize: 11, letterSpacing: 0.88),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            style: AppText.body.copyWith(fontSize: 14, height: 1.45),
            decoration: const InputDecoration(
              filled: false,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Кто, что, к какому сроку…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveBar(Task task) =>
      _bottomButton('Сохранить', () => unawaited(_save(task)));

  /// The one control pinned under the scrollable -- see the class comment. The
  /// microphone used to stand next to it; it is in the text card now, next to
  /// the text it writes into.
  Widget _bottomButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 20),
      child: SizedBox(
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.row),
            ),
            textStyle: AppText.action.copyWith(fontWeight: FontWeight.w700),
          ),
          onPressed: onPressed,
          child: Text(label),
        ),
      ),
    );
  }
}

/// A 30 px pill under the task text: "Причесать", or the microphone alone.
///
/// ## Why the hit area is taller than the pill
///
/// 30 px is what the card has room for without growing a second toolbar;
/// 44 px is the floor for anything tapped ([Targets.minimum]). The difference
/// is transparent padding above and below -- the card's own bottom padding is
/// trimmed to make room for it -- so the pill *looks* 30 and *catches* 44.
class _FieldChip extends StatelessWidget {
  const _FieldChip({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;

  static const double _height = 30;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final tooltip = this.tooltip;

    final pill = Material(
      color: AppColors.card,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.line)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: _height,
          width: label == null ? _height : null,
          child: label == null
              ? Icon(icon, size: 16, color: AppColors.indigoLink)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 14, color: AppColors.indigoLink),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: AppText.chip.copyWith(
                          fontSize: 12.5,
                          color: AppColors.indigoLink,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );

    final hit = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: (Targets.minimum - _height) / 2,
        ),
        child: pill,
      ),
    );

    return tooltip == null ? hit : Tooltip(message: tooltip, child: hit);
  }
}

/// `pending -> blocked -> done` is the order a task actually travels in, and it
/// puts the destructive-feeling "done" at the far end. Same order as the React
/// client's `STATUS_ORDER`, so muscle memory survives the migration.
/// What the menu of an existing reminder can do to it.
enum _ReminderEdit { date, time, noTime }

const List<TaskStatus> _statusOrder = <TaskStatus>[
  TaskStatus.pending,
  TaskStatus.blocked,
  TaskStatus.done,
];

/// One segment of the 38 px status control.
///
/// "Открыта" rather than the old "В очереди": a task nobody has taken is not
/// standing in any queue, it is simply open.
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

    // The selected segment is the white one. Its ink also says which status
    // it is for the two that are not the ordinary case.
    final foreground = !selected
        ? AppColors.muted
        : switch (status) {
            TaskStatus.pending => AppColors.ink,
            TaskStatus.blocked => AppColors.waitingInk,
            TaskStatus.done => AppColors.done,
          };

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.card : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.chip.copyWith(
                fontSize: 13,
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

/// «Жизнь задачи»: куда ушло время, по настоящему журналу (F13).
///
/// ## Что изменилось против F12
///
/// Раньше этот блок рисовал единственные два числа, выводимые из строки задачи:
/// «сколько живёт» и «сколько с последнего движения». Формой он был заготовкой
/// под журнал и прямо об этом писал. Журнал приехал (`task_events`, F11), и
/// теперь здесь то, ради чего он заводился: **четыре дня в очереди, один в
/// работе, три в блокере** — разбивка, которую две метки строки не могут дать в
/// принципе, потому что одиннадцать дней в блокере перестают существовать в ту
/// секунду, когда блокер снимают.
///
/// Композиция при этом ровно та же, что была и что в `design/reference/Edit.html`:
/// заголовок с общим сроком, полоска долей, строки-легенда. Менялся источник,
/// а не экран.
///
/// ## Почему журнал грузится отдельным запросом, а не приезжает с задачей
///
/// Потому что он нужен одному блоку одного экрана, а задача приходит в списке
/// проекта — вместе с двадцатью другими. Роут `GET /tasks/:id/events` стоит
/// одного индексного чтения и не делает `GET /projects/:id/tasks` в двадцать
/// раз толще ради секции, до которой на большинстве открытий не долистают.
///
/// Пока он едет и если он не доехал, блок остаётся на месте и показывает общий
/// срок: он выводится из `createdAt` и врать не может. Разница между «считаем»
/// и «не посчитали» подписана — экран задачи полностью рабочий в обоих случаях.
///
/// ## Одна строка, пока не попросили больше
///
/// Вариант A сжимает блок до тонкой полоски и одной подписи — «открыта 11 дней
/// · с 17.09»: текущая фаза, сколько она идёт и с какого дня. Большинство
/// открытий экрана задачи — чтобы поправить текст или статус, а не читать
/// биографию, и карточка на пол-экрана под полем отодвигала то, ради чего
/// пришли. Тап по строке раскрывает прежнюю карточку целиком — с разбивкой по
/// фазам и легендой; тап по её заголовку сворачивает обратно.
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
        // У клиентской модели задачи нет `focusedAt` — он есть у строки набора
        // (`FocusTask`) и в журнале, событиями `focused`/`unfocused`. Здесь он
        // нужен только как запасной ответ для задачи вообще без журнала, а у
        // такой задачи и набора никакого нет.
        focusedAt: null,
        events: events,
      ),
      null => null,
    };

    // Нечитаемая дата создания и пустой журнал вместе означают, что сказать
    // нечего вообще. Показывать в этом случае заголовок с пустотой под ним
    // хуже, чем не показывать секцию.
    if (life == null && totalDays == null) return const SizedBox.shrink();

    if (!_expanded) return _line(life, totalDays, journal.hasError);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
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
                Text('ЖИЗНЬ ЗАДАЧИ', style: AppText.sectionLabel),
                const Spacer(),
                Text(
                  life == null
                      ? formatDays(totalDays!)
                      : formatSpanLong(life.totalMs),
                  style: AppText.numberSmall,
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
              style: AppText.hint.copyWith(fontSize: 12),
            ),
          ] else
            ..._breakdown(life),
        ],
      ),
    );
  }

  /// Свёрнутый блок: полоска и «открыта 11 дней · с 17.09».
  Widget _line(TaskLife? life, int? totalDays, bool failed) {
    final String text;
    if (life == null) {
      // Без журнала честно известен только общий срок — его и пишем, с
      // припиской, почему разбивки нет.
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
          // The caption takes what it needs, up to three quarters of the
          // width; the bar takes the rest, so it is never squeezed to nothing
          // and never pushed off the edge.
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
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Фазы в том порядке, в каком задача их проживает, а не по величине:
  // полоска читается слева направо как её биография, и пересортировка
  // сегментов сделала бы две соседние задачи несравнимыми.
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
          // Текущая фаза подписана датой, с которой она идёт, — «ждёт с 18.09».
          // Остальные — прошедшим временем: они закончились.
          label: phase == life.phase
              ? '${_currentPhrase(phase)} с ${_shortDate(life.since)}'
              : phaseLabel(phase),
          ms: life[phase],
          emphasised: phase == TaskLifePhase.blocked,
        ),
      ],
    ];
  }

  /// Настоящее время для фазы, которая ещё идёт.
  static String _currentPhrase(TaskLifePhase phase) => switch (phase) {
    TaskLifePhase.queued => 'открыта',
    TaskLifePhase.working => 'в работе',
    TaskLifePhase.blocked => 'ждёт',
    TaskLifePhase.done => 'закрыта',
  };

  // По местному календарю: разбор журнала ведёт время в UTC, и ночное
  // событие иначе подписалось бы вчерашним числом.
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
            style: AppText.body.copyWith(fontSize: 13.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatSpanShort(ms),
          maxLines: 1,
          softWrap: false,
          style: AppText.chip.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: emphasised ? AppColors.waitingInk : AppColors.ink,
          ),
        ),
      ],
    );
  }
}
