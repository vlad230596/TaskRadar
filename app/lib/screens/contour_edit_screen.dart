import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../domain/goals.dart';
import '../models/goal.dart';
import '../navigation/goal_routes.dart';
import '../providers/goal_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/ime_text_controller.dart';
import '../widgets/reminder_time_picker.dart';
import 'contours_screen.dart';

/// One contour (`design/reference/Contour-Edit.html`): name, slots, the
/// default window, the schedule, and deleting -- with the reasons the server
/// would refuse (409) said before the button is pressed whenever the app
/// already knows them.
///
/// A light screen: this is settings, not content. Writes are online-only.
class ContourEditScreen extends ConsumerStatefulWidget {
  const ContourEditScreen({this.contourId, super.key});

  /// Null for a new contour.
  final String? contourId;

  @override
  ConsumerState<ContourEditScreen> createState() => _ContourEditScreenState();
}

/// The windows offered as segments; anything else is «Своё».
const List<int> _windowChoices = <int>[3, 7, 14, 30];

/// What a fresh schedule starts as when switched on.
const ContourSchedule _defaultSchedule = ContourSchedule(
  days: <int>[1, 2, 3, 4, 5],
  from: '09:00',
  to: '19:00',
);

class _ContourEditScreenState extends ConsumerState<ContourEditScreen> {
  final TextEditingController _name = ImeTextController();
  final TextEditingController _customWindow = ImeTextController();
  final FocusNode _nameFocus = FocusNode();

  bool _loaded = false;
  late String _initialName;
  late int _initialSlots;
  late int _initialWindow;
  ContourSchedule? _initialSchedule;

  int _slots = 2;
  int _window = 7;
  bool _custom = false;
  bool _scheduled = false;
  List<int> _days = _defaultSchedule.days;
  String _from = _defaultSchedule.from;
  String _to = _defaultSchedule.to;

  bool _saving = false;

  /// Set when the server refused the delete although the app thought it may.
  String? _refusal;

  bool get _isNew => widget.contourId == null;

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _customWindow.addListener(_changed);
  }

  @override
  void dispose() {
    _name.dispose();
    _customWindow.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _load(Contour? contour) {
    if (_loaded) return;
    _loaded = true;
    _initialName = contour?.name ?? '';
    _initialSlots = contour?.slots ?? 2;
    _initialWindow = contour?.windowDays ?? 7;
    _initialSchedule = contour?.schedule;
    _name.text = _initialName;
    _slots = _initialSlots;
    _window = _initialWindow;
    _custom = !_windowChoices.contains(_window);
    if (_custom) _customWindow.text = '$_window';
    final schedule = contour?.schedule;
    _scheduled = schedule != null;
    if (schedule != null) {
      _days = <int>[...schedule.days]..sort();
      _from = schedule.from;
      _to = schedule.to;
    }
    if (_isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocus.requestFocus();
      });
    }
  }

  int? get _effectiveWindow {
    if (!_custom) return _window;
    final value = int.tryParse(_customWindow.text.trim());
    if (value == null || value < 1 || value > 90) return null;
    return value;
  }

  ContourSchedule? get _schedule => _scheduled
      ? ContourSchedule(days: _days, from: _from, to: _to)
      : null;

  bool get _timesWrong {
    final from = minutesOf(_from);
    final to = minutesOf(_to);
    return _scheduled && (from == null || to == null || to <= from);
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= 40 &&
      _effectiveWindow != null &&
      !_timesWrong &&
      (!_scheduled || _days.isNotEmpty);

  bool get _dirty {
    if (!_loaded) return false;
    if (_isNew) return true;
    return _name.text.trim() != _initialName ||
        _slots != _initialSlots ||
        _effectiveWindow != _initialWindow ||
        _schedule != _initialSchedule;
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final contours = ref.read(contoursProvider.notifier);
    try {
      if (_isNew) {
        await contours.create(
          name: _name.text.trim(),
          slots: _slots,
          windowDays: _effectiveWindow,
          schedule: _schedule,
        );
      } else {
        await contours.edit(
          widget.contourId!,
          name: _name.text.trim(),
          slots: _slots,
          windowDays: _effectiveWindow,
          schedule: _schedule,
          clearSchedule: _schedule == null,
        );
      }
      if (mounted) navigator.pop();
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Не удалось сохранить контур. ${describeApiError(error)}',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime({required bool from}) async {
    final picked = await pickReminderTimeOf(
      context,
      ref,
      current: from ? _from : _to,
      cancelText: 'Отмена',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _delete(Contour contour, List<Contour> all) async {
    final heir = all.firstWhere(
      (other) => other.id != contour.id,
      orElse: () => contour,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить «${contour.name}»?'),
        content: Text(
          'Задачи из его набора перейдут в набор «${heir.name}».',
        ),
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
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(contoursProvider.notifier).delete(contour.id);
      if (mounted) navigator.pop();
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        setState(() => _refusal = describeApiError(error));
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось удалить контур. ${describeApiError(error)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contours = ref.watch(contourListProvider);
    Contour? contour;
    if (!_isNew) {
      for (final candidate in contours) {
        if (candidate.id == widget.contourId) contour = candidate;
      }
      if (contour == null && !_loaded) {
        return const Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                SettingsSubHeader(title: 'Контур'),
                Expanded(child: Center(child: CircularProgressIndicator())),
              ],
            ),
          ),
        );
      }
    }
    _load(contour);

    final goals = ref.watch(goalListProvider);
    final inSlots = contour == null
        ? 0
        : goals.where((g) => g.contourId == contour!.id && g.inSlot).length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SettingsSubHeader(
                  title: _isNew ? 'Новый контур' : 'Контур',
                  action: TextButton(
                    onPressed: _dirty && _valid && !_saving ? _save : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.indigoLink,
                      minimumSize: const Size(0, Targets.minimum),
                      textStyle: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    child: Text(_isNew ? 'Создать' : 'Сохранить'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: <Widget>[
                      const _Label('Название'),
                      _NameField(controller: _name, focusNode: _nameFocus),
                      const _Label('Слотов для целей'),
                      _SlotsRow(
                        slots: _slots,
                        onChanged: (n) => setState(() => _slots = n),
                      ),
                      const _Note(
                        'Две-три — нормально. Больше — и цели снова станут '
                        'списком.',
                      ),
                      if (inSlots > _slots)
                        _Note(
                          'Сейчас в слотах $inSlots — лишняя останется, пока '
                          'не уберёте её.',
                          color: AppColors.goalExpired,
                          weight: FontWeight.w600,
                        ),
                      const _Label('Окно по умолчанию'),
                      _WindowSegments(
                        window: _window,
                        custom: _custom,
                        onChoice: (days) => setState(() {
                          _custom = false;
                          _window = days;
                        }),
                        onCustom: () => setState(() {
                          _custom = true;
                          if (_customWindow.text.isEmpty) {
                            _customWindow.text = '$_window';
                          }
                        }),
                      ),
                      if (_custom) ...<Widget>[
                        const SizedBox(height: 8),
                        _CustomWindowField(controller: _customWindow),
                        if (_effectiveWindow == null)
                          const _Note(
                            'От 1 до 90 дней.',
                            color: AppColors.alarm,
                            weight: FontWeight.w600,
                          ),
                      ],
                      const _Label('Расписание'),
                      _ScheduleCard(
                        enabled: _scheduled,
                        days: _days,
                        from: _from,
                        to: _to,
                        onToggle: (on) => setState(() => _scheduled = on),
                        onDay: (day) => setState(() {
                          final next = <int>{..._days};
                          if (!next.remove(day)) next.add(day);
                          _days = next.toList()..sort();
                        }),
                        onFrom: () => unawaited(_pickTime(from: true)),
                        onTo: () => unawaited(_pickTime(from: false)),
                      ),
                      if (_scheduled && _timesWrong)
                        const _Note(
                          'Конец раньше начала — через полночь нельзя.',
                          color: AppColors.alarm,
                          weight: FontWeight.w600,
                        )
                      else if (_scheduled && _days.isEmpty)
                        const _Note(
                          'Выберите хотя бы один день.',
                          color: AppColors.alarm,
                          weight: FontWeight.w600,
                        )
                      else if (_scheduled)
                        ..._overlaps(contours, contour),
                      if (contour != null) ..._deleteBlock(contour, contours),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// «В пн–пт 9:00–19:00 пересекается с «Личное» — победит тот, что выше в
  /// списке» -- not an error, the order decides.
  List<Widget> _overlaps(List<Contour> all, Contour? self) {
    final mine = _schedule;
    if (mine == null) return const <Widget>[];
    final from = minutesOf(mine.from)!;
    final to = minutesOf(mine.to)!;
    return <Widget>[
      for (final other in all)
        if (other.id != self?.id && other.schedule != null)
          if (_overlap(mine, from, to, other.schedule!) case final days?)
            _Note(
              'В ${describeDays(days)} '
              '${formatClock(mine.from)}–${formatClock(mine.to)} '
              'пересекается с «${other.name}» — победит тот, что выше в '
              'списке.',
            ),
    ];
  }

  static List<int>? _overlap(
    ContourSchedule mine,
    int from,
    int to,
    ContourSchedule other,
  ) {
    final days = mine.days.where(other.days.contains).toList();
    if (days.isEmpty) return null;
    final otherFrom = minutesOf(other.from);
    final otherTo = minutesOf(other.to);
    if (otherFrom == null || otherTo == null) return null;
    if (from >= otherTo || otherFrom >= to) return null;
    return days;
  }

  List<Widget> _deleteBlock(Contour contour, List<Contour> all) {
    final achieved = ref.watch(achievedGoalsProvider).value;
    final goals = ref
        .watch(goalListProvider)
        .where((g) => g.contourId == contour.id)
        .length;
    final achievedHere = (achieved ?? const <GoalView>[])
        .where((g) => g.contourId == contour.id)
        .length;
    final total = goals + achievedHere;
    final last = all.length <= 1;

    final String? reason;
    var toGoals = false;
    if (last) {
      reason =
          'Это единственный контур — цели и набор держатся на нём. Заведите '
          'другой, если хотите удалить этот.';
    } else if (total > 0) {
      reason =
          'Нельзя удалить: в контуре $total ${goalsWord(total)}'
          '${achievedHere > 0 ? ' (с достигнутыми)' : ''}. Сначала перенесите '
          'их в другой контур — в карточке цели, чип контура.';
      toGoals = true;
    } else if (_refusal != null) {
      // The server knew of goals this device did not (another device made
      // them): the same explanation, without a count we cannot vouch for.
      reason =
          'Нельзя удалить: в контуре есть цели (возможно, достигнутые). '
          'Сначала перенесите их в другой контур — в карточке цели, чип '
          'контура.';
      toGoals = true;
    } else {
      reason = null;
    }

    return <Widget>[
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: reason != null ? null : () => _delete(contour, all),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.alarm,
            disabledForegroundColor: AppColors.muted,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          child: const Text('Удалить контур'),
        ),
      ),
      if (reason != null)
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.waitingFill,
            border: Border.all(color: AppColors.waitingLine),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.error_outline,
                size: 18,
                color: AppColors.waitingInk,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      reason,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.waitingInk,
                      ),
                    ),
                    if (toGoals)
                      InkWell(
                        onTap: () => openGoals(context, contourId: contour.id),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'К целям контура →',
                            style: TextStyle(
                              fontFamily: AppFonts.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.indigoLink,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: AppText.sectionLabel.copyWith(letterSpacing: 0.39),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(
    this.text, {
    this.color = AppColors.muted,
    this.weight = FontWeight.w500,
  });

  final String text;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppFonts.text,
        fontWeight: weight,
        fontSize: 12.5,
        height: 1.35,
        color: color,
      ),
    ),
  );
}

InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: AppColors.card,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: AppColors.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: AppColors.indigoLink, width: 1.5),
  ),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
);

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    maxLength: 40,
    textCapitalization: TextCapitalization.sentences,
    style: const TextStyle(
      fontFamily: AppFonts.text,
      fontWeight: FontWeight.w500,
      fontSize: 17,
      color: AppColors.ink,
    ),
    decoration: _fieldDecoration(
      hint: 'Работа, Личное…',
    ).copyWith(counterText: ''),
  );
}

class _CustomWindowField extends StatelessWidget {
  const _CustomWindowField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      style: AppText.numberSmall.copyWith(fontSize: 16),
      decoration: _fieldDecoration(hint: '1–90').copyWith(suffixText: 'дней'),
    ),
  );
}

/// Five 52x52 buttons: the chosen number and below as crowns on dark.
class _SlotsRow extends StatelessWidget {
  const _SlotsRow({required this.slots, required this.onChanged});

  final int slots;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var n = 1; n <= 5; n++) ...<Widget>[
          if (n > 1) const SizedBox(width: 8),
          Semantics(
            button: true,
            selected: n == slots,
            excludeSemantics: true,
            label: '$n ${slotsWord(n)}',
            onTap: () => onChanged(n),
            child: Material(
              color: n <= slots ? AppColors.crownChip : AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: n <= slots
                    ? BorderSide.none
                    : const BorderSide(color: AppColors.line),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () => onChanged(n),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: n <= slots
                        ? const CrownIcon(size: 18, color: AppColors.crown)
                        : Text(
                            '$n',
                            style: const TextStyle(
                              fontFamily: AppFonts.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.muted,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WindowSegments extends StatelessWidget {
  const _WindowSegments({
    required this.window,
    required this.custom,
    required this.onChoice,
    required this.onCustom,
  });

  final int window;
  final bool custom;
  final ValueChanged<int> onChoice;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, bool on, VoidCallback onTap) => Expanded(
      child: Semantics(
        button: true,
        selected: on,
        child: Material(
          color: on ? AppColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 14,
                      color: on ? AppColors.onInk : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          for (final days in _windowChoices)
            segment(
              '$days д',
              !custom && window == days,
              () => onChoice(days),
            ),
          segment('Своё', custom, onCustom),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.enabled,
    required this.days,
    required this.from,
    required this.to,
    required this.onToggle,
    required this.onDay,
    required this.onFrom,
    required this.onTo,
  });

  final bool enabled;
  final List<int> days;
  final String from;
  final String to;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onDay;
  final VoidCallback onFrom;
  final VoidCallback onTo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 0, 14, enabled ? 14 : 0),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => onToggle(!enabled),
            child: SizedBox(
              height: 56,
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Включать по расписанию',
                      style: TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: onToggle,
                    activeTrackColor: AppColors.ink,
                    activeThumbColor: AppColors.onInk,
                  ),
                ],
              ),
            ),
          ),
          if (enabled) ...<Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                for (var day = 1; day <= 7; day++)
                  _DayCircle(
                    label: weekdayShort[day - 1],
                    on: days.contains(day),
                    onTap: () => onDay(day),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _TimeButton(lead: 'с', time: from, onTap: onFrom),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('—', style: TextStyle(color: AppColors.muted)),
                ),
                Expanded(
                  child: _TimeButton(lead: 'до', time: to, onTap: onTo),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? AppColors.ink : AppColors.card,
                border: on ? null : Border.all(color: AppColors.line),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 13,
                  color: on ? AppColors.onInk : AppColors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.lead,
    required this.time,
    required this.onTap,
  });

  final String lead;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '$lead ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                  TextSpan(text: formatClock(time)),
                ],
              ),
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.ink,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
