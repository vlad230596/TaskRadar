import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reminder_schedule.dart';
import '../../domain/reminders.dart';
import '../../providers/reminder_providers.dart';
import '../reminder_time_picker.dart';
import 'editor_theme.dart';

/// A reminder as the editor holds it: the calendar day (`YYYY-MM-DD`, see
/// [calendarDateForApi]) and maybe the time of day (`HH:MM`).
@immutable
class ReminderValue {
  const ReminderValue(this.date, [this.time]);

  /// From a task row's `remindAt` / `remindTime`, or null when it has none.
  /// The row's `2026-10-01T00:00:00.000Z` is read as its calendar day.
  static ReminderValue? fromRow(String? remindAt, String? remindTime) {
    if (remindAt == null) return null;
    return ReminderValue(reminderCalendarDate(remindAt) ?? remindAt, remindTime);
  }

  final String date;
  final String? time;

  ReminderValue withTime(String? time) => ReminderValue(date, time);

  @override
  bool operator ==(Object other) =>
      other is ReminderValue && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => 'ReminderValue($date ${time ?? '--:--'})';
}

/// What the reminder sheet answered: a new value, or [value] null for
/// "убрать напоминание".
@immutable
class ReminderChoice {
  const ReminderChoice(this.value);

  final ReminderValue? value;
}

const List<String> _weekdays = <String>['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// The chip's words for a reminder: «Сегодня, 10:00», «Завтра», «Пт, 18:00»
/// within the coming week, «15.11, 09:30» further out.
String reminderChipLabel(ReminderValue value, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final day = calendarDateFromRemindAt(value.date);
  final time = reminderTimeFromString(value.time);
  final String dayLabel;
  if (day == null) {
    dayLabel = value.date;
  } else {
    final today = DateTime.utc(clock.year, clock.month, clock.day);
    final date = DateTime.utc(day.year, day.month, day.day);
    final offset = date.difference(today).inDays;
    dayLabel = switch (offset) {
      0 => 'Сегодня',
      1 => 'Завтра',
      > 1 && < 7 => _weekdays[date.weekday - 1],
      _ => formatReminderDate(value.date),
    };
  }
  return time == null ? dayLabel : '$dayLabel, ${time.format()}';
}

/// True when the reminder's moment has gone by -- the chip says «уже прошло».
bool reminderIsPast(ReminderValue value, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final today = localTodayCalendarDate(clock);
  final day = reminderCalendarDate(value.date) ?? value.date;
  final order = day.compareTo(today);
  if (order != 0) return order < 0;
  final time = reminderTimeFromString(value.time);
  if (time == null) return false;
  return clock.hour * 60 + clock.minute > time.hour * 60 + time.minute;
}

/// The quick choices of the sheet, from [now]: «Сегодня вечером» (while it
/// is still before 19:00), «Завтра утром» (at the settings hour), «В
/// выходные» (the coming Saturday at 10), «Через неделю» (the day only).
List<({String label, ReminderValue value})> quickReminders(
  DateTime now, {
  ReminderTime morning = ReminderTime.defaultMorning,
}) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime plus(int days) => DateTime(today.year, today.month, today.day + days);
  var toSaturday = DateTime.saturday - today.weekday;
  if (toSaturday < 0 || (toSaturday == 0 && now.hour >= 10)) toSaturday += 7;
  return <({String label, ReminderValue value})>[
    if (now.hour < 19)
      (
        label: 'Сегодня вечером',
        value: ReminderValue(calendarDateForApi(today), '19:00'),
      ),
    (
      label: 'Завтра утром',
      value: ReminderValue(calendarDateForApi(plus(1)), morning.format()),
    ),
    (
      label: 'В выходные',
      value: ReminderValue(calendarDateForApi(plus(toSaturday)), '10:00'),
    ),
    (label: 'Через неделю', value: ReminderValue(calendarDateForApi(plus(7)))),
  ];
}

/// The day picker, as `YYYY-MM-DD`, or null when dismissed. Opens on
/// [current] -- re-assembled from its calendar parts, never parsed as an
/// instant (`remindAtAsLocalDay`), or the picker opens a day early west of
/// UTC.
Future<String?> pickReminderDay(BuildContext context, {String? current}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var initial = current == null ? today : remindAtAsLocalDay(current) ?? today;
  // A past day cannot be offered (`firstDate` is today: a reminder in the
  // past can never fire), so a past one opens on today.
  if (initial.isBefore(today)) initial = today;
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: today,
    lastDate: today.add(const Duration(days: 3650)),
    helpText: 'Когда напомнить',
    cancelText: 'Отмена',
    confirmText: 'Готово',
  );
  return picked == null ? null : calendarDateForApi(picked);
}

/// A new reminder the long way: the day, then the time of day ("Без
/// времени" means the day only). Null when the day picker was dismissed.
Future<ReminderValue?> pickReminderDayAndTime(
  BuildContext context,
  WidgetRef ref, {
  ReminderValue? current,
}) async {
  final day = await pickReminderDay(context, current: current?.date);
  if (day == null || !context.mounted) return null;
  final time = await pickReminderTimeOf(context, ref, current: current?.time);
  return ReminderValue(day, time);
}

enum _Action { pickDay, changeDay, changeTime, noTime, remove }

/// The reminder chip's sheet (spec, section 3): the quick choices, the
/// calendar, and for a set reminder what can be changed in it -- the day
/// (keeping the time), the time, taking the time off, taking it all off.
///
/// Returns null when nothing was chosen.
Future<ReminderChoice?> showReminderSheet(
  BuildContext context,
  WidgetRef ref, {
  ReminderValue? current,
  DateTime? now,
}) async {
  final clock = now ?? DateTime.now();
  final morning =
      ref.read(reminderSettingsProvider).value ?? ReminderTime.defaultMorning;
  final quick = quickReminders(clock, morning: morning);

  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                current == null
                    ? 'Когда напомнить'
                    : 'Напомнить: ${reminderChipLabel(current, now: clock)}',
                style: EditorText.header.copyWith(fontSize: 18),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final option in quick)
                    ActionChip(
                      label: Text(option.label),
                      labelStyle: EditorText.chip,
                      backgroundColor: EditorColors.well,
                      side: const BorderSide(color: EditorColors.line),
                      shape: const StadiumBorder(),
                      onPressed: () => Navigator.of(context).pop(option.value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (current == null)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Выбрать день…'),
                onTap: () => Navigator.of(context).pop(_Action.pickDay),
              )
            else ...<Widget>[
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Изменить дату'),
                onTap: () => Navigator.of(context).pop(_Action.changeDay),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(
                  current.time == null ? 'Добавить время' : 'Изменить время',
                ),
                onTap: () => Navigator.of(context).pop(_Action.changeTime),
              ),
              if (current.time != null)
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined),
                  title: const Text('Убрать время'),
                  subtitle: const Text(
                    'Напомню в час из настроек',
                    style: EditorText.note,
                  ),
                  onTap: () => Navigator.of(context).pop(_Action.noTime),
                ),
              ListTile(
                leading: const Icon(
                  Icons.notifications_off_outlined,
                  color: EditorColors.past,
                ),
                title: const Text('Убрать напоминание'),
                onTap: () => Navigator.of(context).pop(_Action.remove),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return null;

  switch (picked) {
    case final ReminderValue value:
      return ReminderChoice(value);
    case _Action.pickDay:
      final value = await pickReminderDayAndTime(context, ref);
      return value == null ? null : ReminderChoice(value);
    case _Action.changeDay:
      final day = await pickReminderDay(context, current: current?.date);
      if (day == null) return null;
      // The time stays: changing the day of "в 14:30" keeps "в 14:30".
      return ReminderChoice(ReminderValue(day, current?.time));
    case _Action.changeTime:
      // "Отмена", not "Без времени": the sheet has its own line for that,
      // and dismissing a picker opened to change a time changes nothing.
      final time = await pickReminderTimeOf(
        context,
        ref,
        current: current?.time,
        cancelText: 'Отмена',
      );
      if (time == null || current == null) return null;
      return ReminderChoice(current.withTime(time));
    case _Action.noTime:
      return current == null ? null : ReminderChoice(current.withTime(null));
    case _Action.remove:
      return const ReminderChoice(null);
  }
  return null;
}
