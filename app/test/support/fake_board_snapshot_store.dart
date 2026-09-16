import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/storage/board_snapshot_store.dart';

/// In-memory [BoardSnapshotStore].
///
/// Same reasoning as `FakeTokenStorage`: the real store resolves its directory
/// through `path_provider`, a platform channel that does not exist in the
/// `flutter test` VM. The real store's *file* behaviour -- missing, corrupt,
/// wrong schema, atomic replace -- is covered separately in
/// `board_snapshot_store_test.dart` against a real temp directory, so this fake
/// only has to stand in for "there is / is not a snapshot".
class FakeBoardSnapshotStore implements BoardSnapshotStore {
  FakeBoardSnapshotStore({this.snapshot});

  /// What [read] returns. Null means "nothing usable on disk", which is the
  /// answer for every one of the real store's failure modes.
  BoardSnapshot? snapshot;

  /// When set, [read] throws it. Proves the provider above treats an exploding
  /// store the same way as an empty one -- the real store swallows its own
  /// failures, but nothing should depend on that being true forever.
  Object? readFailure;

  /// Delays [read] until completed, so a test can observe the moment when the
  /// network has answered but the disk has not (and vice versa).
  Future<void>? readGate;

  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<BoardSnapshot?> read() async {
    readCount++;
    if (readGate != null) await readGate;
    final failure = readFailure;
    if (failure != null) throw failure;
    return snapshot;
  }

  @override
  Future<BoardSnapshot> write(
    List<BoardProject> projects, {
    DateTime? savedAt,
  }) async {
    writeCount++;
    return snapshot = BoardSnapshot(
      projects: projects,
      savedAt: savedAt ?? DateTime.now(),
    );
  }

  @override
  Future<void> clear() async {
    clearCount++;
    snapshot = null;
  }
}
