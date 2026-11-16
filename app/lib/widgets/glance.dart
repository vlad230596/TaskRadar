import 'package:flutter/material.dart';

import '../domain/project_badge.dart';
import '../domain/task_age.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The three small things every planning screen draws: how old something is,
/// which project it belongs to, and what shape a project's task list is in
/// (F12).
///
/// ## Why these are widgets rather than three helper functions per screen
///
/// The spec's rule is *"меньше текста, больше графики: статусы -- точки,
/// возраст -- число + цвет"*, and it is a rule precisely because a project
/// looks the same on the list screen, on the tile screen, in a project's own
/// header and (from F13) in the work mode. Four copies of "10 px circle, white
/// with a 2 px #C3C6DE border unless it is done" is four chances for one of
/// them to end up 9 px, at which point the language stops being a language.

/// "2 д" -- how long since something last moved.
///
/// ## The one thing this widget must never do
///
/// **Wrap, or shrink.** The spec pins it (`нет переносов`, `flex-shrink: 0`)
/// and says why: it already broke on a phone. The chip shares a row with a
/// project name of arbitrary length, and a `Row` will happily hand a flexible
/// child the space it needs by taking it from an inflexible one -- which turns
/// "12 д" into "12" and then into a two-line chip that makes the row 40 px
/// tall.
///
/// So: no `Flexible`/`Expanded` around it anywhere, `softWrap: false`,
/// `maxLines: 1`, and the *name* beside it is the thing that ellipsises. That
/// ordering is the right one on its own merits -- a truncated project name is
/// still recognisable, a truncated number is a different number.
class AgeChip extends StatelessWidget {
  const AgeChip({required this.days, this.showIcon = true, super.key});

  /// Null draws nothing at all: a row with an unreadable timestamp should look
  /// like a row with nothing wrong, not like a row aged zero days.
  final int? days;

  /// The little clock. Off inside a task row, where the chip sits at the end of
  /// a line of text and the icon would be the third glyph competing for a very
  /// short strip.
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final value = days;
    if (value == null) return const SizedBox.shrink();

    final stale = isStaleAge(value);
    final foreground = stale ? AppColors.waitingInk : AppColors.muted;

    return Container(
      // At least 22, not exactly: at a large system font the digits are
      // taller than that, and a fixed height cut them through the middle.
      constraints: const BoxConstraints(minHeight: 22),
      padding: EdgeInsets.symmetric(horizontal: showIcon ? 8 : 7),
      decoration: BoxDecoration(
        color: stale ? AppColors.waitingChip : AppColors.background,
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      // Scaled down -- never wrapped, never cut -- in the one case where even
      // a line of its own is narrower than the chip: a 320 dp phone at twice
      // the system font. Everywhere else the scale is 1 and this is a no-op.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showIcon) ...<Widget>[
              Icon(Icons.schedule, size: 12, color: foreground),
              const SizedBox(width: 5),
            ],
            Text(
              formatAgeShort(value),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: AppText.chip.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// A project's 40x40 badge: its first letter, on a colour derived from its name.
///
/// See `domain/project_badge.dart` for why the colour is computed rather than
/// stored.
///
/// [color] is how a caller hands over the board-wide allocation from
/// [assignProjectBadgeColors]. **Anywhere two badges can be on screen at once,
/// pass it** -- the per-name hash alone puts different projects on one colour,
/// which is the one thing the badge may not do. Left out, the badge falls back
/// to that hash, which is right only for a project shown on its own.
class ProjectBadge extends StatelessWidget {
  const ProjectBadge({
    required this.name,
    this.size = 40,
    this.color,
    super.key,
  });

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? projectBadgeColor(name),
        borderRadius: BorderRadius.circular(size * 0.35),
      ),
      // Not scaled with the system font: the letter is a mark on a box of
      // fixed size, not text to read -- the name beside it is that -- and at
      // 160 % it no longer fitted the box.
      child: Text(
        projectBadgeLetter(name),
        textScaler: TextScaler.noScaling,
        style: AppText.badge.copyWith(fontSize: size * 0.4),
      ),
    );
  }
}

/// One dot per task, in list order: the shape of a project at a glance.
///
/// Empty ring for work still to do, filled amber for a blocker, filled green
/// for done. Reading left to right it answers "how much is there, how much is
/// finished, is anything stuck" without a single word -- which is the whole
/// bargain the spec strikes ("меньше текста, больше графики").
///
/// ## Why it stops at [maxDots]
///
/// A project with forty tasks would otherwise draw forty dots, squeeze the
/// counter off the end of the row and take a third of a phone's width to say
/// something the counter beside it already says. Past the cap the dots stop and
/// the count carries the rest; the cap is generous enough that the ordinary
/// project (two to eight tasks) never reaches it.
///
/// ## And why it also stops at the edge
///
/// The cap is a count, and a count does not know how wide the row is: eight
/// dots fit a 179 px tile at the reference font size and do not fit the same
/// tile on a 360 dp phone with the system font at 130 %, where they ran over
/// the age beside them. So the strip measures the width it was given and draws
/// only the dots that fit, with the "…" taking the place of the rest -- see
/// [fitDots].
class TaskDots extends StatelessWidget {
  const TaskDots({
    required this.tasks,
    this.size = 10,
    this.maxDots = 12,
    super.key,
  });

  final List<Task> tasks;
  final double size;
  final int maxDots;

  static const double _gap = 5;

  @override
  Widget build(BuildContext context) {
    final more = Text('…', maxLines: 1, softWrap: false, style: AppText.chip);

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = fitDots(
          count: tasks.length,
          cap: maxDots,
          pitch: size + _gap,
          width: constraints.maxWidth,
          moreWidth: measureTextWidth(context, '…', AppText.chip) + _gap,
        );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final task in tasks.take(fit.shown))
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: _Dot(status: task.status, size: size),
              ),
            if (fit.more)
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: more,
              ),
          ],
        );
      },
    );
  }
}

/// How many of [count] dots, each [pitch] wide, a strip [width] wide can show
/// -- at most [cap] -- and whether a "there are more" mark of [moreWidth] has to
/// follow them.
///
/// The mark is reserved only when something is actually left out: a strip
/// whose dots all fit does not lose one to make room for a mark it does not
/// draw.
({int shown, bool more}) fitDots({
  required int count,
  required int cap,
  required double pitch,
  required double width,
  required double moreWidth,
}) {
  final wanted = count < cap ? count : cap;
  if (!width.isFinite) return (shown: wanted, more: count > wanted);
  if (count <= cap && wanted * pitch <= width) {
    return (shown: wanted, more: false);
  }
  final room = ((width - moreWidth) / pitch).floor();
  final shown = room < 0 ? 0 : (room > wanted ? wanted : room);
  return (shown: shown, more: moreWidth <= width);
}

/// How wide [text] is in [style] at this screen's text scale.
double measureTextWidth(BuildContext context, String text, TextStyle style) =>
    measureText(context, text, style).width;

/// The size of [text] on one line in [style] at this screen's text scale --
/// what a layout that has to make room for it in advance needs to know.
Size measureText(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final size = Size(
    painter.width.ceilToDouble(),
    painter.height.ceilToDouble(),
  );
  painter.dispose();
  return size;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.status, required this.size});

  final TaskStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Border? border) = switch (status) {
      TaskStatus.done => (AppColors.done, null),
      TaskStatus.blocked => (AppColors.waitingDot, null),
      TaskStatus.pending => (
        AppColors.card,
        Border.all(color: AppColors.lineStrong, width: 2),
      ),
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        border: border,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// "3 открытых" -- what is left in a project, for the planning board's rows.
/// Not done-out-of-total: that pair only ever grows, and a project with forty
/// finished tasks and two open ones is a small project, not a big one.
class OpenTaskCount extends StatelessWidget {
  const OpenTaskCount({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$count ${_openWord(count)}',
      maxLines: 1,
      softWrap: false,
      style: AppText.chip,
    );
  }
}

/// «открытая / открытые / открытых» for [n].
String _openWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'открытая';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'открытые';
  }
  return 'открытых';
}
