import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_schedule.dart';
import '../notifications/notification_gateway.dart';
import '../notifications/notification_time_zone.dart';
import '../notifications/reminder_scheduler.dart';
import '../providers/reminder_providers.dart';

/// TEMPORARY — F1 only. Delete together with its route when F4 lands.
///
/// This screen is the deliverable of iteration F1, more than the scheduler is.
/// The risk being measured ("do local alarms survive this particular phone's
/// power management, when Web Push did not?") can only be measured on the
/// device, by a person, over a night. What that person needs is not elegant
/// code but the ability to tell three indistinguishable failures apart:
///
///   1. the alarm was never armed        -> the queue section is empty;
///   2. it was armed and the OS ate it   -> it was in the queue, then was not,
///                                          and nothing was shown;
///   3. it fired but was not displayed   -> permissions section says so.
///
/// Every section below exists to answer one of those. `app/NOTIFICATIONS-CHECKLIST.md`
/// is the script that walks through them.
///
/// Nothing in the product should be built on top of this file. F4 replaces it
/// with a real reminder settings screen; the parts worth keeping (the pending
/// queue dump) can move into a small diagnostics page then.
class NotificationBenchScreen extends ConsumerStatefulWidget {
  const NotificationBenchScreen({super.key});

  static const String title = 'Стенд уведомлений (F1)';

  /// Ids for the bench's own one-off alarms. Below [reservedNotificationIds],
  /// so a task reminder can never be hashed onto one of them and a resync can
  /// never sweep them away (their payload is not a reminder payload either).
  static const int _idShowNow = 1;
  static const int _idInTwoMinutes = 2;
  static const int _idTomorrow = 3;

  @override
  ConsumerState<NotificationBenchScreen> createState() =>
      _NotificationBenchScreenState();
}

class _NotificationBenchScreenState
    extends ConsumerState<NotificationBenchScreen> {
  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(reminderSyncProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(NotificationBenchScreen.title),
        actions: [
          IconButton(
            tooltip: 'Обновить очередь',
            onPressed: _refreshEverything,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PlatformCard(),
          const SizedBox(height: 12),
          const _PermissionsCard(),
          const SizedBox(height: 12),
          _OneOffTestsCard(
            onShowNow: _showNow,
            onInTwoMinutes: _scheduleInTwoMinutes,
            onTomorrow: _scheduleTomorrow,
          ),
          const SizedBox(height: 12),
          _SyntheticSetCard(
            onSeed: () => _seedSyntheticSet(),
            onDropFirst: _dropFirstTarget,
            onClear: () => ref.read(reminderTargetsProvider.notifier).clear(),
          ),
          const SizedBox(height: 12),
          _SyncReportCard(report: sync),
          const SizedBox(height: 12),
          const _PendingQueueCard(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancelEverything,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Отменить все уведомления'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- actions -------------------------------------------------------------

  Future<tz.Location> _location() async =>
      (await ref.read(notificationTimeZoneProvider.future)).location;

  void _refreshEverything() {
    ref.invalidate(pendingNotificationsProvider);
    ref.invalidate(notificationPermissionsProvider);
  }

  Future<void> _showNow() async {
    await ref
        .read(notificationGatewayProvider)
        .showNow(
          id: NotificationBenchScreen._idShowNow,
          title: 'TaskRadar',
          body: 'Проверка: уведомление показано сразу',
          payload: 'bench:now',
        );
    _refreshEverything();
    _say(
      'Отправлено. Если ничего не появилось — дело в разрешении '
      'POST_NOTIFICATIONS или в канале, а не в будильниках.',
    );
  }

  Future<void> _scheduleInTwoMinutes() async {
    final location = await _location();
    final fireAt = tz.TZDateTime.now(location).add(const Duration(minutes: 2));
    await _scheduleOneOff(
      id: NotificationBenchScreen._idInTwoMinutes,
      body: 'Проверка: через 2 минуты',
      fireAt: fireAt,
      payload: 'bench:soon',
    );
    _say(
      'Запланировано на ${_formatTime(fireAt)}. Заблокируйте телефон '
      'и не открывайте приложение до срабатывания.',
    );
  }

  Future<void> _scheduleTomorrow() async {
    final location = await _location();
    // `.value ?? default` rather than awaiting the future: this is a diagnostic
    // button, and the settled hour is on screen right next to it. See
    // `_OneOffTestsCard`.
    final at = ref.read(reminderSettingsProvider).value ?? ReminderTime.defaultMorning;
    final today = tz.TZDateTime.now(location);
    final fireAt = tz.TZDateTime(
      location,
      today.year,
      today.month,
      today.day + 1,
      at.hour,
      at.minute,
    );

    await _scheduleOneOff(
      id: NotificationBenchScreen._idTomorrow,
      body: 'Проверка: завтра в ${at.format()}',
      fireAt: fireAt,
      payload: 'bench:tomorrow',
    );
    _say('Запланировано на ${_formatDateTime(fireAt)}.');
  }

  Future<void> _scheduleOneOff({
    required int id,
    required String body,
    required tz.TZDateTime fireAt,
    required String payload,
  }) async {
    final gateway = ref.read(notificationGatewayProvider);
    await gateway.initialize();
    final permissions = await gateway.permissions();

    await gateway.schedule(
      id: id,
      title: 'TaskRadar',
      body: body,
      fireAt: fireAt,
      payload: payload,
      exact: permissions.scheduleMode == NotificationScheduleMode.exact,
    );

    _refreshEverything();
  }

  /// Fills the target set with rows that cover every branch of
  /// [buildReminderSchedule] at once, so one tap exercises the whole thing.
  Future<void> _seedSyntheticSet() async {
    final location = await _location();
    final today = tz.TZDateTime.now(location);

    String isoDay(int offsetDays) {
      final day = tz.TZDateTime(
        location,
        today.year,
        today.month,
        today.day + offsetDays,
      );
      // The exact shape the backend stores: UTC midnight of a calendar date.
      return '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}'
          'T00:00:00.000Z';
    }

    ref
        .read(reminderTargetsProvider.notifier)
        .replaceWith(<TaskReminder>[
          TaskReminder(
            taskId: 'synthetic-yesterday',
            taskTitle: 'Вчерашнее напоминание (должно быть пропущено)',
            remindAt: isoDay(-1),
            projectName: 'Стенд',
          ),
          TaskReminder(
            taskId: 'synthetic-today',
            taskTitle: 'Сегодня (сработает, только если час ещё не прошёл)',
            remindAt: isoDay(0),
            projectName: 'Стенд',
          ),
          TaskReminder(
            taskId: 'synthetic-tomorrow',
            taskTitle: 'Завтра — жду кабель',
            remindAt: isoDay(1),
            projectName: 'Стенд',
          ),
          TaskReminder(
            taskId: 'synthetic-in-3-days',
            taskTitle: 'Через три дня — перезвонить в сервис',
            remindAt: isoDay(3),
            projectName: 'Стенд',
          ),
          const TaskReminder(
            taskId: 'synthetic-broken',
            taskTitle: 'Битая дата (должна быть пропущена с причиной)',
            remindAt: 'не-дата',
            projectName: 'Стенд',
          ),
        ]);
  }

  /// Removes one row from the target set. The point is to watch the queue
  /// *shrink*: a scheduler that only ever adds would look identical on every
  /// other button.
  void _dropFirstTarget() {
    final targets = ref.read(reminderTargetsProvider);
    if (targets.isEmpty) return;
    ref.read(reminderTargetsProvider.notifier).replaceWith(targets.skip(1));
  }

  Future<void> _cancelEverything() async {
    final scheduler = await ref.read(reminderSchedulerProvider.future);
    await scheduler.cancelAll();
    ref.read(reminderTargetsProvider.notifier).clear();
    _refreshEverything();
    _say('Очередь очищена.');
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// --- sections --------------------------------------------------------------

class _PlatformCard extends ConsumerWidget {
  const _PlatformCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(notificationTimeZoneProvider);
    final gateway = ref.watch(notificationGatewayProvider);

    // Watched purely for its side effect: the scheduler provider is what calls
    // `gateway.initialize()`, and `support` only tells the truth afterwards --
    // before that it cannot know the plugin failed to register. Reading the
    // note from an un-initialised gateway would claim full Android support on a
    // device where notifications are impossible, which is the one lie this
    // screen must not tell.
    final ready = ref.watch(reminderSchedulerProvider).hasValue;

    return _Section(
      title: 'Платформа',
      children: [
        Text(ready ? gateway.support.note : '…'),
        const SizedBox(height: 8),
        switch (zone) {
          AsyncData(:final NotificationTimeZone value) => _Row(
            label: 'Часовой пояс',
            value: value.source == TimeZoneSource.device
                ? '${value.name} (от системы)'
                : '${value.name} — ЗАПАСНОЙ вариант, фиксированное '
                      'смещение: время может уехать на час после перевода часов',
            warn: value.source != TimeZoneSource.device,
          ),
          AsyncError(:final error) => _Row(
            label: 'Часовой пояс',
            value: 'ошибка: $error',
            warn: true,
          ),
          _ => const _Row(label: 'Часовой пояс', value: '…'),
        },
      ],
    );
  }
}

class _PermissionsCard extends ConsumerWidget {
  const _PermissionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(notificationPermissionsProvider);

    return _Section(
      title: 'Разрешения',
      children: [
        switch (permissions) {
          AsyncData(:final NotificationPermissionState value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(
                label: 'Уведомления (POST_NOTIFICATIONS)',
                value: _tri(value.notificationsEnabled),
                warn: value.notificationsEnabled == false,
              ),
              _Row(
                label: 'Точные будильники',
                value: _tri(value.canScheduleExactAlarms),
                warn: value.canScheduleExactAlarms == false,
              ),
              if (value.scheduleMode == NotificationScheduleMode.inexact)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Будильники ставятся неточными: сработают, но могут '
                    'опоздать на часы. Для «напомнить утром» это заметно.',
                  ),
                ),
            ],
          ),
          AsyncError(:final error) => Text('Ошибка: $error'),
          _ => const Text('…'),
        },
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () =>
              ref.read(notificationPermissionsProvider.notifier).request(),
          child: const Text('Запросить разрешения'),
        ),
      ],
    );
  }

  static String _tri(bool? value) => switch (value) {
    true => 'выдано',
    false => 'НЕ выдано',
    null => 'неизвестно / неприменимо',
  };
}

class _OneOffTestsCard extends ConsumerWidget {
  const _OneOffTestsCard({
    required this.onShowNow,
    required this.onInTwoMinutes,
    required this.onTomorrow,
  });

  final VoidCallback onShowNow;
  final VoidCallback onInTwoMinutes;
  final VoidCallback onTomorrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at =
        ref.watch(reminderSettingsProvider).value ?? ReminderTime.defaultMorning;

    return _Section(
      title: 'Разовые проверки',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: onShowNow, child: const Text('Показать сейчас')),
            FilledButton(
              onPressed: onInTwoMinutes,
              child: const Text('Через 2 минуты'),
            ),
            FilledButton(
              onPressed: onTomorrow,
              child: Text('Завтра в ${at.format()}'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Час напоминания — ${at.format()}. С F4 он настраивается на экране '
          '«Настройки» и переживает перезапуск; здесь он только показан, '
          'чтобы не было двух мест, где его можно поменять.',
        ),
      ],
    );
  }
}

class _SyntheticSetCard extends ConsumerWidget {
  const _SyntheticSetCard({
    required this.onSeed,
    required this.onDropFirst,
    required this.onClear,
  });

  final VoidCallback onSeed;
  final VoidCallback onDropFirst;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(reminderTargetsProvider);

    return _Section(
      title: 'Синтетический набор задач (${targets.length})',
      children: [
        const Text(
          'Ровно то, что на F2 придёт с доски: список задач с датами. '
          'Любое изменение набора само приводит очередь ОС в соответствие.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: onSeed, child: const Text('Заполнить (5 задач)')),
            OutlinedButton(
              onPressed: targets.isEmpty ? null : onDropFirst,
              child: const Text('Убрать первую'),
            ),
            OutlinedButton(
              onPressed: targets.isEmpty ? null : onClear,
              child: const Text('Очистить'),
            ),
          ],
        ),
        if (targets.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final target in targets)
            _Row(
              label: '#${notificationIdForTask(target.taskId)}',
              value: '${target.remindAt} — ${target.taskTitle}',
            ),
        ],
      ],
    );
  }
}

class _SyncReportCard extends StatelessWidget {
  const _SyncReportCard({required this.report});

  final AsyncValue<ReminderSyncReport> report;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Последняя синхронизация',
      children: [
        switch (report) {
          AsyncData(:final ReminderSyncReport value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value.summary),
              if (value.schedule.reminders.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final reminder in value.schedule.reminders)
                  _Row(
                    label: '#${reminder.id}',
                    value:
                        '${_formatDateTime(reminder.fireAt)} — ${reminder.body}',
                  ),
              ],
              if (value.schedule.skipped.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final skipped in value.schedule.skipped)
                  _Row(
                    label: _skipLabel(skipped.reason),
                    value: skipped.reminder.taskTitle,
                    warn: skipped.reason != SkipReason.inThePast,
                  ),
              ],
            ],
          ),
          AsyncError(:final error) => Text('Ошибка: $error'),
          _ => const Text('…'),
        },
      ],
    );
  }

  static String _skipLabel(SkipReason reason) => switch (reason) {
    SkipReason.malformedDate => 'битая дата',
    SkipReason.inThePast => 'в прошлом',
    SkipReason.idCollision => 'коллизия id',
  };
}

class _PendingQueueCard extends ConsumerWidget {
  const _PendingQueueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingNotificationsProvider);

    return _Section(
      title: 'Очередь ОС (pendingNotificationRequests)',
      children: [
        const Text(
          'Это то, что реально знает система. Пусто — значит не запланировали. '
          'Непусто, а уведомление не пришло — значит съело энергосбережение.',
        ),
        const SizedBox(height: 8),
        switch (pending) {
          AsyncData(:final List<PendingNotification> value) when value.isEmpty =>
            const Text('Очередь пуста.'),
          AsyncData(:final List<PendingNotification> value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in value)
                _Row(
                  label: '#${entry.id}${entry.isReminder ? ' (задача)' : ''}',
                  value: '${entry.body ?? ''}   [${entry.payload ?? '—'}]',
                ),
            ],
          ),
          AsyncError(:final error) => Text('Ошибка: $error'),
          _ => const Text('…'),
        },
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(pendingNotificationsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Перечитать очередь'),
        ),
      ],
    );
  }
}

// --- small shared bits -----------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: warn ? theme.colorScheme.error : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: style),
          ),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _formatTime(tz.TZDateTime value) =>
    '${_two(value.hour)}:${_two(value.minute)}';

String _formatDateTime(tz.TZDateTime value) =>
    '${_two(value.day)}.${_two(value.month)} ${_formatTime(value)}';
