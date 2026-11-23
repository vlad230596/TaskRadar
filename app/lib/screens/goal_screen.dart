import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/goals.dart';
import '../models/goal.dart';
import '../models/task_status.dart';
import '../navigation/app_routes.dart';
import '../providers/board_providers.dart';
import '../providers/dependencies.dart';
import '../providers/goal_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/editor/editor_theme.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/goals/goal_link_sheet.dart';
import '../widgets/goals/idea_link_sheet.dart';
import '../widgets/ime_text_controller.dart';
import 'goals_screen.dart';
import 'note_editor_screen.dart';

/// One goal (`design/goals-ideas-spec.md`, «Цель»; `Goal-Edit.html`): the
/// dark screen of the task editor's family. Also the «+ Цель» screen, empty,
/// when [newInContourId] is given.
class GoalScreen extends StatelessWidget {
  const GoalScreen({
    this.goalId,
    this.newInContourId,
    this.initialTitle,
    super.key,
  });

  final String? goalId;

  /// A new goal in this contour (the chip in the header can change it).
  final String? newInContourId;
  final String? initialTitle;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: editorOverlayStyle,
      child: Scaffold(
        backgroundColor: AppColors.voiceBackground,
        body: SafeArea(
          child: GoalDetail(
            goalId: goalId,
            newInContourId: newInContourId,
            initialTitle: initialTitle,
          ),
        ),
      ),
    );
  }
}

/// The goal's content, on its own screen or (desktop) as the goals screen's
/// right-hand panel ([embedded]: no ×, the panel's own padding).
class GoalDetail extends ConsumerStatefulWidget {
  const GoalDetail({
    this.goalId,
    this.newInContourId,
    this.initialTitle,
    this.embedded = false,
    super.key,
  });

  final String? goalId;
  final String? newInContourId;
  final String? initialTitle;
  final bool embedded;

  @override
  ConsumerState<GoalDetail> createState() => _GoalDetailState();
}

class _GoalDetailState extends ConsumerState<GoalDetail> {
  late final ImeTextController _title = ImeTextController(
    text: widget.initialTitle ?? '',
  );
  late final ImeTextController _why = ImeTextController();

  /// The goal as last answered by the server, for a goal that is not in the
  /// goals list (achieved, opened from History) or not yet loaded.
  GoalView? _fetched;
  Object? _fetchError;

  /// The goal's text the fields were last filled from.
  String? _syncedTitle;
  String? _syncedWhy;

  late String? _newContourId = widget.newInContourId;
  bool? _slotNow;
  bool _busy = false;

  bool get _isNew => widget.goalId == null;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
    _why.addListener(_changed);
    final id = widget.goalId;
    if (id != null && ref.read(goalsProvider.notifier).byId(id) == null) {
      unawaited(_fetch(id));
    }
  }

  void _changed() => setState(() {});

  Future<void> _fetch(String id) async {
    try {
      final goal = await ref.read(goalsApiProvider).fetchGoal(id);
      if (mounted) setState(() => _fetched = goal);
    } catch (error) {
      if (mounted) setState(() => _fetchError = error);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _why.dispose();
    super.dispose();
  }

  GoalView? _goalFrom(List<GoalView> goals) {
    final id = widget.goalId;
    if (id == null) return null;
    for (final goal in goals) {
      if (goal.id == id) return goal;
    }
    final fetched = _fetched;
    return fetched?.id == id ? fetched : null;
  }

  /// Fills the fields from the goal once, and again whenever the saved text
  /// changes under fields that hold no edit of their own.
  void _sync(GoalView goal) {
    final why = goal.why ?? '';
    if (_syncedTitle == null ||
        (_title.text == _syncedTitle && goal.title != _syncedTitle)) {
      _title.text = goal.title;
    }
    if (_syncedWhy == null || (_why.text == _syncedWhy && why != _syncedWhy)) {
      _why.text = why;
    }
    _syncedTitle = goal.title;
    _syncedWhy = why;
  }

  bool _dirty(GoalView goal) =>
      _title.text.trim() != goal.title ||
      _why.text.trim() != (goal.why ?? '').trim();

  /// Runs a goal action, keeping its answer for goals that left the list.
  Future<void> _act(Future<GoalView?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final goal = await action();
      if (goal != null && mounted) setState(() => _fetched = goal);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<GoalView> _guard(Future<GoalView> request, String failure) async {
    try {
      return await request;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                isSlotsFull(error)
                    ? slotsFullText
                    : '$failure ${describeApiError(error)}',
              ),
            ),
          );
      }
      rethrow;
    }
  }

  Future<void> _save(GoalView goal) async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final why = _why.text.trim();
    await _act(
      () => _guard(
        ref
            .read(goalsProvider.notifier)
            .edit(
              goal.id,
              title: title == goal.title ? null : title,
              why: why.isEmpty ? null : why,
              clearWhy: why.isEmpty,
            ),
        'Не удалось сохранить цель.',
      ).then<GoalView?>((g) => g, onError: (Object _) => null),
    );
  }

  Future<void> _create(String contourId, bool slot) async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    final why = _why.text.trim();
    setState(() => _busy = true);
    try {
      await _guard(
        ref
            .read(goalsProvider.notifier)
            .create(
              contourId: contourId,
              title: title,
              why: why.isEmpty ? null : why,
              slot: slot,
            ),
        'Не удалось создать цель.',
      );
      if (mounted) await Navigator.of(context).maybePop();
    } catch (_) {
      // Said in the snackbar.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalListProvider);
    final contours = ref.watch(contourListProvider);
    final goal = _goalFrom(goals);

    if (!_isNew && goal == null) {
      return Column(
        children: <Widget>[
          if (!widget.embedded) _CloseRow(),
          Expanded(
            child: Center(
              child: _fetchError == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Не удалось открыть цель. '
                        '${describeApiError(_fetchError!)}',
                        textAlign: TextAlign.center,
                        style: AppText.voiceNote,
                      ),
                    ),
            ),
          ),
        ],
      );
    }
    if (goal != null) _sync(goal);

    final contourId = goal?.contourId ?? _newContourId;
    final contour = contours.where((c) => c.id == contourId).firstOrNull;
    final usedSlots = contourId == null
        ? 0
        : goals.where((g) => g.contourId == contourId && g.inSlot).length;
    final freeSlot = contour == null || usedSlots < contour.slots;

    final dirty = goal != null && _dirty(goal);

    return Theme(
      data: editorTheme,
      child: Column(
        children: <Widget>[
          _HeaderRow(
            embedded: widget.embedded,
            title: _isNew ? 'Новая цель' : 'Цель',
            contour: contour,
            contours: contours,
            onContour: (target) => unawaited(_changeContour(goal, target)),
            onDelete: goal == null ? null : () => unawaited(_delete(goal)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                widget.embedded ? 26 : 16,
                10,
                widget.embedded ? 26 : 16,
                24,
              ),
              children: <Widget>[
                if (goal != null) _StatePlate(goal: goal, onWindow: _window),
                const SizedBox(height: 12),
                _TitleField(controller: _title, autofocus: _isNew),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: TidyLabelText('ЗАЧЕМ'),
                ),
                _WhyField(controller: _why),
                if (goal != null) ...<Widget>[
                  const SizedBox(height: 18),
                  _TasksSection(goal: goal),
                  const SizedBox(height: 14),
                  _IdeasSection(goal: goal),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.embedded ? 26 : 20,
              12,
              widget.embedded ? 26 : 20,
              widget.embedded ? 26 : 22,
            ),
            child: _isNew
                ? _CreateActions(
                    slotNow: (_slotNow ?? freeSlot) && freeSlot,
                    canSlot: freeSlot,
                    onSlotNow: (value) => setState(() => _slotNow = value),
                    onCreate: _title.text.trim().isEmpty || contourId == null
                        ? null
                        : () => unawaited(
                            _create(
                              contourId,
                              (_slotNow ?? freeSlot) && freeSlot,
                            ),
                          ),
                  )
                : dirty
                ? EditorPrimaryButton(
                    label: 'Сохранить',
                    onPressed: _title.text.trim().isEmpty || _busy
                        ? null
                        : () => unawaited(_save(goal)),
                  )
                : _StateActions(goal: goal!, busy: _busy, act: _act),
          ),
        ],
      ),
    );
  }

  Future<void> _changeContour(GoalView? goal, Contour target) async {
    if (goal == null) {
      setState(() => _newContourId = target.id);
      return;
    }
    if (goal.contourId == target.id) return;
    final goals = ref.read(goalsProvider.notifier);
    final targetUsed = ref
        .read(goalListProvider)
        .where((g) => g.contourId == target.id && g.inSlot)
        .length;
    if (goal.inSlot && targetUsed >= target.slots) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            'В «${target.name}» слоты заняты — цель встанет на скамейку.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Перенести'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await _act(() async {
        try {
          await goals.bench(goal.id);
          return await goals.edit(goal.id, contourId: target.id);
        } catch (error) {
          if (mounted) {
            _say('Не удалось перенести цель. ${describeApiError(error)}');
          }
          return null;
        }
      });
      return;
    }
    await _act(() async {
      try {
        return await goals.edit(goal.id, contourId: target.id);
      } catch (error) {
        if (mounted) {
          _say(
            isSlotsFull(error)
                ? slotsFullText
                : 'Не удалось перенести цель. ${describeApiError(error)}',
          );
        }
        return null;
      }
    });
  }

  Future<void> _window(GoalView goal, int? days) async {
    await _act(() async {
      try {
        return await ref
            .read(goalsProvider.notifier)
            .edit(goal.id, windowDays: days, clearWindow: days == null);
      } catch (error) {
        if (mounted) {
          _say('Не удалось поменять окно. ${describeApiError(error)}');
        }
        return null;
      }
    });
  }

  Future<void> _delete(GoalView goal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('Удалить цель «${goal.title}»? Задачи и идеи останутся.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alarm),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(goalsProvider.notifier).delete(goal.id);
      if (mounted && !widget.embedded) await Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) _say('Не удалось удалить цель. ${describeApiError(error)}');
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// A caps label on dark (the editor's [TidyLabel] look).
class TidyLabelText extends StatelessWidget {
  const TidyLabelText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: _label),
  );
}

const TextStyle _label = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 12,
  letterSpacing: 0.72,
  color: AppColors.voiceMuted,
);

class _CloseRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 0, 0),
      child: IconButton(
        tooltip: 'Закрыть',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.close, color: AppColors.voiceMuted),
      ),
    ),
  );
}

/// × · «Цель» · contour chip · ⋯.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.embedded,
    required this.title,
    required this.contour,
    required this.contours,
    required this.onContour,
    required this.onDelete,
  });

  final bool embedded;
  final String title;
  final Contour? contour;
  final List<Contour> contours;
  final ValueChanged<Contour> onContour;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final contour = this.contour;
    return Padding(
      padding: EdgeInsets.fromLTRB(embedded ? 26 : 6, 10, 8, 0),
      child: Row(
        children: <Widget>[
          if (!embedded) ...<Widget>[
            IconButton(
              tooltip: 'Закрыть',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, color: AppColors.voiceMuted),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(child: Text(title, style: EditorText.header)),
          if (contour != null)
            PopupMenuButton<String>(
              tooltip: 'Контур цели',
              enabled: contours.length > 1,
              color: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (id) {
                final target = contours.where((c) => c.id == id).firstOrNull;
                if (target != null) onContour(target);
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                for (final c in contours)
                  CheckedPopupMenuItem<String>(
                    value: c.id,
                    checked: c.id == contour.id,
                    child: Text(c.name),
                  ),
              ],
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.voiceWell,
                  border: Border.all(color: AppColors.voiceLine),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CrownIcon(size: 13, color: AppColors.crown),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        contour.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.voiceBright,
                        ),
                      ),
                    ),
                    if (contours.length > 1) ...<Widget>[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.expand_more,
                        size: 16,
                        color: AppColors.voiceMuted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (onDelete != null)
            PopupMenuButton<String>(
              tooltip: 'Ещё',
              icon: const Icon(Icons.more_horiz, color: AppColors.voiceMuted),
              color: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (_) => onDelete!(),
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(
                    'Удалить цель',
                    style: TextStyle(color: AppColors.alarm),
                  ),
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

/// The state plate: in a slot (with the window menu), expired, or benched.
class _StatePlate extends StatelessWidget {
  const _StatePlate({required this.goal, required this.onWindow});

  final GoalView goal;
  final Future<void> Function(GoalView goal, int? days) onWindow;

  @override
  Widget build(BuildContext context) {
    const strong = TextStyle(
      fontFamily: AppFonts.text,
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: AppColors.onInk,
    );
    if (goal.achieved) {
      return _plate(AppColors.goalRaised, <Widget>[
        const Icon(Icons.check, size: 16, color: AppColors.doneOnDark),
        const SizedBox(width: 8),
        Text(
          'Достигнута ${shortDate(goal.achievedAt)}',
          style: strong.copyWith(color: AppColors.doneOnDark),
        ),
      ]);
    }
    if (goal.onBench) {
      return _plate(AppColors.voiceWell, const <Widget>[
        BenchIcon(size: 16, color: AppColors.voiceMuted),
        SizedBox(width: 8),
        Text(
          'На скамейке',
          style: TextStyle(
            fontFamily: AppFonts.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: AppColors.voiceMuted,
          ),
        ),
      ]);
    }
    final left = windowLeftLabel(goal.windowEndsAt);
    return _plate(AppColors.goalRaised, <Widget>[
      const CrownIcon(size: 14, color: AppColors.crown),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          goal.windowExpired
              ? windowExpiredLabel(goal.windowEndsAt)
              : left == null
              ? 'В слоте'
              : 'В слоте · $left',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: strong.copyWith(
            color: goal.windowExpired ? AppColors.goalExpired : null,
          ),
        ),
      ),
      PopupMenuButton<int>(
        tooltip: 'Окно цели',
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (value) async {
          if (value == 0) {
            await onWindow(goal, null);
          } else if (value < 0) {
            final days = await _askDays(context, goal.windowDays);
            if (days != null) await onWindow(goal, days);
          } else {
            await onWindow(goal, value);
          }
        },
        itemBuilder: (_) => <PopupMenuEntry<int>>[
          CheckedPopupMenuItem<int>(
            value: 0,
            checked: goal.ownWindowDays == null,
            child: const Text('как у контура'),
          ),
          for (final days in const <int>[3, 7, 14, 30])
            CheckedPopupMenuItem<int>(
              value: days,
              checked: goal.ownWindowDays == days,
              child: Text('$days д'),
            ),
          const PopupMenuItem<int>(value: -1, child: Text('Своё…')),
        ],
        child: SizedBox(
          height: Targets.minimum,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'окно ${goal.windowDays} д',
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.voiceBright,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.expand_more,
                size: 16,
                color: AppColors.voiceBright,
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _plate(Color fill, List<Widget> children) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(children: children),
  );
}

Future<int?> _askDays(BuildContext context, int current) async {
  final controller = ImeTextController(text: '$current');
  final days = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Своё окно'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: const InputDecoration(suffixText: 'дней (1–90)'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () {
            final value = int.tryParse(controller.text);
            if (value == null || value < 1 || value > 90) return;
            Navigator.of(context).pop(value);
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
  controller.dispose();
  return days;
}

InputDecoration _well({required String hint, required double radius}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.voiceMuted),
      filled: true,
      fillColor: AppColors.voiceWell,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(
          color: AppColors.voiceLevelHigh,
          width: 1.5,
        ),
      ),
    );

class _TitleField extends StatelessWidget {
  const _TitleField({required this.controller, required this.autofocus});

  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    minLines: 2,
    maxLines: null,
    maxLength: 200,
    buildCounter:
        (_, {required currentLength, required isFocused, maxLength}) => null,
    textCapitalization: TextCapitalization.sentences,
    style: EditorText.title.copyWith(color: AppColors.onInk),
    cursorColor: AppColors.voiceBright,
    decoration: _well(hint: 'Чего хочу добиться', radius: Radii.panel),
  );
}

class _WhyField extends StatelessWidget {
  const _WhyField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: 1,
    maxLines: 3,
    maxLength: 300,
    buildCounter:
        (_, {required currentLength, required isFocused, maxLength}) =>
            currentLength > 250
            ? Text(
                '$currentLength / 300',
                style: const TextStyle(
                  color: AppColors.voiceMuted,
                  fontSize: 12,
                ),
              )
            : null,
    textCapitalization: TextCapitalization.sentences,
    style: EditorText.body.copyWith(color: AppColors.voiceInk),
    cursorColor: AppColors.voiceBright,
    decoration: _well(hint: 'Что будет, если отложить?', radius: 16),
  );
}

/// «ЗАДАЧИ · 2/5» · «+ Добавить» and the goal's tasks in its order.
class _TasksSection extends ConsumerWidget {
  const _TasksSection({required this.goal});

  final GoalView goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = goal.tasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionTitle(
          text: 'ЗАДАЧИ · ${goal.progress.done}/${goal.progress.total}',
          action: goal.achieved ? null : 'Добавить',
          onAction: () =>
              unawaited(showGoalLinkSheet(context, ref, goal: goal)),
        ),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              'Задач пока нет — привяжите их из проектов.',
              style: AppText.voiceNote,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: tasks.length,
            proxyDecorator: (child, _, _) =>
                Material(color: AppColors.goalRaised, child: child),
            onReorder: (from, to) {
              final index = to > from ? to - 1 : to;
              unawaited(
                ref
                    .read(goalsProvider.notifier)
                    .moveTask(goal.id, tasks[from].id, index)
                    .catchError((Object error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Не удалось переставить. ${describeApiError(error)}',
                            ),
                          ),
                        );
                      }
                      return goal;
                    }),
              );
            },
            itemBuilder: (context, index) => _GoalTaskRow(
              key: ValueKey<String>(tasks[index].id),
              goal: goal,
              task: tasks[index],
              index: index,
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: _label)),
          if (action != null)
            TextButton.icon(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.voiceBright,
                minimumSize: const Size(0, Targets.minimum),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// One task of the goal: handle · status · text and project · ×.
class _GoalTaskRow extends ConsumerWidget {
  const _GoalTaskRow({
    required this.goal,
    required this.task,
    required this.index,
    super.key,
  });

  final GoalView goal;
  final GoalTask task;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStep = goal.nextStep?.id == task.id;
    final done = task.status == TaskStatus.done;
    final blocked = task.status == TaskStatus.blocked;
    final inWork = task.focusedAt != null;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: EdgeInsets.symmetric(vertical: isStep ? 6 : 0),
      decoration: BoxDecoration(
        color: isStep ? AppColors.goalRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        children: <Widget>[
          ReorderableDragStartListener(
            index: index,
            child: const SizedBox(
              width: 28,
              height: Targets.minimum,
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: AppColors.goalDim,
              ),
            ),
          ),
          InkResponse(
            radius: 22,
            onTap: () => unawaited(_toggle(context, ref)),
            child: SizedBox(
              width: 36,
              height: Targets.minimum,
              child: Center(child: _StatusCircle(status: task.status)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () => unawaited(
                AppRoutes.openTask(
                  context,
                  projectId: task.projectId,
                  taskId: task.id,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (isStep) const Text('ШАГ', style: AppText.goalLabel),
                    Text(
                      task.title,
                      style: TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: isStep ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 15,
                        height: 1.3,
                        color: done
                            ? AppColors.voiceMuted
                            : isStep
                            ? AppColors.onInk
                            : AppColors.voiceInk,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.voiceMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        task.projectName,
                        if (inWork && !done) 'в работе',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: blocked
                            ? AppColors.waitingDotOnInk
                            : AppColors.voiceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Отвязать',
            onPressed: () => unawaited(_unlink(context, ref)),
            icon: const Icon(
              Icons.close,
              size: 18,
              color: AppColors.voiceMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// The circle: done <-> pending, as in a project row.
  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final next = task.status == TaskStatus.done
        ? TaskStatus.pending
        : TaskStatus.done;
    final api = ref.read(projectApiProvider);
    final goals = ref.read(goalsProvider.notifier);
    final board = ref.read(boardProvider.notifier);
    try {
      await api.updateTask(task.id, status: next);
      await goals.syncQuietly();
      try {
        board.applyProjectTasks(
          task.projectId,
          await api.fetchTasks(task.projectId),
        );
      } catch (_) {
        // The board is one screen stale; the status is written.
      }
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Не удалось изменить статус. ${describeApiError(error)}',
            ),
          ),
        );
    }
  }

  /// × unlinks at once: «Отвязана · Вернуть».
  Future<void> _unlink(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final goals = ref.read(goalsProvider.notifier);
    try {
      await goals.unlinkTask(goal.id, task.id);
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Не удалось отвязать. ${describeApiError(error)}'),
          ),
        );
      return;
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Отвязана'),
          persist: false,
          action: SnackBarAction(
            label: 'Вернуть',
            onPressed: () => unawaited(
              goals
                  .linkTask(goal.id, task.id)
                  .then<void>((_) {}, onError: (_) {}),
            ),
          ),
        ),
      );
  }
}

class _StatusCircle extends StatelessWidget {
  const _StatusCircle({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      TaskStatus.done => Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: AppColors.doneOnDark,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check,
          size: 15,
          color: AppColors.voiceBackground,
        ),
      ),
      TaskStatus.blocked => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.waitingDotOnInk, width: 2),
        ),
        child: const Icon(
          Icons.pause,
          size: 12,
          color: AppColors.waitingDotOnInk,
        ),
      ),
      TaskStatus.pending => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.voiceLine, width: 2),
        ),
      ),
    };
  }
}

/// «ИДЕИ · N» · «+ Идея» and the goal's ideas.
class _IdeasSection extends ConsumerWidget {
  const _IdeasSection({required this.goal});

  final GoalView goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionTitle(
          text: 'ИДЕИ · ${goal.ideas.length}',
          action: goal.achieved ? null : 'Идея',
          onAction: () =>
              unawaited(showIdeaLinkSheet(context, ref, goal: goal)),
        ),
        for (final idea in goal.ideas)
          SizedBox(
            height: 52,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 6),
                const BulbIcon(size: 18, color: AppColors.ideaOnDark),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => unawaited(_openIdea(context, ref, idea)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          idea.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.text,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            color: AppColors.voiceInk,
                          ),
                        ),
                        Text(
                          idea.projectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.voiceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Отвязать идею',
                  onPressed: () => unawaited(_unlink(context, ref, idea)),
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.voiceMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    GoalIdea idea,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(goalsProvider.notifier).unlinkIdea(goal.id, idea.id);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось отвязать. ${describeApiError(error)}'),
        ),
      );
    }
  }

  Future<void> _openIdea(
    BuildContext context,
    WidgetRef ref,
    GoalIdea idea,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final notes = await ref
          .read(projectApiProvider)
          .fetchNotes(idea.projectId);
      final note = notes.where((n) => n.id == idea.id).firstOrNull;
      if (note == null) throw StateError('Идеи больше нет');
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NoteEditorScreen(
            projectId: idea.projectId,
            note: note,
            projectName: idea.projectName,
          ),
        ),
      );
      unawaited(ref.read(goalsProvider.notifier).syncQuietly());
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось открыть идею. ${describeApiError(error)}'),
        ),
      );
    }
  }
}

/// The bottom of an existing goal, by its state.
class _StateActions extends ConsumerWidget {
  const _StateActions({
    required this.goal,
    required this.busy,
    required this.act,
  });

  final GoalView goal;
  final bool busy;
  final Future<void> Function(Future<GoalView?> Function() action) act;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (goal.achieved) {
      final done = goal.progress.done;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Достигнута ${shortDate(goal.achievedAt)} · $done ${tasksWord(done)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.doneOnDark,
            ),
          ),
          const SizedBox(height: 12),
          _Outlined(
            label: 'Вернуть на скамейку',
            onPressed: busy
                ? null
                : () => unawaited(
                    act(
                      () => _plain(
                        context,
                        ref.read(goalsProvider.notifier).reopen(goal.id),
                      ),
                    ),
                  ),
          ),
        ],
      );
    }
    if (goal.onBench) {
      return Row(
        children: <Widget>[
          Expanded(
            child: _White(
              label: 'Поставить в слот',
              icon: const CrownIcon(size: 20, color: AppColors.voiceBackground),
              onPressed: busy
                  ? null
                  : () => unawaited(
                      act(() => slotGoalWithFeedback(context, ref, goal)),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: _Outlined(
              label: 'Достигнута',
              height: 64,
              onPressed: busy
                  ? null
                  : () => unawaited(
                      act(() => achieveGoalWithUndo(context, ref, goal)),
                    ),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _Outlined(
                label: 'На скамейку',
                icon: const BenchIcon(size: 18, color: AppColors.voiceBright),
                onPressed: busy
                    ? null
                    : () => unawaited(
                        act(() => benchGoalWithUndo(context, ref, goal)),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Outlined(
                label: 'Продлить окно',
                onPressed: busy
                    ? null
                    : () => unawaited(
                        act(() => extendGoalWithFeedback(context, ref, goal)),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _White(
          label: 'Достигнута',
          icon: const Icon(Icons.check, size: 22),
          onPressed: busy
              ? null
              : () => unawaited(
                  act(() => achieveGoalWithUndo(context, ref, goal)),
                ),
        ),
      ],
    );
  }

  static Future<GoalView?> _plain(
    BuildContext context,
    Future<GoalView> request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      return await request;
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не получилось. ${describeApiError(error)}')),
      );
      return null;
    }
  }
}

/// New goal: «Сразу в слот» and «Создать».
class _CreateActions extends StatelessWidget {
  const _CreateActions({
    required this.slotNow,
    required this.canSlot,
    required this.onSlotNow,
    required this.onCreate,
  });

  final bool slotNow;
  final bool canSlot;
  final ValueChanged<bool> onSlotNow;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              const CrownIcon(size: 16, color: AppColors.crown),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Сразу в слот',
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    color: AppColors.voiceInk,
                  ),
                ),
              ),
              if (!canSlot)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    'слоты заняты',
                    style: TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: AppColors.voiceMuted,
                    ),
                  ),
                ),
              Switch(value: slotNow, onChanged: canSlot ? onSlotNow : null),
            ],
          ),
        ),
        const SizedBox(height: 8),
        EditorPrimaryButton(label: 'Создать', onPressed: onCreate),
      ],
    );
  }
}

class _White extends StatelessWidget {
  const _White({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.onInk,
        foregroundColor: AppColors.voiceBackground,
        disabledBackgroundColor: AppColors.voiceLine,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.text,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      icon: icon,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

class _Outlined extends StatelessWidget {
  const _Outlined({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 48,
  });

  final String label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: AppColors.voiceBright,
      backgroundColor: Colors.transparent,
      side: const BorderSide(color: AppColors.voiceLine),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(
        fontFamily: AppFonts.text,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    return SizedBox(
      height: height,
      child: icon == null
          ? OutlinedButton(onPressed: onPressed, style: style, child: text)
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: icon!,
              label: text,
            ),
    );
  }
}
