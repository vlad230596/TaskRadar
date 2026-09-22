import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/task_age.dart';
import '../models/history_snapshot.dart';
import '../models/history_task_event.dart';
import '../navigation/app_routes.dart';
import '../providers/history_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/history_charts.dart';

/// История: что закрыто и что висит (F13).
///
/// ## Что этот режим показывает и чего поэтому не показывает
///
/// Три ответа, и все три — про прошедшее время: сколько закрыто по дням, что
/// висит дольше всего и куда ушёл его возраст, и в каких проектах вообще было
/// движение. Очереди здесь нет — она в планировании, одно нажатие отсюда, и
/// держать её и тут значило бы вернуть экран, на котором есть всё сразу.
///
/// ## Почему ноль рисуется словами, а не нулём
///
/// В базе может не быть ни одной закрытой задачи: журнал завели в F11, а
/// закрывать задачи начали раньше. Огромный «0» над семью лежачими чёрточками
/// выглядит как результат недели — и это единственное место экрана, где
/// неправда не видна вообще никак, потому что нулей в графике не отличить от
/// нулей в данных. Поэтому пустые данные говорят о себе словами, а карточка с
/// числом появляется, только когда число есть.
///
/// ## Почему переключатель диапазона внутри экрана, а не в шапке
///
/// Шапка режима — общая (`ShellScreen`), и на эталоне
/// (`design/reference/History.html`) кнопка «7 дней» стоит справа от заголовка
/// именно в ней. Своей шапки у режима нет, а заводить её значило бы править
/// оболочку, принятую в F12. Разница — один ряд высотой 36 px под заголовком;
/// всё остальное на своих местах.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(historyFeedProvider);
    final snapshot = feed.value;

    return RefreshIndicator(
      onRefresh: () => ref.read(historyFeedProvider.notifier).refresh(),
      child: switch (snapshot) {
        null when feed.hasError => _Filler(
          icon: Icons.cloud_off,
          title: 'Не удалось загрузить историю',
          body:
              '${describeApiError(feed.error!)}\n\nИстория считается на '
              'сервере по журналу переходов — локального снимка у неё нет. '
              'Потяните вниз или нажмите «Повторить».',
          action: const _RetryButton(),
        ),
        null => const _Filler(
          title: 'Считаем историю…',
          body:
              'Сервер проигрывает журнал каждой открытой задачи, чтобы '
              'сказать, сколько она провисела и где.',
        ),
        final HistorySnapshot data => Center(
          child: ConstrainedBox(
            // Тот же потолок, что у планирования: строка задачи с полоской на
            // 1800 px — это полоска в метре от числа, которое она объясняет.
            // Широкое окно получает свою композицию ниже, а не растянутую эту.
            constraints: const BoxConstraints(maxWidth: 1240),
            child: isWideLayout(context)
                ? _WideBody(data: data, failure: feed.error)
                : _PhoneBody(data: data, failure: feed.error),
          ),
        ),
      },
    );
  }
}

/// Скругление карточек истории — 22 px.
///
/// Своё число, а не [Radii.panel] (20): на эталоне и телефона, и десктопа у
/// всех карточек этого режима именно 22, и это не описка — карточки здесь
/// крупнее и реже, чем строки проектов, и живут как панели дашборда. Заводить
/// ради этого общий токен нельзя: 22 не встречается больше нигде.
const double _kHistoryCard = 22;

/// Высота области столбиков вместе с подписями — как в `History.html`.
const double _kBarsBox = 92;

/// Цвет текста на тёплой карточке «висят дольше недели» (`Desk-History.html`).
///
/// Темнее [AppColors.waitingInk]: тот рассчитан на 12–13 px подписи, а здесь
/// это две строки прозой на светло-песочном фоне, где ему не хватает контраста.
const Color _kWarmDeepInk = Color(0xFF5C4310);

// --- телефон ---------------------------------------------------------------

class _PhoneBody extends StatelessWidget {
  const _PhoneBody({required this.data, this.failure});

  final HistorySnapshot data;
  final Object? failure;

  @override
  Widget build(BuildContext context) {
    final stale = data.stale.take(5).toList(growable: false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        if (failure != null) _StaleBanner(error: failure!),

        const Padding(
          padding: EdgeInsets.fromLTRB(Insets.gutter, 0, Insets.gutter, 10),
          child: Align(alignment: Alignment.centerRight, child: _RangePill()),
        ),

        if (data.isEmpty)
          const _EmptyCard()
        else ...<Widget>[
          _ClosedCard(data: data),

          if (stale.isNotEmpty) ...<Widget>[
            const _Heading('Висит дольше всего'),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final task in stale) ...<Widget>[
                    if (task != stale.first) const SizedBox(height: 14),
                    _StaleRow(task: task, scaleMs: data.oldestAgeMs),
                  ],
                ],
              ),
            ),
          ],

          if (data.projects.isNotEmpty) ...<Widget>[
            const _Heading('Движение по проектам'),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final project in data.projects) ...<Widget>[
                    if (project != data.projects.first)
                      const SizedBox(height: 14),
                    _ProjectRow(project: project),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Карточка недели: число закрытых и столбики по дням.
class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.data});

  final HistorySnapshot data;

  @override
  Widget build(BuildContext context) {
    return _Card(
      margin: const EdgeInsets.fromLTRB(Insets.gutter, 4, Insets.gutter, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (data.closedTotal == 0)
            // Ноль не рисуется числом: см. заголовок файла.
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Ни одной закрытой задачи ${data.range.caption}.',
                  style: AppText.body,
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${data.closedTotal}',
                  style: AppText.number.copyWith(
                    fontSize: 44,
                    height: 1,
                    color: AppColors.done,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'сделано',
                  style: AppText.caption.copyWith(
                    fontSize: 13,
                    color: AppColors.inkSoft,
                  ),
                ),
                Text(
                  data.range.caption,
                  style: AppText.caption.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: _kBarsBox,
              child: ClosedByDayBars(days: data.closedByDay),
            ),
          ),
        ],
      ),
    );
  }
}

/// Одна висящая задача: название, возраст, и куда этот возраст ушёл.
class _StaleRow extends StatelessWidget {
  const _StaleRow({required this.task, required this.scaleMs});

  final StaleTask task;
  final int scaleMs;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AppRoutes.openTask(
        context,
        projectId: task.projectId,
        taskId: task.id,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 10),
              // Плашка возраста не переносится и не сжимается — правило спеки.
              Text(
                formatSpanShort(task.ageMs),
                maxLines: 1,
                softWrap: false,
                style: AppText.chip.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: staleAgeColour(task),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          StaleSpanBar(task: task, scaleMs: scaleMs),
        ],
      ),
    );
  }
}

/// Каким цветом написан возраст висящей задачи.
///
/// ## Правило, которого нет в макете буквой
///
/// На эталоне три строки из четырёх написаны тёплым `#8A5A0B`, а четвёртая —
/// серым, и отличается она ровно тем, что у неё есть синий сегмент: её держат в
/// руках. Отсюда правило: возраст — это жалоба, пока задачу никто не взял;
/// задача в наборе «в работе» висит столько же дней, но это уже не претензия к
/// ней, а просто факт. Молодая задача (меньше [kStaleAfterDays]) тоже пишется
/// серым — так же, как плашка возраста проекта в планировании (тот же
/// [isStaleAge], то же число дней).
Color staleAgeColour(StaleTask task, {bool onWide = false}) {
  final quiet = onWide ? AppColors.ink : AppColors.muted;
  if (task.focusedAt != null) return quiet;

  final days = task.ageMs ~/ Duration.millisecondsPerDay;
  return isStaleAge(days) ? AppColors.waitingInk : quiet;
}

/// Одна строка «движения по проектам»: сколько открыто и сколько закрыто.
///
/// ## Почему здесь проекты, а не список закрытых задач
///
/// На эталоне телефона нижний блок — это названия закрытых задач с днём недели.
/// `GET /history` их не отдаёт и отдавать не собирается: он считает **события**,
/// и у события закрытия есть проект, но нет заголовка задачи (см. выборку в
/// `backend/src/routes/history.ts`). Достать заголовки можно было бы только
/// вторым запросом за всеми задачами всех проектов — то есть скачав доску
/// целиком ради подписи к трём строкам. Блок «движение по проектам» с широкого
/// эталона отвечает на тот же вопрос («куда ушла работа») из данных, которые
/// уже пришли.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project});

  final ProjectMovement project;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Expanded(
              child: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.action,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _movementLine(project),
              maxLines: 1,
              softWrap: false,
              style: AppText.caption.copyWith(fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SpanBar(
          height: 12,
          segments: <SpanSegment>[
            SpanSegment(project.closed, AppColors.done),
            SpanSegment(project.opened, AppColors.lineStrong),
          ],
        ),
      ],
    );
  }
}

String _movementLine(ProjectMovement project) {
  final parts = <String>[
    if (project.opened > 0) '${project.opened} открыто',
    if (project.closed > 0) '${project.closed} закрыто',
  ];
  return parts.join(' · ');
}

// --- широкое окно ----------------------------------------------------------

/// `Desk-History.html`: три числа сверху, долгожители и проекты снизу.
class _WideBody extends StatelessWidget {
  const _WideBody({required this.data, this.failure});

  final HistorySnapshot data;
  final Object? failure;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      children: <Widget>[
        if (failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _StaleBanner(error: failure!, margin: EdgeInsets.zero),
          ),

        const Align(alignment: Alignment.centerRight, child: _RangeSegments()),
        const SizedBox(height: 18),

        if (data.isEmpty)
          const _EmptyCard(margin: EdgeInsets.zero)
        else ...<Widget>[
          // 176 px — высота ряда на эталоне, и она здесь нижняя граница, а не
          // точное число: при увеличенном системном кегле подпись в две строки
          // становится тремя, и жёсткая высота обрезала бы её вместо того,
          // чтобы подвинуть ряд ниже.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 176),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: _WideClosedCard(data: data)),
                  const SizedBox(width: 18),
                  SizedBox(width: 260, child: _WideAverageCard(data: data)),
                  const SizedBox(width: 18),
                  SizedBox(width: 260, child: _WideHangingCard(data: data)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _WideStaleCard(data: data)),
              const SizedBox(width: 18),
              SizedBox(width: 400, child: _WideProjectsCard(data: data)),
            ],
          ),
        ],
      ],
    );
  }
}

class _WideClosedCard extends StatelessWidget {
  const _WideClosedCard({required this.data});

  final HistorySnapshot data;

  @override
  Widget build(BuildContext context) {
    return _Card(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (data.closedTotal == 0)
            Flexible(
              child: Text(
                'Ни одной закрытой задачи ${data.range.caption}.',
                style: AppText.body,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${data.closedTotal}',
                  style: AppText.number.copyWith(
                    fontSize: 52,
                    height: 1,
                    color: AppColors.done,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'закрыто ${data.range.caption}',
                  style: AppText.caption.copyWith(
                    fontSize: 14,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          const SizedBox(width: 28),
          Expanded(
            child: SizedBox(
              height: 112,
              child: ClosedByDayBars(
                days: data.closedByDay,
                areaHeight: 93,
                unit: 17,
                gap: 10,
                radius: 7,
                labelSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Столько в среднем висит открытая задача».
///
/// ## Почему это не «средняя жизнь закрытой задачи», как на эталоне
///
/// Потому что её неоткуда взять. `GET /history` считает закрытия **событиями**:
/// сколько и когда. Сколько каждая из них прожила до закрытия, знает только
/// журнал самих этих задач, а его роут отдаёт по одной задаче за раз — то есть
/// «средняя жизнь закрытой» стоила бы запроса на задачу. Среднее по открытым
/// считается из того, что уже пришло, и отвечает на соседний и более полезный
/// вопрос: не «как быстро мы закрываем», а «насколько всё залежалось».
class _WideAverageCard extends StatelessWidget {
  const _WideAverageCard({required this.data});

  final HistorySnapshot data;

  @override
  Widget build(BuildContext context) {
    if (data.stale.isEmpty) {
      return _Card(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text('Открытых задач нет', style: AppText.body),
        ),
      );
    }

    var total = 0;
    for (final task in data.stale) {
      total += task.ageMs;
    }
    final averageDays = total / data.stale.length / Duration.millisecondsPerDay;

    return _Card(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Text.rich(
            TextSpan(
              text: averageDays.toStringAsFixed(1).replaceAll('.', ','),
              children: const <InlineSpan>[
                TextSpan(text: ' д', style: TextStyle(fontSize: 22)),
              ],
            ),
            style: AppText.number.copyWith(fontSize: 52, height: 1),
          ),
          const SizedBox(height: 10),
          Text(
            'столько в среднем висит открытая задача',
            style: AppText.caption.copyWith(
              fontSize: 14,
              height: 1.35,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// «Висят дольше недели — их и стоит переформулировать».
class _WideHangingCard extends StatelessWidget {
  const _WideHangingCard({required this.data});

  final HistorySnapshot data;

  /// Неделя: первый срок, который пережил выходные и ещё одну планёрку.
  static const int _hangingDays = 7;

  @override
  Widget build(BuildContext context) {
    var count = 0;
    for (final task in data.stale) {
      if (task.ageMs ~/ Duration.millisecondsPerDay >= _hangingDays) count++;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.waitingFill,
        border: Border.all(color: AppColors.waitingLine),
        borderRadius: BorderRadius.circular(_kHistoryCard),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Text(
            '$count',
            style: AppText.number.copyWith(
              fontSize: 52,
              height: 1,
              color: AppColors.waitingInk,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            count == 0
                ? 'задач старше недели нет'
                : 'висят дольше недели — их и стоит переформулировать',
            style: AppText.caption.copyWith(
              fontSize: 14,
              height: 1.35,
              color: _kWarmDeepInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _WideStaleCard extends StatelessWidget {
  const _WideStaleCard({required this.data});

  final HistorySnapshot data;

  @override
  Widget build(BuildContext context) {
    final stale = data.stale.take(8).toList(growable: false);

    return _Card(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          HistoryHeading(
            label: 'Висит дольше всего',
            trailing: const PhaseLegend(
              phases: <TaskLifePhase>[
                TaskLifePhase.queued,
                TaskLifePhase.working,
                TaskLifePhase.blocked,
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (stale.isEmpty)
            Text('Открытых задач нет', style: AppText.body)
          else
            for (final task in stale) ...<Widget>[
              if (task != stale.first) const SizedBox(height: 18),
              _WideStaleRow(task: task, scaleMs: data.oldestAgeMs),
            ],
        ],
      ),
    );
  }
}

class _WideStaleRow extends StatelessWidget {
  const _WideStaleRow({required this.task, required this.scaleMs});

  final StaleTask task;
  final int scaleMs;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AppRoutes.openTask(
        context,
        projectId: task.projectId,
        taskId: task.id,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.taskTitle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                task.projectName,
                maxLines: 1,
                softWrap: false,
                style: AppText.caption.copyWith(fontSize: 12.5),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: Text(
                  formatSpanShort(task.ageMs),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  softWrap: false,
                  style: AppText.chip.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: staleAgeColour(task, onWide: true),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StaleSpanBar(task: task, scaleMs: scaleMs, height: 10),
        ],
      ),
    );
  }
}

class _WideProjectsCard extends StatelessWidget {
  const _WideProjectsCard({required this.data});

  final HistorySnapshot data;

  @override
  Widget build(BuildContext context) {
    return _Card(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HistoryHeading(label: 'Движение по проектам'),
          const SizedBox(height: 20),
          if (data.projects.isEmpty)
            Text(
              'Ни в одном проекте ничего не открывали и не закрывали '
              '${data.range.caption}.',
              style: AppText.body,
            )
          else
            for (final project in data.projects) ...<Widget>[
              if (project != data.projects.first) const SizedBox(height: 16),
              _ProjectRow(project: project),
            ],
        ],
      ),
    );
  }
}

// --- общие куски -----------------------------------------------------------

/// Карточка режима: белая, с линией по краю и скруглением 22.
class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(
      Insets.gutter,
      10,
      Insets.gutter,
      0,
    ),
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  });

  final Widget child;
  final EdgeInsets margin;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(_kHistoryCard),
      ),
      child: child,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: HistoryHeading(label: label),
    );
  }
}

/// «Тут ещё ничего не происходило» — и почему это может быть правдой.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    this.margin = const EdgeInsets.fromLTRB(
      Insets.gutter,
      4,
      Insets.gutter,
      0,
    ),
  });

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return _Card(
      margin: margin,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bar_chart, size: 22, color: AppColors.lineStrong),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Итогов пока нет', style: AppText.projectName),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'За выбранный период ничего не закрывали и не заводили, и ни одна '
            'задача не висит. Если так быть не должно — журнал переходов '
            'ведётся с сентября, и всё, что случилось раньше, в него не '
            'попало.',
            style: AppText.hint,
          ),
        ],
      ),
    );
  }
}

/// Переключатель диапазона на телефоне: одна кнопка-таблетка с меню.
///
/// Меню, а не три кнопки в ряд: на 390 px три подписи («7 дней», «30 дней»,
/// «всё время») либо не помещаются рядом с заголовком, либо съезжают до
/// нечитаемого кегля. На эталоне телефона это ровно такая же таблетка с
/// уголком.
class _RangePill extends ConsumerWidget {
  const _RangePill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(historyRangeChoiceProvider);

    return PopupMenuButton<HistoryRange>(
      tooltip: 'За какой срок',
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          ref.read(historyRangeChoiceProvider.notifier).select(value),
      itemBuilder: (_) => <PopupMenuEntry<HistoryRange>>[
        for (final value in HistoryRange.values)
          PopupMenuItem<HistoryRange>(value: value, child: Text(value.label)),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.lineStrong),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              range.label,
              style: AppText.action.copyWith(
                fontSize: 14,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 15,
              color: AppColors.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

/// Переключатель диапазона на широком экране: три кнопки в жёлобе.
class _RangeSegments extends ConsumerWidget {
  const _RangeSegments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(historyRangeChoiceProvider);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final value in HistoryRange.values) ...<Widget>[
            if (value != HistoryRange.values.first) const SizedBox(width: 6),
            Semantics(
              button: true,
              selected: value == range,
              child: Material(
                color: value == range ? AppColors.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => ref
                      .read(historyRangeChoiceProvider.notifier)
                      .select(value),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    child: Text(
                      value.label,
                      style: AppText.action.copyWith(
                        fontSize: 14,
                        color: value == range
                            ? AppColors.onInk
                            : AppColors.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «Не удалось обновить» поверх чисел, которые уже на экране.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({
    required this.error,
    this.margin = const EdgeInsets.fromLTRB(
      Insets.gutter,
      0,
      Insets.gutter,
      10,
    ),
  });

  final Object error;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.waitingFill,
        border: Border.all(color: AppColors.waitingLine),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 18, color: AppColors.waitingInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Не удалось обновить: ${describeApiError(error)}',
              style: AppText.hint.copyWith(color: AppColors.waitingInk),
            ),
          ),
          const _RetryButton(),
        ],
      ),
    );
  }
}

class _RetryButton extends ConsumerWidget {
  const _RetryButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => ref.read(historyFeedProvider.notifier).refresh(),
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Повторить'),
    );
  }
}

/// Экран без данных, который всё ещё тянется жестом обновления.
class _Filler extends StatelessWidget {
  const _Filler({
    required this.title,
    required this.body,
    this.icon,
    this.action,
  });

  /// Null рисует индикатор — состояние загрузки.
  final IconData? icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon == null)
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  else
                    Icon(icon, size: 40, color: AppColors.muted),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppText.projectName,
                  ),
                  const SizedBox(height: 8),
                  Text(body, textAlign: TextAlign.center, style: AppText.hint),
                  if (action != null) ...<Widget>[
                    const SizedBox(height: 12),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
