import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/goals_api.dart';
import '../domain/goals.dart';
import '../domain/not_loaded.dart';
import '../models/goal.dart';
import '../models/task.dart';
import 'board_providers.dart' show noAutomaticRetry;
import 'dependencies.dart';
import 'read_cache_providers.dart';

part 'goal_providers.g.dart';

/// Contours and goals (`design/goals-ideas-contract.md`).
///
/// ## Reads through the cache, writes online only
///
/// Both lists are read like the work set: network first, the local copy when
/// the network is slow or gone ([readThroughCache]). Writes have no outbox in
/// this iteration -- each one is a request whose answer (a whole [GoalView],
/// or a contour) replaces the row in the list; a failure throws to the button
/// that pressed it (`widgets/mutation_feedback.dart`).
///
/// ## Everything degrades to "no goals"
///
/// The contours and the goals are extras on top of the board and the set: a
/// server from before them, or a read that fails with no copy, must leave the
/// app exactly as it was. So the derived providers below answer "unknown"
/// (null, empty) rather than an error, and every screen treats unknown as
/// "draw nothing about goals".

@Riverpod(keepAlive: true)
GoalsApi goalsApi(Ref ref) => GoalsApi(ref.watch(apiClientProvider));

abstract final class GoalCacheKeys {
  static const String contours = 'contours';
  static const String goals = 'goals';
  static const String achieved = 'goals.achieved';
}

/// `GET /contours`: the contours in order and the manual choice.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class Contours extends _$Contours {
  @override
  Future<ContourList> build() {
    final api = ref.watch(goalsApiProvider);
    return readThroughCache<ContourList>(
      ref,
      key: GoalCacheKeys.contours,
      fetch: api.fetchContours,
      encode: (value) => jsonDecode(jsonEncode(value.toJson())),
      decode: (json) =>
          ContourList.fromJson((json! as Map).cast<String, dynamic>()),
      onLateFresh: (shown, fresh) {
        if (ref.mounted && identical(state.value, shown)) {
          state = AsyncData(fresh);
        }
      },
    );
  }

  GoalsApi get _api => ref.read(goalsApiProvider);

  ContourList get _current =>
      state.value ?? (throw state.error ?? const NotLoadedException());

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Contours refresh failed: $error');
    }
  }

  Future<Contour> create({
    required String name,
    int? slots,
    int? windowDays,
    ContourSchedule? schedule,
  }) async {
    final created = await _api.createContour(
      name: name,
      slots: slots,
      windowDays: windowDays,
      schedule: schedule,
    );
    final list = _current;
    _set(list.copyWith(contours: <Contour>[...list.contours, created]));
    return created;
  }

  Future<Contour> edit(
    String id, {
    String? name,
    int? slots,
    int? windowDays,
    ContourSchedule? schedule,
    bool clearSchedule = false,
    double? position,
  }) async {
    final updated = await _api.updateContour(
      id,
      name: name,
      slots: slots,
      windowDays: windowDays,
      schedule: schedule,
      clearSchedule: clearSchedule,
      position: position,
    );
    final list = _current;
    final contours = <Contour>[
      for (final contour in list.contours)
        if (contour.id == id) updated else contour,
    ]..sort((a, b) => a.position.compareTo(b.position));
    _set(list.copyWith(contours: contours));
    return updated;
  }

  /// Moves [id] to [index] in the order: a position between its new
  /// neighbours (contours are a handful of rows; the server takes the
  /// position as given).
  Future<void> reorder(String id, int index) async {
    final list = _current;
    final others = <Contour>[
      for (final contour in list.contours)
        if (contour.id != id) contour,
    ];
    final at = index.clamp(0, others.length);
    final before = at == 0 ? null : others[at - 1].position;
    final after = at >= others.length ? null : others[at].position;
    final double position;
    if (before == null && after == null) {
      position = 1000;
    } else if (before == null) {
      position = after! - 1000;
    } else if (after == null) {
      position = before + 1000;
    } else {
      position = (before + after) / 2;
    }
    final moved = list.contours.firstWhere((contour) => contour.id == id);
    // Optimistic: the list in its new order for the one round trip.
    _set(
      list.copyWith(
        contours: <Contour>[
          ...others.take(at),
          moved.copyWith(position: position),
          ...others.skip(at),
        ],
      ),
    );
    try {
      await edit(id, position: position);
    } catch (_) {
      if (ref.mounted) _set(list);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _api.deleteContour(id);
    final list = _current;
    _set(
      list.copyWith(
        contours: <Contour>[
          for (final contour in list.contours)
            if (contour.id != id) contour,
        ],
        active: list.active.contourId == id
            ? const ActiveContourChoice()
            : list.active,
      ),
    );
  }

  /// The manual switch: [contourId] until the schedules would next give a
  /// different answer (`until` per the contract), or until switched again
  /// when no contour has a schedule. Returns that `until`.
  Future<DateTime?> choose(String contourId, {DateTime? now}) async {
    final list = _current;
    final until = nextScheduleChange(list.contours, now ?? DateTime.now());
    final saved = await _api.setActiveContour(
      contourId: contourId,
      until: until,
    );
    _set(_current.copyWith(active: saved));
    return until;
  }

  /// «Вернуть по расписанию».
  Future<void> followSchedule() async {
    final saved = await _api.setActiveContour(contourId: null, until: null);
    _set(_current.copyWith(active: saved));
  }

  void _set(ContourList list) {
    if (!ref.mounted) return;
    state = AsyncData(list);
    unawaited(
      ref
          .read(readCacheStoreProvider)
          .write(GoalCacheKeys.contours, jsonDecode(jsonEncode(list.toJson()))),
    );
  }
}

/// The contours in order, or empty while unknown.
@Riverpod(keepAlive: true)
List<Contour> contourList(Ref ref) {
  final list = ref.watch(contoursProvider).value?.contours ?? const <Contour>[];
  return <Contour>[...list]..sort((a, b) => a.position.compareTo(b.position));
}

/// The active contour, resolved on this device ([resolveActiveContour]), or
/// null while the contours are unknown -- which every screen reads as "no
/// goals, one working set", the app as it was before contours.
///
/// Re-resolves itself at the next moment the answer can change (a schedule's
/// edge or the manual choice's `until`); no timer when nothing can change.
@Riverpod(keepAlive: true)
Contour? activeContour(Ref ref) {
  final list = ref.watch(contoursProvider).value;
  if (list == null || list.contours.isEmpty) return null;
  final now = DateTime.now();
  final active = resolveActiveContour(list.contours, list.active, now);

  DateTime? next = nextScheduleChange(list.contours, now);
  final until = list.active.until == null
      ? null
      : DateTime.tryParse(list.active.until!);
  if (list.active.contourId != null && until != null && until.isAfter(now)) {
    if (next == null || until.isBefore(next)) next = until;
  }
  if (next != null) {
    final wait = next.difference(now) + const Duration(seconds: 1);
    final timer = Timer(wait, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return active;
}

/// The active contour's id, or null while unknown.
@Riverpod(keepAlive: true)
String? activeContourId(Ref ref) => ref.watch(activeContourProvider)?.id;

/// The default contour (first by position) -- where a task in the set with no
/// contour belongs. Null while unknown.
@Riverpod(keepAlive: true)
String? defaultContourId(Ref ref) {
  final list = ref.watch(contourListProvider);
  return list.isEmpty ? null : list.first.id;
}

/// Whether the active contour is a manual choice in force.
@Riverpod(keepAlive: true)
bool activeContourIsManual(Ref ref) {
  final list = ref.watch(contoursProvider).value;
  if (list == null) return false;
  // Re-read whenever the resolution does (it carries the timer).
  ref.watch(activeContourProvider);
  return isManualChoice(list.contours, list.active, DateTime.now());
}

/// Goals in slots and on the bench, in contour order then position.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class Goals extends _$Goals {
  @override
  Future<List<GoalView>> build() {
    final api = ref.watch(goalsApiProvider);
    return readThroughCache<List<GoalView>>(
      ref,
      key: GoalCacheKeys.goals,
      fetch: api.fetchGoals,
      encode: (rows) => jsonDecode(jsonEncode(rows)),
      decode: (json) => List<GoalView>.unmodifiable(
        (json! as List<dynamic>).map(
          (row) => GoalView.fromJson((row as Map).cast<String, dynamic>()),
        ),
      ),
      onLateFresh: (shown, fresh) {
        if (ref.mounted && identical(state.value, shown)) {
          state = AsyncData(fresh);
        }
      },
    );
  }

  GoalsApi get _api => ref.read(goalsApiProvider);

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Goals refresh failed: $error');
    }
  }

  /// Re-read without a loading frame (after a write elsewhere changed tasks).
  Future<void> syncQuietly() async {
    try {
      final fresh = await _api.fetchGoals();
      if (!ref.mounted) return;
      _setAll(fresh);
    } catch (error) {
      debugPrint('Quiet goals sync failed: $error');
    }
  }

  Future<GoalView> create({
    required String contourId,
    required String title,
    String? why,
    bool slot = false,
  }) async {
    final goal = await _api.createGoal(
      contourId: contourId,
      title: title,
      why: why,
      slot: slot,
    );
    _put(goal);
    return goal;
  }

  Future<GoalView> edit(
    String id, {
    String? title,
    String? why,
    bool clearWhy = false,
    String? contourId,
    int? windowDays,
    bool clearWindow = false,
    double? position,
  }) => _apply(
    _api.updateGoal(
      id,
      title: title,
      why: why,
      clearWhy: clearWhy,
      contourId: contourId,
      windowDays: windowDays,
      clearWindow: clearWindow,
      position: position,
    ),
  );

  Future<GoalView> slot(String id, {int? windowDays}) =>
      _apply(_api.slotGoal(id, windowDays: windowDays));
  Future<GoalView> extend(String id) => _apply(_api.extendGoal(id));
  Future<GoalView> bench(String id) => _apply(_api.benchGoal(id));

  Future<GoalView> achieve(String id) async {
    final goal = await _apply(_api.achieveGoal(id));
    ref.invalidate(achievedGoalsProvider);
    return goal;
  }

  Future<GoalView> reopen(String id) async {
    final goal = await _apply(_api.reopenGoal(id));
    ref.invalidate(achievedGoalsProvider);
    return goal;
  }

  Future<void> delete(String id) async {
    await _api.deleteGoal(id);
    final rows = state.value;
    if (rows != null && ref.mounted) {
      _setAll(<GoalView>[
        for (final row in rows)
          if (row.id != id) row,
      ]);
    }
    ref.invalidate(achievedGoalsProvider);
  }

  Future<GoalView> linkTask(String goalId, String taskId) =>
      _apply(_api.linkTask(goalId, taskId));
  Future<GoalView> unlinkTask(String goalId, String taskId) =>
      _apply(_api.unlinkTask(goalId, taskId));
  Future<GoalView> linkIdea(String goalId, String noteId) =>
      _apply(_api.linkIdea(goalId, noteId));
  Future<GoalView> unlinkIdea(String goalId, String noteId) =>
      _apply(_api.unlinkIdea(goalId, noteId));

  /// Reorder a goal's task: [index] in the goal's list after the move.
  Future<GoalView> moveTask(String goalId, String taskId, int index) {
    final goal = byId(goalId);
    final others = <GoalTask>[
      for (final task in goal?.tasks ?? const <GoalTask>[])
        if (task.id != taskId) task,
    ];
    final at = index.clamp(0, others.length);
    if (goal != null) {
      final moved = goal.tasks.firstWhere((task) => task.id == taskId);
      _put(
        goal.copyWith(
          tasks: <GoalTask>[...others.take(at), moved, ...others.skip(at)],
        ),
      );
    }
    return _apply(
      _api.moveTask(
        goalId,
        taskId,
        beforeTaskId: at == 0 ? null : others[at - 1].id,
        afterTaskId: at >= others.length ? null : others[at].id,
      ),
      rollback: goal,
    );
  }

  /// Reorder goals within a contour: [id] moved to [index] among
  /// [orderInContour] (that contour's goals as shown, without [id]).
  Future<GoalView> reorder(
    String id,
    List<GoalView> orderWithout,
    int index,
  ) {
    final at = index.clamp(0, orderWithout.length);
    final before = at == 0 ? null : orderWithout[at - 1].position;
    final after = at >= orderWithout.length
        ? null
        : orderWithout[at].position;
    final double position;
    if (before == null && after == null) {
      position = 1000;
    } else if (before == null) {
      position = after! - 1000;
    } else if (after == null) {
      position = before + 1000;
    } else {
      position = (before + after) / 2;
    }
    final goal = byId(id);
    if (goal != null) _put(goal.copyWith(position: position), sort: true);
    return _apply(_api.updateGoal(id, position: position), rollback: goal);
  }

  GoalView? byId(String id) {
    for (final goal in state.value ?? const <GoalView>[]) {
      if (goal.id == id) return goal;
    }
    return null;
  }

  Future<GoalView> _apply(Future<GoalView> request, {GoalView? rollback}) async {
    try {
      final goal = await request;
      _put(goal, sort: true);
      return goal;
    } catch (_) {
      if (rollback != null) _put(rollback, sort: true);
      rethrow;
    }
  }

  /// Swaps [goal] into the list (or out of it, once achieved).
  void _put(GoalView goal, {bool sort = false}) {
    if (!ref.mounted) return;
    final rows = state.value ?? const <GoalView>[];
    final next = <GoalView>[
      for (final row in rows)
        if (row.id != goal.id) row,
      if (!goal.achieved) goal,
    ];
    if (sort || !rows.any((row) => row.id == goal.id)) {
      final order = <String, double>{
        for (final contour in ref.read(contourListProvider))
          contour.id: contour.position,
      };
      next.sort((a, b) {
        final byContour = (order[a.contourId] ?? 0).compareTo(
          order[b.contourId] ?? 0,
        );
        return byContour != 0 ? byContour : a.position.compareTo(b.position);
      });
    } else {
      // Keep the row where it was.
      final index = rows.indexWhere((row) => row.id == goal.id);
      if (!goal.achieved && index >= 0) {
        next
          ..removeWhere((row) => row.id == goal.id)
          ..insert(index, goal);
      }
    }
    _setAll(next);
  }

  void _setAll(List<GoalView> rows) {
    if (!ref.mounted) return;
    state = AsyncData(List<GoalView>.unmodifiable(rows));
    unawaited(
      ref
          .read(readCacheStoreProvider)
          .write(GoalCacheKeys.goals, jsonDecode(jsonEncode(rows))),
    );
  }
}

/// The goals list, or empty while unknown (or unavailable).
@Riverpod(keepAlive: true)
List<GoalView> goalList(Ref ref) =>
    ref.watch(goalsProvider).value ?? const <GoalView>[];

/// Goals of [contourId], in their order.
List<GoalView> goalsOfContour(List<GoalView> goals, String contourId) => <
  GoalView
>[
  for (final goal in goals)
    if (goal.contourId == contourId) goal,
];

/// Which (unachieved) goals each task serves, built from the goals list --
/// so a crown follows a link the moment it is made, without re-reading the
/// board. Null while the goals are unknown: callers then fall back to the
/// task's own `goals` as the server last sent them.
@Riverpod(keepAlive: true)
Map<String, List<TaskGoalRef>>? taskGoalIndex(Ref ref) {
  final goals = ref.watch(goalsProvider).value;
  if (goals == null) return null;
  final index = <String, List<TaskGoalRef>>{};
  for (final goal in goals) {
    final link = TaskGoalRef(
      id: goal.id,
      title: goal.title,
      contourId: goal.contourId,
    );
    for (final task in goal.tasks) {
      (index[task.id] ??= <TaskGoalRef>[]).add(link);
    }
  }
  return index;
}

/// The goals of a task: from the live index when known, else as sent.
List<TaskGoalRef> goalsOfTask(
  Map<String, List<TaskGoalRef>>? index,
  String taskId,
  List<TaskGoalRef> sent,
) {
  if (index == null) return sent;
  return index[taskId] ?? const <TaskGoalRef>[];
}

/// Achieved goals, newest first -- the history screen's «Достигнутые цели».
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
Future<List<GoalView>> achievedGoals(Ref ref) async {
  final api = ref.watch(goalsApiProvider);
  final rows = await readThroughCache<List<GoalView>>(
    ref,
    key: GoalCacheKeys.achieved,
    fetch: () => api.fetchGoals(states: const <GoalState>[GoalState.achieved]),
    encode: (rows) => jsonDecode(jsonEncode(rows)),
    decode: (json) => List<GoalView>.unmodifiable(
      (json! as List<dynamic>).map(
        (row) => GoalView.fromJson((row as Map).cast<String, dynamic>()),
      ),
    ),
    onLateFresh: (_, _) {},
  );
  final sorted = <GoalView>[...rows]
    ..sort((a, b) => (b.achievedAt ?? '').compareTo(a.achievedAt ?? ''));
  return List<GoalView>.unmodifiable(sorted);
}

/// One task, fetched by id -- a goal's step opened from somewhere that is not
/// a list.
@riverpod
Future<Task> taskById(Ref ref, String id) =>
    ref.watch(goalsApiProvider).fetchTask(id);
