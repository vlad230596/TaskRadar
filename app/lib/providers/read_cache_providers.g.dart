// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'read_cache_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The read cache for everything but the board. See [ReadCacheStore].

@ProviderFor(readCacheStore)
final readCacheStoreProvider = ReadCacheStoreProvider._();

/// The read cache for everything but the board. See [ReadCacheStore].

final class ReadCacheStoreProvider
    extends $FunctionalProvider<ReadCacheStore, ReadCacheStore, ReadCacheStore>
    with $Provider<ReadCacheStore> {
  /// The read cache for everything but the board. See [ReadCacheStore].
  ReadCacheStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readCacheStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readCacheStoreHash();

  @$internal
  @override
  $ProviderElement<ReadCacheStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ReadCacheStore create(Ref ref) {
    return readCacheStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReadCacheStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReadCacheStore>(value),
    );
  }
}

String _$readCacheStoreHash() => r'695d2eec206537538daba0b8c1f18b402d4e1da4';

/// Which reads are on screen from the cache rather than the network, and how
/// old they are -- so a screen can say "local copy from 09:40" the way the
/// board's stale banner does. A key leaves the map when a fresh answer lands.

@ProviderFor(CachedReads)
final cachedReadsProvider = CachedReadsProvider._();

/// Which reads are on screen from the cache rather than the network, and how
/// old they are -- so a screen can say "local copy from 09:40" the way the
/// board's stale banner does. A key leaves the map when a fresh answer lands.
final class CachedReadsProvider
    extends $NotifierProvider<CachedReads, Map<String, DateTime>> {
  /// Which reads are on screen from the cache rather than the network, and how
  /// old they are -- so a screen can say "local copy from 09:40" the way the
  /// board's stale banner does. A key leaves the map when a fresh answer lands.
  CachedReadsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cachedReadsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cachedReadsHash();

  @$internal
  @override
  CachedReads create() => CachedReads();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, DateTime> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, DateTime>>(value),
    );
  }
}

String _$cachedReadsHash() => r'3f0cc5fc2e76609e9f267935f506c6020b96494d';

/// Which reads are on screen from the cache rather than the network, and how
/// old they are -- so a screen can say "local copy from 09:40" the way the
/// board's stale banner does. A key leaves the map when a fresh answer lands.

abstract class _$CachedReads extends $Notifier<Map<String, DateTime>> {
  Map<String, DateTime> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Map<String, DateTime>, Map<String, DateTime>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, DateTime>, Map<String, DateTime>>,
              Map<String, DateTime>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
