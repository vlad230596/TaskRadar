import 'dart:async';

import 'package:taskradar/providers/read_cache_providers.dart';

import 'support/memory_read_cache_store.dart';

/// Runs around every test file in this directory (a `flutter_test`
/// convention). See [debugReadCacheStoreFactory] for why it exists.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugReadCacheStoreFactory = MemoryReadCacheStore.new;
  await testMain();
}
