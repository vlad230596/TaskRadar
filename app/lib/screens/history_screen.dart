import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../domain/goals.dart' show CrownLevel, shortDate, tasksWord;
import '../domain/today_view.dart'
    show addDays, localDayOfInstant, weekdayDate;
import '../domain/reminders.dart' show calendarDateForApi;
import '../models/goal.dart';
import '../models/task_status.dart';
import '../models/today_history.dart';
import '../navigation/app_routes.dart';
import '../navigation/goal_routes.dart';
import '../navigation/review_routes.dart';
import '../providers/goal_providers.dart';
import '../providers/outbox_providers.dart';
import '../providers/shell_providers.dart';
import '../providers/today_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/glance.dart';
import '../widgets/goals/crown.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/history_charts.dart' show HistoryHeading;
import '../widgets/mode_navigation.dart';
import '../widgets/mode_title.dart';
import '../widgets/outbox_history.dart';
import '../widgets/today/next_sheet.dart';
import '../widgets/today/today_icons.dart';
import 'review_screen.dart';
import 'shell_screen.dart';

/// «История» (`design/today-history-spec.md` §9): what was done and where the
/// weeks went.
///
/// Two questions (`design/history-review-decisions.md`): «Куда ушла неделя?»
/// -- «Недели», the closings week by week with the review records -- and
/// «Что следует из сделанного?» -- «Сделано», the closings newest first with
/// «Следом…» on each. The review card sits on top of «Сделано», and only when
/// the review is due. The old «Висит дольше всего» and the day chart are gone:
/// the tail, «Позже» and the review answer «что гниёт» now.
///
/// On a wide window both lists stand side by side with no tabs.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // «Офлайн»: what this device wrote with no network. History too -- of
    // this device's writes -- switched in the header.
    if (ref.watch(historyShowsOutboxProvider)) {
      return RefreshIndicator(
        onRefresh: () => ref.read(outboxProvider.notifier).flush(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: const OutboxHistoryView(),
          ),
        ),
      );
    }

    if (isWideLayout(context)) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(40, 0, 40, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 600, child: DoneFeedView(wide: true)),
            SizedBox(width: 28),
            Expanded(child: WeeksView(wide: true)),
          ],
        ),
      );
    }

    final tab = ref.watch(historyTabProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(Insets.gutter, 4, Insets.gutter, 0),
          child: HistoryTabs(),
        ),
        Expanded(
          child: switch (tab) {
            HistoryTab.done => const DoneFeedView(),
            HistoryTab.weeks => const WeeksView(),
          },
        ),
      ],
    );
  }
}

/// The mode's header: «История» and «Офлайн · N». The period pill of the old
/// screen is gone -- the tabs are the period now.
class HistoryHeader extends ConsumerWidget {
  const HistoryHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 18, Insets.gutter, 12),
      child: LayoutBuilder(
        builder: (context, box) {
          final pill = AppText.action.copyWith(fontSize: 14);
          final needed =
              10 +
              17 +
              6 +
              measureTextWidth(context, 'Офлайн · 99', pill) +
              12 +
              8 +
              48;
          final compact = box.maxWidth - needed < 70;
          return Row(
            children: <Widget>[
              Expanded(child: ModeTitle(AppMode.history.title)),
              _OfflinePill(compact: compact),
              const SizedBox(width: 8),
              const ShellOverflowButton(),
            ],
          );
        },
      ),
    );
  }
}

/// «Офлайн» in the header: switches the mode between its lists and the
/// outbox, with the outbox's count on it.
class _OfflinePill extends ConsumerWidget {
  const _OfflinePill({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(historyShowsOutboxProvider);
    final counts = ref.watch(outboxCountsProvider);
    final total = counts.waiting + counts.decisions;
    final ink = on
        ? AppColors.onInk
        : counts.decisions > 0
        ? AppColors.waitingInk
        : AppColors.inkSoft;

    return Semantics(
      button: true,
      selected: on,
      label: compact ? 'Офлайн' : null,
      child: Material(
        color: on
            ? AppColors.ink
            : counts.decisions > 0
            ? AppColors.waitingChip
            : AppColors.card,
        shape: StadiumBorder(
          side: BorderSide(color: on ? AppColors.ink : AppColors.lineStrong),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => ref.read(historyShowsOutboxProvider.notifier).show(!on),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: EdgeInsets.fromLTRB(10, 4, compact ? 10 : 12, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  total == 0
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  size: 17,
                  color: ink,
                ),
                if (!compact || total > 0) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    compact
                        ? '$total'
                        : total == 0
                        ? 'Офлайн'
                        : 'Офлайн · $total',
                    maxLines: 1,
                    softWrap: false,
                    style: AppText.action.copyWith(fontSize: 14, color: ink),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Сделано · Недели»: the segment of the project screen («Задачи | Идеи»).
class HistoryTabs extends ConsumerWidget {
  const HistoryTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(historyTabProvider);
    Widget segment(HistoryTab value, String label) {
      final on = value == tab;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? AppColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () => ref.read(historyTabProvider.notifier).select(value),
              child: SizedBox(
                height: 38,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 14,
                      color: on ? AppColors.onInk : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          segment(HistoryTab.done, 'Сделано'),
          const SizedBox(width: 2),
          segment(HistoryTab.weeks, 'Недели'),
        ],
      ),
    );
  }
}

// --- pure helpers -------------------------------------------------------------

/// A day heading of «Сделано»: «Сегодня», «Вчера», «вт 24.11», and
/// «вт 24.11.2025» for a day of another year.
@visibleForTesting
String doneDayLabel(String day, String today) {
  if (day == today) return 'Сегодня';
  if (day == addDays(today, -1)) return 'Вчера';
  final label = weekdayDate(day);
  return day.substring(0, 4) == today.substring(0, 4)
      ? label
      : '$label.${day.substring(0, 4)}';
}

/// The closings grouped by local day, in the feed's order (newest first).
@visibleForTesting
List<({String day, List<DoneItem> items})> groupDoneByDay(
  List<DoneItem> items,
) {
  final groups = <({String day, List<DoneItem> items})>[];
  for (final item in items) {
    final day = localDayOfInstant(item.doneAt) ?? '';
    if (groups.isEmpty || groups.last.day != day) {
      groups.add((day: day, items: <DoneItem>[item]));
    } else {
      groups.last.items.add(item);
    }
  }
  return groups;
}

/// «14:32» -- the local time of an instant.
@visibleForTesting
String clockOfInstant(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  return '${at.hour}:${at.minute.toString().padLeft(2, '0')}';
}

const List<String> _monthsGenitive = <String>[
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// «+ итоги ноября» when the review due now is the first of a new month --
/// the month before [now] -- or null. The first review ever is not monthly
/// (contract: nothing to compare a month with).
@visibleForTesting
String? monthlyCaption(String? lastAt, DateTime now) {
  final last = lastAt == null ? null : DateTime.tryParse(lastAt)?.toLocal();
  if (last == null) return null;
  final local = now.toLocal();
  if (last.year == local.year && last.month == local.month) return null;
  final previous = DateTime(local.year, local.month - 1);
  return '+ итоги ${_monthsGenitive[previous.month - 1]}';
}

/// «пора», or «пропущен с пн 23.11» once a day has passed since it became
/// due. Second value: true for «пропущен».
@visibleForTesting
(String, bool) reviewDueLabel(ReviewStatus status, DateTime now) {
  final next = status.nextAt == null
      ? null
      : DateTime.tryParse(status.nextAt!)?.toLocal();
  if (next == null || now.difference(next) <= const Duration(days: 1)) {
    return ('пора', false);
  }
  return ('пропущен с ${weekdayDate(calendarDateForApi(next))}', true);
}

/// The achieved goals from [from] on by `achievedAt`, newest first.
@visibleForTesting
List<GoalView> achievedSince(List<GoalView> goals, DateTime? from) {
  final rows = <GoalView>[
    for (final goal in goals)
      if (goal.achievedAt != null &&
          (from == null ||
              !(DateTime.tryParse(goal.achievedAt!)?.toLocal().isBefore(from) ??
                  true)))
        goal,
  ]..sort((a, b) => (b.achievedAt ?? '').compareTo(a.achievedAt ?? ''));
  return rows;
}

/// «30.11 – 6.12» for the week starting [start].
@visibleForTesting
String weekRange(String start) {
  String short(String day) {
    final p = day.split('-');
    return '${int.parse(p[2])}.${p[1]}';
  }

  return '${short(start)} – ${short(addDays(start, 6))}';
}

// --- «Сделано» ----------------------------------------------------------------

/// The «Сделано» feed: the review card when due, the closings by day.
class DoneFeedView extends ConsumerStatefulWidget {
  const DoneFeedView({this.wide = false, super.key});

  final bool wide;

  @override
  ConsumerState<DoneFeedView> createState() => _DoneFeedViewState();
}

class _DoneFeedViewState extends ConsumerState<DoneFeedView> {
  /// Follow-ups made from a row in this visit of the screen: a memory of the
  /// screen, not data (spec §9.3).
  final Map<String, FollowUp> _followUps = <String, FollowUp>{};

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(doneFeedStateProvider);
    final value = feed.value;
    final today = ref.watch(todayKeyProvider);
    final offline = ref.watch(appOfflineProvider) || (value?.fromCache ?? false);
    final due = ref.watch(reviewDueProvider);

    final children = <Widget>[];
    if (offline && value != null) children.add(const _OfflineNote());
    if (due) children.add(const ReviewCard());

    if (value == null) {
      children.add(
        feed.hasError
            ? _Message(
                icon: Icons.cloud_off,
                title: 'Не удалось загрузить',
                body: describeApiError(feed.error!),
                action: TextButton.icon(
                  onPressed: () =>
                      ref.read(doneFeedStateProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Повторить'),
                ),
              )
            : const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
      );
    } else if (value.items.isEmpty) {
      children.add(const _DoneEmpty());
    } else {
      final groups = groupDoneByDay(value.items);
      var seen = 0;
      for (final group in groups) {
        seen += group.items.length;
        final nearEnd = seen >= value.items.length - 6;
        children.add(
          _DayGroup(
            label: doneDayLabel(group.day, today),
            items: group.items,
            followUps: _followUps,
            wide: widget.wide,
            onFollowUp: (taskId, made) =>
                setState(() => _followUps[taskId] = made),
            onShown: nearEnd && value.hasMore
                ? () => ref.read(doneFeedStateProvider.notifier).loadMore()
                : null,
          ),
        );
      }
      if (value.loadingMore) {
        children.add(
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        );
      } else if (!value.hasMore) {
        children.add(
          SizedBox(
            height: 44,
            child: Center(
              child: Text(
                'Раньше закрытого нет',
                style: AppText.hint.copyWith(fontSize: 13),
              ),
            ),
          ),
        );
      } else {
        children.add(
          TextButton(
            onPressed: () => ref.read(doneFeedStateProvider.notifier).loadMore(),
            child: const Text('Показать ещё'),
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        unawaited(ref.read(reviewStatusStateProvider.notifier).refresh());
        await ref.read(doneFeedStateProvider.notifier).refresh();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 24, top: widget.wide ? 0 : 0),
        children: children,
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: SizedBox(
        height: 40,
        child: Row(
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Без сети — показано, что было загружено',
                style: AppText.hint,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneEmpty extends StatelessWidget {
  const _DoneEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.doneChip,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 40, color: AppColors.done),
          ),
          const SizedBox(height: 16),
          Text(
            'Пока ничего не закрыто',
            textAlign: TextAlign.center,
            style: AppText.projectName.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            'Закрытые задачи будут здесь — с временем и проектом, чтобы '
            'видно было, что из них следует.',
            textAlign: TextAlign.center,
            style: AppText.hint.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _DayGroup extends StatefulWidget {
  const _DayGroup({
    required this.label,
    required this.items,
    required this.followUps,
    required this.onFollowUp,
    required this.wide,
    this.onShown,
  });

  final String label;
  final List<DoneItem> items;
  final Map<String, FollowUp> followUps;
  final void Function(String taskId, FollowUp made) onFollowUp;
  final bool wide;

  /// Called after the group is first laid out: the next page, when the end
  /// of the loaded list is near.
  final VoidCallback? onShown;

  @override
  State<_DayGroup> createState() => _DayGroupState();
}

class _DayGroupState extends State<_DayGroup> {
  @override
  void initState() {
    super.initState();
    final shown = widget.onShown;
    if (shown != null) WidgetsBinding.instance.addPostFrameCallback((_) => shown());
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: SizedBox(
            height: 12 + 12,
            child: Row(
              children: <Widget>[
                Text(
                  '${widget.label.toUpperCase()} · ${items.length}',
                  style: AppText.sectionLabel,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: ColoredBox(
                    color: AppColors.line,
                    child: SizedBox(height: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: <Widget>[
              for (var i = 0; i < items.length; i++) ...<Widget>[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 34),
                    child: ColoredBox(
                      color: AppColors.lineFaint,
                      child: SizedBox(height: 1, width: double.infinity),
                    ),
                  ),
                DoneRow(
                  item: items[i],
                  followUp: widget.followUps[items[i].task.id],
                  wide: widget.wide,
                  onFollowUp: (made) =>
                      widget.onFollowUp(items[i].task.id, made),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One closing: check, title, project · time, «Вернуть», «Следом».
class DoneRow extends ConsumerWidget {
  const DoneRow({
    required this.item,
    required this.onFollowUp,
    this.followUp,
    this.wide = false,
    super.key,
  });

  final DoneItem item;
  final FollowUp? followUp;
  final ValueChanged<FollowUp> onFollowUp;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = item.task.task;
    final crown = watchCrown(ref, task.id, task.goals);
    final offline = ref.watch(appOfflineProvider);
    final made = followUp;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: wide ? 56 : 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const SizedBox(
            width: 22,
            child: Icon(Icons.check, size: 18, color: AppColors.done),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => AppRoutes.openTask(
                context,
                projectId: task.projectId,
                taskId: task.id,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        height: 1.3,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        if (crown != CrownLevel.none) ...<Widget>[
                          CrownChip(
                            bright: crown == CrownLevel.bright,
                            size: 18,
                            iconSize: 11,
                            radius: 6,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            '${item.task.projectName} · '
                            '${clockOfInstant(item.doneAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        ),
                      ],
                    ),
                    if (made != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          const TodayIcon(
                            TodayGlyph.next,
                            size: 12,
                            color: AppColors.indigoLink,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '${made.title} · ${weekdayDate(made.date)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                color: AppColors.indigoLink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Tooltip(
            message: offline ? 'Вернуть можно с сетью' : 'Вернуть',
            child: InkResponse(
              onTap: () => _reopen(context, ref),
              radius: 22,
              child: SizedBox(
                width: Targets.minimum,
                height: Targets.minimum,
                child: Center(
                  child: TodayIcon(
                    TodayGlyph.reopen,
                    size: 20,
                    color: offline ? AppColors.lineStrong : AppColors.muted,
                    semanticLabel: 'Вернуть',
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SizedBox(
              height: Targets.minimum,
              child: Center(
                child: SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final created = await showNextSheet(
                        context,
                        projectId: task.projectId,
                        projectName: item.task.projectName,
                        afterTitle: task.title,
                      );
                      if (created != null) onFollowUp(created);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: AppColors.lineStrong),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    icon: const TodayIcon(
                      TodayGlyph.next,
                      size: 15,
                      color: AppColors.ink,
                    ),
                    label: const Text('Следом'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text, {SnackBarAction? action}) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(text), persist: false, action: action),
        );
    }

    if (ref.read(appOfflineProvider)) {
      say('Вернуть можно с сетью');
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final task = item.task.task;
    try {
      final reopened = await reopenTask(container, task);
      say(
        'Вернули в «${item.task.projectName}»',
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => unawaited(() async {
            try {
              await setDayTaskStatus(container, reopened, TaskStatus.done);
              container.read(doneFeedStateProvider.notifier).restore(item);
              unawaited(container.read(doneFeedStateProvider.notifier).refresh());
            } catch (error) {
              if (messenger.mounted) {
                say('Не удалось отменить. ${describeApiError(error)}');
              }
            }
          }()),
        ),
      );
    } on NetworkException {
      say('Вернуть можно с сетью');
    } catch (error) {
      say('Не удалось вернуть. ${describeApiError(error)}');
    }
  }
}

// --- the review card ------------------------------------------------------------

/// «Пересмотр недели» on the goal gradient (§9.2): shown only while due.
class ReviewCard extends ConsumerWidget {
  const ReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(reviewStatusStateProvider).value;
    if (status == null || !status.due) return const SizedBox.shrink();
    final now = ref.watch(appClockProvider)();
    final (label, missed) = reviewDueLabel(status, now);
    final offline = ref.watch(appOfflineProvider);

    final since = status.lastAt == null
        ? now.subtract(const Duration(days: 7))
        : DateTime.tryParse(status.lastAt!)?.toLocal() ??
              now.subtract(const Duration(days: 7));
    final items = ref.watch(doneFeedStateProvider).value?.items ?? const [];
    final closed = items.where((item) {
      final at = DateTime.tryParse(item.doneAt);
      return at != null && !at.isBefore(since);
    }).length;
    final inWindows = ref
        .watch(goalListProvider)
        .where((goal) => goal.inSlot)
        .length;
    final monthly = monthlyCaption(status.lastAt, now);

    return Container(
      key: const ValueKey<String>('review-card'),
      margin: const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.goalStart, AppColors.goalEnd],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2E14183C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const TodayIcon(
                TodayGlyph.review,
                size: 18,
                color: Color(0xFFFFFFFF),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Пересмотр недели',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: missed ? AppColors.goalExpired : AppColors.voiceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'С ${weekdayDate(calendarDateForApi(since))} · закрыто $closed · '
            'целей в окнах $inWindows',
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
              height: 1.35,
              color: AppColors.voiceMuted,
            ),
          ),
          if (monthly != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              monthly,
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.doneOnDark,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              SizedBox(
                width: 160,
                height: 52,
                child: FilledButton(
                  onPressed: offline ? null : () => openReview(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.voiceBackground,
                    disabledBackgroundColor: AppColors.goalWellLine,
                    disabledForegroundColor: AppColors.voiceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  child: const Text('Начать'),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  offline ? 'нужна сеть' : '≈ 5 мин',
                  style: const TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppColors.voiceMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- «Недели» -----------------------------------------------------------------

/// The weeks: 12 bars, the achieved goals, the records week by week.
class WeeksView extends ConsumerStatefulWidget {
  const WeeksView({this.wide = false, super.key});

  final bool wide;

  @override
  ConsumerState<WeeksView> createState() => _WeeksViewState();
}

class _WeeksViewState extends ConsumerState<WeeksView> {
  final Map<String, GlobalKey> _records = <String, GlobalKey>{};

  void _scrollTo(String start) {
    final context = _records[start]?.currentContext;
    if (context == null) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weeks = ref.watch(historyWeeksProvider);
    final value = weeks.value;
    final today = ref.watch(todayKeyProvider);

    final Widget body;
    if (value == null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          if (weeks.hasError)
            _Message(
              icon: Icons.cloud_off,
              title: 'Не удалось загрузить недели',
              body: describeApiError(weeks.error!),
              action: TextButton.icon(
                onPressed: () => ref.invalidate(historyWeeksProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Повторить'),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      );
    } else {
      final oldest = value.isEmpty ? null : value.last.start;
      final from = oldest == null ? null : _localDate(oldest);
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          WeeksSummary(
            weeks: value,
            today: today,
            wide: widget.wide,
            onTapWeek: _scrollTo,
          ),
          _AchievedGoalsSection(from: from),
          if (value.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: HistoryHeading(label: 'По неделям'),
            ),
          for (final week in value)
            Padding(
              key: _records.putIfAbsent(week.start, GlobalKey.new),
              padding: const EdgeInsets.fromLTRB(
                Insets.gutter,
                0,
                Insets.gutter,
                10,
              ),
              child: week.review == null
                  ? _WeekPlain(week: week)
                  : _WeekRecord(week: week),
            ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(historyWeeksProvider);
        try {
          await ref.read(historyWeeksProvider.future);
        } catch (_) {}
      },
      child: body,
    );
  }
}

DateTime _localDate(String day) {
  final p = day.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// The Monday of [today]'s week.
String _mondayOf(String today) {
  final weekday = _localDate(today).weekday;
  return addDays(today, 1 - weekday);
}

/// The summary card: this week's number, the average, 12 bars.
class WeeksSummary extends StatelessWidget {
  const WeeksSummary({
    required this.weeks,
    required this.today,
    required this.onTapWeek,
    this.wide = false,
    super.key,
  });

  /// Freshest first, as the server sends them.
  final List<HistoryWeek> weeks;
  final String today;
  final ValueChanged<String> onTapWeek;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final thisMonday = _mondayOf(today);
    final current = weeks.isNotEmpty && weeks.first.start == thisMonday
        ? weeks.first
        : null;
    final past = <HistoryWeek>[
      for (final week in weeks)
        if (week != current) week,
    ];
    final average = past.isEmpty
        ? null
        : (past.fold<int>(0, (sum, w) => sum + w.closed) / past.length)
              .round();
    final bars = weeks.reversed.toList(growable: false);
    final maxClosed = bars.fold<int>(0, (m, w) => math.max(m, w.closed));

    return Container(
      margin: const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${current?.closed ?? 0}',
                style: AppText.number.copyWith(
                  fontSize: 44,
                  height: 1,
                  color: AppColors.done,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'на этой неделе',
                style: AppText.caption.copyWith(
                  fontSize: 13,
                  color: AppColors.inkSoft,
                ),
              ),
              if (average != null)
                Text(
                  'в среднем $average',
                  style: AppText.caption.copyWith(fontWeight: FontWeight.w500),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: wide ? 140 : 108,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (var i = 0; i < bars.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: _WeekBar(
                        week: bars[i],
                        current: bars[i].start == thisMonday,
                        showNumber:
                            bars[i].start == thisMonday ||
                            (bars[i].closed == maxClosed && maxClosed > 0),
                        showLabel:
                            bars[i].start == thisMonday ||
                            (bars.length - 1 - i) % 3 == 0,
                        maxClosed: maxClosed,
                        onTap: () => onTapWeek(bars[i].start),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.week,
    required this.current,
    required this.showNumber,
    required this.showLabel,
    required this.maxClosed,
    required this.onTap,
  });

  final HistoryWeek week;
  final bool current;
  final bool showNumber;
  final bool showLabel;
  final int maxClosed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = week.start.split('-');
    final label = current ? 'эта' : '${int.parse(p[2])}.${p[1]}';
    return Semantics(
      button: true,
      label: '${weekRange(week.start)}: ${week.closed} закрыто',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            const labelBox = 16.0;
            const numberBox = 16.0;
            const dotBox = 8.0;
            final area = math.max(
              4.0,
              box.maxHeight - labelBox - numberBox - dotBox,
            );
            final height = week.closed == 0 || maxClosed == 0
                ? 4.0
                : math.max(4.0, area * week.closed / maxClosed);
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  height: numberBox,
                  child: showNumber
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('${week.closed}', style: AppText.weekNumber),
                        )
                      : null,
                ),
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: week.closed == 0
                        ? AppColors.weekBarEmpty
                        : current
                        ? AppColors.weekBarNow
                        : AppColors.weekBar,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                SizedBox(
                  height: labelBox,
                  child: showLabel
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              label,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: AppFonts.text,
                                fontWeight: current
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontSize: 10.5,
                                color: current
                                    ? AppColors.indigoInk
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
                SizedBox(
                  height: dotBox,
                  child: week.review == null
                      ? null
                      : Center(
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: AppColors.voiceBackground,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A week with no review: one bordered row.
class _WeekPlain extends StatelessWidget {
  const _WeekPlain({required this.week});

  final HistoryWeek week;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Text(
            weekRange(week.start),
            style: const TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.inkSoft,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: '${week.closed} закрыто'),
                  TextSpan(
                    text: ' · без пересмотра',
                    style: AppText.caption.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppText.caption.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// A week with a review record: dates, closed, the summary, projects, goals.
class _WeekRecord extends StatefulWidget {
  const _WeekRecord({required this.week});

  final HistoryWeek week;

  @override
  State<_WeekRecord> createState() => _WeekRecordState();
}

class _WeekRecordState extends State<_WeekRecord> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final week = widget.week;
    final review = week.review!;
    final summary = review.summary?.trim() ?? '';
    final projects = week.byProject.isNotEmpty
        ? week.byProject
        : review.byProject;
    final shown = _expanded ? projects : projects.take(4).toList();
    final top = projects.fold<int>(0, (m, p) => math.max(m, p.closed));

    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: projects.length > 4
            ? () => setState(() => _expanded = !_expanded)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    weekRange(week.start),
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  if (review.monthly) ...<Widget>[
                    const SizedBox(width: 8),
                    Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.indigoFill,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Text(
                        'месяц',
                        style: TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          color: AppColors.indigoInk,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${week.closed}',
                    style: const TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: AppColors.done,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('закрыто', style: AppText.caption),
                ],
              ),
              if (summary.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(left: 10),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: AppColors.voiceBackground,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      height: 1.35,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
              if (shown.isNotEmpty) const SizedBox(height: 10),
              for (final project in shown)
                SizedBox(
                  height: 24,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: top == 0
                                ? 0
                                : math.max(0.04, project.closed / top),
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.done,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${project.closed}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: AppFonts.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_expanded && projects.length > 4)
                Text(
                  'и ещё ${projects.length - 4}',
                  style: AppText.caption.copyWith(color: AppColors.indigoLink),
                ),
              for (final goal in review.achievedGoals) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    const CrownIcon(size: 13, color: AppColors.crownOnLight),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        goal.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppText.projectName),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: AppText.hint),
          if (action != null) ...<Widget>[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

// --- достигнутые цели (design/goals-ideas-spec.md, п. 8) --------------------

/// «ДОСТИГНУТЫЕ ЦЕЛИ · N»: the newest large on the goal gradient, the rest as
/// light rows. Nothing when there are none since [from], or when the read
/// failed -- goals are an extra on this screen, never its error.
class _AchievedGoalsSection extends ConsumerWidget {
  const _AchievedGoalsSection({required this.from});

  final DateTime? from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = achievedSince(
      ref.watch(achievedGoalsProvider).value ?? const <GoalView>[],
      from,
    );
    if (goals.isEmpty) return const SizedBox.shrink();
    final contours = <String, String>{
      for (final contour in ref.watch(contourListProvider))
        contour.id: contour.name,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 20, Insets.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const CrownIcon(size: 13, color: AppColors.crownOnLight),
              const SizedBox(width: 8),
              Expanded(
                child: HistoryHeading(
                  label: 'Достигнутые цели · ${goals.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AchievedHero(goal: goals.first),
          for (final goal in goals.skip(1)) ...<Widget>[
            const SizedBox(height: 8),
            _AchievedRow(goal: goal, contourName: contours[goal.contourId]),
          ],
        ],
      ),
    );
  }
}

/// The newest achieved goal, large.
class _AchievedHero extends StatelessWidget {
  const _AchievedHero({required this.goal});

  final GoalView goal;

  static const TextStyle _big = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextStyle _under = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 12.5,
    color: AppColors.voiceBright,
  );

  @override
  Widget build(BuildContext context) {
    final why = (goal.why ?? '').trim();
    final days = _daysFromTo(goal.createdAt, goal.achievedAt);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.goal),
        onTap: () => openGoal(context, goal.id),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.goalStart, AppColors.goalEnd],
            ),
            borderRadius: BorderRadius.circular(Radii.goal),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x2E14183C),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const CrownIcon(size: 22, color: AppColors.crown),
                  const Spacer(),
                  const Icon(
                    Icons.check,
                    size: 14,
                    color: AppColors.doneOnDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Достигнута ${shortDate(goal.achievedAt)}',
                    style: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.doneOnDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                goal.title,
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  height: 1.3,
                  color: AppColors.onInk,
                ),
              ),
              if (why.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(why, style: AppText.goalWhy),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 22,
                runSpacing: 10,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '${goal.progress.done}',
                        style: _big.copyWith(color: AppColors.doneOnDark),
                      ),
                      Text(
                        '${tasksWord(goal.progress.done)} закрыто',
                        style: _under,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '$days',
                        style: _big.copyWith(color: AppColors.onInk),
                      ),
                      Text('${_daysWord(days)} от начала', style: _under),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _daysFromTo(String fromIso, String? toIso) {
  final from = DateTime.tryParse(fromIso)?.toLocal();
  final to = toIso == null ? null : DateTime.tryParse(toIso)?.toLocal();
  if (from == null || to == null) return 1;
  final days = DateTime(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime(from.year, from.month, from.day)).inDays;
  return days < 1 ? 1 : days;
}

/// «день / дня / дней» for [n].
String _daysWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'день';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'дня';
  return 'дней';
}

/// An older achieved goal: a light 64 px row.
class _AchievedRow extends StatelessWidget {
  const _AchievedRow({required this.goal, required this.contourName});

  final GoalView goal;
  final String? contourName;

  @override
  Widget build(BuildContext context) {
    final done = goal.progress.done;
    final meta = <String>[
      shortDate(goal.achievedAt),
      '$done ${tasksWord(done)}',
      ?contourName,
    ].join(' · ');
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        onTap: () => openGoal(context, goal.id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.crownChip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const CrownIcon(size: 20, color: AppColors.crown),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      goal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
