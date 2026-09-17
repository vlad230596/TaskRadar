import 'package:taskradar/storage/capture_queue_store.dart';

/// In-memory [CaptureQueueStore].
///
/// Same reasoning as `FakeBoardSnapshotStore`: the real store resolves its
/// directory through `path_provider`, a platform channel that does not exist in
/// the `flutter test` VM. The real store's *file* behaviour -- missing,
/// corrupt, wrong schema, atomic replace, the corrupt file being set aside
/// rather than deleted -- is covered in `capture_queue_store_test.dart` against
/// a real temp directory, so this fake only stands in for "here is the queue".
class FakeCaptureQueueStore implements CaptureQueueStore {
  FakeCaptureQueueStore({List<PendingCapture>? queue})
    : queue = queue ?? <PendingCapture>[];

  /// What [read] returns and what [write] replaces.
  List<PendingCapture> queue;

  /// When set, [write] throws it. This is the failure the whole feature hinges
  /// on: a queue that cannot be written is a line that exists nowhere, and the
  /// capture path must report it rather than pretend.
  Object? writeFailure;

  /// When set, [read] throws it. The real store swallows its own read failures,
  /// but nothing above it should depend on that being true forever.
  Object? readFailure;

  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<List<PendingCapture>> read() async {
    readCount++;
    final failure = readFailure;
    if (failure != null) throw failure;
    return List<PendingCapture>.unmodifiable(queue);
  }

  @override
  Future<void> write(List<PendingCapture> queue) async {
    writeCount++;
    final failure = writeFailure;
    if (failure != null) throw failure;
    this.queue = List<PendingCapture>.from(queue);
  }

  @override
  Future<void> clear() async {
    clearCount++;
    queue = <PendingCapture>[];
  }
}
