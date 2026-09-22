import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/focus_api.dart';
import '../api/project_api.dart';
import '../models/focus_task.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'focus_providers.g.dart';

/// Набор «в работе»: состояние режима работы и три записи, которые его меняют
/// (F13).
///
/// ## Три правила, вокруг которых написан файл
///
/// 1. **Порядок набора — серверный.** `GET /focus` отдаёт строки по `focusedAt`
///    по возрастанию, и здесь никто не сортирует. То же правило, что для
///    `Task.position`: клиент, который решил переупорядочить список сам, рано
///    или поздно разойдётся с сервером — молча.
/// 2. **Оптимистичное обновление живёт один круг.** Как и везде в приложении
///    (см. `project_providers.dart`), это предсказание на время запроса, а не
///    офлайновая правка: не удалось — откат и вслух сказанная причина.
/// 3. **Правило пяти — экранное.** [kFocusSlots] читает экран сбора, сервер про
///    него не знает (`backend/src/routes/focus.ts` объясняет, почему). Поэтому
///    здесь нет ни проверки, ни ошибки «больше пяти»: набор из шести — это
///    экран, который прокручивается, а не сломанные данные.

/// Сколько задач помещается в набор — и на экран, и в голову.
///
/// Пять слотов рисует шапка `design/reference/Pick.html`; это единственное
/// место, где число что-то значит, поэтому и константа одна. Ограничение мягкое:
/// экран не даёт взять шестую, но не притворяется, будто её отверг сервер.
const int kFocusSlots = 5;

/// Роуты набора. Здесь, а не в `dependencies.dart`, по той же причине, по какой
/// `FocusApi` вообще отдельный класс: это один режим, и его зависимости удобнее
/// читать рядом с ним.
@Riverpod(keepAlive: true)
FocusApi focusApi(Ref ref) => FocusApi(ref.watch(apiClientProvider));

/// Сам набор: `GET /focus`, и три записи, которые его меняют.
///
/// `keepAlive`, потому что набор смотрят сразу два места — режим работы и
/// полоска «В работе» на планировании, — и они живут в `IndexedStack`
/// одновременно. Автодиспоуз здесь означал бы перезапрос на каждое переключение
/// режима.
///
/// Автоповтор выключен ([noAutomaticRetry]) ровно по тем же причинам, что у
/// доски: у пользователя есть явный повтор, а невидимый на 38 секунд делает
/// видимый похожим на сломанный.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class FocusSet extends _$FocusSet {
  @override
  Future<List<FocusTask>> build() => ref.watch(focusApiProvider).fetchFocus();

  FocusApi get _focus => ref.read(focusApiProvider);
  ProjectApi get _projects => ref.read(projectApiProvider);

  /// Потянуть вниз, «повторить», и возврат с экрана сбора.
  ///
  /// Возвращается нормально при ошибке — как `Board.refresh`: будущее жеста
  /// крутит только спиннер, а сама ошибка живёт на экране.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Focus refresh failed: $error');
    }
  }

  /// Взять задачу в работу.
  ///
  /// [projectName] — от вызывающего, потому что он его уже знает (строка проекта
  /// на доске, заголовок экрана проекта), а `GET /focus` ответит настоящим
  /// именем секундой позже. Это единственное поле оптимистичной строки, которого
  /// нет в самой [Task].
  ///
  /// Задача уже в наборе — не делаем ничего и не ходим на сервер. Роут
  /// идемпотентен и повтор был бы безвреден, но повтор, который ничего не меняет,
  /// — это запрос ради запроса; а главное, оптимистичная строка второй раз
  /// удвоила бы задачу в списке на один кадр.
  Future<void> take(Task task, {required String projectName}) {
    return _write(
      optimistic: (rows) {
        if (rows.any((row) => row.id == task.id)) return null;
        return <FocusTask>[...rows, _optimistic(task, projectName)];
      },
      // Перечитываем набор: `focusedAt` ставит сервер (экран показывает его как
      // «в работе с 9:40»), и он же решает, куда строка встанет. Догадка клиента
      // про время была бы видимой неправдой.
      send: () async {
        await _focus.addToFocus(task.id);
        return null;
      },
    );
  }

  /// Убрать задачу из набора.
  ///
  /// В отличие от [take] — без перечитывания: набор минус одна строка и есть
  /// ответ сервера, порядок остальных от этого не меняется. Роут идемпотентен,
  /// так что и повтор, и «её там уже нет» заканчиваются одинаково.
  Future<void> drop(String taskId) {
    return _write(
      optimistic: (rows) {
        if (!rows.any((row) => row.id == taskId)) return null;
        return <FocusTask>[
          for (final row in rows)
            if (row.id != taskId) row,
        ];
      },
      send: () async {
        await _focus.removeFromFocus(taskId);
        return _current;
      },
    );
  }

  /// «Сделано» с экрана работы.
  ///
  /// Один `PATCH /tasks/:id`, а не два запроса: закрытая задача **сама** выходит
  /// из набора (`backend/src/domain/taskEvents.ts` — `leavesFocus`), и это
  /// сделано ровно для того, чтобы телефон не досылал второй запрос, который на
  /// плохой связи не уйдёт и оставит в наборе покойника.
  ///
  /// Доску после этого обновляем отдельно и **по-хорошему**: закрытая задача
  /// меняет и текущую задачу проекта, и счётчик, и точки на планировании. Список
  /// задач проекта — это ровно то, что лежит в строке доски
  /// (см. [Board.applyProjectTasks]), поэтому один `GET /projects/:id/tasks`
  /// вместо целого `GET /board`. Его провал не откатывает «сделано»: задача
  /// закрыта, а доска — всего лишь на один экран устаревшая.
  Future<void> complete(FocusTask task) {
    return _write(
      optimistic: (rows) => <FocusTask>[
        for (final row in rows)
          if (row.id != task.id) row,
      ],
      send: () async {
        await _projects.updateTask(task.id, status: TaskStatus.done);
        await _syncBoard(task.projectId);
        return _current;
      },
    );
  }

  /// Перечитать доску по одному проекту после записи, сделанной отсюда.
  ///
  /// Молча глотает свою ошибку — намеренно: к моменту вызова задача уже закрыта,
  /// и превращать устаревшую доску в «не удалось отметить сделанной» значило бы
  /// соврать про то, что как раз получилось.
  Future<void> _syncBoard(String projectId) async {
    try {
      final rows = await _projects.fetchTasks(projectId);
      if (!ref.mounted) return;
      ref.read(boardProvider.notifier).applyProjectTasks(projectId, rows);
    } catch (error) {
      debugPrint('Board splice after a focus write failed: $error');
    }
  }

  List<FocusTask> get _current => state.value ?? const <FocusTask>[];

  /// Общая форма всех трёх записей: показать предсказание, отправить, осесть на
  /// правде, вернуть всё назад при провале.
  ///
  /// [optimistic] возвращает null, когда делать нечего (задача уже в наборе, её
  /// там нет) — тогда не будет ни кадра, ни запроса. [send] возвращает список,
  /// если он уже и есть правда, или null — «спроси сервер заново».
  ///
  /// Ошибка пробрасывается, а не кладётся в `state`: набор на экране цел, не
  /// удалась именно запись, и рассказать об этом — дело кнопки
  /// (`widgets/mutation_feedback.dart`).
  Future<void> _write({
    required List<FocusTask>? Function(List<FocusTask> rows) optimistic,
    required Future<List<FocusTask>?> Function() send,
  }) {
    return _enqueue(() async {
      final previous = state.value;
      if (previous == null) return;

      final predicted = optimistic(previous);
      if (predicted == null) return;

      state = AsyncData(List<FocusTask>.unmodifiable(predicted));

      try {
        final settled = await send() ?? await _focus.fetchFocus();
        // Экран мог уйти из-под записи. Запись всё равно произошла, просто
        // рассказывать уже некому.
        if (!ref.mounted) return;
        state = AsyncData(List<FocusTask>.unmodifiable(settled));
      } catch (error) {
        if (ref.mounted) state = AsyncData(previous);
        rethrow;
      }
    });
  }

  /// Записи выполняются по очереди.
  ///
  /// Откат определён только относительно известного «до», а у двух записей в
  /// полёте такого «до» нет: вторая взяла бы предсказание первой за точку
  /// возврата. На экране сбора, где чекбоксы жмут подряд, это не теория.
  Future<void> _pending = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final chained = _pending.then<void>(
      (_) => action(),
      onError: (Object _) => action(),
    );
    _pending = chained.catchError((Object _) {});
    return chained;
  }

  /// Строка набора, собранная из задачи и имени её проекта, — на один круг,
  /// пока сервер не ответит настоящей.
  ///
  /// `focusedAt` — «сейчас», и это не выдумка, а то же самое, что сделает сервер:
  /// набор упорядочен по `focusedAt`, новая задача встаёт в конец.
  FocusTask _optimistic(Task task, String projectName) => FocusTask(
    id: task.id,
    projectId: task.projectId,
    title: task.title,
    description: task.description,
    status: task.status,
    position: task.position,
    remindAt: task.remindAt,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
    focusedAt: DateTime.now().toUtc().toIso8601String(),
    project: FocusProject(id: task.projectId, name: projectName),
  );
}

/// Id задач, которые сейчас в наборе.
///
/// Отдельный провайдер, потому что строке задачи в проекте нужен ровно этот
/// вопрос — «я в наборе?» — и ничего больше. Пока набор не загружен, множество
/// пустое: это честнее, чем показывать кнопку «взять в работу» нажатой на
/// основании того, чего мы ещё не знаем.
@Riverpod(keepAlive: true)
Set<String> focusedTaskIds(Ref ref) {
  final rows = ref.watch(focusSetProvider).value;
  if (rows == null) return const <String>{};
  return <String>{for (final row in rows) row.id};
}
