import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/task_age.dart';
import '../models/board_project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../providers/board_providers.dart';
import '../providers/focus_providers.dart';
import '../providers/scope_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/glance.dart';
import '../widgets/mutation_feedback.dart';
import 'work_screen.dart';

/// Сбор набора: что беру в работу (F13).
///
/// Эталон — `design/reference/Pick.html`: чекбоксы по проектам и пять слотов
/// точками в шапке.
///
/// ## Правило пяти — экранное, и ведёт себя как экранное
///
/// Сервер предела не знает и знать не обязан (`backend/src/routes/focus.ts`):
/// пять — это то, что помещается на экран работы и в голову, а не свойство
/// данных. Поэтому шестая задача здесь просто не берётся: экран говорит, что
/// слоты кончились, и предлагает освободить один — и **не** притворяется, будто
/// запрос ушёл и сервер его отверг. Набор из шести, собранный curl-ом, этот
/// экран покажет как шесть занятых слотов, а не как ошибку.
///
/// ## Почему галочка — это сразу запись
///
/// Набор серверный, и другого места, где он живёт, нет. Локальный черновик
/// «отмечено, но не сохранено» добавил бы состояние, которое надо было бы
/// сохранять кнопкой внизу — и терять при любом выходе назад. Вместо этого
/// каждый тап — идемпотентный запрос, оптимистичный на экране, а кнопка внизу
/// просто возвращает к работе.
///
/// ## Что в списке
///
/// Задачи проектов текущего набора проектов (скоупа), кроме закрытых и кроме
/// блокеров. Закрытая задача — уже не работа; блокер — работа, которой сейчас
/// нельзя заняться, а набор отвечает на вопрос «чем займусь». Задача, попавшая в
/// блокер уже **после** того, как её взяли, из набора не выпадает (так решает
/// сервер) — но предлагать взять её отсюда значило бы предлагать взяться за
/// ожидание.
class PickScreen extends ConsumerWidget {
  const PickScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(boardViewProvider);
    final scope = ref.watch(activeScopeProvider);
    final chosen = ref.watch(focusedTaskIdsProvider);

    final projects = view is BoardReady
        ? projectsInScope(view.projects, scope)
        : const <BoardProject>[];

    final body = switch (view) {
      BoardLoading() => const _Message(
        icon: null,
        title: 'Загружаем проекты…',
        body: 'Набор собирается из того, что есть на доске.',
      ),
      BoardUnavailable(:final error) => _Message(
        icon: Icons.cloud_off,
        title: 'Не удалось загрузить проекты',
        body: describeApiError(error),
      ),
      BoardReady() => _Choices(projects: projects, chosen: chosen),
    };

    return Scaffold(
      body: SafeArea(
        // Ограничено по ширине, а не растянуто: строка выбора — это чекбокс,
        // текст и возраст, и на 1440 px возраст уехал бы в полуметре от задачи,
        // к которой относится. Десктопной страницы сбора в эталоне нет — это
        // тот же телефонный экран, поставленный посередине.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PickHeader(taken: chosen.length),
                Expanded(child: body),
                _WorkOnButton(taken: chosen.length),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Шапка: крестик, название и пять слотов.
class _PickHeader extends StatelessWidget {
  const _PickHeader({required this.taken});

  final int taken;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 10, 16, 12),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 22),
            color: AppColors.ink,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Беру в работу',
              style: AppText.screen.copyWith(fontSize: 17),
            ),
          ),
          const SizedBox(width: 8),
          FocusSlots(taken: taken, size: 12, gap: 6, showFree: true),
        ],
      ),
    );
  }
}

/// Проекты, а внутри — задачи с чекбоксами.
class _Choices extends StatelessWidget {
  const _Choices({required this.projects, required this.chosen});

  final List<BoardProject> projects;
  final Set<String> chosen;

  @override
  Widget build(BuildContext context) {
    final sections = <BoardProject>[
      for (final entry in projects)
        if (_pickable(entry.tasks, chosen).isNotEmpty) entry,
    ];

    if (sections.isEmpty) {
      return const _Message(
        icon: Icons.playlist_add_check,
        title: 'Брать нечего',
        body:
            'В проектах этого набора нет открытых задач — или всё, что было, '
            'уже в работе.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 8, Insets.gutter, 8),
      children: <Widget>[
        for (final entry in sections) ...<Widget>[
          _SectionLabel(name: entry.project.name),
          for (final task in _pickable(entry.tasks, chosen))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _TaskChoice(
                task: task,
                projectName: entry.project.name,
                chosen: chosen.contains(task.id),
                taken: chosen.length,
              ),
            ),
        ],
      ],
    );
  }
}

/// Что можно взять: не закрытое и не блокер — плюс то, что уже взято, потому
/// что снять галочку надо уметь с того же экрана, где её поставили.
List<Task> _pickable(List<Task> tasks, Set<String> chosen) => <Task>[
  for (final task in tasks)
    if (chosen.contains(task.id) ||
        (task.status != TaskStatus.done && task.status != TaskStatus.blocked))
      task,
];

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: <Widget>[
          // `flex: 0`, а не обычный `Flexible`: тот делит свободное место
          // поровну с линией справа, и линия выходит вдвое короче, чем на
          // эталонной странице. Так имя берёт ровно свою ширину, а линия — всё
          // остальное.
          Flexible(
            flex: 0,
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.sectionLabel,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: AppColors.line, height: 1)),
        ],
      ),
    );
  }
}

/// Одна строка выбора. Взятая — чернильная, с оранжевой галочкой.
class _TaskChoice extends ConsumerWidget {
  const _TaskChoice({
    required this.task,
    required this.projectName,
    required this.chosen,
    required this.taken,
  });

  final Task task;
  final String projectName;
  final bool chosen;

  /// Сколько задач уже в наборе — чтобы шестая мягко не бралась.
  final int taken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final age = daysSinceMovement(task.updatedAt, createdAt: task.createdAt);

    return Material(
      color: chosen ? AppColors.ink : AppColors.card,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        onTap: () => _toggle(context, ref),
        borderRadius: BorderRadius.circular(Radii.card),
        child: Container(
          constraints: const BoxConstraints(minHeight: Targets.row),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: chosen ? AppColors.ink : AppColors.line,
            ),
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Row(
            children: <Widget>[
              _Check(chosen: chosen),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: _choiceTitle.copyWith(
                    fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                    color: chosen ? AppColors.onInk : AppColors.ink,
                  ),
                ),
              ),
              // Только у невзятых: у взятой возраст уже ничего не решает, а чип
              // на чернильном фоне был бы третьим цветом в строке.
              if (!chosen) ...<Widget>[
                const SizedBox(width: 12),
                AgeChip(days: age, showIcon: false),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(focusSetProvider.notifier);

    if (chosen) {
      unawaited(
        runMutation(
          context,
          () => notifier.drop(task.id),
          failure: 'Не удалось убрать задачу из набора.',
        ),
      );
      return;
    }

    if (taken >= kFocusSlots) {
      // Не запрос и не ошибка: правило экранное, и сказано оно так, как есть.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'В наборе уже пять задач — больше на экран работы не помещается. '
              'Снимите одну.',
            ),
          ),
        );
      return;
    }

    unawaited(
      runMutation(
        context,
        () => notifier.take(task, projectName: projectName),
        failure: 'Не удалось взять задачу в работу.',
      ),
    );
  }
}

/// Квадратик 22×22: пустой с контуром или залитый янтарной галочкой.
///
/// Янтарь (`AppColors.waitingDotOnInk`) — потому что галочка стоит на чернилах,
/// где индиго ушло бы в фон, а зелёное значило бы «сделано».
class _Check extends StatelessWidget {
  const _Check({required this.chosen});

  final bool chosen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: chosen ? AppColors.waitingDotOnInk : AppColors.card,
        borderRadius: BorderRadius.circular(6),
        border: chosen
            ? null
            : Border.all(color: AppColors.lineStrong, width: 2),
      ),
      child: chosen
          ? const Icon(Icons.check, size: 16, color: AppColors.ink)
          : null,
    );
  }
}

/// «Работать над тремя» — и назад, к работе.
class _WorkOnButton extends StatelessWidget {
  const _WorkOnButton({required this.taken});

  final int taken;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 18),
      child: SizedBox(
        height: 60,
        child: FilledButton.icon(
          onPressed: taken == 0 ? null : () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            textStyle: AppText.action.copyWith(fontSize: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.panel),
            ),
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_forward, size: 22),
          label: Text(
            taken == 0 ? 'Пока ничего не выбрано' : 'Работать над ${_count(taken)}',
          ),
        ),
      ),
    );
  }
}

/// «одной», «двумя», … — творительный падеж, как в эталоне («Работать над
/// тремя»).
///
/// Прописью только до пяти: больше на экран сбора и не берут, а шестая
/// (собранная curl-ом) честно назовётся цифрой.
String _count(int taken) => switch (taken) {
  1 => 'одной',
  2 => 'двумя',
  3 => 'тремя',
  4 => 'четырьмя',
  5 => 'пятью',
  _ => '$taken задачами',
};

/// Текст по центру для состояний, в которых выбирать не из чего.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  /// Null рисует спиннер.
  final IconData? icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
          ],
        ),
      ),
    );
  }
}

/// Строка выбора: 15.5 — тот же кегль, что у задачи в списке проекта, потому
/// что это те же самые задачи.
const TextStyle _choiceTitle = TextStyle(
  fontFamily: AppFonts.text,
  fontSize: 15.5,
  height: 1.3,
);
