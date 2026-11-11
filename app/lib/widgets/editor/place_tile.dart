import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/geofence_plan.dart';
import '../../models/task_location.dart';
import '../../providers/geofence_providers.dart';
import '../../screens/settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'location_picker.dart';

/// The spec's name for the same widget (`design/task-editor-spec.md` §11).
typedef LocationTile = PlaceTile;

/// The editor's place section (`design/task-editor-spec.md` §7): «Напомнить по
/// месту» when there is none, the chosen place with «изменить» / «убрать» when
/// there is one, and -- under it -- whether the zone will actually fire on this
/// phone, because a place reminder that silently cannot work is worse than
/// none.
///
/// Stateless about the value: the editor owns the draft, this only reports
/// changes through [onChanged] (null = remove the place).
///
/// Drawn for the editor's dark palette (`voice*` tokens).
class PlaceTile extends ConsumerWidget {
  const PlaceTile({
    super.key,
    this.value,
    required this.onChanged,
    this.taskId,
  });

  /// The draft's place, or null.
  final TaskLocation? value;

  final ValueChanged<TaskLocation?> onChanged;

  /// The task being edited, for the «лимит» status; null for a new task.
  final String? taskId;

  Future<void> _pick(BuildContext context) async {
    final picked = await pickLocation(context, initial: value);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = value;
    if (place == null) {
      return _Shell(
        onTap: () => _pick(context),
        icon: Icons.add_location_alt_outlined,
        title: 'Напомнить по месту',
        subtitle: 'Когда окажетесь рядом',
      );
    }

    final status = ref.watch(placeReminderStatusProvider(taskId));
    final note = placeStatusNote(status);
    final opensSettings =
        status == PlaceReminderStatus.off ||
        status == PlaceReminderStatus.noBackgroundAccess;

    return _Shell(
      onTap: () => _pick(context),
      icon: Icons.place,
      title: place.label?.trim().isNotEmpty == true
          ? place.label!.trim()
          : defaultPlaceLabel,
      subtitle: 'Радиус ${place.radius} м · при входе',
      note: note,
      noteWarns: status != PlaceReminderStatus.phoneOnly,
      onNoteTap: opensSettings
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            )
          : null,
      trailing: <Widget>[
        IconButton(
          tooltip: 'Изменить место',
          onPressed: () => _pick(context),
          icon: const Icon(Icons.edit_location_alt_outlined),
          color: AppColors.voiceMuted,
        ),
        IconButton(
          tooltip: 'Убрать место',
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.close),
          color: AppColors.voiceMuted,
        ),
      ],
    );
  }
}

/// The line under a chosen place, or null when there is nothing to say.
String? placeStatusNote(PlaceReminderStatus status) => switch (status) {
  PlaceReminderStatus.phoneOnly => 'Срабатывает только на телефоне',
  PlaceReminderStatus.off =>
    'Не сработает: напоминания по месту выключены — включить в Настройках',
  PlaceReminderStatus.noBackgroundAccess =>
    'Не сработает: нет доступа к геопозиции в фоне — открыть Настройки',
  PlaceReminderStatus.overLimit =>
    'Не отслеживается: мест больше $geofenceLimit (лимит телефона)',
  PlaceReminderStatus.failed =>
    'Телефон не принял место — попробуем ещё раз при следующем запуске',
  PlaceReminderStatus.active || PlaceReminderStatus.unknown => null,
};

class _Shell extends StatelessWidget {
  const _Shell({
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.note,
    this.noteWarns = true,
    this.onNoteTap,
    this.trailing = const <Widget>[],
  });

  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? note;
  final bool noteWarns;
  final VoidCallback? onNoteTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final muted = AppText.hint.copyWith(color: AppColors.voiceMuted);
    return Material(
      color: AppColors.voiceWell,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.voiceLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: AppColors.voiceBright, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.action.copyWith(
                            color: AppColors.voiceInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: muted),
                      ],
                    ),
                  ),
                  ...trailing,
                  if (trailing.isEmpty) const SizedBox(height: 44),
                ],
              ),
              if (note != null)
                InkWell(
                  onTap: onNoteTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(34, 6, 10, 2),
                    child: Text(
                      note!,
                      style: muted.copyWith(
                        color: noteWarns
                            ? AppColors.waitingDotOnInk
                            : AppColors.voiceMuted,
                        decoration: onNoteTap == null
                            ? null
                            : TextDecoration.underline,
                        decorationColor: AppColors.waitingDotOnInk,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
