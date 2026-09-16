import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/board_reminders.dart';
import '../models/board_project.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../storage/board_snapshot_store.dart';
import 'dependencies.dart';
import 'reminder_providers.dart';

part 'board_providers.g.dart';

/// The board: one fetch, one cache, and the rule for which of the two is on
/// screen.
///
/// ## The shape, and why it is three providers instead of one
///
/// The plan's requirement is "the screen draws from the snapshot instantly
/// while a request for fresh data goes out in parallel". The obvious way to
/// write that -- one notifier that returns the cache from `build` and then
/// overwrites its own state when the request lands -- has a race that is
/// invisible until it bites: a transport that answers immediately (which is
/// exactly what the fake backend in the tests does) can complete *before* the
/// cached first value has been published, and the notifier then overwrites the
/// fresh board with the stale one.
///
/// So the two sources stay separate and honest:
///
/// - [board] is only ever the network. Loading means "the wire has not
///   answered", an error means "the wire failed", and it knows nothing about
///   files.
/// - [boardSnapshot] is only ever the disk, read once.
/// - [boardView] combines them into the single value the screen renders, and it
///   is a plain synchronous provider, so there is no state to race over.
///
/// The parallelism falls out of it: [boardView] watches both in one synchronous
/// build, so the HTTP request and the disk read start in the same microtask.

/// The last good board from disk, or null if there is nothing usable there.
///
/// Read exactly once per app run: after the first successful refresh the
/// snapshot is strictly worse than what [board] holds, and re-reading it could
/// only ever show the user older data than they already have.
@Riverpod(keepAlive: true)
Future<BoardSnapshot?> boardSnapshot(Ref ref) =>
    ref.watch(boardSnapshotStoreProvider).read();

/// A board that came from the server, with the moment it arrived.
@immutable
class FreshBoard {
  const FreshBoard({required this.projects, required this.fetchedAt});

  final List<BoardProject> projects;

  /// When this response landed. Shown to the user when the *next* refresh
  /// fails, so "what you see is from 09:12" is answerable.
  final DateTime fetchedAt;
}

/// Switches Riverpod 3's automatic retry off for the board.
///
/// ## Why the framework default is wrong here
///
/// Riverpod 3 retries a provider whose build threw, up to **ten times** with
/// exponential backoff (200 ms doubling to 6.4 s) -- roughly 38 seconds of
/// silent reattempts. That default is aimed at a transient blip, and it is
/// actively bad for this screen:
///
/// - [Board.refresh] awaits `future`, and `future` only settles once the
///   retries are exhausted. A pull-to-refresh against an unreachable server
///   would leave the spinner turning for most of a minute, which reads as a
///   frozen app, not as a retry.
/// - the user already has an explicit, always-available retry: the pull
///   gesture and the button in the banner. An invisible one on top of it just
///   makes the visible one feel broken.
/// - the product is deliberate about failing loudly rather than pretending
///   (see the plan's note on offline writes); a read path that hides failures
///   for 38 seconds is the same pretence in a different place.
///
/// So: one attempt, one honest answer, and the next attempt is the user's.
Duration? noAutomaticRetry(int retryCount, Object error) => null;

/// `GET /board?archived=false`, plus the snapshot write that follows it.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class Board extends _$Board {
  @override
  Future<FreshBoard> build() async {
    final projects = await ref.watch(boardApiProvider).fetchBoard();

    // Persist before returning, and reuse the `savedAt` the store wrote instead
    // of reading the clock a second time -- otherwise "last updated" on screen
    // and "savedAt" in the file would disagree by a few milliseconds for no
    // reason. `write` swallows its own failures (see BoardSnapshotStore): a
    // cache that cannot be written must not turn a good response into an error.
    final snapshot = await ref
        .read(boardSnapshotStoreProvider)
        .write(projects);

    return FreshBoard(projects: projects, fetchedAt: snapshot.savedAt);
  }

  /// Pull-to-refresh, and the "повторить" button.
  ///
  /// `invalidateSelf` + `await future` rather than assigning a loading state by
  /// hand: Riverpod carries the previous value into the new loading/error
  /// state, which is what lets [boardView] keep showing the board that is
  /// already on screen instead of flashing a spinner or an error page over it.
  ///
  /// Returns normally on failure. The caller is a `RefreshIndicator`, whose
  /// future only controls the spinner; the failure itself belongs on screen as
  /// [BoardReady.refreshError], not as an exception thrown at a gesture
  /// handler.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      debugPrint('Board refresh failed: $error');
    }
  }

  /// Writes an authoritative task list for one project into the board that is
  /// already loaded, without asking `GET /board` again.
  ///
  /// ## Why the project screen pushes instead of the board pulling
  ///
  /// Editing inside a project changes four things the board shows -- the current
  /// task, the done/total counter, the blocker badges, and (through
  /// [boardReminderBridge]) **the set of armed alarms**. The obvious way to keep
  /// them honest is `ref.invalidate(boardProvider)` after every write, and that
  /// is one extra full board round trip per keystroke-sized edit, on a phone,
  /// for data the client is already holding.
  ///
  /// It is also unnecessary, because of an exact correspondence in the backend:
  /// a `GET /board` row is "`GET /projects/:id` plus its tasks"
  /// (`backend/src/routes/board.ts`), and `GET /projects/:id/tasks` returns
  /// precisely that `tasks` array -- same order, same `isCurrent` annotation
  /// from the same `annotateIsCurrent`. So the list the project screen has just
  /// re-read *is* the board row's tasks, and splicing it in is not an
  /// approximation of a refresh, it is the refresh, minus the request.
  ///
  /// The project's own fields (`name`, `archivedAt`) cannot change from inside
  /// the project screen in F3, so they are left alone. F4's archive action
  /// changes which *rows* exist and must invalidate the board properly rather
  /// than reach for this method.
  ///
  /// ## What must not break
  ///
  /// [boardReminderBridge] compares by **identity** to decide whether to re-arm
  /// the queue, so this builds a new list rather than mutating in place, and the
  /// bridge picks the change up on its own. No scheduler call appears here --
  /// that property (there is exactly one place that turns board data into
  /// alarms) is the whole point of the F1 design, and a mutation path that armed
  /// alarms itself would be the second place.
  void applyProjectTasks(String projectId, List<Task> tasks) {
    final current = state.value;

    // Nothing from the wire yet: the board is either still loading or showing
    // the snapshot, and there is no in-memory row to splice into. Marking it
    // stale is the honest move -- the next read refetches once, rather than the
    // board keeping rows this write has just invalidated.
    if (current == null) {
      ref.invalidateSelf();
      return;
    }

    var found = false;
    final projects = <BoardProject>[
      for (final row in current.projects)
        if (row.project.id == projectId)
          () {
            found = true;
            return row.copyWith(tasks: List<Task>.unmodifiable(tasks));
          }()
        else
          row,
    ];

    // The project is not on this board at all (archived, or the board is the
    // archive view). Leaving the state untouched also leaves `published`
    // identity untouched in the bridge, so nothing is re-armed for nothing.
    if (!found) return;

    state = AsyncData(
      FreshBoard(
        projects: List<BoardProject>.unmodifiable(projects),
        // Deliberately the *original* fetch time. The board's "данные от ..."
        // label answers "how old is what I am looking at", and a mutation to one
        // project does not make the other fifteen rows any fresher. Claiming
        // otherwise would turn a truthful staleness indicator into a lie that is
        // impossible to notice.
        fetchedAt: current.fetchedAt,
      ),
    );

    // Keep the read cache in step, so a restart with no network shows what was
    // just written rather than the state before it -- including for the alarm
    // set, which is half the reason the snapshot exists. Same `savedAt` for the
    // same reason as above; `write` never throws (see BoardSnapshotStore).
    unawaited(
      ref
          .read(boardSnapshotStoreProvider)
          .write(projects, savedAt: current.fetchedAt),
    );
  }

  /// Writes a project's **own row** -- in practice its name -- into the board
  /// already in memory, leaving that row's tasks untouched.
  ///
  /// The sibling of [applyProjectTasks], and it exists for the same reason: a
  /// rename changes one string on one card, and `ref.invalidate(boardProvider)`
  /// would pay a whole `GET /board` for it. The splice is exact rather than an
  /// approximation, because `PATCH /projects/:id` answers with byte-identical
  /// JSON to the `GET /projects/:id` a board row is built from
  /// (`backend/src/routes/board.ts`, and the backend test that asserts the two
  /// key sets match).
  ///
  /// A name cannot move a task, change `isCurrent`, or add or remove a reminder
  /// -- but it does appear **inside the notification**
  /// (`TaskReminder.projectName`, `domain/board_reminders.dart`), so the armed
  /// alarms have to be re-worded or a renamed project keeps nagging under its old
  /// name for weeks. That happens here for free and with no scheduler call, by
  /// the same mechanism as everywhere else: a new projects list is a new target
  /// set for [boardReminderBridge], and replacing the target set *is* the
  /// reschedule (`ReminderScheduler.sync` re-arms every target against stable
  /// per-task ids, so a re-arm replaces rather than duplicates).
  ///
  /// **No board in memory means no splice**, and no refetch either. Unlike
  /// [applyProjectTasks] this does not `invalidateSelf`: a rename is applied
  /// twice (optimistically, then with the server's row), and invalidating from
  /// the optimistic half would fire a `GET /board` that answers with the *old*
  /// name. The case is also nearly unreachable -- the board provider only has no
  /// value while the very first fetch of this run is in flight or has failed,
  /// and that fetch, whenever it lands, carries the new name anyway.
  void applyProject(Project project) {
    final current = state.value;
    if (current == null) return;

    var found = false;
    final projects = <BoardProject>[
      for (final row in current.projects)
        if (row.project.id == project.id)
          () {
            found = true;
            return row.copyWith(project: project);
          }()
        else
          row,
    ];

    // Not on this board: an archived project renamed from the archive screen
    // takes this branch, and leaving the state alone is what keeps that rename
    // from re-arming anything.
    if (!found) return;

    state = AsyncData(
      FreshBoard(
        projects: List<BoardProject>.unmodifiable(projects),
        // The original fetch time, for the reason spelled out in
        // [applyProjectTasks]: renaming one project does not make the other
        // fifteen rows any fresher.
        fetchedAt: current.fetchedAt,
      ),
    );

    unawaited(
      ref
          .read(boardSnapshotStoreProvider)
          .write(projects, savedAt: current.fetchedAt),
    );
  }
}

/// Where the rows on screen came from.
enum BoardOrigin {
  /// Straight from `GET /board`.
  network,

  /// From the snapshot file. The user is looking at the past and has to be
  /// told so.
  cache,
}

/// What the board screen renders. See the note at the top of this file.
@immutable
sealed class BoardView {
  const BoardView();
}

/// Nothing to show yet: no snapshot has been read and no response has arrived.
///
/// This is also the state for "the snapshot file was missing, corrupt, or from
/// an older schema" -- deliberately. An unreadable cache must never be
/// presented as an empty board, because "you have no projects" and "we could
/// not read the cache" look identical on screen and mean opposite things.
class BoardLoading extends BoardView {
  const BoardLoading();
}

/// No data from either source, and the refresh failed. The only state where the
/// screen has nothing but an error to show.
class BoardUnavailable extends BoardView {
  const BoardUnavailable(this.error);

  final Object error;
}

/// There are rows to draw.
class BoardReady extends BoardView {
  const BoardReady({
    required this.projects,
    required this.origin,
    required this.updatedAt,
    this.isRefreshing = false,
    this.refreshError,
  });

  /// In server order: projects by `createdAt` ascending, tasks by `position`.
  /// May be empty -- that is the genuine "no projects at all" case, and only
  /// reachable from a source that actually succeeded.
  final List<BoardProject> projects;

  final BoardOrigin origin;

  /// When the data on screen was fetched. For [BoardOrigin.cache] this is the
  /// snapshot's `savedAt`, i.e. possibly yesterday.
  final DateTime updatedAt;

  /// A refresh is in flight behind the rows currently shown.
  final bool isRefreshing;

  /// The last refresh attempt failed. Combined with [origin] this is the
  /// "showing you yesterday's data, and we could not do better" state the plan
  /// asks for explicitly.
  final Object? refreshError;

  bool get isStale => origin == BoardOrigin.cache;

  bool get isEmpty => projects.isEmpty;
}

/// Folds the network provider and the snapshot into one value.
@Riverpod(keepAlive: true)
BoardView boardView(Ref ref) {
  // Watched before the snapshot so the request goes out first; both start in
  // this same synchronous build, which is where "in parallel" comes from.
  final live = ref.watch(boardProvider);
  final cached = ref.watch(boardSnapshotProvider);

  // Anything the wire has *ever* returned wins over the file, including while a
  // later refresh is loading or after it has failed -- Riverpod keeps the
  // previous value in both of those states.
  if (live.value case final FreshBoard fresh) {
    return BoardReady(
      projects: fresh.projects,
      origin: BoardOrigin.network,
      updatedAt: fresh.fetchedAt,
      isRefreshing: live.isLoading,
      refreshError: live.error,
    );
  }

  // Nothing from the wire yet: draw the snapshot, and say where it came from.
  if (cached.value case final BoardSnapshot snapshot) {
    return BoardReady(
      projects: snapshot.projects,
      origin: BoardOrigin.cache,
      updatedAt: snapshot.savedAt,
      isRefreshing: live.isLoading,
      refreshError: live.error,
    );
  }

  // Neither source has anything. Report the failure only once the disk has
  // also had its say -- a refused connection fails in microseconds, well
  // before the file is read, and flashing an error page before the cache
  // arrives would be a worse lie than waiting one more frame.
  final error = live.error;
  if (error != null && !cached.isLoading) return BoardUnavailable(error);

  return const BoardLoading();
}

/// The wire from "the board changed" to "the OS alarm queue changed".
///
/// ## What this preserves
///
/// F1 built the reminder graph so that **changing the target set *is* the
/// reschedule**: `reminderSync` watches `reminderTargets`, so nobody calls
/// "reschedule" and there is no second place that has to remember to. This
/// provider keeps that property while adding the real data source -- it writes
/// the targets and nothing else. No scheduler call appears anywhere in the
/// board code.
///
/// ## Why it is a provider with two `listen`s
///
/// - The board is *listened to*, not watched, because writing another
///   notifier's state is a side effect and belongs outside a build.
/// - `reminderSync` is listened to with an empty callback purely to keep it
///   alive. A `keepAlive` provider that nobody subscribes to is never created
///   at all, so without this the targets would change and nothing downstream
///   would exist to notice. An empty `listen` rather than a `watch` because a
///   `watch` would rebuild this provider on every sync report and re-register
///   both subscriptions.
///
/// The board screen watches this once; that is the only thing that has to
/// remember anything.
@Riverpod(keepAlive: true)
void boardReminderBridge(Ref ref) {
  List<BoardProject>? published;

  void publish(BoardView view) {
    if (view is! BoardReady) return;

    // Identity, not equality: every `isRefreshing` flip produces a new
    // `BoardView` around the *same* list instance, and re-publishing an
    // unchanged set would re-arm every alarm for nothing.
    if (identical(view.projects, published)) return;
    published = view.projects;

    ref
        .read(reminderTargetsProvider.notifier)
        .replaceWith(remindersFromBoard(view.projects));
  }

  ref.listen(reminderSyncProvider, (_, _) {});

  // Writing another provider's state from a listener callback is fine *here*:
  // Riverpod clears its "currently building" marker before notifying listeners
  // of a rebuild, specifically so that a rebuild can update other providers.
  // Note this arms alarms from the *cached* board too, not just from the
  // network one -- knowing `remindAt` with no network is half the reason the
  // snapshot exists at all.
  ref.listen(boardViewProvider, (_, next) => publish(next));

  /*
   * Catch-up for a board that already has a value by the time this provider is
   * first created -- a re-mount, a hot restart, a navigation back to the board.
   * The listener above only fires on *changes*, so without this the very first
   * board would be skipped.
   *
   * `fireImmediately: true` is the obvious way to write it and is wrong: it
   * runs the callback synchronously inside *this* build, and Riverpod asserts
   * "Providers are not allowed to modify other providers during their
   * initialization". Deferring the read by one microtask puts it after this
   * build has finished, which is the only ordering that makes sense anyway --
   * the board is published first, the alarms follow.
   */
  Future.microtask(() {
    if (!ref.mounted) return;
    publish(ref.read(boardViewProvider));
  });
}
