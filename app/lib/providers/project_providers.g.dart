// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The project screen's state (F3): one project, its tasks, its notes, and
/// every write in the application.
///
/// ## The three rules this file is built around
///
/// The migration plan fixes three properties that a mutation path is very good
/// at breaking, so they are restated here where the breaking would happen:
///
/// 1. **The server computes `isCurrent`; the client never re-derives it.** The
///    rule ("the first `pending` task in `position` order") is three lines long
///    and lives in `backend/src/domain/isCurrent.ts` -- which is exactly why
///    reimplementing it is tempting and wrong. It is a property of the whole
///    ordered list, and a second copy of it would drift the first time the
///    backend gains a status, an archived flag, or a scope.
///
/// 2. **The cache is read-only; every write needs the network.** There is no
///    operation queue and no conflict resolution. An optimistic update is a
///    *prediction shown for one round trip*, not an offline edit: when the write
///    fails the prediction is rolled back and the failure is said out loud.
///
/// 3. **Changing the reminder target set *is* the reschedule.** Nothing in this
///    file mentions the scheduler. Writes flow into the board (see
///    [Board.applyProjectTasks]) and `boardReminderBridge` does the rest,
///    because a second place that remembers to re-arm alarms is a second place
///    that can forget.
///
/// ## What "reconcile" means, and why most writes do one
///
/// `POST /projects/:id/tasks`, `PATCH /tasks/:id` and `PATCH /tasks/:id/position`
/// each answer with a single raw row: no `isCurrent`, and -- for a move -- no
/// word about the *other* rows the server may have renumbered when the float gap
/// between two neighbours ran out (see `ProjectApi`, and
/// `backend/src/domain/position.ts`). So any mutation that can move the "first
/// pending task" around, or that can trigger a rebalance, ends with one
/// `GET /projects/:id/tasks`: the cheapest question whose answer is complete.
///
/// That is one extra request for a create, a status change, a delete or a move,
/// and **zero** for a title or description edit (which provably change neither
/// the order nor which task is current -- see [mergeMutatedTask]) and zero for
/// anything to do with notes. The board is then updated from the very same
/// response instead of being refetched, so a write costs at most two round
/// trips total, never a board reload on top.
// --- reading ----------------------------------------------------------------
/// The project's own row.
///
/// ## Why this usually costs nothing
///
/// A board row is `GET /projects/:id`'s answer with the tasks attached
/// (`backend/src/routes/board.ts`), so when the board is loaded -- which is
/// every time the user got here by tapping a card -- the project is already in
/// memory and asking the server again would be asking a question we hold the
/// answer to. The fetch is for the other entry point: F4's notification deep
/// link, which can land here on a cold start with nothing loaded.
///
/// `ref.read` rather than `ref.watch` on the board: this is a one-shot lookup,
/// and watching would rebuild the provider on every board tick -- including the
/// ticks this screen's own task writes produce through
/// [Board.applyProjectTasks]. For a project that is *not* on the board (the
/// archived one a reminder deep link opens) each of those rebuilds would be a
/// fresh `GET /projects/:id`.
///
/// That leaves one way for the row to change under us, and it is the reason
/// [applyProject] exists: `PATCH /projects/:id` can rename a project, and the
/// rename is pushed in here rather than pulled -- see
/// `ProjectLifecycle.rename`.
///
/// A 404 (deleted, or archived -- `getProjectOrThrow` makes no distinction, and
/// that is deliberate) is not caught: [projectView] turns it into
/// [ProjectMissing].

@ProviderFor(ProjectHeader)
final projectHeaderProvider = ProjectHeaderFamily._();

/// The project screen's state (F3): one project, its tasks, its notes, and
/// every write in the application.
///
/// ## The three rules this file is built around
///
/// The migration plan fixes three properties that a mutation path is very good
/// at breaking, so they are restated here where the breaking would happen:
///
/// 1. **The server computes `isCurrent`; the client never re-derives it.** The
///    rule ("the first `pending` task in `position` order") is three lines long
///    and lives in `backend/src/domain/isCurrent.ts` -- which is exactly why
///    reimplementing it is tempting and wrong. It is a property of the whole
///    ordered list, and a second copy of it would drift the first time the
///    backend gains a status, an archived flag, or a scope.
///
/// 2. **The cache is read-only; every write needs the network.** There is no
///    operation queue and no conflict resolution. An optimistic update is a
///    *prediction shown for one round trip*, not an offline edit: when the write
///    fails the prediction is rolled back and the failure is said out loud.
///
/// 3. **Changing the reminder target set *is* the reschedule.** Nothing in this
///    file mentions the scheduler. Writes flow into the board (see
///    [Board.applyProjectTasks]) and `boardReminderBridge` does the rest,
///    because a second place that remembers to re-arm alarms is a second place
///    that can forget.
///
/// ## What "reconcile" means, and why most writes do one
///
/// `POST /projects/:id/tasks`, `PATCH /tasks/:id` and `PATCH /tasks/:id/position`
/// each answer with a single raw row: no `isCurrent`, and -- for a move -- no
/// word about the *other* rows the server may have renumbered when the float gap
/// between two neighbours ran out (see `ProjectApi`, and
/// `backend/src/domain/position.ts`). So any mutation that can move the "first
/// pending task" around, or that can trigger a rebalance, ends with one
/// `GET /projects/:id/tasks`: the cheapest question whose answer is complete.
///
/// That is one extra request for a create, a status change, a delete or a move,
/// and **zero** for a title or description edit (which provably change neither
/// the order nor which task is current -- see [mergeMutatedTask]) and zero for
/// anything to do with notes. The board is then updated from the very same
/// response instead of being refetched, so a write costs at most two round
/// trips total, never a board reload on top.
// --- reading ----------------------------------------------------------------
/// The project's own row.
///
/// ## Why this usually costs nothing
///
/// A board row is `GET /projects/:id`'s answer with the tasks attached
/// (`backend/src/routes/board.ts`), so when the board is loaded -- which is
/// every time the user got here by tapping a card -- the project is already in
/// memory and asking the server again would be asking a question we hold the
/// answer to. The fetch is for the other entry point: F4's notification deep
/// link, which can land here on a cold start with nothing loaded.
///
/// `ref.read` rather than `ref.watch` on the board: this is a one-shot lookup,
/// and watching would rebuild the provider on every board tick -- including the
/// ticks this screen's own task writes produce through
/// [Board.applyProjectTasks]. For a project that is *not* on the board (the
/// archived one a reminder deep link opens) each of those rebuilds would be a
/// fresh `GET /projects/:id`.
///
/// That leaves one way for the row to change under us, and it is the reason
/// [applyProject] exists: `PATCH /projects/:id` can rename a project, and the
/// rename is pushed in here rather than pulled -- see
/// `ProjectLifecycle.rename`.
///
/// A 404 (deleted, or archived -- `getProjectOrThrow` makes no distinction, and
/// that is deliberate) is not caught: [projectView] turns it into
/// [ProjectMissing].
final class ProjectHeaderProvider
    extends $AsyncNotifierProvider<ProjectHeader, Project> {
  /// The project screen's state (F3): one project, its tasks, its notes, and
  /// every write in the application.
  ///
  /// ## The three rules this file is built around
  ///
  /// The migration plan fixes three properties that a mutation path is very good
  /// at breaking, so they are restated here where the breaking would happen:
  ///
  /// 1. **The server computes `isCurrent`; the client never re-derives it.** The
  ///    rule ("the first `pending` task in `position` order") is three lines long
  ///    and lives in `backend/src/domain/isCurrent.ts` -- which is exactly why
  ///    reimplementing it is tempting and wrong. It is a property of the whole
  ///    ordered list, and a second copy of it would drift the first time the
  ///    backend gains a status, an archived flag, or a scope.
  ///
  /// 2. **The cache is read-only; every write needs the network.** There is no
  ///    operation queue and no conflict resolution. An optimistic update is a
  ///    *prediction shown for one round trip*, not an offline edit: when the write
  ///    fails the prediction is rolled back and the failure is said out loud.
  ///
  /// 3. **Changing the reminder target set *is* the reschedule.** Nothing in this
  ///    file mentions the scheduler. Writes flow into the board (see
  ///    [Board.applyProjectTasks]) and `boardReminderBridge` does the rest,
  ///    because a second place that remembers to re-arm alarms is a second place
  ///    that can forget.
  ///
  /// ## What "reconcile" means, and why most writes do one
  ///
  /// `POST /projects/:id/tasks`, `PATCH /tasks/:id` and `PATCH /tasks/:id/position`
  /// each answer with a single raw row: no `isCurrent`, and -- for a move -- no
  /// word about the *other* rows the server may have renumbered when the float gap
  /// between two neighbours ran out (see `ProjectApi`, and
  /// `backend/src/domain/position.ts`). So any mutation that can move the "first
  /// pending task" around, or that can trigger a rebalance, ends with one
  /// `GET /projects/:id/tasks`: the cheapest question whose answer is complete.
  ///
  /// That is one extra request for a create, a status change, a delete or a move,
  /// and **zero** for a title or description edit (which provably change neither
  /// the order nor which task is current -- see [mergeMutatedTask]) and zero for
  /// anything to do with notes. The board is then updated from the very same
  /// response instead of being refetched, so a write costs at most two round
  /// trips total, never a board reload on top.
  // --- reading ----------------------------------------------------------------
  /// The project's own row.
  ///
  /// ## Why this usually costs nothing
  ///
  /// A board row is `GET /projects/:id`'s answer with the tasks attached
  /// (`backend/src/routes/board.ts`), so when the board is loaded -- which is
  /// every time the user got here by tapping a card -- the project is already in
  /// memory and asking the server again would be asking a question we hold the
  /// answer to. The fetch is for the other entry point: F4's notification deep
  /// link, which can land here on a cold start with nothing loaded.
  ///
  /// `ref.read` rather than `ref.watch` on the board: this is a one-shot lookup,
  /// and watching would rebuild the provider on every board tick -- including the
  /// ticks this screen's own task writes produce through
  /// [Board.applyProjectTasks]. For a project that is *not* on the board (the
  /// archived one a reminder deep link opens) each of those rebuilds would be a
  /// fresh `GET /projects/:id`.
  ///
  /// That leaves one way for the row to change under us, and it is the reason
  /// [applyProject] exists: `PATCH /projects/:id` can rename a project, and the
  /// rename is pushed in here rather than pulled -- see
  /// `ProjectLifecycle.rename`.
  ///
  /// A 404 (deleted, or archived -- `getProjectOrThrow` makes no distinction, and
  /// that is deliberate) is not caught: [projectView] turns it into
  /// [ProjectMissing].
  ProjectHeaderProvider._({
    required ProjectHeaderFamily super.from,
    required String super.argument,
  }) : super(
         retry: noAutomaticRetry,
         name: r'projectHeaderProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectHeaderHash();

  @override
  String toString() {
    return r'projectHeaderProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProjectHeader create() => ProjectHeader();

  @override
  bool operator ==(Object other) {
    return other is ProjectHeaderProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectHeaderHash() => r'fa6bbc40c5a329b6c2e938a56f654c0fa35805d9';

/// The project screen's state (F3): one project, its tasks, its notes, and
/// every write in the application.
///
/// ## The three rules this file is built around
///
/// The migration plan fixes three properties that a mutation path is very good
/// at breaking, so they are restated here where the breaking would happen:
///
/// 1. **The server computes `isCurrent`; the client never re-derives it.** The
///    rule ("the first `pending` task in `position` order") is three lines long
///    and lives in `backend/src/domain/isCurrent.ts` -- which is exactly why
///    reimplementing it is tempting and wrong. It is a property of the whole
///    ordered list, and a second copy of it would drift the first time the
///    backend gains a status, an archived flag, or a scope.
///
/// 2. **The cache is read-only; every write needs the network.** There is no
///    operation queue and no conflict resolution. An optimistic update is a
///    *prediction shown for one round trip*, not an offline edit: when the write
///    fails the prediction is rolled back and the failure is said out loud.
///
/// 3. **Changing the reminder target set *is* the reschedule.** Nothing in this
///    file mentions the scheduler. Writes flow into the board (see
///    [Board.applyProjectTasks]) and `boardReminderBridge` does the rest,
///    because a second place that remembers to re-arm alarms is a second place
///    that can forget.
///
/// ## What "reconcile" means, and why most writes do one
///
/// `POST /projects/:id/tasks`, `PATCH /tasks/:id` and `PATCH /tasks/:id/position`
/// each answer with a single raw row: no `isCurrent`, and -- for a move -- no
/// word about the *other* rows the server may have renumbered when the float gap
/// between two neighbours ran out (see `ProjectApi`, and
/// `backend/src/domain/position.ts`). So any mutation that can move the "first
/// pending task" around, or that can trigger a rebalance, ends with one
/// `GET /projects/:id/tasks`: the cheapest question whose answer is complete.
///
/// That is one extra request for a create, a status change, a delete or a move,
/// and **zero** for a title or description edit (which provably change neither
/// the order nor which task is current -- see [mergeMutatedTask]) and zero for
/// anything to do with notes. The board is then updated from the very same
/// response instead of being refetched, so a write costs at most two round
/// trips total, never a board reload on top.
// --- reading ----------------------------------------------------------------
/// The project's own row.
///
/// ## Why this usually costs nothing
///
/// A board row is `GET /projects/:id`'s answer with the tasks attached
/// (`backend/src/routes/board.ts`), so when the board is loaded -- which is
/// every time the user got here by tapping a card -- the project is already in
/// memory and asking the server again would be asking a question we hold the
/// answer to. The fetch is for the other entry point: F4's notification deep
/// link, which can land here on a cold start with nothing loaded.
///
/// `ref.read` rather than `ref.watch` on the board: this is a one-shot lookup,
/// and watching would rebuild the provider on every board tick -- including the
/// ticks this screen's own task writes produce through
/// [Board.applyProjectTasks]. For a project that is *not* on the board (the
/// archived one a reminder deep link opens) each of those rebuilds would be a
/// fresh `GET /projects/:id`.
///
/// That leaves one way for the row to change under us, and it is the reason
/// [applyProject] exists: `PATCH /projects/:id` can rename a project, and the
/// rename is pushed in here rather than pulled -- see
/// `ProjectLifecycle.rename`.
///
/// A 404 (deleted, or archived -- `getProjectOrThrow` makes no distinction, and
/// that is deliberate) is not caught: [projectView] turns it into
/// [ProjectMissing].

final class ProjectHeaderFamily extends $Family
    with
        $ClassFamilyOverride<
          ProjectHeader,
          AsyncValue<Project>,
          Project,
          FutureOr<Project>,
          String
        > {
  ProjectHeaderFamily._()
    : super(
        retry: noAutomaticRetry,
        name: r'projectHeaderProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The project screen's state (F3): one project, its tasks, its notes, and
  /// every write in the application.
  ///
  /// ## The three rules this file is built around
  ///
  /// The migration plan fixes three properties that a mutation path is very good
  /// at breaking, so they are restated here where the breaking would happen:
  ///
  /// 1. **The server computes `isCurrent`; the client never re-derives it.** The
  ///    rule ("the first `pending` task in `position` order") is three lines long
  ///    and lives in `backend/src/domain/isCurrent.ts` -- which is exactly why
  ///    reimplementing it is tempting and wrong. It is a property of the whole
  ///    ordered list, and a second copy of it would drift the first time the
  ///    backend gains a status, an archived flag, or a scope.
  ///
  /// 2. **The cache is read-only; every write needs the network.** There is no
  ///    operation queue and no conflict resolution. An optimistic update is a
  ///    *prediction shown for one round trip*, not an offline edit: when the write
  ///    fails the prediction is rolled back and the failure is said out loud.
  ///
  /// 3. **Changing the reminder target set *is* the reschedule.** Nothing in this
  ///    file mentions the scheduler. Writes flow into the board (see
  ///    [Board.applyProjectTasks]) and `boardReminderBridge` does the rest,
  ///    because a second place that remembers to re-arm alarms is a second place
  ///    that can forget.
  ///
  /// ## What "reconcile" means, and why most writes do one
  ///
  /// `POST /projects/:id/tasks`, `PATCH /tasks/:id` and `PATCH /tasks/:id/position`
  /// each answer with a single raw row: no `isCurrent`, and -- for a move -- no
  /// word about the *other* rows the server may have renumbered when the float gap
  /// between two neighbours ran out (see `ProjectApi`, and
  /// `backend/src/domain/position.ts`). So any mutation that can move the "first
  /// pending task" around, or that can trigger a rebalance, ends with one
  /// `GET /projects/:id/tasks`: the cheapest question whose answer is complete.
  ///
  /// That is one extra request for a create, a status change, a delete or a move,
  /// and **zero** for a title or description edit (which provably change neither
  /// the order nor which task is current -- see [mergeMutatedTask]) and zero for
  /// anything to do with notes. The board is then updated from the very same
  /// response instead of being refetched, so a write costs at most two round
  /// trips total, never a board reload on top.
  // --- reading ----------------------------------------------------------------
  /// The project's own row.
  ///
  /// ## Why this usually costs nothing
  ///
  /// A board row is `GET /projects/:id`'s answer with the tasks attached
  /// (`backend/src/routes/board.ts`), so when the board is loaded -- which is
  /// every time the user got here by tapping a card -- the project is already in
  /// memory and asking the server again would be asking a question we hold the
  /// answer to. The fetch is for the other entry point: F4's notification deep
  /// link, which can land here on a cold start with nothing loaded.
  ///
  /// `ref.read` rather than `ref.watch` on the board: this is a one-shot lookup,
  /// and watching would rebuild the provider on every board tick -- including the
  /// ticks this screen's own task writes produce through
  /// [Board.applyProjectTasks]. For a project that is *not* on the board (the
  /// archived one a reminder deep link opens) each of those rebuilds would be a
  /// fresh `GET /projects/:id`.
  ///
  /// That leaves one way for the row to change under us, and it is the reason
  /// [applyProject] exists: `PATCH /projects/:id` can rename a project, and the
  /// rename is pushed in here rather than pulled -- see
  /// `ProjectLifecycle.rename`.
  ///
  /// A 404 (deleted, or archived -- `getProjectOrThrow` makes no distinction, and
  /// that is deliberate) is not caught: [projectView] turns it into
  /// [ProjectMissing].

  ProjectHeaderProvider call(String projectId) =>
      ProjectHeaderProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectHeaderProvider';
}

/// The project screen's state (F3): one project, its tasks, its notes, and
/// every write in the application.
///
/// ## The three rules this file is built around
///
/// The migration plan fixes three properties that a mutation path is very good
/// at breaking, so they are restated here where the breaking would happen:
///
/// 1. **The server computes `isCurrent`; the client never re-derives it.** The
///    rule ("the first `pending` task in `position` order") is three lines long
///    and lives in `backend/src/domain/isCurrent.ts` -- which is exactly why
///    reimplementing it is tempting and wrong. It is a property of the whole
///    ordered list, and a second copy of it would drift the first time the
///    backend gains a status, an archived flag, or a scope.
///
/// 2. **The cache is read-only; every write needs the network.** There is no
///    operation queue and no conflict resolution. An optimistic update is a
///    *prediction shown for one round trip*, not an offline edit: when the write
///    fails the prediction is rolled back and the failure is said out loud.
///
/// 3. **Changing the reminder target set *is* the reschedule.** Nothing in this
///    file mentions the scheduler. Writes flow into the board (see
///    [Board.applyProjectTasks]) and `boardReminderBridge` does the rest,
///    because a second place that remembers to re-arm alarms is a second place
///    that can forget.
///
/// ## What "reconcile" means, and why most writes do one
///
/// `POST /projects/:id/tasks`, `PATCH /tasks/:id` and `PATCH /tasks/:id/position`
/// each answer with a single raw row: no `isCurrent`, and -- for a move -- no
/// word about the *other* rows the server may have renumbered when the float gap
/// between two neighbours ran out (see `ProjectApi`, and
/// `backend/src/domain/position.ts`). So any mutation that can move the "first
/// pending task" around, or that can trigger a rebalance, ends with one
/// `GET /projects/:id/tasks`: the cheapest question whose answer is complete.
///
/// That is one extra request for a create, a status change, a delete or a move,
/// and **zero** for a title or description edit (which provably change neither
/// the order nor which task is current -- see [mergeMutatedTask]) and zero for
/// anything to do with notes. The board is then updated from the very same
/// response instead of being refetched, so a write costs at most two round
/// trips total, never a board reload on top.
// --- reading ----------------------------------------------------------------
/// The project's own row.
///
/// ## Why this usually costs nothing
///
/// A board row is `GET /projects/:id`'s answer with the tasks attached
/// (`backend/src/routes/board.ts`), so when the board is loaded -- which is
/// every time the user got here by tapping a card -- the project is already in
/// memory and asking the server again would be asking a question we hold the
/// answer to. The fetch is for the other entry point: F4's notification deep
/// link, which can land here on a cold start with nothing loaded.
///
/// `ref.read` rather than `ref.watch` on the board: this is a one-shot lookup,
/// and watching would rebuild the provider on every board tick -- including the
/// ticks this screen's own task writes produce through
/// [Board.applyProjectTasks]. For a project that is *not* on the board (the
/// archived one a reminder deep link opens) each of those rebuilds would be a
/// fresh `GET /projects/:id`.
///
/// That leaves one way for the row to change under us, and it is the reason
/// [applyProject] exists: `PATCH /projects/:id` can rename a project, and the
/// rename is pushed in here rather than pulled -- see
/// `ProjectLifecycle.rename`.
///
/// A 404 (deleted, or archived -- `getProjectOrThrow` makes no distinction, and
/// that is deliberate) is not caught: [projectView] turns it into
/// [ProjectMissing].

abstract class _$ProjectHeader extends $AsyncNotifier<Project> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<Project> build(String projectId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Project>, Project>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Project>, Project>,
              AsyncValue<Project>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

/// One project's tasks, and every write that touches them.

@ProviderFor(ProjectTasks)
final projectTasksProvider = ProjectTasksFamily._();

/// One project's tasks, and every write that touches them.
final class ProjectTasksProvider
    extends $AsyncNotifierProvider<ProjectTasks, List<Task>> {
  /// One project's tasks, and every write that touches them.
  ProjectTasksProvider._({
    required ProjectTasksFamily super.from,
    required String super.argument,
  }) : super(
         retry: noAutomaticRetry,
         name: r'projectTasksProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectTasksHash();

  @override
  String toString() {
    return r'projectTasksProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProjectTasks create() => ProjectTasks();

  @override
  bool operator ==(Object other) {
    return other is ProjectTasksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectTasksHash() => r'732912f1127aa7912a92bf1c6955ee4486ac33b4';

/// One project's tasks, and every write that touches them.

final class ProjectTasksFamily extends $Family
    with
        $ClassFamilyOverride<
          ProjectTasks,
          AsyncValue<List<Task>>,
          List<Task>,
          FutureOr<List<Task>>,
          String
        > {
  ProjectTasksFamily._()
    : super(
        retry: noAutomaticRetry,
        name: r'projectTasksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One project's tasks, and every write that touches them.

  ProjectTasksProvider call(String projectId) =>
      ProjectTasksProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectTasksProvider';
}

/// One project's tasks, and every write that touches them.

abstract class _$ProjectTasks extends $AsyncNotifier<List<Task>> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<List<Task>> build(String projectId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Task>>, List<Task>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Task>>, List<Task>>,
              AsyncValue<List<Task>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

/// One project's notes, and their CRUD.
///
/// Much simpler than [ProjectTasks] for one structural reason: a note has no
/// server-computed field and no ordering key, so `POST` and `PATCH` return the
/// complete truth about the row and there is nothing to reconcile. Notes also
/// never appear on the board, so nothing is pushed there.

@ProviderFor(ProjectNotes)
final projectNotesProvider = ProjectNotesFamily._();

/// One project's notes, and their CRUD.
///
/// Much simpler than [ProjectTasks] for one structural reason: a note has no
/// server-computed field and no ordering key, so `POST` and `PATCH` return the
/// complete truth about the row and there is nothing to reconcile. Notes also
/// never appear on the board, so nothing is pushed there.
final class ProjectNotesProvider
    extends $AsyncNotifierProvider<ProjectNotes, List<Note>> {
  /// One project's notes, and their CRUD.
  ///
  /// Much simpler than [ProjectTasks] for one structural reason: a note has no
  /// server-computed field and no ordering key, so `POST` and `PATCH` return the
  /// complete truth about the row and there is nothing to reconcile. Notes also
  /// never appear on the board, so nothing is pushed there.
  ProjectNotesProvider._({
    required ProjectNotesFamily super.from,
    required String super.argument,
  }) : super(
         retry: noAutomaticRetry,
         name: r'projectNotesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectNotesHash();

  @override
  String toString() {
    return r'projectNotesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ProjectNotes create() => ProjectNotes();

  @override
  bool operator ==(Object other) {
    return other is ProjectNotesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectNotesHash() => r'd5fb681bde450be55e421c4a26da3d791b82f8d8';

/// One project's notes, and their CRUD.
///
/// Much simpler than [ProjectTasks] for one structural reason: a note has no
/// server-computed field and no ordering key, so `POST` and `PATCH` return the
/// complete truth about the row and there is nothing to reconcile. Notes also
/// never appear on the board, so nothing is pushed there.

final class ProjectNotesFamily extends $Family
    with
        $ClassFamilyOverride<
          ProjectNotes,
          AsyncValue<List<Note>>,
          List<Note>,
          FutureOr<List<Note>>,
          String
        > {
  ProjectNotesFamily._()
    : super(
        retry: noAutomaticRetry,
        name: r'projectNotesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One project's notes, and their CRUD.
  ///
  /// Much simpler than [ProjectTasks] for one structural reason: a note has no
  /// server-computed field and no ordering key, so `POST` and `PATCH` return the
  /// complete truth about the row and there is nothing to reconcile. Notes also
  /// never appear on the board, so nothing is pushed there.

  ProjectNotesProvider call(String projectId) =>
      ProjectNotesProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectNotesProvider';
}

/// One project's notes, and their CRUD.
///
/// Much simpler than [ProjectTasks] for one structural reason: a note has no
/// server-computed field and no ordering key, so `POST` and `PATCH` return the
/// complete truth about the row and there is nothing to reconcile. Notes also
/// never appear on the board, so nothing is pushed there.

abstract class _$ProjectNotes extends $AsyncNotifier<List<Note>> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<List<Note>> build(String projectId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Note>>, List<Note>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Note>>, List<Note>>,
              AsyncValue<List<Note>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

/// Folds the network reads and the board snapshot into the single value the
/// screen renders.
///
/// Same shape, and the same reasoning, as `boardView`: two sources that must not
/// race are kept apart and combined in a plain synchronous provider. The payoff
/// here is that a project opened from the board draws instantly -- its tasks are
/// already in memory, and after F4's notification deep link they may be in the
/// *snapshot* with no network at all, which is the whole reason the snapshot
/// holds tasks rather than just project names.

@ProviderFor(projectView)
final projectViewProvider = ProjectViewFamily._();

/// Folds the network reads and the board snapshot into the single value the
/// screen renders.
///
/// Same shape, and the same reasoning, as `boardView`: two sources that must not
/// race are kept apart and combined in a plain synchronous provider. The payoff
/// here is that a project opened from the board draws instantly -- its tasks are
/// already in memory, and after F4's notification deep link they may be in the
/// *snapshot* with no network at all, which is the whole reason the snapshot
/// holds tasks rather than just project names.

final class ProjectViewProvider
    extends $FunctionalProvider<ProjectView, ProjectView, ProjectView>
    with $Provider<ProjectView> {
  /// Folds the network reads and the board snapshot into the single value the
  /// screen renders.
  ///
  /// Same shape, and the same reasoning, as `boardView`: two sources that must not
  /// race are kept apart and combined in a plain synchronous provider. The payoff
  /// here is that a project opened from the board draws instantly -- its tasks are
  /// already in memory, and after F4's notification deep link they may be in the
  /// *snapshot* with no network at all, which is the whole reason the snapshot
  /// holds tasks rather than just project names.
  ProjectViewProvider._({
    required ProjectViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectViewHash();

  @override
  String toString() {
    return r'projectViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ProjectView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProjectView create(Ref ref) {
    final argument = this.argument as String;
    return projectView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProjectView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProjectView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectViewHash() => r'b6157c4652f60de2a825d34fa7fb258cecb8e66d';

/// Folds the network reads and the board snapshot into the single value the
/// screen renders.
///
/// Same shape, and the same reasoning, as `boardView`: two sources that must not
/// race are kept apart and combined in a plain synchronous provider. The payoff
/// here is that a project opened from the board draws instantly -- its tasks are
/// already in memory, and after F4's notification deep link they may be in the
/// *snapshot* with no network at all, which is the whole reason the snapshot
/// holds tasks rather than just project names.

final class ProjectViewFamily extends $Family
    with $FunctionalFamilyOverride<ProjectView, String> {
  ProjectViewFamily._()
    : super(
        retry: null,
        name: r'projectViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Folds the network reads and the board snapshot into the single value the
  /// screen renders.
  ///
  /// Same shape, and the same reasoning, as `boardView`: two sources that must not
  /// race are kept apart and combined in a plain synchronous provider. The payoff
  /// here is that a project opened from the board draws instantly -- its tasks are
  /// already in memory, and after F4's notification deep link they may be in the
  /// *snapshot* with no network at all, which is the whole reason the snapshot
  /// holds tasks rather than just project names.

  ProjectViewProvider call(String projectId) =>
      ProjectViewProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectViewProvider';
}
