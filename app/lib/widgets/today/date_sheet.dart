import 'package:flutter/material.dart';

import '../../domain/reminder_schedule.dart';
import '../../domain/reminders.dart';
import '../../domain/today_view.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'today_icons.dart';

/// The «Дата» and «Время» sheets (`design/today-history-spec.md` §7): dark,
/// the editor's family. One date sheet for every place a date is chosen --
/// the editor's chip, the tail's «Дата…», a blocker's «Ещё ждём…», a row's
/// long-press menu.
///
/// A tap on any day or quick button applies and closes: a date without a
/// time is the common case. The time is its own optional step.

/// What a sheet answered: a value, or [value] null for «Снять дату» /
/// «Убрать время».
@immutable
class SheetChoice {
  const SheetChoice(this.value);

  final String? value;

  bool get cleared => value == null;
}

const List<String> _monthsFull = <String>[
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

/// Opens the date sheet. [current] is the task's day (`YYYY-MM-DD` or a
/// stored `remindAt`), [time] its time -- shown as «Время 15:00 сохранится».
/// [subtitle] is «Когда этим заняться», or «Когда проверить снова» from «Ещё
/// ждём…».
Future<SheetChoice?> showTaskDateSheet(
  BuildContext context, {
  String? current,
  String? time,
  String? today,
  String subtitle = 'Когда этим заняться',
}) {
  final day = today ?? localTodayCalendarDate();
  return showModalBottomSheet<SheetChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.voiceBackground,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => DateSheet(
      current: current == null ? null : taskDay(current),
      time: time,
      today: day,
      subtitle: subtitle,
    ),
  );
}

class DateSheet extends StatefulWidget {
  const DateSheet({
    required this.today,
    this.current,
    this.time,
    this.subtitle = 'Когда этим заняться',
    super.key,
  });

  final String today;
  final String? current;
  final String? time;
  final String subtitle;

  @override
  State<DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<DateSheet> {
  late DateTime _month = () {
    final shown = localDateOf(widget.current ?? widget.today);
    return DateTime(shown.year, shown.month);
  }();

  void _pick(String day) => Navigator.of(context).pop(SheetChoice(day));

  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    final quick = <({String label, String day})>[
      (label: 'Сегодня', day: today),
      (label: 'Завтра', day: addDays(today, 1)),
      (label: 'Пн', day: nextMonday(today)),
    ];
    final time = reminderTimeFromString(widget.time);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _Handle(),
            _SheetHeader(title: 'Дата', subtitle: widget.subtitle),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                for (var i = 0; i < quick.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _QuickDay(
                      label: quick[i].label,
                      caption: i == 2
                          ? shortDate(quick[i].day)
                          : weekdayDate(quick[i].day),
                      selected: widget.current == quick[i].day,
                      onTap: () => _pick(quick[i].day),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _MonthHeader(
              month: _month,
              onPrevious: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              onNext: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
            ),
            _MonthGrid(
              month: _month,
              today: today,
              selected: widget.current,
              onPick: _pick,
            ),
            if (time != null && widget.current != null) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const TodayIcon(
                    TodayGlyph.clock,
                    size: 14,
                    color: AppColors.voiceMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Время ${formatClock(time.format())} сохранится',
                    style: _note,
                  ),
                ],
              ),
            ],
            if (widget.current != null) ...<Widget>[
              const SizedBox(height: 14),
              _OutlinedDark(
                label: 'Снять дату',
                onPressed: () =>
                    Navigator.of(context).pop(const SheetChoice(null)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the time sheet; answers `HH:MM`, or a clear. [current] is the time
/// set now.
Future<SheetChoice?> showTaskTimeSheet(
  BuildContext context, {
  String? current,
}) {
  return showModalBottomSheet<SheetChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.voiceBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _TimeSheet(current: current),
  );
}

class _TimeSheet extends StatelessWidget {
  const _TimeSheet({this.current});

  final String? current;

  static const List<String> _presets = <String>[
    '09:00',
    '12:00',
    '15:00',
    '18:00',
    '20:00',
  ];

  Future<void> _other(BuildContext context) async {
    final initial = reminderTimeFromString(current) ?? const ReminderTime(9, 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: 'Время',
      cancelText: 'Отмена',
      confirmText: 'Готово',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(
      context,
    ).pop(SheetChoice(reminderTimeForApi(picked.hour, picked.minute)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _Handle(),
            const _SheetHeader(
              title: 'Время',
              subtitle: 'Пуш в это время. Без времени — без пуша.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final preset in _presets)
                  _Pill(
                    label: formatClock(preset),
                    selected: current == preset,
                    onTap: () =>
                        Navigator.of(context).pop(SheetChoice(preset)),
                  ),
                _Pill(label: 'Другое…', onTap: () => _other(context)),
              ],
            ),
            if (current != null) ...<Widget>[
              const SizedBox(height: 16),
              _OutlinedDark(
                label: 'Убрать время',
                onPressed: () =>
                    Navigator.of(context).pop(const SheetChoice(null)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- parts ------------------------------------------------------------------

const TextStyle _note = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w500,
  fontSize: 13,
  color: AppColors.voiceMuted,
);

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.voiceLine,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                  color: AppColors.voiceInk,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Закрыть',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: AppColors.voiceMuted),
            ),
          ],
        ),
        Text(
          subtitle,
          style: AppText.voiceNote.copyWith(fontSize: 14),
        ),
      ],
    );
  }
}

class _QuickDay extends StatelessWidget {
  const _QuickDay({
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? AppColors.voiceBackground : AppColors.voiceInk;
    return Material(
      color: selected ? AppColors.card : AppColors.voiceWell,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? AppColors.card : AppColors.voiceLine,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: selected ? AppColors.muted : AppColors.voiceMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${_monthsFull[month.month - 1]} ${month.year}',
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.voiceInk,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Предыдущий месяц',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left, color: AppColors.voiceBright),
        ),
        IconButton(
          tooltip: 'Следующий месяц',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, color: AppColors.voiceBright),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.onPick,
  });

  final DateTime month;
  final String today;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final lead = first.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = <Widget>[
      for (final name in kWeekdaysShort)
        Center(
          child: Text(
            name,
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.voiceMuted,
            ),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _DayCell(
          day: calendarDateForApi(DateTime(month.year, month.month, d)),
          number: d,
          today: today,
          selected: selected,
          onPick: onPick,
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 44 / 40,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.number,
    required this.today,
    required this.selected,
    required this.onPick,
  });

  final String day;
  final int number;
  final String today;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final isSelected = day == selected;
    final isToday = day == today;
    // Past days stay pressable: a date set backwards lands in the tail.
    final past = day.compareTo(today) < 0;
    return Semantics(
      button: true,
      selected: isSelected,
      label: weekdayDate(day),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onPick(day),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? AppColors.card : null,
              border: isToday && !isSelected
                  ? Border.all(color: AppColors.voiceLevelHigh, width: 1.5)
                  : null,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: isSelected
                    ? AppColors.voiceBackground
                    : past
                    ? AppColors.voiceMuted.withValues(alpha: 0.5)
                    : AppColors.voiceInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.selected = false});

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.card : AppColors.voiceWell,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: selected ? AppColors.voiceBackground : AppColors.voiceInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinedDark extends StatelessWidget {
  const _OutlinedDark({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.voiceBright,
          side: const BorderSide(color: AppColors.voiceLine),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: AppText.action.copyWith(fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}
