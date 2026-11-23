import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/goals.dart';
import '../models/goal.dart';
import '../navigation/goal_routes.dart';
import '../providers/goal_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/mutation_feedback.dart';

/// Settings → Contours (`design/reference/Contours.html`): the sets of goal
/// slots, in their order, the first being the default. Drag to reorder; a tap
/// opens the contour.
class ContoursScreen extends ConsumerWidget {
  const ContoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contoursProvider);
    final contours = ref.watch(contourListProvider);
    final active = ref.watch(activeContourIdProvider);

    final Widget body;
    if (contours.isEmpty && state.hasError) {
      body = _Message(
        text: 'Не удалось загрузить контуры. ${describeApiError(state.error!)}',
        action: TextButton(
          onPressed: () =>
              unawaited(ref.read(contoursProvider.notifier).refresh()),
          child: const Text('Повторить'),
        ),
      );
    } else if (contours.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(Insets.gutter, 0, Insets.gutter, 16),
        buildDefaultDragHandles: false,
        header: const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 14),
          child: Text(
            'Контур — свой набор слотов для целей и свой набор задач в работе. '
            'Активный выбирается по расписанию; первый в списке — по '
            'умолчанию.',
            style: TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w500,
              fontSize: 14,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
        ),
        itemCount: contours.length,
        onReorder: (from, to) {
          // ReorderableListView counts the slot the row left as still there.
          final index = to > from ? to - 1 : to;
          if (index == from) return;
          unawaited(
            runMutation(
              context,
              () => ref
                  .read(contoursProvider.notifier)
                  .reorder(contours[from].id, index),
              failure: 'Не удалось переставить контур.',
            ),
          );
        },
        itemBuilder: (context, index) {
          final contour = contours[index];
          return Padding(
            key: ValueKey<String>(contour.id),
            padding: const EdgeInsets.only(bottom: 10),
            child: _ContourCard(
              contour: contour,
              index: index,
              active: contour.id == active,
              isDefault: index == 0,
            ),
          );
        },
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _Header(title: 'Контуры'),
                Expanded(child: body),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: () => openContour(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.onInk,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Контур'),
                    ),
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

/// «2 слота · окно 7 д · пн–пт 9:00–19:00».
String contourSummary(Contour contour) {
  final schedule = contour.schedule;
  final when = schedule == null
      ? 'без расписания'
      : '${describeDays(schedule.days)} '
            '${formatClock(schedule.from)}–${formatClock(schedule.to)}';
  return '${contour.slots} ${slotsWord(contour.slots)} · '
      'окно ${contour.windowDays} д · $when';
}

class _ContourCard extends StatelessWidget {
  const _ContourCard({
    required this.contour,
    required this.index,
    required this.active,
    required this.isDefault,
  });

  final Contour contour;
  final int index;
  final bool active;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        onTap: () => openContour(context, contourId: contour.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
          child: Row(
            children: <Widget>[
              ReorderableDragStartListener(
                index: index,
                child: const Tooltip(
                  message: 'Перетащить',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: SizedBox(
                      width: 40,
                      height: 52,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: AppColors.lineStrong,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppColors.crownChip : AppColors.crownMutedChip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CrownIcon(
                  size: 18,
                  color: active ? AppColors.crown : AppColors.crownMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            contour.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (active) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minHeight: 22),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.indigoFill,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Text(
                              'сейчас',
                              style: TextStyle(
                                fontFamily: AppFonts.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                                color: AppColors.indigoInk,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contourSummary(contour),
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w500,
                        fontSize: 12.5,
                        color: AppColors.muted,
                      ),
                    ),
                    if (isDefault) ...<Widget>[
                      const SizedBox(height: 2),
                      const Text(
                        'по умолчанию',
                        style: TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.lineStrong),
            ],
          ),
        ),
      ),
    );
  }
}

/// The white header bar of a settings sub-screen: back, the title, and an
/// optional action on the right.
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SettingsSubHeader(title: title);
}

/// The settings sub-screens' header, shared with the contour screen.
class SettingsSubHeader extends StatelessWidget {
  const SettingsSubHeader({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Назад',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left, size: 26),
            color: AppColors.ink,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.screen.copyWith(fontSize: 18),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, textAlign: TextAlign.center, style: AppText.hint),
            ?action,
          ],
        ),
      ),
    );
  }
}
