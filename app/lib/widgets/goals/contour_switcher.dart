import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../domain/goals.dart';
import '../../models/goal.dart';
import '../../navigation/goal_routes.dart';
import '../../providers/goal_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'goal_icons.dart';

/// The contour switcher (`design/goals-ideas-spec.md`, п. 4): a dark pill with
/// a crown, the active contour's name and its slots as dots; a coral dot when
/// the choice is manual. Shown only with more than one contour -- callers
/// check [showContourSwitcher].
///
/// Deliberately unlike the white scope pill: the scope is what is *shown*,
/// the contour is which goals are *in force*.
bool showContourSwitcher(WidgetRef ref) =>
    ref.watch(contourListProvider).length > 1;

class ContourSwitcher extends ConsumerWidget {
  const ContourSwitcher({this.wide = false, super.key});

  /// Desktop: 34 high, r 17.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contours = ref.watch(contourListProvider);
    final active = ref.watch(activeContourProvider);
    if (contours.length < 2 || active == null) return const SizedBox.shrink();
    final goals = ref.watch(goalListProvider);
    final manual = ref.watch(activeContourIsManualProvider);
    final taken = goals
        .where((goal) => goal.contourId == active.id && goal.inSlot)
        .length;
    final height = wide ? 34.0 : 30.0;

    return Semantics(
      button: true,
      label: 'Контур: ${active.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: () => unawaited(_openMenu(context, ref, contours, active)),
        child: Container(
          height: height,
          padding: EdgeInsets.fromLTRB(wide ? 12 : 10, 0, wide ? 14 : 12, 0),
          decoration: BoxDecoration(
            color: AppColors.crownChip,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CrownIcon(size: wide ? 13 : 12, color: AppColors.crown),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  active.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: wide ? 14 : 13,
                    color: AppColors.onInk,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SlotDots(taken: taken, total: active.slots),
              const SizedBox(width: 6),
              const Icon(
                Icons.expand_more,
                size: 14,
                color: AppColors.voiceMuted,
              ),
              if (manual) ...<Widget>[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'выбрано вручную',
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.voiceRecordingSoft,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    List<Contour> contours,
    Contour active,
  ) async {
    final goals = ref.read(goalListProvider);
    final manual = ref.read(activeContourIsManualProvider);
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        overlay.size.width - origin.dx - 280,
        0,
      ),
      constraints: const BoxConstraints.tightFor(width: 280),
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: <PopupMenuEntry<String>>[
        for (final contour in contours)
          PopupMenuItem<String>(
            value: contour.id,
            height: 56,
            child: Row(
              children: <Widget>[
                Icon(
                  contour.id == active.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: contour.id == active.id
                      ? AppColors.ink
                      : AppColors.lineStrong,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        contour.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        describeSchedule(contour.schedule),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${goals.where((g) => g.contourId == contour.id && g.inSlot).length}'
                  '/${contour.slots}',
                  style: AppText.numberSmall.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        if (manual) ...<PopupMenuEntry<String>>[
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: _bySchedule,
            height: 48,
            child: Row(
              children: <Widget>[
                Icon(Icons.schedule, size: 20, color: AppColors.inkSoft),
                SizedBox(width: 12),
                Text('Вернуть по расписанию'),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: _configure,
          height: 48,
          child: Row(
            children: <Widget>[
              Icon(Icons.tune, size: 20, color: AppColors.inkSoft),
              SizedBox(width: 12),
              Text('Настроить контуры…'),
            ],
          ),
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice == _configure) {
      await openContours(context);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(contoursProvider.notifier);
    try {
      if (choice == _bySchedule) {
        await notifier.followSchedule();
        messenger
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Контур — по расписанию')));
        return;
      }
      if (choice == active.id && !manual) return;
      final until = await notifier.choose(choice);
      final name = contours.firstWhere((c) => c.id == choice).name;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(manualSwitchToast(name, until))));
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Не удалось переключить контур. ${describeApiError(error)}',
            ),
          ),
        );
    }
  }
}

const String _bySchedule = '__schedule__';
const String _configure = '__configure__';

/// A contour's slots as dots: taken `crown`, free [free] (default `goalDim`).
/// [ring] draws free slots as rings (the planning entry), else as fills.
class SlotDots extends StatelessWidget {
  const SlotDots({
    required this.taken,
    required this.total,
    this.size = 6,
    this.gap = 3,
    this.ring = false,
    super.key,
  });

  final int taken;
  final int total;
  final double size;
  final double gap;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final count = taken > total ? taken : total;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.only(right: i == count - 1 ? 0 : gap),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < taken
                    ? (i < total ? AppColors.crown : AppColors.goalExpired)
                    : (ring ? Colors.transparent : AppColors.goalDim),
                border: i >= taken && ring
                    ? Border.all(color: AppColors.goalDim, width: 1.5)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
