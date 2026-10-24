import 'package:taskradar/storage/outbox_store.dart';

/// In-memory [OutboxStore], for the reason `FakeCaptureQueueStore` gives:
/// the real one resolves its directory through a platform channel the test VM
/// does not have. The file format is covered against a real temp directory in
/// `outbox_test.dart`.
class FakeOutboxStore implements OutboxStore {
  FakeOutboxStore({List<OutboxEntry>? entries})
    : entries = entries ?? <OutboxEntry>[];

  /// What [read] returns and what [write] replaces.
  List<OutboxEntry> entries;

  /// When set, [write] throws it: the write that would leave an offline edit
  /// existing nowhere.
  Object? writeFailure;

  int writeCount = 0;

  @override
  Future<List<OutboxEntry>> read() async =>
      List<OutboxEntry>.unmodifiable(entries);

  @override
  Future<void> write(List<OutboxEntry> entries) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    writeCount++;
    this.entries = List<OutboxEntry>.of(entries);
  }

  @override
  Future<void> clear() async => entries = <OutboxEntry>[];
}
