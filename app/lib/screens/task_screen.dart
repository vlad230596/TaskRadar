import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../widgets/dictation.dart';
import '../widgets/history_charts.dart';
import '../widgets/mode_navigation.dart';
import '../widgets/mutation_feedback.dart';

/// One task, large enough to read and edit (F12).
///
/// ## The number this screen exists for
///
/// **252 px of text field at 20 px type** ([Targets.taskField],
/// `AppText.taskField`). Complaint number one was "в композере видно два-три
/// слова, продиктованную фразу нельзя ни прочитать, ни поправить", and the old
/// answer was an inline one-line editor inside a 56 px reorderable row -- which
/// is the same field with a different border.
///
/// Everything else here follows from that: a task is opened rather than edited
/// in place, so there is room; the status is three 54 px buttons rather than a
/// popup menu; the reminder is a full-width row rather than a 30 px text
/// button; and the microphone is the same indigo square in the same corner as
/// on every other sub-screen.
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
  const TaskScreen.draft({required this.projectId, super.key}) : taskId = null;

  final String projectId;

  /// Null on [TaskScreen.draft]: there is no row yet, and "Сохранить" creates
  /// one.
  final String? taskId;

  @override
  ConsumerState<TaskScreen> createState() => _TaskScreenState();
}

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

    final ok = await runMutation(
      context,
      () => _tasks.create(title),
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
    // one PATCH in the common case and zero when nothing was touched.
    final ok = await runMutation(
      context,
      () async {
        await _tasks.editTitle(task, title);
        await _tasks.editDescription(task, note.isEmpty ? null : note);
      },
      failure: 'Не удалось сохранить задачу.',
    );
    if (!ok || !mounted) return;
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

  Future<void> _pickReminder() async {
    // Read fresh rather than taken from the caller: this is reached straight
    // after a status change, and the row the caller is holding is the one from
    // before it -- still `pending`, which `setRemindAt` refuses.
    final task = _find(ref.read(projectTasksProvider(widget.projectId)).value);
    if (task == null) return;

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
    if (picked == null || !mounted) return;

    await runMutation(
      context,
      () => _tasks.setRemindAt(task, calendarDateForApi(picked)),
      failure: 'Не удалось сохранить дату напоминания.',
    );
  }

  Future<void> _clearReminder(Task task) async {
    await runMutation(
      context,
      () => _tasks.setRemindAt(task, null),
      failure: 'Не удалось убрать дату напоминания.',
    );
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

  /// Dictation into the title, appended rather than replacing -- a phrase said
  /// in two goes is one thought continued.
  Future<void> _dictate() async {
    final text = await AppRoutes.openDictation(
      context,
      destination: const FieldDestination('в задачу'),
    );
    if (text == null || text.isEmpty || !mounted) return;
    appendDictated(_title, text: text);
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
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _textField(),
                    const SizedBox(height: 16),
                    _statusRow(task),
                    if (task.status == TaskStatus.blocked) ...<Widget>[
                      const SizedBox(height: 8),
                      _reminderRow(task),
                    ],
                    const SizedBox(height: 8),
                    _noteSection(),
                    const SizedBox(height: 16),
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

  /// The draft screen: the same 252 px field, and nothing that would be a lie
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
            _textField(),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.gutter,
                12,
                Insets.gutter,
                18,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: Targets.row,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.stub),
                          ),
                          textStyle: AppText.action.copyWith(fontSize: 16),
                        ),
                        onPressed: () => unawaited(_create()),
                        child: const Text('Добавить'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  MicrophoneSquare(
                    tooltip: 'Продиктовать',
                    onPressed: () => unawaited(_dictate()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Task task, String? projectName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 32,
                constraints: const BoxConstraints(maxWidth: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.indigoFill,
                  borderRadius: BorderRadius.circular(Radii.card),
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
                          fontSize: 13,
                          color: AppColors.indigoInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

  Widget _textField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
      child: Container(
        height: Targets.taskField,
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.indigoLink, width: 1.5),
          borderRadius: BorderRadius.circular(Radii.panel),
        ),
        padding: const EdgeInsets.all(Insets.gutter),
        child: TextField(
          controller: _title,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
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
      ),
    );
  }

  Widget _statusRow(Task task) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
      child: Row(
        children: <Widget>[
          for (final status in _statusOrder) ...<Widget>[
            Expanded(
              child: _StatusButton(
                status: status,
                selected: task.status == status,
                onTap: () => unawaited(_setStatus(task, status)),
              ),
            ),
            if (status != _statusOrder.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _reminderRow(Task task) {
    final remindAt = task.remindAt;
    final due = remindAt != null && isReminderDue(remindAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
      child: Material(
        color: AppColors.waitingFill,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          onTap: () => unawaited(_pickReminder()),
          borderRadius: BorderRadius.circular(Radii.card),
          child: Container(
            height: 52,
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.waitingLine),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  due
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none,
                  size: 20,
                  color: AppColors.waitingInk,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    remindAt == null
                        ? 'Напомнить когда-нибудь…'
                        : 'Напомнить ${formatReminderDate(remindAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.action.copyWith(
                      color: AppColors.waitingInk,
                    ),
                  ),
                ),
                if (remindAt == null)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.waitingInk,
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Убрать дату напоминания',
                    onPressed: () => unawaited(_clearReminder(task)),
                    icon: const Icon(Icons.event_busy, size: 18),
                    color: AppColors.waitingInk,
                  ),
              ],
            ),
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
  /// Folded away when empty, so the screen that matters (a 252 px field and
  /// three status buttons) is the screen you get unless you asked for more.
  Widget _noteSection() {
    if (!_noteOpen) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            onPressed: () => setState(() => _noteOpen = true),
            icon: const Icon(Icons.notes, size: 18),
            label: const Text('Заметка к задаче'),
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: _note,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          style: AppText.body.copyWith(color: AppColors.ink),
          decoration: const InputDecoration(
            filled: false,
            isCollapsed: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Кто, что, к какому сроку…',
          ),
        ),
      ),
    );
  }

  Widget _saveBar(Task task) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.gutter,
        12,
        Insets.gutter,
        18,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: Targets.row,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.stub),
                  ),
                  textStyle: AppText.action.copyWith(fontSize: 16),
                ),
                onPressed: () => unawaited(_save(task)),
                child: const Text('Сохранить'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MicrophoneSquare(
            tooltip: 'Дописать голосом',
            onPressed: () => unawaited(_dictate()),
          ),
        ],
      ),
    );
  }
}

/// `pending -> blocked -> done` is the order a task actually travels in, and it
/// puts the destructive-feeling "done" at the far end. Same order as the React
/// client's `STATUS_ORDER`, so muscle memory survives the migration.
const List<TaskStatus> _statusOrder = <TaskStatus>[
  TaskStatus.pending,
  TaskStatus.blocked,
  TaskStatus.done,
];

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final TaskStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (String label, IconData icon, Color accent, Color fill) =
        switch (status) {
          TaskStatus.pending => (
            'В очереди',
            Icons.circle_outlined,
            AppColors.indigoLink,
            AppColors.indigoFill,
          ),
          TaskStatus.blocked => (
            'Блокер',
            Icons.pause_circle_outline,
            AppColors.waitingDot,
            AppColors.waitingFill,
          ),
          TaskStatus.done => (
            'Сделано',
            Icons.check_circle_outline,
            AppColors.done,
            Color(0xFFEAF3EE),
          ),
        };

    final foreground = selected
        ? (status == TaskStatus.blocked ? AppColors.waitingInk : accent)
        : AppColors.muted;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? fill : AppColors.card,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.card),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? accent : AppColors.line,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 20, color: foreground),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: AppText.chip.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
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
class _LifeOfTask extends ConsumerWidget {
  const _LifeOfTask({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
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
      ),
    );
  }

  List<Widget> _breakdown(TaskLife life) {
    // Фазы в том порядке, в каком задача их проживает, а не по величине:
    // полоска читается слева направо как её биография, и пересортировка
    // сегментов сделала бы две соседние задачи несравнимыми.
    const order = <TaskLifePhase>[
      TaskLifePhase.queued,
      TaskLifePhase.working,
      TaskLifePhase.blocked,
      TaskLifePhase.done,
    ];
    final shown = <TaskLifePhase>[
      for (final phase in order)
        if (life[phase] > 0) phase,
    ];

    return <Widget>[
      const SizedBox(height: 12),
      SpanBar(
        height: 16,
        segments: <SpanSegment>[
          for (final phase in shown) SpanSegment(life[phase], phaseColour(phase)),
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
    TaskLifePhase.queued => 'лежит в очереди',
    TaskLifePhase.working => 'в работе',
    TaskLifePhase.blocked => 'ждёт',
    TaskLifePhase.done => 'закрыта',
  };

  static String _shortDate(DateTime at) =>
      '${at.day.toString().padLeft(2, '0')}.'
      '${at.month.toString().padLeft(2, '0')}';
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
