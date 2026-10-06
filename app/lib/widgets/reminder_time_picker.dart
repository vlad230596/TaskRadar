import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminder_schedule.dart';
import '../domain/reminders.dart';
import '../models/task.dart';
import '../providers/reminder_providers.dart';

/// The second half of picking a reminder: the time of day, after the day.
///
/// Returns `HH:MM` for the server's `remindTime`, or null when the picker is
/// dismissed. Dismissing is an answer, not an abort -- "that day, whenever" --
/// which is why the button says "Без времени": the reminder then fires at the
/// hour from the settings, as every reminder did before it had a time.
///
/// [cancelText] is "Без времени" when the time follows a freshly picked day.
/// Changing the time of an existing reminder passes "Отмена" instead, and then
/// null simply means "leave it as it was".
///
/// Opens on the task's own time if it has one, else on that settings hour.
/// One function for both places a day is picked (the task screen, and the
/// status menu on a row), so the two cannot drift.
Future<String?> pickReminderTime(
  BuildContext context,
  WidgetRef ref,
  Task task, {
  String cancelText = 'Без времени',
}) async {
  final initial =
      reminderTimeFromString(task.remindTime) ??
      ref.read(reminderSettingsProvider).value ??
      ReminderTime.defaultMorning;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    helpText: 'Во сколько напомнить',
    cancelText: cancelText,
    confirmText: 'Готово',
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  return time == null ? null : reminderTimeForApi(time.hour, time.minute);
}
