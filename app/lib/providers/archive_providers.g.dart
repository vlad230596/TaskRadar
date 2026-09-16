// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'archive_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The archive, the four writes that move a project between the board, the
/// archive and nothing at all (F4), and the rename that moves it nowhere (B6).
///
/// ## Why archive and delete are two different things
///
/// Copied from Trello on purpose -- `../../project-tracker-brief.md` records the
/// observation and the decision. An archive is reversible and is the move you
/// make constantly ("this one is done for now"); a delete is irreversible and is
/// the move you make twice a year. Collapsing them into one button means the
/// frequent gesture and the unrecoverable one are the same gesture.
///
/// The backend enforces the ordering rather than trusting the UI:
/// `canHardDeleteProject` (`backend/src/domain/projectDeleteGuard.ts`) answers
/// 409 for a project that is still active, so `DELETE /projects/:id` is only
/// ever reachable *through* the archive. This file mirrors that in the client so
/// the refusal is instant and legible, but the guard itself stays on the server,
/// where no client can skip it.
///
/// ## Why some of these invalidate the board and one of them splices it
///
/// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
/// write inside a project: the row is still there, only its tasks changed.
/// Create, archive, unarchive and delete change **which rows exist**, on both
/// boards at once, and there is no splice that can express "this project is now
/// on the other board". So they invalidate, which costs one `GET /board` per
/// action -- something a person does a handful of times a week.
///
/// [ProjectLifecycle.rename] is the opposite case and therefore takes the
/// opposite route: the row stays exactly where it is and one string in it
/// changes, so it is spliced into whichever lists are on screen
/// ([Board.applyProject], [ArchivedBoard.applyProject],
/// [ProjectHeader.applyProject]) and costs no read at all.
///
/// Either way the alarms follow, with no scheduler call anywhere: whatever
/// changes the board -- an invalidation or a splice -- changes the target set,
/// `boardReminderBridge` publishes it, and `reminderSync` re-arms. An archived
/// project stops nagging because its blocked tasks are no longer on the board
/// (that is what archiving *means*), and a renamed project's alarms start saying
/// the new name because the notification text carries it.
/// `GET /board?archived=true` -- the archive, in the same shape as the board.
///
/// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
/// app's home. Letting it dispose means re-opening it re-reads, which is what
/// you want from a list whose whole purpose is to be acted on.
///
/// No snapshot and no cache. The archive is never the thing you need at 09:00
/// with no signal, and a second cache file to keep in step would be pure cost.
///
/// A notifier rather than a plain future provider only because of [applyProject]
/// -- renaming a project from this screen has to show up in it without paying
/// for a second `GET /board?archived=true`.

@ProviderFor(ArchivedBoard)
final archivedBoardProvider = ArchivedBoardProvider._();

/// The archive, the four writes that move a project between the board, the
/// archive and nothing at all (F4), and the rename that moves it nowhere (B6).
///
/// ## Why archive and delete are two different things
///
/// Copied from Trello on purpose -- `../../project-tracker-brief.md` records the
/// observation and the decision. An archive is reversible and is the move you
/// make constantly ("this one is done for now"); a delete is irreversible and is
/// the move you make twice a year. Collapsing them into one button means the
/// frequent gesture and the unrecoverable one are the same gesture.
///
/// The backend enforces the ordering rather than trusting the UI:
/// `canHardDeleteProject` (`backend/src/domain/projectDeleteGuard.ts`) answers
/// 409 for a project that is still active, so `DELETE /projects/:id` is only
/// ever reachable *through* the archive. This file mirrors that in the client so
/// the refusal is instant and legible, but the guard itself stays on the server,
/// where no client can skip it.
///
/// ## Why some of these invalidate the board and one of them splices it
///
/// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
/// write inside a project: the row is still there, only its tasks changed.
/// Create, archive, unarchive and delete change **which rows exist**, on both
/// boards at once, and there is no splice that can express "this project is now
/// on the other board". So they invalidate, which costs one `GET /board` per
/// action -- something a person does a handful of times a week.
///
/// [ProjectLifecycle.rename] is the opposite case and therefore takes the
/// opposite route: the row stays exactly where it is and one string in it
/// changes, so it is spliced into whichever lists are on screen
/// ([Board.applyProject], [ArchivedBoard.applyProject],
/// [ProjectHeader.applyProject]) and costs no read at all.
///
/// Either way the alarms follow, with no scheduler call anywhere: whatever
/// changes the board -- an invalidation or a splice -- changes the target set,
/// `boardReminderBridge` publishes it, and `reminderSync` re-arms. An archived
/// project stops nagging because its blocked tasks are no longer on the board
/// (that is what archiving *means*), and a renamed project's alarms start saying
/// the new name because the notification text carries it.
/// `GET /board?archived=true` -- the archive, in the same shape as the board.
///
/// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
/// app's home. Letting it dispose means re-opening it re-reads, which is what
/// you want from a list whose whole purpose is to be acted on.
///
/// No snapshot and no cache. The archive is never the thing you need at 09:00
/// with no signal, and a second cache file to keep in step would be pure cost.
///
/// A notifier rather than a plain future provider only because of [applyProject]
/// -- renaming a project from this screen has to show up in it without paying
/// for a second `GET /board?archived=true`.
final class ArchivedBoardProvider
    extends $AsyncNotifierProvider<ArchivedBoard, List<BoardProject>> {
  /// The archive, the four writes that move a project between the board, the
  /// archive and nothing at all (F4), and the rename that moves it nowhere (B6).
  ///
  /// ## Why archive and delete are two different things
  ///
  /// Copied from Trello on purpose -- `../../project-tracker-brief.md` records the
  /// observation and the decision. An archive is reversible and is the move you
  /// make constantly ("this one is done for now"); a delete is irreversible and is
  /// the move you make twice a year. Collapsing them into one button means the
  /// frequent gesture and the unrecoverable one are the same gesture.
  ///
  /// The backend enforces the ordering rather than trusting the UI:
  /// `canHardDeleteProject` (`backend/src/domain/projectDeleteGuard.ts`) answers
  /// 409 for a project that is still active, so `DELETE /projects/:id` is only
  /// ever reachable *through* the archive. This file mirrors that in the client so
  /// the refusal is instant and legible, but the guard itself stays on the server,
  /// where no client can skip it.
  ///
  /// ## Why some of these invalidate the board and one of them splices it
  ///
  /// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
  /// write inside a project: the row is still there, only its tasks changed.
  /// Create, archive, unarchive and delete change **which rows exist**, on both
  /// boards at once, and there is no splice that can express "this project is now
  /// on the other board". So they invalidate, which costs one `GET /board` per
  /// action -- something a person does a handful of times a week.
  ///
  /// [ProjectLifecycle.rename] is the opposite case and therefore takes the
  /// opposite route: the row stays exactly where it is and one string in it
  /// changes, so it is spliced into whichever lists are on screen
  /// ([Board.applyProject], [ArchivedBoard.applyProject],
  /// [ProjectHeader.applyProject]) and costs no read at all.
  ///
  /// Either way the alarms follow, with no scheduler call anywhere: whatever
  /// changes the board -- an invalidation or a splice -- changes the target set,
  /// `boardReminderBridge` publishes it, and `reminderSync` re-arms. An archived
  /// project stops nagging because its blocked tasks are no longer on the board
  /// (that is what archiving *means*), and a renamed project's alarms start saying
  /// the new name because the notification text carries it.
  /// `GET /board?archived=true` -- the archive, in the same shape as the board.
  ///
  /// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
  /// app's home. Letting it dispose means re-opening it re-reads, which is what
  /// you want from a list whose whole purpose is to be acted on.
  ///
  /// No snapshot and no cache. The archive is never the thing you need at 09:00
  /// with no signal, and a second cache file to keep in step would be pure cost.
  ///
  /// A notifier rather than a plain future provider only because of [applyProject]
  /// -- renaming a project from this screen has to show up in it without paying
  /// for a second `GET /board?archived=true`.
  ArchivedBoardProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'archivedBoardProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$archivedBoardHash();

  @$internal
  @override
  ArchivedBoard create() => ArchivedBoard();
}

String _$archivedBoardHash() => r'33698be63585b96ecb93ee373ba7cceaadf2260e';

/// The archive, the four writes that move a project between the board, the
/// archive and nothing at all (F4), and the rename that moves it nowhere (B6).
///
/// ## Why archive and delete are two different things
///
/// Copied from Trello on purpose -- `../../project-tracker-brief.md` records the
/// observation and the decision. An archive is reversible and is the move you
/// make constantly ("this one is done for now"); a delete is irreversible and is
/// the move you make twice a year. Collapsing them into one button means the
/// frequent gesture and the unrecoverable one are the same gesture.
///
/// The backend enforces the ordering rather than trusting the UI:
/// `canHardDeleteProject` (`backend/src/domain/projectDeleteGuard.ts`) answers
/// 409 for a project that is still active, so `DELETE /projects/:id` is only
/// ever reachable *through* the archive. This file mirrors that in the client so
/// the refusal is instant and legible, but the guard itself stays on the server,
/// where no client can skip it.
///
/// ## Why some of these invalidate the board and one of them splices it
///
/// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
/// write inside a project: the row is still there, only its tasks changed.
/// Create, archive, unarchive and delete change **which rows exist**, on both
/// boards at once, and there is no splice that can express "this project is now
/// on the other board". So they invalidate, which costs one `GET /board` per
/// action -- something a person does a handful of times a week.
///
/// [ProjectLifecycle.rename] is the opposite case and therefore takes the
/// opposite route: the row stays exactly where it is and one string in it
/// changes, so it is spliced into whichever lists are on screen
/// ([Board.applyProject], [ArchivedBoard.applyProject],
/// [ProjectHeader.applyProject]) and costs no read at all.
///
/// Either way the alarms follow, with no scheduler call anywhere: whatever
/// changes the board -- an invalidation or a splice -- changes the target set,
/// `boardReminderBridge` publishes it, and `reminderSync` re-arms. An archived
/// project stops nagging because its blocked tasks are no longer on the board
/// (that is what archiving *means*), and a renamed project's alarms start saying
/// the new name because the notification text carries it.
/// `GET /board?archived=true` -- the archive, in the same shape as the board.
///
/// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
/// app's home. Letting it dispose means re-opening it re-reads, which is what
/// you want from a list whose whole purpose is to be acted on.
///
/// No snapshot and no cache. The archive is never the thing you need at 09:00
/// with no signal, and a second cache file to keep in step would be pure cost.
///
/// A notifier rather than a plain future provider only because of [applyProject]
/// -- renaming a project from this screen has to show up in it without paying
/// for a second `GET /board?archived=true`.

abstract class _$ArchivedBoard extends $AsyncNotifier<List<BoardProject>> {
  FutureOr<List<BoardProject>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<BoardProject>>, List<BoardProject>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<BoardProject>>, List<BoardProject>>,
              AsyncValue<List<BoardProject>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Create, rename, archive, unarchive, delete: every write a *project* has.
///
/// A notifier with no state of its own: the state these produce lives in the two
/// board providers, and giving this one a copy would be a second source of truth
/// for "which projects exist". Every method throws on failure -- the caller (a
/// button) turns that into a message, exactly as the task writes do.

@ProviderFor(ProjectLifecycle)
final projectLifecycleProvider = ProjectLifecycleProvider._();

/// Create, rename, archive, unarchive, delete: every write a *project* has.
///
/// A notifier with no state of its own: the state these produce lives in the two
/// board providers, and giving this one a copy would be a second source of truth
/// for "which projects exist". Every method throws on failure -- the caller (a
/// button) turns that into a message, exactly as the task writes do.
final class ProjectLifecycleProvider
    extends $NotifierProvider<ProjectLifecycle, void> {
  /// Create, rename, archive, unarchive, delete: every write a *project* has.
  ///
  /// A notifier with no state of its own: the state these produce lives in the two
  /// board providers, and giving this one a copy would be a second source of truth
  /// for "which projects exist". Every method throws on failure -- the caller (a
  /// button) turns that into a message, exactly as the task writes do.
  ProjectLifecycleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectLifecycleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectLifecycleHash();

  @$internal
  @override
  ProjectLifecycle create() => ProjectLifecycle();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$projectLifecycleHash() => r'7e0fee052dbc066b1f177bbc6f1e1871e1b5e6e4';

/// Create, rename, archive, unarchive, delete: every write a *project* has.
///
/// A notifier with no state of its own: the state these produce lives in the two
/// board providers, and giving this one a copy would be a second source of truth
/// for "which projects exist". Every method throws on failure -- the caller (a
/// button) turns that into a message, exactly as the task writes do.

abstract class _$ProjectLifecycle extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
