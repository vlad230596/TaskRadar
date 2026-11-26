import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../models/focus_task.dart';
import '../models/task_status.dart';
import '../navigation/app_routes.dart';
import '../domain/goals.dart';
import '../models/goal.dart';
import '../providers/focus_providers.dart';
import '../providers/goal_providers.dart';
import '../providers/shell_providers.dart';
import '../providers/today_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/glance.dart';
import '../widgets/goals/contour_switcher.dart';
import '../widgets/goals/crown.dart';
import '../widgets/goals/goal_block.dart';
import '../widgets/goals/goal_icons.dart';
import '../widgets/mode_navigation.dart';
import '../widgets/mode_title.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/today/day_block.dart';
import '../widgets/today/next_sheet.dart';
import 'pick_screen.dart';
import 'shell_screen.dart';
import '../storage/read_cache_store.dart';
import '../widgets/local_copy_note.dart';

/// Режим работы: две-пять задач, которые действительно в руках, и одна из них
/// крупно (F13).
///
/// ## Что этот режим показывает и почему именно так
///
/// Эталон — `design/reference/Focus.html`: одна задача кеглем 27, кнопка
/// «Сделано» высотой 68 и следом остальные задачи набора, у каждой — имя
/// проекта. Всё остальное спрятано, и это и есть «экономия мыслетоплива»: на
/// экране только то, чем можно заняться прямо сейчас.
///
/// ## Крупно — первая задача, которая не блокер
///
/// Набор упорядочен сервером (`focusedAt` по возрастанию), и крупно показывается
/// первая его строка — **кроме** случая, когда она в блокере. Блокер намеренно
/// не выводит задачу из набора (`backend/src/domain/taskEvents.ts`: ждать кабель
/// — это тоже работа над задачей), но показывать крупно то, чего сейчас сделать
/// нельзя, — значит занять единственный крупный слот экрана тем, о чём решение
/// уже принято. Если блокеры вообще все, крупно идёт первая: пустой экран при
/// непустом наборе врал бы сильнее.
///
/// ## Чего здесь нет по сравнению с эталоном
///
/// Кнопки «Блокер». Она требует продолжения — даты напоминания, — потому что
/// блокер без даты никогда больше о себе не напомнит; всё это уже живёт на
/// экране задачи, куда ведёт «Правка». Вместо неё в паре с «Правкой» стоит
/// «Убрать» — действие, которого в эталоне не было видно вовсе, а без него из
/// набора нельзя выйти иначе как через экран сбора.
class WorkScreen extends ConsumerWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The active contour's set (`design/goals-ideas-contract.md`: each
    // contour keeps its own); every set at once while contours are unknown.
    final set = ref.watch(activeFocusSetProvider);
    final blockSteps = watchGoalBlockStepIds(ref);
    final todayIds = watchTodayIds(ref);
    final goalsHeader = isWideLayout(context)
        ? const Padding(
            padding: EdgeInsets.fromLTRB(40, 0, 40, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                WorkGoalsStrip(),
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 400, child: DayBlock(wide: true)),
                ),
              ],
            ),
          )
        : const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[WorkGoals(), DayBlock()],
          );

    final Widget body = switch (set) {
      AsyncData(:final value) when value.isEmpty => _NoSet(
        header: goalsHeader,
      ),
      // Everything in the set is a goal step or in «Сегодня»: it is in work
      // up there, and the list under it has nothing of its own.
      AsyncData(:final value)
          when shownOnWorkList(value, blockSteps, todayIds: todayIds).isEmpty =>
        _OnlyGoalSteps(
          header: goalsHeader,
          inToday: value.any((task) => todayIds.contains(task.id)),
        ),
      AsyncData(:final value) => _Set(
        tasks: shownOnWorkList(value, blockSteps, todayIds: todayIds),
      ),
      AsyncError(:final error) => _Failed(error: error),
      _ => const _Filler(
        title: 'Загружаем набор…',
        body:
            'Набор живёт на сервере — его собирают за столом, а '
            'отрабатывают отсюда.',
      ),
    };

    return Column(
      children: <Widget>[
        // Offline (or a server that does not answer), the set on screen is
        // the copy saved on the last good read -- and says so.
        const LocalCopyNote(cacheKey: ReadCacheKeys.focus),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              unawaited(ref.read(goalsProvider.notifier).syncQuietly());
              await ref.read(focusSetProvider.notifier).refresh();
            },
            child: body,
          ),
        ),
      ],
    );
  }
}

/// Шапка режима работы: название, точки набора и кнопка «Набор».
///
/// В эталоне (`design/reference/Focus.html`) точки и кнопка стоят в одной
/// строке с названием режима, а не отдельной полосой под ним. Шапку режима
/// рисует оболочка, поэтому она и приходит оттуда — как `PlanHeader` у режима
/// планирования.
class WorkHeader extends ConsumerWidget {
  const WorkHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref.watch(activeFocusSetProvider).value ?? const <FocusTask>[];
    // The dots count the whole set (the rule of five is about the set), and
    // the current one is the big card -- which is never a goal step.
    final shown = shownOnWorkList(
      tasks,
      watchGoalBlockStepIds(ref),
      todayIds: watchTodayIds(ref),
    );
    final current = shown.isEmpty ? null : _headOf(shown).id;
    final wide = isWideLayout(context);
    final switcher = showContourSwitcher(ref);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 18, Insets.gutter, 12),
      child: Row(
        children: <Widget>[
          // Название и точки набора делят то, что осталось от кнопок справа;
          // не влезает — сжимается название, а не переносится посреди слова.
          // Название берёт свою ширину первым, точки — то, что осталось:
          // поровну они делили место, и на узком телефоне с крупным шрифтом
          // название сжималось до мелкого шрифта ради одной точки.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final title = measureTextWidth(
                  context,
                  AppMode.work.title,
                  AppText.mode,
                );
                final room =
                    box.maxWidth - title - 12 - (wide && switcher ? 200 : 0);
                final row = Row(
                  children: <Widget>[
                    Flexible(child: ModeTitle(AppMode.work.title)),
                    // Desktop: the contour pill beside the mode's name.
                    if (wide && switcher) ...<Widget>[
                      const SizedBox(width: 16),
                      const ContourSwitcher(wide: true),
                    ],
                    // Пустой набор не рисует ряд пустых слотов: точки
                    // описывают набор, а его пока нет, и об этом говорит само
                    // тело экрана.
                    if (tasks.isNotEmpty && room > 0) ...<Widget>[
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: room),
                        child: FocusSlots(
                          taken: tasks.length,
                          current: current == null
                              ? null
                              : tasks.indexWhere(
                                  (task) => task.id == current,
                                ),
                          size: wide ? 12 : 11,
                          gap: wide ? 7 : 6,
                        ),
                      ),
                    ],
                  ],
                );
                // Phone: the contour pill under the mode's name.
                if (wide || !switcher) return row;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    row,
                    const SizedBox(height: 6),
                    const ContourSwitcher(),
                  ],
                );
              },
            ),
          ),
          _PickButton(empty: tasks.isEmpty),
          const ShellOverflowButton(),
        ],
      ),
    );
  }
}

/// «Набор» — кнопка-контур, которая ведёт на экран сбора.
class _PickButton extends StatelessWidget {
  const _PickButton({required this.empty});

  /// Пустой набор называет её по делу: собрать, а не пересобрать.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);

    return SizedBox(
      height: wide ? Targets.minimum : 36,
      child: OutlinedButton.icon(
        onPressed: () => openPickScreen(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkSoft,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: AppColors.lineStrong),
          padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 14),
          textStyle: wide
              ? AppText.action
              : AppText.chip.copyWith(fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(wide ? Radii.card : 18),
          ),
        ),
        icon: Icon(Icons.format_list_bulleted, size: wide ? 18 : 15),
        label: Text(empty ? 'Собрать' : 'Набор'),
      ),
    );
  }
}

/// Набор точками. Две роли, и обе есть на эталонных страницах.
///
/// - **Где я в наборе** ([current] задан, `Focus.html`): по точке на задачу,
///   чернилами — та, что сейчас крупно, остальные серые. Отвечает на «сколько
///   ещё после этой».
/// - **Сколько слотов занято** ([showFree], `Pick.html`): пять точек, занятые
///   чернилами, свободные контуром. Отвечает на «сколько ещё можно взять».
///
/// Один виджет, потому что это один и тот же ряд точек об одном и том же
/// наборе; две копии разошлись бы в размере на первой же правке.
class FocusSlots extends StatelessWidget {
  const FocusSlots({
    required this.taken,
    this.current,
    this.size = 12,
    this.gap = 6,
    this.showFree = false,
    super.key,
  });

  final int taken;

  /// Какая из точек сейчас крупная задача, если это вопрос экрана.
  final int? current;

  final double size;
  final double gap;
  final bool showFree;

  @override
  Widget build(BuildContext context) {
    // Набор из шести (его можно собрать curl-ом — предела на сервере нет)
    // рисует шесть точек, а не пять: слоты описывают набор, а не наоборот.
    final total = showFree
        ? (taken > kFocusSlots ? taken : kFocusSlots)
        : taken;

    final more = AppText.chip.copyWith(color: AppColors.muted);

    return Semantics(
      label: current == null
          ? 'В наборе $taken из $kFocusSlots'
          : 'Задача ${current! + 1} из $taken',
      // Сколько влезает, столько и точек, остальное — «+N». Предела на сервере
      // нет, и набор из шестнадцати рисовал шестнадцать точек поверх кнопки
      // «Набор» и за край экрана.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fit = fitDots(
            count: total,
            cap: total,
            pitch: size + gap,
            // The last dot has no gap after it.
            width: constraints.maxWidth + gap,
            moreWidth: measureTextWidth(context, '+$total', more) + gap,
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < fit.shown; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == fit.shown - 1 && !fit.more ? 0 : gap,
                  ),
                  child: _slot(i),
                ),
              if (fit.more)
                Flexible(
                  child: Text(
                    '+${total - fit.shown}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: more,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _slot(int i) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch ((i < taken, i == current, current == null)) {
        // Занятый слот на экране сбора.
        (true, _, true) => AppColors.ink,
        // Та самая задача — и остальные задачи набора.
        (_, true, false) => AppColors.ink,
        (true, false, false) => AppColors.lineStrong,
        // Свободный слот.
        _ => Colors.transparent,
      },
      border: i < taken
          ? null
          : Border.all(color: AppColors.lineStrong, width: 2),
    ),
  );
}

/// Набор, который есть: одна задача крупно и остальные следом.
class _Set extends StatelessWidget {
  const _Set({required this.tasks});

  final List<FocusTask> tasks;

  @override
  Widget build(BuildContext context) {
    final head = _headOf(tasks);
    final rest = <FocusTask>[
      for (final task in tasks)
        if (task.id != head.id) task,
    ];

    if (isWideLayout(context)) return _WideSet(head: head, rest: rest);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        const WorkGoals(),
        const DayBlock(),
        _HeadCard(task: head),
        if (rest.isNotEmpty) ...<Widget>[
          const _NextLabel(),
          for (final task in rest)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.gutter,
                Insets.gap,
                Insets.gutter,
                0,
              ),
              child: _NextRow(task: task),
            ),
        ],
      ],
    );
  }
}

/// Десктоп: крупная задача во всю левую половину, набор — колонкой справа
/// (`design/reference/Desk-Focus.html`).
///
/// Правая колонка эталона несёт ещё заметки проекта и «закрыто сегодня». Первое
/// — чужой экран (заметки грузятся отдельным запросом на проект), второе
/// считается по журналу задач, то есть по данным режима истории. Обоего здесь
/// нет намеренно: половина панели, заполненная правдоподобным нулём, хуже, чем
/// её отсутствие.
class _WideSet extends StatelessWidget {
  const _WideSet({required this.head, required this.rest});

  final FocusTask head;
  final List<FocusTask> rest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The goals as a strip of cards above the big task
          // (`Desk-Focus-Goals.html`).
          const WorkGoalsStrip(),
          Expanded(
            child: _WideRow(head: head, rest: rest),
          ),
        ],
      ),
    );
  }
}

class _WideRow extends StatelessWidget {
  const _WideRow({required this.head, required this.rest});

  final FocusTask head;
  final List<FocusTask> rest;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The day column (`Desk-Focus-Today.html`): the tail, then
        // «Сегодня», scrolling on its own.
        SizedBox(
          width: 400,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: const <Widget>[DayBlock(wide: true)],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: _HeadCard(task: head, wide: true)),
        const SizedBox(width: 24),
        SizedBox(
          width: 320,
          child: ListView(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 0, 16),
                child: Text('ДАЛЬШЕ В НАБОРЕ', style: AppText.sectionLabel),
              ),
              for (final task in rest)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _NextRow(task: task, wide: true),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Та самая одна задача: чип проекта, текст кеглем 27 и «Сделано» высотой 68.
class _HeadCard extends ConsumerWidget {
  const _HeadCard({required this.task, this.wide = false});

  final FocusTask task;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = task.status == TaskStatus.blocked;
    final goals = watchTaskGoals(ref, task.id, task.goals);
    final since = Text(
      blocked ? 'ждёт' : focusedSince(task.focusedAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _meta.copyWith(
        color: blocked ? AppColors.waitingInk : AppColors.muted,
      ),
    );

    return Container(
      margin: wide
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(Insets.gutter, 6, Insets.gutter, 0),
      padding: wide
          ? const EdgeInsets.fromLTRB(36, 36, 36, 32)
          : const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(wide ? 28 : 26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (goals.isNotEmpty) ...<Widget>[
            // With a goal chip the time goes under the chips on a phone (it
            // never fits beside both at 390), beside them on a desktop.
            Row(
              children: <Widget>[
                _ProjectChip(name: task.project.name, wide: wide),
                const SizedBox(width: 8),
                Flexible(
                  child: _GoalChip(
                    goals: goals,
                    activeContourId: ref.watch(activeContourIdProvider),
                  ),
                ),
                if (wide) ...<Widget>[
                  const SizedBox(width: 12),
                  Flexible(child: since),
                ],
              ],
            ),
            if (!wide) ...<Widget>[const SizedBox(height: 8), since],
          ] else
            Row(
              children: <Widget>[
                _ProjectChip(name: task.project.name, wide: wide),
                const SizedBox(width: 12),
                // Подпись у правого края, как в эталоне: чип отвечает «откуда
                // задача», подпись — «с какого времени», и между ними воздух.
                Expanded(
                  child: Align(
                    // На десктопе эталон ставит подпись сразу за чипом: там
                    // карточка шириной в тысячу пикселей, и у правого края
                    // подпись оказалась бы в другом конце экрана от того, что
                    // описывает.
                    alignment: wide
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Text(
                      blocked ? 'ждёт' : focusedSince(task.focusedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _meta.copyWith(
                        color: blocked ? AppColors.waitingInk : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          SizedBox(height: wide ? 28 : 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 620 : double.infinity),
            child: Text(task.title, style: wide ? _titleWide : _title),
          ),
          if (wide) const Spacer() else const SizedBox(height: 22),
          if (wide)
            // A wrap: with the day column beside it (`Desk-Focus-Today.html`)
            // the card is narrower than the three buttons on a 1440 window.
            Wrap(
              spacing: 14,
              runSpacing: 12,
              children: <Widget>[
                _DoneButton(task: task, wide: true),
                _SecondaryButton(
                  icon: Icons.remove_circle_outline,
                  label: 'Убрать',
                  wide: true,
                  onPressed: () => _drop(context, ref, task),
                ),
                _SecondaryButton(
                  icon: Icons.edit_outlined,
                  label: 'Правка',
                  wide: true,
                  onPressed: () => _open(context, task),
                ),
              ],
            )
          else ...<Widget>[
            _DoneButton(task: task),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SecondaryButton(
                    icon: Icons.remove_circle_outline,
                    label: 'Убрать',
                    onPressed: () => _drop(context, ref, task),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SecondaryButton(
                    icon: Icons.edit_outlined,
                    label: 'Правка',
                    onPressed: () => _open(context, task),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// «Сделано»: 68 px на телефоне, 76 на десктопе, и это самая большая мишень
/// экрана — по ней попадают не глядя.
class _DoneButton extends ConsumerWidget {
  const _DoneButton({required this.task, this.wide = false});

  final FocusTask task;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final button = FilledButton.icon(
      onPressed: () => unawaited(completeFocusTask(context, ref, task)),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.done,
        foregroundColor: AppColors.onInk,
        minimumSize: Size(0, wide ? 76 : 68),
        padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20),
        textStyle: wide ? _doneLabelWide : _doneLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(wide ? Radii.large : 22),
        ),
      ),
      icon: const Icon(Icons.check, size: 26),
      label: const Text('Сделано'),
    );

    return wide ? button : SizedBox(width: double.infinity, child: button);
  }
}

/// «Убрать» и «Правка» — одинаковые по весу и намеренно спокойные: рядом с
/// зелёной кнопкой высотой 68 второй акцент означал бы, что выбор из двух.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.inkSoft,
        backgroundColor: AppColors.card,
        side: const BorderSide(color: AppColors.line),
        minimumSize: Size(0, wide ? 76 : 52),
        padding: EdgeInsets.symmetric(horizontal: wide ? 26 : 12),
        textStyle: wide
            ? AppText.action.copyWith(fontSize: 16)
            : _secondaryLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(wide ? Radii.large : 18),
        ),
      ),
      icon: Icon(icon, size: wide ? 20 : 19),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Чип проекта: единственное место на экране, где сказано, откуда задача.
class _ProjectChip extends StatelessWidget {
  const _ProjectChip({required this.name, this.wide = false});

  final String name;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    // Без `alignment` и без фиксированной высоты: Container с выравниванием
    // растягивается на все доступные ограничения, и чип превращается в полосу
    // на пол-экрана. Высоту (28/32) даёт вертикальный отступ вокруг текста.
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 14 : 12,
        vertical: wide ? 7 : 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.indigoFill,
        borderRadius: BorderRadius.circular(wide ? 16 : 14),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _chipProject.copyWith(fontSize: wide ? 14 : 13),
      ),
    );
  }
}

/// The goal chip of the big card: 28 high, the first bright goal's name in
/// white on `#14183C` with the crown, «+1» for more.
class _GoalChip extends StatelessWidget {
  const _GoalChip({required this.goals, required this.activeContourId});

  final List<TaskGoalRef> goals;
  final String? activeContourId;

  @override
  Widget build(BuildContext context) {
    final bright = <TaskGoalRef>[
      for (final goal in goals)
        if (activeContourId == null || goal.contourId == activeContourId) goal,
    ];
    final lead = bright.isNotEmpty ? bright.first : goals.first;
    final lit = bright.isNotEmpty;
    return Container(
      height: 28,
      padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
      decoration: BoxDecoration(
        color: lit ? AppColors.crownChip : AppColors.crownMutedChip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CrownIcon(
            size: 13,
            color: lit ? AppColors.crown : AppColors.crownMuted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                lead.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: lit ? AppColors.onInk : AppColors.inkSoft,
                ),
              ),
            ),
          ),
          if (goals.length > 1)
            Text(
              ' +${goals.length - 1}',
              style: const TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.voiceMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _NextLabel extends StatelessWidget {
  const _NextLabel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(Insets.gutter, 20, Insets.gutter, 0),
      child: Row(
        children: <Widget>[
          Text('ДАЛЬШЕ', style: AppText.sectionLabel),
          SizedBox(width: 8),
          Expanded(child: Divider(color: AppColors.line, height: 1)),
        ],
      ),
    );
  }
}

/// Остальные задачи набора: кружок — «сделано», текст — открыть, крестик —
/// убрать из набора.
class _NextRow extends ConsumerWidget {
  const _NextRow({required this.task, this.wide = false});

  final FocusTask task;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = task.status == TaskStatus.blocked;
    final crown = watchCrown(ref, task.id, task.goals);

    return Container(
      decoration: BoxDecoration(
        color: blocked ? AppColors.waitingFill : AppColors.card,
        border: Border.all(
          color: blocked ? AppColors.waitingLine : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(wide ? Radii.panel : 18),
      ),
      padding: EdgeInsets.all(wide ? 4 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Tooltip(
            message: blocked
                ? 'Блокер — отметить сделанной'
                : 'Отметить сделанной',
            child: InkWell(
              onTap: () => unawaited(completeFocusTask(context, ref, task)),
              child: SizedBox(
                width: Targets.minimum,
                height: Targets.minimum,
                child: Center(
                  child: blocked
                      ? const Icon(
                          Icons.pause_circle_outline,
                          size: 26,
                          color: AppColors.waitingInk,
                        )
                      : Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.lineStrong,
                              width: 2,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _open(context, task),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: wide ? 14 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      task.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: wide ? _nextTitleWide : _nextTitle,
                    ),
                    SizedBox(height: wide ? 8 : 5),
                    Row(
                      children: <Widget>[
                        // `[♛] TaskRadar`: the crown before the project.
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
                            task.project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Убрать из набора',
            child: InkWell(
              onTap: () => _drop(context, ref, task),
              child: const SizedBox(
                width: Targets.minimum,
                height: Targets.minimum,
                child: Icon(Icons.close, size: 18, color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Пустой набор: честное состояние с одной кнопкой.
///
/// Не «здесь пока ничего нет», а «наберите» — пустой набор это не поломка и не
/// ожидание данных, это ровно то состояние, из которого начинается день.
class _NoSet extends StatelessWidget {
  const _NoSet({this.header});

  /// The goals above the empty set: an empty set is exactly when a goal's
  /// step is the thing to take.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return _Filler(
      header: header,
      icon: Icons.adjust,
      title: 'Набор пуст',
      body:
          'Режим работы показывает 2–5 задач, взятых в работу: одну крупно, '
          'остальные следом. Наберите их — на экране проектов или сразу здесь.',
      action: SizedBox(
        height: Targets.row,
        child: FilledButton.icon(
          onPressed: () => openPickScreen(context),
          icon: const Icon(Icons.playlist_add_check, size: 20),
          label: const Text('Собрать набор'),
        ),
      ),
    );
  }
}

/// The set holds only steps of the goal block: they are in work up in the
/// block, and the list has nothing else -- not «Набор пуст», which would be
/// untrue.
class _OnlyGoalSteps extends StatelessWidget {
  const _OnlyGoalSteps({required this.header, this.inToday = false});

  final Widget header;

  /// Some of the set is dated today and shown in «Сегодня» (coordinator,
  /// answer 2), not only goal steps.
  final bool inToday;

  @override
  Widget build(BuildContext context) {
    return _Filler(
      header: header,
      icon: Icons.adjust,
      title: inToday ? 'Набор — выше' : 'В работе — шаги целей',
      body: inToday
          ? 'Задачи набора с датой на сегодня — в «Сегодня», шаги целей — '
                'в блоке целей. Кроме них в наборе ничего нет.'
          : 'Они в блоке целей выше. Кроме них в наборе ничего нет — '
                'добавьте задачи на экране проектов или сразу здесь.',
      action: SizedBox(
        height: Targets.row,
        child: OutlinedButton.icon(
          onPressed: () => openPickScreen(context),
          icon: const Icon(Icons.playlist_add_check, size: 20),
          label: const Text('Набор'),
        ),
      ),
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Filler(
      icon: Icons.cloud_off,
      title: 'Не удалось загрузить набор',
      body:
          '${describeApiError(error)}\n\nНабор живёт на сервере и локального '
          'снимка у него нет — показать нечего.',
      action: TextButton.icon(
        onPressed: () => ref.read(focusSetProvider.notifier).refresh(),
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Повторить'),
      ),
    );
  }
}

/// Открыть экран сбора набора.
Future<void> openPickScreen(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      // Полноэкранный диалог, а не обычный push: сбор — это то, откуда
      // возвращаются с ответом, а не место, вглубь которого идут. Крестик в
      // шапке (эталон) и жест «вниз» означают одно и то же.
      fullscreenDialog: true,
      builder: (_) => const PickScreen(),
    ),
  );
}

void _open(BuildContext context, FocusTask task) {
  unawaited(
    AppRoutes.openTask(context, projectId: task.projectId, taskId: task.id),
  );
}

void _drop(BuildContext context, WidgetRef ref, FocusTask task) {
  unawaited(
    runMutation(
      context,
      () => ref.read(focusSetProvider.notifier).drop(task.id),
      failure: 'Не удалось убрать задачу из набора.',
    ),
  );
}

/// The ids of the goal steps the block shows (see [goalBlockStepIds]).
Set<String> watchGoalBlockStepIds(WidgetRef ref) => goalBlockStepIds(
  activeContourId: ref.watch(activeContourIdProvider),
  goals: ref.watch(goalListProvider),
);

/// The set as the work screen lists it: without the goal steps of the block.
///
/// A step taken from the goal block is in work *in the block* -- its «в
/// работе» chip is its state there -- and is not listed a second time as the
/// big card or under «Дальше» (owner, 26.11: «задачи из блока … должны
/// уходить в свой статус в блоке и не показываться на общем экране в
/// работе»). Once the step is done or blocked it stops being the goal's next
/// step and, if still in the set, comes back to the list.
///
/// The same for a task of the set dated today (coordinator, answer 2 -- the
/// owner's): it is shown only in «Сегодня», with the «в работе» dot.
List<FocusTask> shownOnWorkList(
  List<FocusTask> set,
  Set<String> blockStepIds, {
  Set<String> todayIds = const <String>{},
}) {
  if (blockStepIds.isEmpty && todayIds.isEmpty) return set;
  return <FocusTask>[
    for (final task in set)
      if (!blockStepIds.contains(task.id) && !todayIds.contains(task.id)) task,
  ];
}

/// The ids of the open tasks in «Сегодня».
Set<String> watchTodayIds(WidgetRef ref) {
  final view = ref.watch(dayViewProvider);
  if (view == null) return const <String>{};
  return <String>{for (final entry in view.today) entry.id};
}

/// «Сделано» on the big card or a row of «Дальше»: the write, then «Сделано:
/// … · Следом… · Отменить» (spec §4.4). The undo reopens the task and takes
/// it back into the set.
Future<void> completeFocusTask(
  BuildContext context,
  WidgetRef ref,
  FocusTask task,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final ok = await runMutation(
    context,
    () => ref.read(focusSetProvider.notifier).complete(task),
    failure: 'Не удалось отметить задачу сделанной.',
  );
  if (!ok || !context.mounted) return;
  showDoneSnackBar(
    ScaffoldMessenger.of(context),
    title: task.title,
    projectId: task.projectId,
    projectName: task.project.name,
    undo: () async {
      final row = container
          .read(placedBoardTasksProvider)
          ?.where((entry) => entry.id == task.id)
          .firstOrNull;
      if (row == null) return;
      final reopened = row.task.copyWith(status: TaskStatus.done);
      await setDayTaskStatus(container, reopened, task.status);
      await container
          .read(focusSetProvider.notifier)
          .take(
            freshTask(container, reopened).copyWith(status: task.status),
            projectName: task.project.name,
          );
    },
  );
}

/// Первая задача набора, которой можно заняться. См. заметку у [WorkScreen].
FocusTask _headOf(List<FocusTask> tasks) {
  for (final task in tasks) {
    if (task.status != TaskStatus.blocked) return task;
  }
  return tasks.first;
}

/// «в работе с 9:40» — или «в работе с 21.09», если это было не сегодня.
///
/// Час без ведущего нуля, как в эталоне; минуты с ним, иначе 9:5 читается как
/// девять с половиной.
String focusedSince(String iso, {DateTime? now}) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return 'в работе';

  final at = parsed.toLocal();
  final today = (now ?? DateTime.now()).toLocal();

  final sameDay =
      at.year == today.year && at.month == today.month && at.day == today.day;
  if (sameDay) {
    return 'в работе с ${at.hour}:${at.minute.toString().padLeft(2, '0')}';
  }

  return 'в работе с ${at.day.toString().padLeft(2, '0')}.'
      '${at.month.toString().padLeft(2, '0')}';
}

/// Текст по центру, который всё равно прокручивается — иначе «потянуть, чтобы
/// обновить» поверх него не работает.
class _Filler extends StatelessWidget {
  const _Filler({
    required this.title,
    required this.body,
    this.icon,
    this.action,
    this.header,
  });

  /// Drawn at the top, above the centred text.
  final Widget? header;

  /// Null рисует спиннер — состояние загрузки.
  final IconData? icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
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
            Icon(icon, size: 40, color: AppColors.lineStrong),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppText.projectName),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: AppText.hint),
          if (action != null) ...<Widget>[const SizedBox(height: 20), action!],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          // With a header (the goals and the day block) the text follows it
          // rather than being centred: the day block's rows are not sized by
          // intrinsics, and a centred note under a long «Сегодня» would sit
          // off screen anyway.
          child: header == null
              ? Center(child: content)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[header!, Center(child: content)],
                ),
        ),
      ),
    );
  }
}

/// Осталось от F12 ради режима истории, который ещё ждёт своих данных.
class ModeNotYet extends StatelessWidget {
  const ModeNotYet({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) =>
      _Filler(icon: icon, title: title, body: body);
}

// --- кегли, которых нет в теме ---------------------------------------------
//
// Все четыре — числа с эталонных страниц, которых больше нигде в приложении не
// бывает: 27 и 46 — это та самая «одна задача крупно», 19 — подпись на
// единственной кнопке высотой 68. Заводить их в `theme/tokens.dart` значило бы
// поселить в общей теме стиль, у которого ровно одно место применения.

/// Задача крупно на телефоне: 27/600, как в `Focus.html`.
const TextStyle _title = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w600,
  fontSize: 27,
  height: 1.28,
  letterSpacing: -0.27,
  color: AppColors.ink,
);

/// Она же на десктопе: 46/600 (`Desk-Focus.html`).
const TextStyle _titleWide = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w600,
  fontSize: 46,
  height: 1.2,
  letterSpacing: -0.69,
  color: AppColors.ink,
);

const TextStyle _doneLabel = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 19,
);

const TextStyle _doneLabelWide = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 20,
);

const TextStyle _secondaryLabel = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w600,
  fontSize: 15,
);

const TextStyle _chipProject = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w700,
  fontSize: 13,
  color: AppColors.indigoInk,
);

const TextStyle _meta = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w600,
  fontSize: 12.5,
  color: AppColors.muted,
);

const TextStyle _nextTitle = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w500,
  fontSize: 16,
  height: 1.32,
  color: AppColors.ink,
);

const TextStyle _nextTitleWide = TextStyle(
  fontFamily: AppFonts.text,
  fontWeight: FontWeight.w500,
  fontSize: 16.5,
  height: 1.32,
  color: AppColors.ink,
);
