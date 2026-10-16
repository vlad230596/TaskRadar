import 'package:taskradar/storage/read_cache_store.dart';

/// [ReadCacheStore] in memory: what `flutter_test_config.dart` hands every
/// test, and what an offline test seeds directly.
class MemoryReadCacheStore implements ReadCacheStore {
  final Map<String, CachedRead> entries = <String, CachedRead>{};
  int writeCount = 0;

  /// Seeds an entry as if a previous run had saved it.
  void seed(String key, Object? json, {DateTime? savedAt}) {
    entries[key] = CachedRead(json: json, savedAt: savedAt ?? DateTime.now());
  }

  @override
  Future<CachedRead?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, Object? json) async {
    writeCount++;
    entries[key] = CachedRead(json: json, savedAt: DateTime.now());
  }

  @override
  Future<void> clear() async => entries.clear();
}
