import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/task_age.dart';
import '../models/history_snapshot.dart';
import '../models/history_task_event.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Графика режима «История»: столбики недели, полоски долей, подписи разделов
/// (F13).
///
/// ## Почему это отдельный файл, а не части экрана
///
/// Потому что каждая из этих трёх вещей рисуется дважды: на телефоне и на
/// широком экране, с разными размерами и одинаковым смыслом. Спецификация
/// требует «меньше текста, больше графики», а значит именно графика — то, что
/// обязано совпадать между `History.html` и `Desk-History.html`; размеры там
/// разные, правила чтения одни и те же. Полоска долей, кроме того, живёт и на
/// экране задачи — это её блок «жизнь задачи».

/// Цвет фазы жизни задачи. Одно место на всё приложение.
///
/// Серый — очередь, индиго — работа, янтарный — блокер, зелёный — закрыто. Так
/// и на эталонных страницах, и цвета здесь не новые: это те же токены, что у
/// статусов в остальном интерфейсе, — сегмент полоски и точка статуса в списке
/// задач обязаны означать одно и то же, иначе графика вместо текста ничего не
/// экономит.
Color phaseColour(TaskLifePhase phase) => switch (phase) {
  TaskLifePhase.queued => AppColors.lineStrong,
  TaskLifePhase.working => AppColors.indigoLink,
  TaskLifePhase.blocked => AppColors.waitingDot,
  TaskLifePhase.done => AppColors.done,
};

/// Как фаза называется в легенде и в строке под полоской.
///
/// Прошедшее время не случайно: строка читается как «куда ушла жизнь задачи»,
/// то есть про то, что уже было. Текущая фаза получает приписку «с 18.09» —
/// см. `Edit.html` и экран задачи.
String phaseLabel(TaskLifePhase phase) => switch (phase) {
  TaskLifePhase.queued => 'лежала в очереди',
  TaskLifePhase.working => 'была в работе',
  TaskLifePhase.blocked => 'ждала',
  TaskLifePhase.done => 'закрыта',
};

/// Короткая подпись фазы — для легенды широкого экрана.
String phaseShortLabel(TaskLifePhase phase) => switch (phase) {
  TaskLifePhase.queued => 'в очереди',
  TaskLifePhase.working => 'в работе',
  TaskLifePhase.blocked => 'блокер',
  TaskLifePhase.done => 'закрыто',
};

/// Один сегмент полоски: сколько и каким цветом.
@immutable
class SpanSegment {
  const SpanSegment(this.weight, this.colour);

  /// В любых единицах, лишь бы одинаковых внутри одной полоски. На практике —
  /// миллисекунды или число задач.
  final int weight;
  final Color colour;
}

/// Горизонтальная полоска долей на общей подложке.
///
/// ## Почему у неё есть знаменатель
///
/// [total] — то, за что принимается полная ширина. Без него полоска показывала
/// бы состав, но не величину: четыре строки «висит дольше всего» с полосками во
/// всю ширину выглядели бы одинаково висящими, хотя одна из них старше вчетверо.
/// С общим знаменателем (возраст самой старой) длина полоски — это и есть
/// возраст, и его видно, не читая число справа. Так же и на эталоне: там доли
/// заданы процентами от общей для всех строк шкалы, а не от своей.
///
/// Null — знаменатель равен сумме сегментов, то есть полоска всегда полная.
/// Это режим блока «жизнь задачи», где вопрос другой: не «сколько», а «куда».
///
/// **Ненулевой сегмент всегда видно.** Минимальная доля не даёт получасовому
/// заходу в работу схлопнуться в ноль пикселей; цена — что очень короткие
/// сегменты нарисованы чуть длиннее, чем они есть, и это лучше, чем сегмент,
/// которого нет на экране, но есть в числах.
class SpanBar extends StatelessWidget {
  const SpanBar({
    required this.segments,
    this.total,
    this.height = 8,
    this.track = AppColors.lineFaint,
    super.key,
  });

  final List<SpanSegment> segments;
  final int? total;
  final double height;
  final Color track;

  /// Тысячные, ниже которых сегмент не опускается. 8/1000 — это примерно 2 px
  /// на полоске шириной с телефон.
  static const int _minShare = 8;

  @override
  Widget build(BuildContext context) {
    var sum = 0;
    for (final segment in segments) {
      sum += math.max(0, segment.weight);
    }
    final denominator = math.max(total ?? sum, sum);

    final flexes = <int>[];
    var used = 0;
    for (final segment in segments) {
      if (segment.weight <= 0 || denominator <= 0) {
        flexes.add(0);
        continue;
      }
      final share = math.max(
        _minShare,
        (segment.weight * 1000 / denominator).round(),
      );
      flexes.add(share);
      used += share;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: track,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < segments.length; i++)
                if (flexes[i] > 0)
                  Expanded(
                    flex: flexes[i],
                    child: ColoredBox(color: segments[i].colour),
                  ),
              // Остаток до знаменателя. Без него полоска, занимающая треть
              // шкалы, растянулась бы на всю ширину и перестала бы что-либо
              // сравнивать. Только при заданном [total]: без него знаменатель
              // и есть сумма сегментов, и «остаток» был бы щелью от округления.
              if (total != null && used < 1000)
                Expanded(flex: 1000 - used, child: const SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полоска «куда ушёл возраст» для одной висящей задачи.
///
/// Сегменты в том порядке, в каком задача их прожила бы: очередь, работа,
/// блокер. Порядок постоянный, а не по величине, — иначе две соседние строки
/// нельзя сравнить глазом.
class StaleSpanBar extends StatelessWidget {
  const StaleSpanBar({
    required this.task,
    required this.scaleMs,
    this.height = 8,
    this.now,
    super.key,
  });

  final StaleTask task;

  /// Общий знаменатель: возраст самой старой висящей задачи.
  final int scaleMs;

  final double height;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final inWork = task.inWorkMs(now: now);

    return SpanBar(
      height: height,
      total: scaleMs,
      segments: <SpanSegment>[
        SpanSegment(
          // Время в наборе идёт поверх очереди, а не рядом: см. `inWorkMs`.
          task.byStatus.pendingMs - inWork,
          phaseColour(TaskLifePhase.queued),
        ),
        SpanSegment(inWork, phaseColour(TaskLifePhase.working)),
        SpanSegment(
          task.byStatus.blockedMs,
          phaseColour(TaskLifePhase.blocked),
        ),
      ],
    );
  }
}

/// Столбики «сколько закрыто в каждый день».
///
/// ## Как считается высота
///
/// Один закрытый день — [unit] пикселей, но не больше, чем помещается: при
/// пятнадцати закрытиях за день шкала сжимается, чтобы самый высокий столбик
/// остался в карточке. День без закрытий — не нулевой столбик, а лежачая
/// черта в [_zeroHeight] пикселей: ноль высотой в ноль — это дырка в графике,
/// которую глаз читает как отсутствие данных, а не как «в этот день ничего не
/// закрыли».
class ClosedByDayBars extends StatelessWidget {
  const ClosedByDayBars({
    required this.days,
    this.areaHeight = 73,
    this.unit = 12,
    this.gap = 6,
    this.radius = 6,
    this.labelSize = 10.5,
    this.now,
    super.key,
  });

  final List<HistoryDay> days;

  /// Высота, отведённая самим столбикам, без подписей.
  final double areaHeight;

  /// Пикселей на одну закрытую задачу, пока они помещаются.
  final double unit;

  final double gap;
  final double radius;
  final double labelSize;
  final DateTime? now;

  /// Высота черты в день, когда ничего не закрыли.
  static const double _zeroHeight = 4;

  /// Дальше этого числа столбиков подписывать каждый бессмысленно — подписи
  /// сливаются. Тридцать дней получают подпись раз в неделю.
  static const int _labelEvery = 10;

  static const List<String> _weekdays = <String>[
    'пн',
    'вт',
    'ср',
    'чт',
    'пт',
    'сб',
    'вс',
  ];

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return SizedBox(height: areaHeight);

    var maxCount = 0;
    for (final day in days) {
      if (day.count > maxCount) maxCount = day.count;
    }

    final scale = maxCount == 0
        ? unit
        : math.min(unit, (areaHeight - _zeroHeight) / maxCount);

    final today = _key((now ?? DateTime.now()).toLocal());
    final dense = days.length > _labelEvery;
    final columnGap = dense ? 2.0 : gap;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (var i = 0; i < days.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: columnGap),
          Expanded(
            child: _Column(
              day: days[i],
              isToday: days[i].date == today,
              height: days[i].count == 0
                  ? _zeroHeight
                  : math.max(6, days[i].count * scale),
              radius: radius,
              labelSize: labelSize,
              // Плотная шкала подписывает каждый седьмой столбик, считая от
              // сегодняшнего: так крайняя правая подпись всегда есть, а
              // расстояние между ними — неделя.
              label: !dense
                  ? _weekdayOf(days[i])
                  : ((days.length - 1 - i) % 7 == 0
                        ? _dayOfMonth(days[i])
                        : null),
            ),
          ),
        ],
      ],
    );
  }

  static String? _weekdayOf(HistoryDay day) {
    final date = day.day;
    return date == null ? null : _weekdays[date.weekday - 1];
  }

  static String? _dayOfMonth(HistoryDay day) {
    final date = day.day;
    return date == null ? null : '${date.day}';
  }

  static String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _Column extends StatelessWidget {
  const _Column({
    required this.day,
    required this.isToday,
    required this.height,
    required this.radius,
    required this.labelSize,
    required this.label,
  });

  final HistoryDay day;
  final bool isToday;
  final double height;
  final double radius;
  final double labelSize;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colour = day.count == 0
        ? AppColors.line
        : (isToday
              // Сегодняшний столбик — индиговый, потому что он единственный ещё
              // не закончился: сравнивать его с остальными по высоте нельзя, и
              // цвет об этом предупреждает раньше, чем это придёт в голову.
              ? AppColors.voiceLevelHigh
              : AppColors.done);

    return Semantics(
      label: '${day.date}: ${day.count}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            height: height,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          SizedBox(height: label == null ? 0 : 6),
          Text(
            label ?? '',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: AppText.caption.copyWith(
              fontSize: labelSize,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
              color: isToday ? AppColors.indigoInk : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Подпись раздела: «ВИСИТ ДОЛЬШЕ ВСЕГО» и линия до края.
class HistoryHeading extends StatelessWidget {
  const HistoryHeading({required this.label, this.trailing, super.key});

  final String label;

  /// То, что стоит справа вместо линии, — легенда на широком экране.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(label.toUpperCase(), style: AppText.sectionLabel),
        const SizedBox(width: 8),
        if (trailing == null)
          const Expanded(child: ColoredBox(color: AppColors.line, child: SizedBox(height: 1)))
        else ...<Widget>[const Spacer(), trailing!],
      ],
    );
  }
}

/// Квадратик-цвет и подпись: легенда фаз.
class PhaseLegend extends StatelessWidget {
  const PhaseLegend({required this.phases, this.spacing = 14, super.key});

  final List<TaskLifePhase> phases;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final phase in phases) ...<Widget>[
          if (phase != phases.first) SizedBox(width: spacing),
          PhaseDot(phase: phase),
          const SizedBox(width: 7),
          Text(phaseShortLabel(phase), style: AppText.caption),
        ],
      ],
    );
  }
}

/// Квадратик 11x11 со скруглением 3 — тот же, что в легенде «жизни задачи».
class PhaseDot extends StatelessWidget {
  const PhaseDot({required this.phase, this.size = 11, super.key});

  final TaskLifePhase phase;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: phaseColour(phase),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// «8 д» — короткая форма промежутка, для числа справа в строке.
///
/// Меньше суток — «<1 д», а не «0 д»: ноль здесь читался бы как «ничего не
/// было», хотя это «было, но недолго». Та же причина, по которой
/// `daysSince` возвращает null вместо нуля для нечитаемой метки.
String formatSpanShort(int ms) {
  final days = ms ~/ Duration.millisecondsPerDay;
  if (days < 1) return '<1 д';
  return '$days д';
}

/// «8 дней» — длинная форма, для числа над полоской.
///
/// Склонение берётся из `domain/task_age.dart`: второго набора русских
/// числительных в приложении быть не должно.
String formatSpanLong(int ms) {
  final days = ms ~/ Duration.millisecondsPerDay;
  if (days < 1) return 'меньше дня';
  return formatDays(days);
}
