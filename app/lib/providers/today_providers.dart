import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_exception.dart';
import '../api/today_history_api.dart';
import '../domain/reminders.dart';
import '../domain/today_view.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../models/today_history.dart';
import '../storage/read_cache_store.dart';
import 'board_providers.dart';
import 'dependencies.dart';
import 'focus_providers.dart';
import 'outbox_providers.dart';
import 'project_providers.dart';
import 'read_cache_providers.dart';
import 'scope_providers.dart';

part 'today_providers.g.dart';

/// «Сегодня», the owner's server settings, «Сделано», «Недели» and the review
/// status (`design/today-history-contract.md`).

@Riverpod(keepAlive: true)
TodayHistoryApi todayHistoryApi(Ref ref) =>
    TodayHistoryApi(ref.watch(apiClientProvider));

/// The clock the day block reads. A provider so tests stand on a fixed day.
@Riverpod(keepAlive: true)
DateTime Function() appClock(Ref ref) => DateTime.now;

/// The owner's today, `YYYY-MM-DD`, local.
///
/// Not a timer: the shell calls [TodayKey.check] when the app comes back to
/// the foreground, and the Work screen when it is built -- a phone left on
/// the Work screen over midnight shows yesterday until it is touched, which
/// is what it would also do for the set. A pending timer in every widget test
/// would cost more than that.
@Riverpod(keepAlive: true)
class TodayKey extends _$TodayKey {
  @override
  String build() => calendarDateForApi(ref.watch(appClockProvider)());

  /// Moves to the new day if midnight has passed.
  void check() {
    final now = calendarDateForApi(ref.read(appClockProvider)());
    if (now != state) state = now;
  }
}

// --- server settings ------------------------------------------------------------

/// `GET /settings`, through the read cache: the horizon is needed offline to
/// fold «Позже», and the last known value is the honest one.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class OwnerSettingsState extends _$OwnerSettingsState {
  @override
  Future<OwnerSettings> build() {
    final api = ref.watch(todayHistoryApiProvider);
    return readThroughCache<OwnerSettings>(
      ref,
      key: ReadCacheKeys.ownerSettings,
      fetch: api.fetchSettings,
      encode: (value) => value.toJson(),
      decode: (json) =>
          OwnerSettings.fromJson((json! as Map).cast<String, dynamic>()),
      onLateFresh: (shown, fresh) {
        if (ref.mounted && identical(state.value, shown)) {
          state = AsyncData(fresh);
        }
      },
    );
  }

  /// Writes any subset; online only (the settings say «нужна сеть»
  /// offline). Throws the server's or the network's error.
  Future<void> save({
    int? laterHorizonDays,
    int? reviewWeekday,
    String? reviewTime,
  }) async {
    final saved = await ref
        .read(todayHistoryApiProvider)
        .updateSettings(
          laterHorizonDays: laterHorizonDays,
          reviewWeekday: reviewWeekday,
          reviewTime: reviewTime,
        );
    if (!ref.mounted) return;
    unawaited(
      ref
          .read(readCacheStoreProvider)
          .write(ReadCacheKeys.ownerSettings, saved.toJson()),
    );
    ref.read(cachedReadsProvider.notifier).markFresh(ReadCacheKeys.ownerSettings);
    state = AsyncData(saved);
    // The review's due moment moves with its day and time.
    ref.invalidate(reviewStatusStateProvider);
  }
}

/// The «Позже» horizon in days: the server's, the default until it is known.
@Riverpod(keepAlive: true)
int laterHorizonDays(Ref ref) =>
    ref.watch(ownerSettingsStateProvider).value?.laterHorizonDays ??
    kDefaultLaterHorizonDays;

// --- the day block ------------------------------------------------------------

/// Rows changed by a day action that the board has not caught up with yet:
/// the one round trip between «Сегодня» pressed and the server's list, so the
/// row moves at the press. Cleared by the action when its write ends.
@Riverpod(keepAlive: true)
class DayOverrides extends _$DayOverrides {
  @override
  Map<String, Task> build() => const <String, Task>{};

  void put(Task task) => state = <String, Task>{...state, task.id: task};

  void clear(Iterable<String> ids) {
    final next = <String, Task>{...state};
    var changed = false;
    for (final id in ids) {
      changed = next.remove(id) != null || changed;
    }
    if (changed) state = next;
  }
}

/// The board as the day block reads it: the outbox's waiting edits and the
/// day actions in flight applied. Null while the board is not there at all.
@Riverpod(keepAlive: true)
List<DayTask>? placedBoardTasks(Ref ref) {
  final view = ref.watch(boardViewProvider);
  if (view is! BoardReady) return null;
  final rows = withOutboxEdits(view.projects, ref.watch(outboxEntriesProvider));
  final overrides = ref.watch(dayOverridesProvider);
  final placed = placeBoardTasks(
    rows,
    scopes: ref.watch(scopesProvider).value ?? const [],
  );
  if (overrides.isEmpty) return placed;
  return <DayTask>[
    for (final entry in placed)
      if (overrides[entry.id] case final Task patched)
        DayTask(
          task: patched,
          projectName: entry.projectName,
          scopeId: entry.scopeId,
          scopeName: entry.scopeName,
          scopeOrder: entry.scopeOrder,
          projectOrder: entry.projectOrder,
        )
      else
        entry,
  ];
}

/// «Сегодня», what was closed today and «С прошлых дней», computed on the
/// client from the board (contract: offline «Сегодня» from the cache, the
/// server's `/today` is for MCP and checking). Null before any board.
@Riverpod(keepAlive: true)
DayView? dayView(Ref ref) {
  final tasks = ref.watch(placedBoardTasksProvider);
  if (tasks == null) return null;
  return dayViewOf(tasks, ref.watch(todayKeyProvider));
}

/// Whether the app is drawing from local copies because the server did not
/// answer: the last board refresh failed on the network. Used for the
/// «без сети» notes and the online-only buttons («Вернуть», the review).
@Riverpod(keepAlive: true)
bool appOffline(Ref ref) {
  final view = ref.watch(boardViewProvider);
  return view is BoardReady && view.refreshError is NetworkException;
}

// --- task actions from outside a project screen --------------------------------

/// Runs [body] on the task list of [projectId], held open for the write so its
/// reconcile reaches the board even though no project screen is watching.
Future<T> onProjectTasks<T>(
  ProviderContainer container,
  String projectId,
  Future<T> Function(ProjectTasks tasks) body,
) async {
  final provider = projectTasksProvider(projectId);
  final hold = container.listen(provider, (_, _) {});
  try {
    return await body(container.read(provider.notifier));
  } finally {
    hold.close();
  }
}

/// The freshest copy of [task]: the project's list when it is loaded.
Task freshTask(ProviderContainer container, Task task) {
  final provider = projectTasksProvider(task.projectId);
  if (container.exists(provider)) {
    for (final row in container.read(provider).value ?? const <Task>[]) {
      if (row.id == task.id) return row;
    }
  }
  return task;
}

/// A date change from the day block, a row's quick action or the date sheet.
///
/// [date] null takes the date off («В стопку», «Снять дату»); [time] is the
/// time to keep (the date sheet keeps it, quick actions drop it -- the
/// coordinator's answer 4). Shows the move at once through [DayOverrides].
Future<WriteOutcome> setTaskDate(
  ProviderContainer container,
  Task task, {
  required String? date,
  String? time,
}) async {
  final base = freshTask(container, task);
  if (base.status == TaskStatus.done) return WriteOutcome.sent;
  final overrides = container.read(dayOverridesProvider.notifier);
  overrides.put(
    base.copyWith(remindAt: date, remindTime: date == null ? null : time),
  );
  try {
    return await onProjectTasks(
      container,
      base.projectId,
      (tasks) => tasks.setRemindAt(base, date, time: date == null ? null : time),
    );
  } finally {
    overrides.clear(<String>[base.id]);
  }
}

/// A status change from the day block (done, unblock, back to pending).
Future<WriteOutcome> setDayTaskStatus(
  ProviderContainer container,
  Task task,
  TaskStatus status,
) async {
  final base = freshTask(container, task);
  if (base.status == status) return WriteOutcome.sent;
  final wasInFocus = container.read(anyFocusedTaskIdsProvider).contains(base.id);
  final overrides = container.read(dayOverridesProvider.notifier);
  overrides.put(
    base.copyWith(
      status: status,
      doneAt: status == TaskStatus.done
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    ),
  );
  try {
    final outcome = await onProjectTasks(
      container,
      base.projectId,
      (tasks) => tasks.setStatus(base, status),
    );
    if (wasInFocus && status == TaskStatus.done) {
      unawaited(container.read(focusSetProvider.notifier).syncQuietly());
    }
    return outcome;
  } finally {
    overrides.clear(<String>[base.id]);
  }
}

/// «Следом…»: a follow-up in the same project with a date, through the
/// outbox like any create.
Future<WriteOutcome> createFollowUp(
  ProviderContainer container, {
  required String projectId,
  required String title,
  required String date,
}) => onProjectTasks(
  container,
  projectId,
  (tasks) => tasks.create(title, remindAt: date),
);

// --- «Сделано» ----------------------------------------------------------------

/// The «Сделано» feed: pages of `/history/done`, the first page cached.
@immutable
class DoneFeed {
  const DoneFeed({
    required this.items,
    this.nextBefore,
    this.loadingMore = false,
    this.fromCache = false,
  });

  final List<DoneItem> items;
  final String? nextBefore;
  final bool loadingMore;

  /// The first page is the local copy: the server did not answer.
  final bool fromCache;

  bool get hasMore => nextBefore != null;

  DoneFeed copyWith({
    List<DoneItem>? items,
    String? nextBefore,
    bool clearNext = false,
    bool? loadingMore,
    bool? fromCache,
  }) => DoneFeed(
    items: items ?? this.items,
    nextBefore: clearNext ? null : (nextBefore ?? this.nextBefore),
    loadingMore: loadingMore ?? this.loadingMore,
    fromCache: fromCache ?? this.fromCache,
  );
}

const int kDonePageSize = 50;

@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class DoneFeedState extends _$DoneFeedState {
  @override
  Future<DoneFeed> build() async {
    final api = ref.watch(todayHistoryApiProvider);
    final page = await readThroughCache<DonePage>(
      ref,
      key: ReadCacheKeys.historyDone,
      fetch: () => api.fetchDone(limit: kDonePageSize),
      encode: (page) => <String, dynamic>{
        'items': <Object>[for (final item in page.items) item.toJson()],
        'nextBefore': page.nextBefore,
      },
      decode: (json) =>
          DonePage.fromJson((json! as Map).cast<String, dynamic>()),
      onLateFresh: (shown, fresh) {
        if (!ref.mounted) return;
        state = AsyncData(
          DoneFeed(items: fresh.items, nextBefore: fresh.nextBefore),
        );
      },
    );
    final cached = ref
        .read(cachedReadsProvider)
        .containsKey(ReadCacheKeys.historyDone);
    return DoneFeed(
      items: page.items,
      nextBefore: page.nextBefore,
      fromCache: cached,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Done feed refresh failed: $error');
    }
  }

  /// The next page, when there is one and none is loading.
  Future<void> loadMore() async {
    final feed = state.value;
    if (feed == null || !feed.hasMore || feed.loadingMore) return;
    state = AsyncData(feed.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(todayHistoryApiProvider)
          .fetchDone(before: feed.nextBefore, limit: kDonePageSize);
      if (!ref.mounted) return;
      final seen = <String>{for (final item in feed.items) item.task.id};
      state = AsyncData(
        DoneFeed(
          items: <DoneItem>[
            ...feed.items,
            for (final item in page.items)
              if (!seen.contains(item.task.id)) item,
          ],
          nextBefore: page.nextBefore,
          fromCache: feed.fromCache,
        ),
      );
    } catch (error) {
      debugPrint('Done feed: next page failed: $error');
      if (ref.mounted) state = AsyncData(feed.copyWith(loadingMore: false));
    }
  }

  /// Drops a row locally («Вернуть»), or puts it back (its undo).
  void remove(String taskId) {
    final feed = state.value;
    if (feed == null) return;
    state = AsyncData(
      feed.copyWith(
        items: <DoneItem>[
          for (final item in feed.items)
            if (item.task.id != taskId) item,
        ],
      ),
    );
  }

  void restore(DoneItem item) {
    final feed = state.value;
    if (feed == null) return;
    final items = <DoneItem>[
      ...feed.items.where((row) => row.task.id != item.task.id),
      item,
    ]..sort((a, b) => b.doneAt.compareTo(a.doneAt));
    state = AsyncData(feed.copyWith(items: items));
  }
}

/// «Вернуть»: `POST /tasks/:id/reopen`, online only. Puts the board's row
/// right (the project's list is re-read) and the working set (it may be back
/// in it). Throws the network's or the server's error.
Future<Task> reopenTask(ProviderContainer container, Task task) async {
  final reopened = await container
      .read(todayHistoryApiProvider)
      .reopenTask(task.id);
  container.read(doneFeedStateProvider.notifier).remove(task.id);
  try {
    final rows = await container
        .read(projectApiProvider)
        .fetchTasks(task.projectId);
    container.read(boardProvider.notifier).applyProjectTasks(task.projectId, rows);
    final provider = projectTasksProvider(task.projectId);
    if (container.exists(provider)) {
      container.read(provider.notifier).adopt(rows);
    }
  } catch (error) {
    debugPrint('Board splice after reopen failed: $error');
  }
  unawaited(container.read(focusSetProvider.notifier).syncQuietly());
  container.invalidate(historyWeeksProvider);
  return reopened;
}

// --- «Недели» -----------------------------------------------------------------

@Riverpod(keepAlive: true, retry: noAutomaticRetry)
Future<List<HistoryWeek>> historyWeeks(Ref ref) {
  final api = ref.watch(todayHistoryApiProvider);
  return readThroughCache<List<HistoryWeek>>(
    ref,
    key: ReadCacheKeys.historyWeeks,
    fetch: () => api.fetchWeeks(),
    encode: (weeks) => <String, dynamic>{
      'weeks': <Object>[for (final week in weeks) week.toJson()],
    },
    decode: HistoryWeek.listFromJson,
    onLateFresh: (_, _) {},
  );
}

// --- the review -----------------------------------------------------------------

/// `GET /reviews/status`, through the read cache: the History tab's dot and
/// the card. The local push is scheduled from it.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class ReviewStatusState extends _$ReviewStatusState {
  @override
  Future<ReviewStatus> build() {
    final api = ref.watch(todayHistoryApiProvider);
    return readThroughCache<ReviewStatus>(
      ref,
      key: ReadCacheKeys.reviewStatus,
      fetch: api.fetchReviewStatus,
      encode: (value) => value.toJson(),
      decode: (json) =>
          ReviewStatus.fromJson((json! as Map).cast<String, dynamic>()),
      onLateFresh: (shown, fresh) {
        if (ref.mounted) state = AsyncData(fresh);
      },
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Review status refresh failed: $error');
    }
  }

  /// The review was recorded: not due until the next moment.
  void recorded(Review review) {
    state = AsyncData(ReviewStatus(due: false, lastAt: review.periodEnd));
    unawaited(refresh());
  }
}

/// True while the review is due: the dot on «История», the card.
@Riverpod(keepAlive: true)
bool reviewDue(Ref ref) =>
    ref.watch(reviewStatusStateProvider).value?.due ?? false;

// --- the rhythm -------------------------------------------------------------------

/// Saves a project's rhythm and puts the answer into the board.
Future<Project> saveRhythm(
  ProviderContainer container,
  String projectId, {
  required int? closedPerWeek,
  required int? maxOpen,
}) async {
  final project = await container
      .read(todayHistoryApiProvider)
      .setRhythm(projectId, closedPerWeek: closedPerWeek, maxOpen: maxOpen);
  container.read(boardProvider.notifier).applyProject(project);
  final header = projectHeaderProvider(projectId);
  if (container.exists(header)) {
    container.read(header.notifier).applyProject(project);
  }
  return project;
}

// --- small interface notes ------------------------------------------------------

/// One of the device's interface notes (see `SettingsStore.readUiNote`).
/// Written optimistically: a note that fails to save costs the next run a
/// hint shown twice, not this one an error.
@Riverpod(keepAlive: true)
class UiNote extends _$UiNote {
  @override
  Future<String?> build(String key) =>
      ref.watch(settingsStoreProvider).readUiNote(key);

  Future<void> write(String value) async {
    state = AsyncData(value);
    try {
      await ref.read(settingsStoreProvider).writeUiNote(key, value);
    } catch (error) {
      debugPrint('Could not save the note "$key": $error');
    }
  }
}

/// Keys of [UiNote].
abstract final class UiNotes {
  /// The day «Сегодня» was folded on; folded until that day ends.
  static const String todayFolded = 'today.folded';

  /// The swipe hint over a project's list was closed.
  static const String swipeHint = 'hint.swipeDate';

  /// «Позже» unfolded in a project.
  static String laterOpen(String projectId) => 'later.$projectId';
}
