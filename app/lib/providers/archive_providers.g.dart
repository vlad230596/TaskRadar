// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'archive_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The archive, and the four writes that move a project between the board, the
/// archive and nothing at all (F4).
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
/// ## Why these invalidate the board instead of splicing it
///
/// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
/// write inside a project: the row is still there, only its tasks changed. These
/// four change **which rows exist**, on both boards at once, and there is no
/// splice that can express "this project is now on the other board". So they
/// invalidate, which costs one `GET /board` per archive/unarchive/delete -- an
/// action a person performs a handful of times a week.
///
/// That invalidation is also what re-arms the alarms, with no scheduler call
/// anywhere: the refreshed board no longer contains the archived project's
/// blocked tasks, `boardReminderBridge` publishes the smaller target set, and
/// the scheduler cancels what is no longer wanted. An archived project must stop
/// nagging -- that is the point of archiving it -- and this is the only place
/// that has to be true for it to happen.
/// `GET /board?archived=true` -- the archive, in the same shape as the board.
///
/// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
/// app's home. Letting it dispose means re-opening it re-reads, which is what
/// you want from a list whose whole purpose is to be acted on.
///
/// No snapshot and no cache. The archive is never the thing you need at 09:00
/// with no signal, and a second cache file to keep in step would be pure cost.

@ProviderFor(archivedBoard)
final archivedBoardProvider = ArchivedBoardProvider._();

/// The archive, and the four writes that move a project between the board, the
/// archive and nothing at all (F4).
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
/// ## Why these invalidate the board instead of splicing it
///
/// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
/// write inside a project: the row is still there, only its tasks changed. These
/// four change **which rows exist**, on both boards at once, and there is no
/// splice that can express "this project is now on the other board". So they
/// invalidate, which costs one `GET /board` per archive/unarchive/delete -- an
/// action a person performs a handful of times a week.
///
/// That invalidation is also what re-arms the alarms, with no scheduler call
/// anywhere: the refreshed board no longer contains the archived project's
/// blocked tasks, `boardReminderBridge` publishes the smaller target set, and
/// the scheduler cancels what is no longer wanted. An archived project must stop
/// nagging -- that is the point of archiving it -- and this is the only place
/// that has to be true for it to happen.
/// `GET /board?archived=true` -- the archive, in the same shape as the board.
///
/// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
/// app's home. Letting it dispose means re-opening it re-reads, which is what
/// you want from a list whose whole purpose is to be acted on.
///
/// No snapshot and no cache. The archive is never the thing you need at 09:00
/// with no signal, and a second cache file to keep in step would be pure cost.

final class ArchivedBoardProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BoardProject>>,
          List<BoardProject>,
          FutureOr<List<BoardProject>>
        >
    with
        $FutureModifier<List<BoardProject>>,
        $FutureProvider<List<BoardProject>> {
  /// The archive, and the four writes that move a project between the board, the
  /// archive and nothing at all (F4).
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
  /// ## Why these invalidate the board instead of splicing it
  ///
  /// F3's [Board.applyProjectTasks] updates one row in place, which is exact for a
  /// write inside a project: the row is still there, only its tasks changed. These
  /// four change **which rows exist**, on both boards at once, and there is no
  /// splice that can express "this project is now on the other board". So they
  /// invalidate, which costs one `GET /board` per archive/unarchive/delete -- an
  /// action a person performs a handful of times a week.
  ///
  /// That invalidation is also what re-arms the alarms, with no scheduler call
  /// anywhere: the refreshed board no longer contains the archived project's
  /// blocked tasks, `boardReminderBridge` publishes the smaller target set, and
  /// the scheduler cancels what is no longer wanted. An archived project must stop
  /// nagging -- that is the point of archiving it -- and this is the only place
  /// that has to be true for it to happen.
  /// `GET /board?archived=true` -- the archive, in the same shape as the board.
  ///
  /// Not `keepAlive`, unlike [board]: the archive is a screen you visit, not the
  /// app's home. Letting it dispose means re-opening it re-reads, which is what
  /// you want from a list whose whole purpose is to be acted on.
  ///
  /// No snapshot and no cache. The archive is never the thing you need at 09:00
  /// with no signal, and a second cache file to keep in step would be pure cost.
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
  $FutureProviderElement<List<BoardProject>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<BoardProject>> create(Ref ref) {
    return archivedBoard(ref);
  }
}

String _$archivedBoardHash() => r'aa697b6de502b2fa3b2dc90a822ce0c816f4c006';

/// Create, archive, unarchive, delete.
///
/// A notifier with no state of its own: the state these produce lives in the two
/// board providers, and giving this one a copy would be a second source of truth
/// for "which projects exist". Every method throws on failure -- the caller (a
/// button) turns that into a message, exactly as the task writes do.

@ProviderFor(ProjectLifecycle)
final projectLifecycleProvider = ProjectLifecycleProvider._();

/// Create, archive, unarchive, delete.
///
/// A notifier with no state of its own: the state these produce lives in the two
/// board providers, and giving this one a copy would be a second source of truth
/// for "which projects exist". Every method throws on failure -- the caller (a
/// button) turns that into a message, exactly as the task writes do.
final class ProjectLifecycleProvider
    extends $NotifierProvider<ProjectLifecycle, void> {
  /// Create, archive, unarchive, delete.
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

String _$projectLifecycleHash() => r'70d9ac7a62428cabefaa83bd05b3006865f947e4';

/// Create, archive, unarchive, delete.
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
