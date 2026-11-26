import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../domain/reminders.dart';
import '../../domain/today_view.dart';
import '../../models/task.dart';
import '../../providers/today_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'date_sheet.dart';
import 'today_icons.dart';

/// The quick date actions of a task row (`design/today-history-spec.md`
/// §5.2): «Сегодня» / «Завтра» by a swipe on the phone, by hover buttons on
/// the desktop, and with «Дата…» / «Снять дату» in the long-press menu.

/// What the date block of a row's menu answered.
enum RowDateAction { today, tomorrow, pick, clear }

/// Puts [task] on [date] (null: takes the date off) and offers the undo:
/// «На сегодня · Отменить». Quick actions drop the time (coordinator answer
/// 4); [keepTime] is the date sheet's case.
Future<void> moveTaskDate(
  BuildContext context,
  Task task, {
  required String? date,
  bool keepTime = false,
  String? message,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final today = container.read(todayKeyProvider);
  final before = freshTask(container, task);
  final previousDate = taskDay(before.remindAt);
  final previousTime = before.remindTime;
  try {
    await setTaskDate(
      container,
      before,
      date: date,
      time: keepTime ? before.remindTime : null,
    );
  } catch (error) {
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Не удалось изменить дату. ${describeApiError(error)}'),
        ),
      );
    return;
  }
  if (messenger == null || !messenger.mounted) return;
  final text =
      message ??
      (date == null
          ? 'В стопке'
          : date == today
          ? 'На сегодня'
          : date == addDays(today, 1)
          ? 'На завтра'
          : 'На ${weekdayDate(date)}');
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        persist: false,
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => unawaited(() async {
            try {
              await setTaskDate(
                container,
                freshTask(container, before),
                date: previousDate,
                time: previousTime,
              );
            } catch (error) {
              debugPrint('Undoing a date change failed: $error');
            }
          }()),
        ),
      ),
    );
}

/// Runs the date block of a row's menu for [task].
Future<void> runRowDateAction(
  BuildContext context,
  Task task,
  RowDateAction action,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final today = container.read(todayKeyProvider);
  switch (action) {
    case RowDateAction.today:
      await moveTaskDate(context, task, date: today);
    case RowDateAction.tomorrow:
      await moveTaskDate(context, task, date: addDays(today, 1));
    case RowDateAction.clear:
      await moveTaskDate(context, task, date: null, message: 'Дата снята');
    case RowDateAction.pick:
      final choice = await showTaskDateSheet(
        context,
        current: task.remindAt,
        time: task.remindTime,
        today: today,
      );
      if (choice == null || !context.mounted) return;
      await moveTaskDate(context, task, date: choice.value, keepTime: true);
  }
}

/// The date block under the three statuses in a row's long-press menu.
List<Widget> rowDateMenuItems(
  BuildContext context, {
  required Task task,
  required String today,
}) {
  final day = taskDay(task.remindAt);
  Widget item(RowDateAction action, String label, {bool enabled = true}) =>
      ListTile(
        key: ValueKey<String>('row-date-${action.name}'),
        enabled: enabled,
        leading: action == RowDateAction.clear
            ? const Icon(Icons.event_busy_outlined)
            : const TodayIcon(
                TodayGlyph.calendar,
                size: 22,
                color: AppColors.inkSoft,
              ),
        title: Text(label),
        onTap: () => Navigator.of(context).pop(action),
      );
  return <Widget>[
    const Divider(height: 1),
    item(
      RowDateAction.today,
      day == today ? 'Уже сегодня' : 'Сегодня',
      enabled: day != today,
    ),
    item(RowDateAction.tomorrow, 'Завтра'),
    item(RowDateAction.pick, 'Дата…'),
    if (day != null) item(RowDateAction.clear, 'Снять дату'),
  ];
}

/// The phone's swipe: the row moves left and two tiles «Сегодня» /
/// «Завтра» show under it; a full swipe (past 60 % of the width) is
/// «Сегодня» at once.
class DateSwipe extends StatefulWidget {
  const DateSwipe({
    required this.child,
    required this.alreadyToday,
    required this.onToday,
    required this.onTomorrow,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool alreadyToday;
  final VoidCallback onToday;
  final VoidCallback onTomorrow;
  final bool enabled;

  @override
  State<DateSwipe> createState() => _DateSwipeState();
}

class _DateSwipeState extends State<DateSwipe>
    with SingleTickerProviderStateMixin {
  static const double _tile = 76;
  static const double _gap = 6;
  static const double _reveal = _tile * 2 + _gap + 6;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  double _dx = 0;
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      setState(
        () => _dx = _from + (_to - _from) * Curves.easeOut.transform(_settle.value),
      );
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _from = _dx;
    _to = target;
    unawaited(_settle.forward(from: 0));
  }

  void _close() => _animateTo(0);

  void _act(VoidCallback action) {
    _close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final open = _dx < -1;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _settle.stop(),
          onHorizontalDragUpdate: (details) => setState(
            () => _dx = (_dx + details.delta.dx).clamp(-width, 0.0),
          ),
          onHorizontalDragEnd: (_) {
            if (-_dx > width * 0.6 && !widget.alreadyToday) {
              _act(widget.onToday);
            } else if (-_dx > _reveal / 2) {
              _animateTo(-_reveal);
            } else {
              _close();
            }
          },
          child: Stack(
            children: <Widget>[
              if (open)
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _Tile(
                        key: const ValueKey<String>('swipe-today'),
                        label: widget.alreadyToday ? 'уже сегодня' : 'Сегодня',
                        fill: widget.alreadyToday
                            ? AppColors.lineFaint
                            : AppColors.ink,
                        ink: widget.alreadyToday
                            ? AppColors.muted
                            : AppColors.onInk,
                        onTap: widget.alreadyToday
                            ? null
                            : () => _act(widget.onToday),
                      ),
                      const SizedBox(width: _gap),
                      _Tile(
                        key: const ValueKey<String>('swipe-tomorrow'),
                        label: 'Завтра',
                        fill: AppColors.indigoFill,
                        ink: AppColors.indigoInk,
                        onTap: () => _act(widget.onTomorrow),
                      ),
                    ],
                  ),
                ),
              Transform.translate(
                offset: Offset(_dx, 0),
                child: open
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                        child: AbsorbPointer(child: widget.child),
                      )
                    : widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.fill,
    required this.ink,
    required this.onTap,
    super.key,
  });

  final String label;
  final Color fill;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _DateSwipeState._tile,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TodayIcon(TodayGlyph.calendar, size: 18, color: ink),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The desktop's hover buttons «Сегодня» / «Завтра» before «в работу».
class HoverDateButtons extends StatelessWidget {
  const HoverDateButtons({
    required this.alreadyToday,
    required this.onToday,
    required this.onTomorrow,
    super.key,
  });

  final bool alreadyToday;
  final VoidCallback onToday;
  final VoidCallback onTomorrow;

  @override
  Widget build(BuildContext context) {
    final text = AppText.action.copyWith(fontSize: 13, fontWeight: FontWeight.w700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!alreadyToday)
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: onToday,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.lineStrong),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: text,
              ),
              child: const Text('Сегодня'),
            ),
          ),
        const SizedBox(width: 6),
        SizedBox(
          height: 32,
          child: TextButton(
            onPressed: onTomorrow,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.indigoLink,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: text,
            ),
            child: const Text('Завтра'),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// A hover state for a builder: the desktop row's buttons.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}

/// «Позже: N · ближайшая 25 фев» (§5.3): the folded row at the end of a
/// project's open tasks, and the heading «ПОЗЖЕ · N» when unfolded.
class LaterToggle extends StatelessWidget {
  const LaterToggle({
    required this.count,
    required this.nearest,
    required this.expanded,
    required this.onTap,
    super.key,
  });

  final int count;

  /// The nearest «Позже» date's label («25 фев»), or null.
  final String? nearest;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      return Semantics(
        button: true,
        expanded: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.card),
          child: SizedBox(
            height: Targets.minimum,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 2),
                Text(
                  'ПОЗЖЕ · $count',
                  style: AppText.sectionLabel.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.expand_less, color: AppColors.muted),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      );
    }
    final nearest = this.nearest;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Semantics(
        button: true,
        expanded: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: CustomPaint(
            painter: _DashedBorder(),
            child: Container(
              height: 52,
              padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
              child: Row(
                children: <Widget>[
                  const TodayIcon(
                    TodayGlyph.later,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Позже · ',
                    style: AppText.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  Text(
                    '$count',
                    style: AppText.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: nearest == null
                        ? const SizedBox.shrink()
                        : Text(
                            'ближайшая $nearest',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.hint.copyWith(fontSize: 13),
                          ),
                  ),
                  const SizedBox(
                    width: Targets.minimum,
                    child: Icon(Icons.expand_more, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.laterLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(16),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => false;
}

/// The one-time hint over a project's list (coordinator answer 8).
class SwipeHint extends StatelessWidget {
  const SwipeHint({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
      decoration: BoxDecoration(
        color: AppColors.indigoFill,
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        children: <Widget>[
          const TodayIcon(
            TodayGlyph.calendar,
            size: 16,
            color: AppColors.indigoInk,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Свайп влево по задаче — «Сегодня» или «Завтра»',
              style: AppText.hint.copyWith(color: AppColors.indigoInk),
            ),
          ),
          IconButton(
            tooltip: 'Понятно',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18, color: AppColors.indigoInk),
          ),
        ],
      ),
    );
  }
}

/// The local today, for code with no provider at hand.
String localToday() => localTodayCalendarDate();
