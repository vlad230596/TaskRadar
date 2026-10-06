import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/dictation_api.dart';
import '../domain/reminder_schedule.dart';
import '../providers/dictation_providers.dart';
import '../providers/reminder_providers.dart';
import '../providers/voice_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
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
      body: SafeArea(
        // The same column the other sub-screens use: a phone screen set in the
        // middle of a wide window, because a setting whose value sits a metre
        // away from its name on a 1440 px window is no longer read as one row.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _SettingsHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.gutter,
                      8,
                      Insets.gutter,
                      24,
                    ),
                    children: const <Widget>[
                      _SectionLabel('Напоминания'),
                      _SettingsGroup(
                        children: <Widget>[
                          _ReminderTimeTile(),
                          _PermissionsTile(),
                        ],
                      ),
                      _SectionLabel('Голос'),
                      _SettingsGroup(
                        children: <Widget>[
                          _VoiceModelTile(),
                          _DictationModelTile(),
                        ],
                      ),
                      _SectionLabel('Диагностика'),
                      _SettingsGroup(children: <Widget>[_BenchTile()]),
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
    final state = ref.watch(voiceModelInstallationProvider);
    final notifier = ref.read(voiceModelInstallationProvider.notifier);
    final model = notifier.model;

    return switch (state) {
      // The browser build, where there is nothing to offer: no download button,
      // because the download could not lead anywhere. See
      // `VoiceModelUnsupported`.
      VoiceModelUnsupported() => const _SettingRow(
        icon: Icons.mic_off,
        title: 'Голосовой ввод недоступен',
        description:
            'Распознавание идёт на устройстве и требует модели на диске — '
            'в браузере её негде держать. Диктовка работает в приложении для '
            'Android и Windows.',
      ),

      VoiceModelUnknown() => const _SettingRow(
        icon: Icons.mic_none,
        title: 'Голосовой ввод',
        description: 'Проверяем, скачана ли модель…',
      ),

      VoiceModelMissing(:final lastError) => _SettingRow(
        icon: Icons.mic_none,
        tone: lastError == null ? _Tone.plain : _Tone.alarm,
        title: 'Голосовой ввод',
        description: lastError == null
            ? 'Распознавание работает на устройстве и без сети. '
                  'Модель нужно скачать один раз: '
                  '${_megabytes(model.downloadBytes)} загрузки, '
                  '${_megabytes(model.installedBytes)} на диске.'
            : 'Не удалось скачать модель: $lastError',
        descriptionColor: lastError == null ? null : AppColors.alarm,
        trailing: FilledButton(
          onPressed: () => notifier.install(),
          style: _compactButton,
          child: Text(lastError == null ? 'Скачать' : 'Ещё раз'),
        ),
      ),

      VoiceModelInstalling(:final fraction, :final unpacking) => _SettingRow(
        icon: Icons.mic_none,
        title: 'Голосовой ввод',
        description: unpacking
            // Its own phase on purpose: unpacking takes tens of seconds and
            // reports no progress, and a bar sitting at 100% in silence looks
            // exactly like a hang.
            ? 'Распаковываем модель…'
            : 'Скачиваем модель…',
        below: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: unpacking ? null : fraction,
            minHeight: 4,
          ),
        ),
        trailing: TextButton(
          // Cancelling an unpack is not offered: it is a few tens of seconds
          // and stopping it halfway leaves the directory to be cleaned up
          // anyway.
          onPressed: unpacking ? null : notifier.cancelInstall,
          child: const Text('Отмена'),
        ),
      ),

      VoiceModelReady(:final installed) => _SettingRow(
        icon: Icons.mic,
        tone: _Tone.ready,
        title: 'Голосовой ввод готов',
        description:
            '${model.name}. Занимает ${_megabytes(installed.bytesOnDisk)}. '
            'Распознавание идёт на устройстве — запись никуда не отправляется.',
        trailing: TextButton(
          onPressed: () => _confirmRemoval(context, ref),
          // "Выбросить" is the one red in the app; deleting a quarter of a
          // gigabyte the user agreed to download is the same kind of act.
          style: TextButton.styleFrom(foregroundColor: AppColors.alarm),
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

    return _SettingRow(
      icon: Icons.alarm,
      title: 'Время утреннего напоминания',
      description: time == null
          // The read is a disk round trip, so there is a frame or two with no
          // answer. Showing the default during it would be a lie that
          // occasionally flashes the wrong number at someone who set 07:30.
          ? 'Загружаем…'
          : 'Напоминания без времени приходят в ${time.format()} по '
                'местному времени в выбранный день.',
      // The value is the point of the row, so it is set as one of the
      // screen's few numbers -- the same chip the app gives an age.
      trailing: time == null ? null : _ValueChip(time.format()),
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

/// The model that turns a dictation into a task on "Разобрать" (F14).
///
/// Changeable here so that trying another model -- a free one stopped being
/// free, a faster one appeared -- is not an SSH session. Only the model: the
/// API key stays in the server's `.env`, which this app can neither read nor
/// write, and that is deliberate (`backend/src/domain/dictationModel.ts`).
class _DictationModelTile extends ConsumerWidget {
  const _DictationModelTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(dictationModelSettingProvider);
    const icon = Icons.auto_awesome_outlined;
    const title = 'Модель разбора диктовки';

    return switch (setting) {
      AsyncData(:final value) => _SettingRow(
        icon: icon,
        title: title,
        description: value.override == null
            ? '${value.model} · по умолчанию с сервера'
            : '${value.model} · выбрана здесь, '
                  'по умолчанию ${value.defaultModel}',
        trailing: const _Chevron(),
        onTap: () => _edit(context, ref, value),
      ),
      AsyncError(:final error) => _SettingRow(
        icon: icon,
        tone: _Tone.waiting,
        title: title,
        description: switch (error) {
          NetworkException() => 'Нет связи с сервером.',
          ApiException(statusCode: 503) =>
            'Разбор не настроен на сервере: нет ключа модели в .env.',
          _ => 'Не удалось узнать модель.',
        },
        trailing: error is ApiException && error.statusCode == 503
            ? null
            : IconButton(
                tooltip: 'Ещё раз',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(dictationModelSettingProvider),
              ),
      ),
      _ => const _SettingRow(
        icon: icon,
        title: title,
        description: 'Спрашиваем сервер…',
      ),
    };
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    DictationModel current,
  ) async {
    final choice = await showDialog<_ModelChoice>(
      context: context,
      builder: (_) => _DictationModelDialog(current: current),
    );
    if (choice == null || !context.mounted) return;

    await runMutation(
      context,
      () =>
          ref.read(dictationModelSettingProvider.notifier).choose(choice.model),
      success: 'Модель сохранена — применится со следующего разбора.',
      failure: 'Не удалось сохранить модель.',
    );
  }
}

/// What the dialog closed with. A class rather than a bare `String?`, because
/// "go back to the default" (null) and "the dialog was dismissed" must not be
/// the same value.
class _ModelChoice {
  const _ModelChoice(this.model);

  final String? model;
}

class _DictationModelDialog extends StatefulWidget {
  const _DictationModelDialog({required this.current});

  final DictationModel current;

  @override
  State<_DictationModelDialog> createState() => _DictationModelDialogState();
}

class _DictationModelDialogState extends State<_DictationModelDialog> {
  late final TextEditingController _model = TextEditingController(
    text: widget.current.model,
  );

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Модель разбора'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _model,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Идентификатор модели',
              hintText: 'vendor/model-name',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Как в каталоге провайдера, например на OpenRouter. '
            'По умолчанию: ${widget.current.defaultModel}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        if (widget.current.override != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _ModelChoice(null)),
            child: const Text('По умолчанию'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _model,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(_ModelChoice(value.text.trim())),
            child: const Text('Сохранить'),
          ),
        ),
      ],
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
      return _SettingRow(
        icon: Icons.info_outline,
        title: 'Разрешения',
        description: support.note,
      );
    }

    final state = permissions.value;
    final enabled = state?.notificationsEnabled;
    final exact = state?.canScheduleExactAlarms;
    final missing = enabled == false || exact == false;

    return _SettingRow(
      icon: enabled == false
          ? Icons.notifications_off
          : Icons.notifications_active,
      tone: switch ((enabled, exact)) {
        (false, _) => _Tone.alarm,
        (true, false) => _Tone.waiting,
        _ => _Tone.plain,
      },
      title: 'Разрешения на уведомления',
      // Only the row that has something to grant says it can be tapped.
      trailing: missing ? const _Chevron() : null,
      description: switch ((enabled, exact)) {
        (null, _) => 'Проверяем…',
        (false, _) =>
          'Уведомления запрещены — напоминания не будут показаны. '
              'Нажмите, чтобы запросить разрешение.',
        (true, false) =>
          'Уведомления разрешены, но точные будильники — нет: напоминание '
              'может опоздать на часы. Нажмите, чтобы выдать разрешение.',
        (true, _) => 'Уведомления и точные будильники разрешены.',
      },
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
    return _SettingRow(
      icon: Icons.biotech_outlined,
      title: NotificationBenchScreen.title,
      description:
          'Очередь будильников, разовые проверки и разрешения — для проверки '
          'по чек-листу на реальном телефоне.',
      trailing: const _Chevron(),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const NotificationBenchScreen(),
        ),
      ),
    );
  }
}

// --- the screen's own pieces ------------------------------------------------

/// The header every sub-screen has: a white bar with a hairline under it, the
/// back chevron, and the title in the display face -- the same bar as the
/// project screen's, instead of Material's app bar, which set the title at a
/// different height and left the screen looking borrowed from another app.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(canPop ? 4 : Insets.gutter, 10, 16, 10),
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: <Widget>[
          if (canPop)
            IconButton(
              tooltip: 'Назад',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left, size: 26),
              color: AppColors.ink,
            ),
          const Expanded(child: Text('Настройки', style: AppText.screen)),
        ],
      ),
    );
  }
}

/// "НАПОМИНАНИЯ ————": the group's name with a rule running out to the edge,
/// as the pick screen labels its projects.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: <Widget>[
          Text(name.toUpperCase(), style: AppText.sectionLabel),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: AppColors.line, height: 1)),
        ],
      ),
    );
  }
}

/// One white card holding a group's rows, with the faintest rule between them.
///
/// A card per group rather than per row: two rows about reminders are one
/// subject, and ten separate cards on one screen would read as a list of
/// things to do rather than a page of choices.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(
                color: AppColors.lineFaint,
                height: 1,
                indent: 14 + _SettingRow.iconBox + 12,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// How a row's icon is tinted: by what the row is saying, not by decoration.
enum _Tone {
  /// Nothing to report.
  plain(AppColors.background, AppColors.muted),

  /// Something is set up and working -- the speech model on disk.
  ready(AppColors.indigoFill, AppColors.indigoInk),

  /// Works, but not fully: exact alarms denied, the server unreachable.
  waiting(AppColors.waitingChip, AppColors.waitingInk),

  /// Broken in a way the user has to fix.
  alarm(Color(0xFFFBE7E3), AppColors.alarm);

  const _Tone(this.fill, this.ink);

  final Color fill;
  final Color ink;
}

/// One setting: an icon in a rounded square, a name, a sentence about it, and
/// the control on the right.
///
/// The name and the sentence are two different styles on purpose -- 15/600 ink
/// and 13/500 muted, as everywhere else in the app. `ListTile` set both at the
/// same size and colour, and a screen of five equal paragraphs gave the eye
/// nowhere to land.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    this.description,
    this.descriptionColor,
    this.tone = _Tone.plain,
    this.trailing,
    this.below,
    this.onTap,
  });

  static const double iconBox = 36;

  final IconData icon;
  final String title;
  final String? description;
  final Color? descriptionColor;
  final _Tone tone;
  final Widget? trailing;

  /// Under the sentence: the download's progress bar.
  final Widget? below;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Targets.row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: tone.fill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: tone.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  // Centres a one-line name on the icon square.
                  padding: const EdgeInsets.only(top: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: AppText.action),
                      if (description != null) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          description!,
                          style: descriptionColor == null
                              ? AppText.hint
                              : AppText.hint.copyWith(color: descriptionColor),
                        ),
                      ],
                      if (below != null) ...<Widget>[
                        const SizedBox(height: 10),
                        below!,
                      ],
                    ],
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                // Aligned to the name rather than to the whole block: a button
                // floating in the middle of a four-line sentence belongs to no
                // line in particular.
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The current value of a row, in a chip: "09:00".
class _ValueChip extends StatelessWidget {
  const _ValueChip(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(value, style: AppText.numberSmall.copyWith(fontSize: 15)),
    );
  }
}

/// "This row opens something."
class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Icon(Icons.chevron_right, size: 24, color: AppColors.lineStrong),
    );
  }
}

/// A filled button that fits beside a sentence: the 44 px floor kept, the
/// horizontal padding Material gives a full-width action taken away.
final ButtonStyle _compactButton = FilledButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 16),
);
