import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../domain/goals.dart';
import '../models/goal.dart';
import '../navigation/app_routes.dart';
import '../navigation/goal_routes.dart';
import '../providers/goal_providers.dart';
import '../providers/shell_providers.dart';
import '../screens/dictation_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/goals/crown.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/mode_navigation.dart';
import 'goal_screen.dart';

/// The goals screen (`design/goals-ideas-spec.md`, п. 5; `Goals.html`,
/// `Desk-Goals.html`): one contour per tab, its slots (used of total), the
/// bench, «+ Цель». Reached from «Планирование».
///
/// Everything a goal can be asked to do from here -- slot, extend, bench,
/// achieve -- is an online write through [Goals]; the helpers at the bottom
/// of this file ([slotGoalWithFeedback] and its siblings) say what happened
/// in a snackbar, with «Вернуть» where the spec asks for it, and are public so
/// the work screen's block can say it the same way.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({this.contourId, super.key});

  /// The tab to open on; the active contour's when null.
  final String? contourId;

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  String? _tab;

  /// The goal shown in the desktop panel.
  String? _selected;

  String? _tabOf(List<Contour> contours, String? active) {
    final wanted = _tab ?? widget.contourId ?? active;
    if (contours.any((c) => c.id == wanted)) return wanted;
    return contours.isEmpty ? null : contours.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final contours = ref.watch(contourListProvider);
    final goalsState = ref.watch(goalsProvider);
    final goals = ref.watch(goalListProvider);
    final active = ref.watch(activeContourIdProvider);
    final tab = _tabOf(contours, active);
    final contour = contours.where((c) => c.id == tab).firstOrNull;
    final wide = isWideLayout(context);

    final Widget body;
    if (contour == null) {
      body = _Message(
        loading: ref.watch(contoursProvider).isLoading || goalsState.isLoading,
        text: 'Не удалось загрузить цели. Нужна сеть.',
        onRetry: () {
          unawaited(ref.read(contoursProvider.notifier).refresh());
          unawaited(ref.read(goalsProvider.notifier).refresh());
        },
      );
    } else {
      final ofContour = goalsOfContour(goals, contour.id);
      final list = _GoalsList(
        contour: contour,
        goals: ofContour,
        selected: wide ? (_selected ?? _firstId(ofContour)) : null,
        onOpen: wide
            ? (id) => setState(() => _selected = id)
            : (id) => unawaited(openGoal(context, id)),
        bottomPadding: wide ? 24 : 104,
      );
      body = wide
          ? _WideBody(list: list, goalId: _selected ?? _firstId(ofContour))
          : list;
    }

    final tabs = contours.length > 1
        ? _ContourTabs(
            contours: contours,
            goals: goals,
            selected: tab,
            wide: wide,
            onSelect: (id) => setState(() {
              _tab = id;
              _selected = null;
            }),
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (wide)
              _WideHeader(tabs: tabs, contourId: tab)
            else ...<Widget>[
              _Header(),
              if (tabs != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: tabs,
                ),
            ],
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: body),
                  if (!wide && tab != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _BottomBar(contourId: tab),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _firstId(List<GoalView> goals) {
    for (final goal in goals) {
      if (goal.inSlot) return goal.id;
    }
    return goals.isEmpty ? null : goals.first.id;
  }
}

/// Phone header: back 44 · «Цели» · ⋯ («Контуры…», «Достигнутые»).
class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Назад',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Цели',
              style: AppText.screenTight.copyWith(fontSize: 18),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            icon: const Icon(Icons.more_horiz, color: AppColors.muted),
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'contours') unawaited(openContours(context));
              if (value == 'achieved') openAchievedGoals(context, ref);
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'contours', child: Text('Контуры…')),
              PopupMenuItem<String>(
                value: 'achieved',
                child: Text('Достигнутые'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Desktop header: back · «Цели» · tabs · flexible · «Контуры» · «+ Цель».
class _WideHeader extends StatelessWidget {
  const _WideHeader({required this.tabs, required this.contourId});

  final Widget? tabs;
  final String? contourId;

  @override
  Widget build(BuildContext context) {
    final contourId = this.contourId;
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Назад',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          ),
          const SizedBox(width: 6),
          Text('Цели', style: AppText.screen.copyWith(fontSize: 22)),
          if (tabs != null) ...<Widget>[
            const SizedBox(width: 18),
            Flexible(child: tabs!),
          ],
          const Spacer(),
          SizedBox(
            height: Targets.minimum,
            child: OutlinedButton(
              onPressed: () => unawaited(openContours(context)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.inkSoft,
                side: const BorderSide(color: AppColors.lineStrong),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: AppText.action.copyWith(fontSize: 15),
              ),
              child: const Text('Контуры'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: Targets.minimum,
            child: FilledButton.icon(
              onPressed: contourId == null
                  ? null
                  : () => unawaited(openNewGoal(context, contourId: contourId)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: AppColors.onInk,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: AppText.action.copyWith(fontSize: 15),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Цель'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The contour segment: one tab per contour, «used/total» beside the name.
class _ContourTabs extends StatelessWidget {
  const _ContourTabs({
    required this.contours,
    required this.goals,
    required this.selected,
    required this.onSelect,
    required this.wide,
  });

  final List<Contour> contours;
  final List<GoalView> goals;
  final String? selected;
  final ValueChanged<String> onSelect;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    Widget tab(Contour contour) {
      final on = contour.id == selected;
      final used = goals
          .where((g) => g.contourId == contour.id && g.inSlot)
          .length;
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (on) ...<Widget>[
            const CrownIcon(size: 13, color: AppColors.crown),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              contour.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontSize: wide ? 14.5 : 14,
                fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                color: on ? AppColors.onInk : AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$used/${contour.slots}',
            style: AppText.goalCount.copyWith(
              fontSize: 12,
              color: on ? AppColors.crown : AppColors.muted,
            ),
          ),
        ],
      );
      return Semantics(
        selected: on,
        button: true,
        child: InkWell(
          onTap: () => onSelect(contour.id),
          borderRadius: BorderRadius.circular(wide ? 13 : 11),
          child: Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.crownChip : Colors.transparent,
              borderRadius: BorderRadius.circular(wide ? 13 : 11),
            ),
            child: content,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: wide ? AppColors.background : AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(wide ? 16 : 14),
      ),
      child: Row(
        mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          for (final contour in contours)
            if (wide)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: tab(contour),
              )
            else
              Expanded(child: tab(contour)),
        ],
      ),
    );
  }
}

/// The scrolling list of one contour: slots, free slots, bench, achieved.
class _GoalsList extends ConsumerWidget {
  const _GoalsList({
    required this.contour,
    required this.goals,
    required this.selected,
    required this.onOpen,
    required this.bottomPadding,
  });

  final Contour contour;
  final List<GoalView> goals;
  final String? selected;
  final ValueChanged<String> onOpen;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = goals.where((g) => g.inSlot).toList();
    final bench = goals.where((g) => g.onBench).toList();
    final full = slots.length >= contour.slots;
    final over = slots.length > contour.slots;
    final achieved =
        ref
            .watch(achievedGoalsProvider)
            .value
            ?.where((g) => g.contourId == contour.id)
            .length ??
        0;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(goalsProvider.notifier).refresh();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
        children: <Widget>[
          _SectionHeader(
            text: 'В СЛОТАХ · ${slots.length} из ${contour.slots}',
            alarm: over,
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Слотов стало меньше — уберите лишнюю цель на скамейку',
                style: AppText.chip.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          _ReorderableGoals(
            goals: slots,
            itemBuilder: (goal, index) => Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
              child: GoalSlotCard(
                goal: goal,
                index: index,
                selected: goal.id == selected,
                onTap: () => onOpen(goal.id),
              ),
            ),
          ),
          for (var i = slots.length; i < contour.slots; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: _FreeSlot(contour: contour, bench: bench),
            ),
          _SectionHeader(
            text: 'СКАМЕЙКА · ${bench.length}',
            leading: const BenchIcon(size: 14, color: AppColors.muted),
            top: 22,
          ),
          _ReorderableGoals(
            goals: bench,
            itemBuilder: (goal, index) => Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
              child: _BenchCard(
                goal: goal,
                index: index,
                full: full,
                selected: goal.id == selected,
                onTap: () => onOpen(goal.id),
              ),
            ),
          ),
          if (bench.isEmpty)
            Text(
              'Пусто. Сюда уходят цели, которые подождут.',
              style: AppText.hint.copyWith(fontSize: 13),
            ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => openAchievedGoals(context, ref),
            child: SizedBox(
              height: Targets.minimum,
              child: Row(
                children: <Widget>[
                  Text(
                    'Достигнутые · $achieved',
                    style: AppText.action.copyWith(
                      fontSize: 14,
                      color: AppColors.indigoLink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: AppColors.indigoLink,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section's caps label with a rule after it.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.text,
    this.leading,
    this.alarm = false,
    this.top = 18,
  });

  final String text;
  final Widget? leading;
  final bool alarm;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(0, top, 0, 8),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 8)],
          Text(
            text,
            style: AppText.sectionLabel.copyWith(
              color: alarm ? AppColors.goalExpired : null,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: AppColors.line, height: 1)),
        ],
      ),
    );
  }
}

/// Goals reordered by a long press, within their own section.
class _ReorderableGoals extends ConsumerWidget {
  const _ReorderableGoals({required this.goals, required this.itemBuilder});

  final List<GoalView> goals;
  final Widget Function(GoalView goal, int index) itemBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (goals.isEmpty) return const SizedBox.shrink();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: goals.length,
      proxyDecorator: (child, _, _) => Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(Radii.goal),
        child: child,
      ),
      onReorder: (from, to) {
        final moved = goals[from];
        final without = <GoalView>[...goals]..removeAt(from);
        final index = to > from ? to - 1 : to;
        unawaited(
          ref
              .read(goalsProvider.notifier)
              .reorder(moved.id, without, index)
              .catchError((Object error) {
                if (!context.mounted) return moved;
                _snack(
                  context,
                  'Не удалось переставить цель. ${describeApiError(error)}',
                );
                return moved;
              }),
        );
      },
      itemBuilder: (context, index) {
        final goal = goals[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey<String>(goal.id),
          index: index,
          child: itemBuilder(goal, index),
        );
      },
    );
  }
}

/// A goal in a slot: the block's look as a card of its own (Goals.html).
class GoalSlotCard extends ConsumerWidget {
  const GoalSlotCard({
    required this.goal,
    required this.onTap,
    this.index = 0,
    this.selected = false,
    super.key,
  });

  final GoalView goal;
  final VoidCallback onTap;
  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = goal.nextStep;
    final left = windowLeftLabel(goal.windowEndsAt);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        gradient: goalGradient,
        borderRadius: BorderRadius.circular(Radii.goal),
        boxShadow: goalShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.goal),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const _DotsHandle(),
                    const SizedBox(width: 6),
                    const CrownIcon(size: 16, color: AppColors.crown),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        goal.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.goalTitle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${goal.progress.done}/${goal.progress.total}',
                      style: AppText.goalCount,
                    ),
                    _GoalMenu(goal: goal),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(42, 0, 10, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (goal.windowExpired)
                        Text(
                          windowExpiredLabel(goal.windowEndsAt),
                          style: AppText.goalWhy.copyWith(
                            color: AppColors.goalExpired,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                goal.why ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.goalWhy,
                              ),
                            ),
                            if (left != null) ...<Widget>[
                              const SizedBox(width: 10),
                              Text(
                                left,
                                style: AppText.goalWhy.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      if (goal.tasks.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        GoalProgressSegments(goal: goal),
                      ],
                      if (!goal.windowExpired) ...<Widget>[
                        const SizedBox(height: 9),
                        Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              const TextSpan(
                                text: 'ШАГ  ',
                                style: AppText.goalLabel,
                              ),
                              TextSpan(
                                text: step?.title ?? 'Обсудить, что дальше',
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: AppColors.voiceBright,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (goal.windowExpired)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 12, 10, 2),
                    child: ExpiredGoalActions(goal: goal),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!selected) return card;
    // The selected goal (desktop): gold ring through a 3 px gap.
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.goal + 5),
        border: Border.all(color: AppColors.crown, width: 2),
      ),
      child: card,
    );
  }
}

/// Six dots, the visible drag handle of a slot card.
class _DotsHandle extends StatelessWidget {
  const _DotsHandle();

  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
      width: 3.2,
      height: 3.2,
      margin: const EdgeInsets.all(1.4),
      decoration: const BoxDecoration(
        color: AppColors.goalDim,
        shape: BoxShape.circle,
      ),
    );
    return SizedBox(
      width: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < 3; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[dot(), dot()],
            ),
        ],
      ),
    );
  }
}

/// «⋯» on a slot card: «Продлить окно», «На скамейку», «Достигнута».
class _GoalMenu extends ConsumerWidget {
  const _GoalMenu({required this.goal});

  final GoalView goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: Targets.minimum,
      height: Targets.minimum,
      child: PopupMenuButton<String>(
        tooltip: 'Действия',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz, color: AppColors.voiceMuted),
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (value) {
          switch (value) {
            case 'extend':
              unawaited(extendGoalWithFeedback(context, ref, goal));
            case 'bench':
              unawaited(benchGoalWithUndo(context, ref, goal));
            case 'achieve':
              unawaited(achieveGoalWithUndo(context, ref, goal));
          }
        },
        itemBuilder: (_) => const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'extend', child: Text('Продлить окно')),
          PopupMenuItem<String>(value: 'bench', child: Text('На скамейку')),
          PopupMenuItem<String>(value: 'achieve', child: Text('Достигнута')),
        ],
      ),
    );
  }
}

/// The three buttons of an expired window: «Оставить» · «На скамейку» ·
/// «Достигнута» (88 · flexible · 112 on a phone).
class ExpiredGoalActions extends ConsumerWidget {
  const ExpiredGoalActions({required this.goal, this.wide = false, super.key});

  final GoalView goal;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.row),
    );
    const label = TextStyle(fontFamily: AppFonts.text, fontSize: 14);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 88,
          height: Targets.minimum,
          child: FilledButton(
            onPressed: () =>
                unawaited(extendGoalWithFeedback(context, ref, goal)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.onInk,
              foregroundColor: AppColors.voiceBackground,
              padding: EdgeInsets.zero,
              shape: shape,
              textStyle: label.copyWith(fontWeight: FontWeight.w700),
            ),
            child: const Text('Оставить'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: Targets.minimum,
            child: OutlinedButton(
              onPressed: () => unawaited(benchGoalWithUndo(context, ref, goal)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.voiceBright,
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: AppColors.goalWellLine),
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: label.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (wide) ...<Widget>[
                    const BenchIcon(size: 16, color: AppColors.voiceBright),
                    const SizedBox(width: 6),
                  ],
                  const Flexible(
                    child: Text(
                      'На скамейку',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          height: Targets.minimum,
          child: OutlinedButton.icon(
            onPressed: () => unawaited(achieveGoalWithUndo(context, ref, goal)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.doneOnDark,
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: Color(0x807FD1A8)),
              padding: EdgeInsets.zero,
              shape: shape,
              textStyle: label.copyWith(fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Достигнута', maxLines: 1, softWrap: false),
          ),
        ),
      ],
    );
  }
}

/// Progress as segments: one per task (up to 12; more is one solid bar).
class GoalProgressSegments extends StatelessWidget {
  const GoalProgressSegments({required this.goal, super.key});

  final GoalView goal;

  @override
  Widget build(BuildContext context) {
    final total = goal.progress.total;
    final done = goal.progress.done;
    if (total == 0) return const SizedBox.shrink();
    Widget bar(Color color, {int flex = 1}) => Expanded(
      flex: flex,
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    if (total > 12) {
      return Row(
        children: <Widget>[
          if (done > 0) bar(AppColors.doneOnDark, flex: done),
          if (total - done > 0) bar(AppColors.goalWellLine, flex: total - done),
        ],
      );
    }
    return Row(
      children: <Widget>[
        for (var i = 0; i < total; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 3),
          bar(i < done ? AppColors.doneOnDark : AppColors.goalWellLine),
        ],
      ],
    );
  }
}

/// An empty slot: dashed outline, «Свободный слот» · «+ Поставить».
class _FreeSlot extends ConsumerWidget {
  const _FreeSlot({required this.contour, required this.bench});

  final Contour contour;
  final List<GoalView> bench;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomPaint(
      painter: const DashedRRectPainter(radius: Radii.goal),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.goal),
        onTap: () => unawaited(_fill(context, ref)),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Свободный слот',
                    style: AppText.action.copyWith(
                      fontSize: 15,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                Text(
                  '+ Поставить',
                  style: AppText.action.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.indigoLink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A sheet: the bench to choose from, or a new goal.
  Future<void> _fill(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('ПОСТАВИТЬ В СЛОТ', style: AppText.sectionLabel),
            ),
            for (final goal in bench)
              ListTile(
                minTileHeight: 56,
                leading: const CrownChip(bright: false),
                title: Text(
                  goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.projectName.copyWith(fontSize: 15.5),
                ),
                onTap: () => Navigator.of(context).pop(goal.id),
              ),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.add, color: AppColors.indigoLink),
              title: Text(
                'Новая цель',
                style: AppText.action.copyWith(color: AppColors.indigoLink),
              ),
              onTap: () => Navigator.of(context).pop(_newGoal),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _newGoal) {
      await openNewGoal(context, contourId: contour.id);
      return;
    }
    final goal = bench.where((g) => g.id == choice).firstOrNull;
    if (goal != null) await slotGoalWithFeedback(context, ref, goal);
  }

  static const String _newGoal = '__new__';
}

/// A benched goal: a light card with «В слот» (or «Слоты заняты»).
class _BenchCard extends ConsumerWidget {
  const _BenchCard({
    required this.goal,
    required this.index,
    required this.full,
    required this.selected,
    required this.onTap,
  });

  final GoalView goal;
  final int index;
  final bool full;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final why = (goal.why ?? '').trim();
    final subtitle = goal.tasks.isEmpty
        ? 'задач нет'
        : <String>[
            '${goal.progress.done}/${goal.progress.total}',
            if (why.isNotEmpty) why,
          ].join(' · ');
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? AppColors.crown : AppColors.line,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(Radii.stub),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.stub),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: <Widget>[
                const CrownChip(bright: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        goal.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                          height: 1.3,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.chip.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: Targets.minimum,
                  child: Center(
                    child: SizedBox(
                      height: 36,
                      child: full
                          ? OutlinedButton(
                              onPressed: () => _snack(context, slotsFullText),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.muted,
                                side: const BorderSide(
                                  color: AppColors.lineStrong,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: AppText.action.copyWith(
                                  fontSize: 13,
                                ),
                              ),
                              child: const Text('Слоты заняты'),
                            )
                          : FilledButton(
                              onPressed: () => unawaited(
                                slotGoalWithFeedback(context, ref, goal),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.ink,
                                foregroundColor: AppColors.onInk,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: AppText.action.copyWith(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('В слот'),
                            ),
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

/// The pinned bar: «+ Цель» and the microphone (dictates the new goal's
/// title, then opens it).
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.contourId});

  final String contourId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: <double>[0, 0.22],
          colors: <Color>[Color(0x00F3F3F7), AppColors.background],
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: () =>
                    unawaited(openNewGoal(context, contourId: contourId)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: AppColors.onInk,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.stub),
                  ),
                  textStyle: AppText.action.copyWith(fontSize: 16),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Цель'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MicrophoneSquare(
            tooltip: 'Продиктовать цель',
            onPressed: () => unawaited(dictateNewGoal(context, contourId)),
          ),
        ],
      ),
    );
  }
}

/// Desktop: the list (440) and the selected goal's panel.
class _WideBody extends StatelessWidget {
  const _WideBody({required this.list, required this.goalId});

  final Widget list;
  final String? goalId;

  @override
  Widget build(BuildContext context) {
    final goalId = this.goalId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(width: 440, child: list),
          const SizedBox(width: 28),
          Expanded(
            child: goalId == null
                ? const Center(
                    child: Text(
                      'Выберите цель слева или заведите новую.',
                      style: AppText.hint,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: ColoredBox(
                      color: AppColors.voiceBackground,
                      child: GoalDetail(
                        key: ValueKey<String>(goalId),
                        goalId: goalId,
                        embedded: true,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.loading,
    required this.text,
    required this.onRetry,
  });

  final bool loading;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, textAlign: TextAlign.center, style: AppText.hint),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

// -- Shared looks -------------------------------------------------------------

/// The goal block's gradient (`goalStart -> goalEnd`).
const LinearGradient goalGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[AppColors.goalStart, AppColors.goalEnd],
);

/// The goal block's shadow.
const List<BoxShadow> goalShadow = <BoxShadow>[
  BoxShadow(color: Color(0x2E14183C), blurRadius: 18, offset: Offset(0, 6)),
];

/// A 1.5 px dashed rounded rectangle in `lineStrong` (an empty slot).
class DashedRRectPainter extends CustomPainter {
  const DashedRRectPainter({
    required this.radius,
    this.color = AppColors.lineStrong,
  });

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.radius != radius || old.color != color;
}

// -- Actions with their feedback ------------------------------------------------

/// The spec's text for a refused «В слот» (and for 409 `slots_full`).
const String slotsFullText =
    'Сначала освободите слот: «В слот» встанет, когда одна из целей уйдёт '
    'на скамейку или будет достигнута.';

/// Whether [error] is the server's 409 `slots_full`.
bool isSlotsFull(Object error) {
  if (error is! ApiException || error.statusCode != 409) return false;
  final body = error.body;
  return body is Map && body['error'] == 'slots_full';
}

void _snack(
  BuildContext context,
  String text, {
  String? action,
  Future<void> Function()? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  _showOn(messenger, text, action: action, onAction: onAction);
}

void _showOn(
  ScaffoldMessengerState messenger,
  String text, {
  String? action,
  Future<void> Function()? onAction,
}) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        persist: false,
        action: action == null || onAction == null
            ? null
            : SnackBarAction(
                label: action,
                onPressed: () => unawaited(() async {
                  try {
                    await onAction();
                  } catch (error) {
                    if (!messenger.mounted) return;
                    _showOn(
                      messenger,
                      isSlotsFull(error)
                          ? slotsFullText
                          : 'Не удалось вернуть. ${describeApiError(error)}',
                    );
                  }
                }()),
              ),
      ),
    );
}

Future<GoalView?> _run(
  BuildContext context,
  Future<GoalView> Function() action, {
  required String failure,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    return await action();
  } catch (error) {
    if (messenger != null && messenger.mounted) {
      _showOn(
        messenger,
        isSlotsFull(error)
            ? slotsFullText
            : '$failure ${describeApiError(error)}',
      );
    }
    return null;
  }
}

/// «В слот»: a 409 `slots_full` says the spec's sentence.
Future<GoalView?> slotGoalWithFeedback(
  BuildContext context,
  WidgetRef ref,
  GoalView goal,
) => _run(
  context,
  () => ref.read(goalsProvider.notifier).slot(goal.id),
  failure: 'Не удалось поставить цель в слот.',
);

/// «Оставить» / «Продлить окно»: toast «Продлено до 1.12».
Future<GoalView?> extendGoalWithFeedback(
  BuildContext context,
  WidgetRef ref,
  GoalView goal,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await _run(
    context,
    () => ref.read(goalsProvider.notifier).extend(goal.id),
    failure: 'Не удалось продлить окно.',
  );
  if (result != null && messenger != null && messenger.mounted) {
    _showOn(messenger, 'Продлено до ${shortDate(result.windowEndsAt)}');
  }
  return result;
}

/// «На скамейку», no dialog: «Цель на скамейке · Вернуть».
Future<GoalView?> benchGoalWithUndo(
  BuildContext context,
  WidgetRef ref,
  GoalView goal,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final goals = ref.read(goalsProvider.notifier);
  final result = await _run(
    context,
    () => goals.bench(goal.id),
    failure: 'Не удалось убрать цель на скамейку.',
  );
  if (result != null && messenger != null && messenger.mounted) {
    _showOn(
      messenger,
      'Цель на скамейке',
      action: 'Вернуть',
      onAction: () => goals.slot(goal.id),
    );
  }
  return result;
}

/// «Достигнута», no dialog: «Цель достигнута · Вернуть» (back where it was:
/// reopened, and into its slot again if it was in one).
Future<GoalView?> achieveGoalWithUndo(
  BuildContext context,
  WidgetRef ref,
  GoalView goal,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final goals = ref.read(goalsProvider.notifier);
  final wasInSlot = goal.inSlot;
  final result = await _run(
    context,
    () => goals.achieve(goal.id),
    failure: 'Не удалось отметить цель достигнутой.',
  );
  if (result != null && messenger != null && messenger.mounted) {
    _showOn(
      messenger,
      'Цель достигнута',
      action: 'Вернуть',
      onAction: () async {
        await goals.reopen(goal.id);
        if (wasInSlot) await goals.slot(goal.id);
      },
    );
  }
  return result;
}

/// «Достигнутые»: the history mode, whose «Достигнутые цели» lists them.
void openAchievedGoals(BuildContext context, WidgetRef ref) {
  final shell = ref.read(shellModeProvider.notifier);
  Navigator.of(context).popUntil((route) => route.isFirst);
  unawaited(shell.select(AppMode.history));
}

/// The microphone: dictation, then a new goal with the words as its title.
Future<void> dictateNewGoal(BuildContext context, String contourId) async {
  final result = await AppRoutes.openDictation(
    context,
    destination: const FieldDestination('название цели'),
  );
  final title = switch (result) {
    FieldWords(:final text) => text,
    FieldTaskText(:final title) => title,
    null => '',
  }.trim();
  if (title.isEmpty || !context.mounted) return;
  await openNewGoal(context, contourId: contourId, title: title);
}
