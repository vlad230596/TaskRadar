import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../storage/read_cache_store.dart';

part 'read_cache_providers.g.dart';

/// The read cache for everything but the board. See [ReadCacheStore].
@Riverpod(keepAlive: true)
ReadCacheStore readCacheStore(Ref ref) =>
    debugReadCacheStoreFactory?.call() ??
    (kIsWeb ? WebReadCacheStore() : FileReadCacheStore());

/// Set by `test/flutter_test_config.dart` for every test file at once.
///
/// The file store would do real disk I/O through `path_provider`, which never
/// completes inside a widget test's fake clock -- every screen that reads a
/// cached list would hang on its first frame. The board snapshot is overridden
/// per test instead; this store is read by enough screens that a per-test
/// override would have to be repeated in every file that pumps the app.
@visibleForTesting
ReadCacheStore Function()? debugReadCacheStoreFactory;

/// Which reads are on screen from the cache rather than the network, and how
/// old they are -- so a screen can say "local copy from 09:40" the way the
/// board's stale banner does. A key leaves the map when a fresh answer lands.
@Riverpod(keepAlive: true)
class CachedReads extends _$CachedReads {
  @override
  Map<String, DateTime> build() => const <String, DateTime>{};

  void markCached(String key, DateTime savedAt) {
    if (state[key] == savedAt) return;
    state = <String, DateTime>{...state, key: savedAt};
  }

  void markFresh(String key) {
    if (!state.containsKey(key)) return;
    state = <String, DateTime>{...state}..remove(key);
  }
}

/// How long a read with a cached copy waits for the network before drawing
/// the copy. Online, the answer usually arrives inside it and nothing stale is
/// ever painted; on a dead or hanging network the copy is up in well under a
/// second instead of after a 10-15 s timeout.
const Duration readCacheGrace = Duration(milliseconds: 400);

/// The read path for a cached list: network first for [readCacheGrace], then
/// the copy, with the network answer delivered later through [onLateFresh].
///
/// - No copy: exactly the old behaviour -- the network's answer or its error.
/// - Copy, and the network fails or stalls: the copy, marked in
///   [cachedReadsProvider]. A later network answer is handed to [onLateFresh]
///   together with the copy that was returned, so the caller can refuse to
///   overwrite a list that has been edited since.
/// - Every network answer refreshes the copy.
Future<T> readThroughCache<T extends Object>(
  Ref ref, {
  required String key,
  required Future<T> Function() fetch,
  required Object? Function(T value) encode,
  required T Function(Object? json) decode,
  required void Function(T shown, T fresh) onLateFresh,
}) async {
  final store = ref.read(readCacheStoreProvider);
  final reads = ref.read(cachedReadsProvider.notifier);

  Future<T> fromNetwork() async {
    final value = await fetch();
    unawaited(store.write(key, encode(value)));
    reads.markFresh(key);
    return value;
  }

  final network = fromNetwork();
  // Handled below in every branch; this only stops a failure that lands while
  // the disk is still being read from counting as unhandled.
  network.ignore();
  final cached = await store.read(key);

  T? copy;
  if (cached != null) {
    try {
      copy = decode(cached.json);
    } catch (error) {
      debugPrint('Read cache: "$key" no longer parses: $error');
    }
  }
  if (copy == null) return network;

  try {
    final quick = await Future.any<T?>(<Future<T?>>[
      network,
      Future<T?>.delayed(readCacheGrace),
    ]);
    if (quick != null) return quick;
  } catch (error) {
    debugPrint('Read "$key" failed, showing the local copy: $error');
    reads.markCached(key, cached!.savedAt);
    return copy;
  }

  reads.markCached(key, cached!.savedAt);
  final shown = copy;
  unawaited(
    network.then(
      (fresh) => onLateFresh(shown, fresh),
      onError: (Object error) =>
          debugPrint('Read "$key" failed behind the local copy: $error'),
    ),
  );
  return shown;
}
