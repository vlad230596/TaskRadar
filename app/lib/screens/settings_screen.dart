import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminder_schedule.dart';
import '../providers/reminder_providers.dart';
import '../providers/voice_providers.dart';
import '../voice/voice_model.dart';
import '../widgets/mutation_feedback.dart';
import 'notification_bench_screen.dart';

/// Settings (F4). One real setting, and the two diagnostics that belong next to
/// it.
///
/// The setting is the hour reminders fire at. It is a *setting* rather than
/// something derived from the data because `remindAt` has day granularity and no
/// time-of-day component at all: the user picked a date, and "at what time on
/// that date" is a preference about mornings, not a fact about the task.
///
/// The permission block is here rather than only on the bench because a denied
/// `POST_NOTIFICATIONS` is completely silent -- `zonedSchedule` succeeds, the
/// alarm fires, and the OS drops the notification. Someone whose reminders stop
/// arriving has no other place to look that would tell them why.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _ReminderTimeTile(),
          Divider(height: 24),
          _VoiceModelTile(),
          Divider(height: 24),
          _PermissionsTile(),
          Divider(height: 24),
          _BenchTile(),
        ],
      ),
    );
  }
}

/// The speech model (F9): downloading it, seeing what it costs, deleting it.
///
/// ## Why a quarter of a gigabyte is a settings screen and not a silent fetch
///
/// The model is 163 MB to download and 236 MB on disk -- more than the rest of
/// the app by an order of magnitude. Downloading that the first time somebody
/// touches a microphone button, on whatever connection they happen to be on,
/// is the kind of surprise that gets an app uninstalled. So it is presented as
/// something to agree to, with the number visible before the decision and a way
/// to take it back afterwards.
///
/// The microphone button in the sandbox appears only once this says "готово".
class _VoiceModelTile extends ConsumerWidget {
  const _VoiceModelTile();

  static String _megabytes(int bytes) => '${(bytes / 1000000).round()} МБ';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(voiceModelInstallationProvider);
    final notifier = ref.read(voiceModelInstallationProvider.notifier);
    final model = notifier.model;

    return switch (state) {
      VoiceModelUnknown() => const ListTile(
        leading: Icon(Icons.mic_none),
        title: Text('Голосовой ввод'),
        subtitle: Text('Проверяем, скачана ли модель…'),
      ),

      VoiceModelMissing(:final lastError) => ListTile(
        leading: const Icon(Icons.mic_none),
        title: const Text('Голосовой ввод'),
        subtitle: Text(
          lastError == null
              ? 'Распознавание работает на устройстве и без сети. '
                    'Модель нужно скачать один раз: '
                    '${_megabytes(model.downloadBytes)} загрузки, '
                    '${_megabytes(model.installedBytes)} на диске.'
              : 'Не удалось скачать модель: $lastError',
          style: lastError == null
              ? null
              : theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
        ),
        isThreeLine: true,
        trailing: FilledButton.tonal(
          onPressed: () => notifier.install(),
          child: Text(lastError == null ? 'Скачать' : 'Ещё раз'),
        ),
      ),

      VoiceModelInstalling(:final fraction, :final unpacking) => ListTile(
        leading: const Icon(Icons.mic_none),
        title: const Text('Голосовой ввод'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unpacking
                  // Its own phase on purpose: unpacking takes tens of seconds
                  // and reports no progress, and a bar sitting at 100% in
                  // silence looks exactly like a hang.
                  ? 'Распаковываем модель…'
                  : 'Скачиваем модель…',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: unpacking ? null : fraction),
          ],
        ),
        isThreeLine: true,
        trailing: TextButton(
          // Cancelling an unpack is not offered: it is a few tens of seconds
          // and stopping it halfway leaves the directory to be cleaned up
          // anyway.
          onPressed: unpacking ? null : notifier.cancelInstall,
          child: const Text('Отмена'),
        ),
      ),

      VoiceModelReady(:final installed) => ListTile(
        leading: Icon(Icons.mic, color: theme.colorScheme.primary),
        title: const Text('Голосовой ввод готов'),
        subtitle: Text(
          '${model.name}. Занимает ${_megabytes(installed.bytesOnDisk)}. '
          'Распознавание идёт на устройстве — запись никуда не отправляется.',
        ),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: () => _confirmRemoval(context, ref),
          child: const Text('Удалить'),
        ),
      ),
    };
  }

  Future<void> _confirmRemoval(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Удалить модель?',
      message:
          'Голосовой ввод перестанет работать, пока модель не скачать заново.',
      confirmLabel: 'Удалить',
    );
    if (!confirmed) return;

    await ref.read(voiceModelInstallationProvider.notifier).remove();
  }
}

class _ReminderTimeTile extends ConsumerWidget {
  const _ReminderTimeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    final time = settings.value;

    return ListTile(
      leading: const Icon(Icons.alarm),
      title: const Text('Время утреннего напоминания'),
      subtitle: Text(
        time == null
            // The read is a disk round trip, so there is a frame or two with no
            // answer. Showing the default during it would be a lie that
            // occasionally flashes the wrong number at someone who set 07:30.
            ? 'Загружаем…'
            : 'Напоминания приходят в ${time.format()} по местному времени '
                  'в выбранный день.',
      ),
      trailing: time == null
          ? null
          : Text(time.format(), style: Theme.of(context).textTheme.titleMedium),
      onTap: time == null ? null : () => _pick(context, ref, time),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    ReminderTime current,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Когда напоминать',
      cancelText: 'Отмена',
      confirmText: 'Готово',
    );
    if (picked == null || !context.mounted) return;

    // Saving the setting is the *entire* action. Nothing here mentions the
    // scheduler: `reminderSync` watches this provider, so changing it re-arms
    // every queued alarm at the new hour by itself. A "reschedule" call here
    // would be a second place that has to remember to fire, which is exactly
    // what F1 designed the graph to avoid.
    await runMutation(
      context,
      () => ref
          .read(reminderSettingsProvider.notifier)
          .setTime(ReminderTime(picked.hour, picked.minute)),
      failure: 'Время применено, но сохранить его не удалось.',
    );
  }
}

/// Notification permissions, read without prompting and requestable on tap.
class _PermissionsTile extends ConsumerWidget {
  const _PermissionsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(notificationPermissionsProvider);
    final support = ref.watch(notificationGatewayProvider).support;

    if (!support.hasRuntimePermission) {
      return ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Разрешения'),
        subtitle: Text(support.note),
      );
    }

    final state = permissions.value;
    final enabled = state?.notificationsEnabled;
    final exact = state?.canScheduleExactAlarms;

    return ListTile(
      leading: Icon(
        enabled == false ? Icons.notifications_off : Icons.notifications_active,
        color: enabled == false ? Theme.of(context).colorScheme.error : null,
      ),
      title: const Text('Разрешения на уведомления'),
      subtitle: Text(switch ((enabled, exact)) {
        (null, _) => 'Проверяем…',
        (false, _) =>
          'Уведомления запрещены — напоминания не будут показаны. '
              'Нажмите, чтобы запросить разрешение.',
        (true, false) =>
          'Уведомления разрешены, но точные будильники — нет: напоминание '
              'может опоздать на часы. Нажмите, чтобы выдать разрешение.',
        (true, _) => 'Уведомления и точные будильники разрешены.',
      }),
      onTap: () => ref.read(notificationPermissionsProvider.notifier).request(),
    );
  }
}

/// The F1 bench, reachable but no longer in the way.
///
/// It stays because `NOTIFICATIONS-CHECKLIST.md` is still the only way to answer
/// "did the alarm survive the night on this phone", and that question does not
/// go away just because the product feature is finished. It moved off the board
/// app bar because it is a diagnostic, and a diagnostic on the home screen
/// competes with the things the home screen is for.
class _BenchTile extends StatelessWidget {
  const _BenchTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.biotech_outlined),
      title: const Text(NotificationBenchScreen.title),
      subtitle: const Text(
        'Очередь будильников, разовые проверки и разрешения — для проверки '
        'по чек-листу на реальном телефоне.',
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const NotificationBenchScreen(),
        ),
      ),
    );
  }
}
