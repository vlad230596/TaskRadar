// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_link_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the pending request and resolves it against the board.

@ProviderFor(NotificationLink)
final notificationLinkProvider = NotificationLinkProvider._();

/// Holds the pending request and resolves it against the board.
final class NotificationLinkProvider
    extends $NotifierProvider<NotificationLink, NotificationLinkState> {
  /// Holds the pending request and resolves it against the board.
  NotificationLinkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationLinkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationLinkHash();

  @$internal
  @override
  NotificationLink create() => NotificationLink();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationLinkState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationLinkState>(value),
    );
  }
}

String _$notificationLinkHash() => r'5bbfa6f92cc3ccd118dd732a1dfd44d39960f27d';

/// Holds the pending request and resolves it against the board.

abstract class _$NotificationLink extends $Notifier<NotificationLinkState> {
  NotificationLinkState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<NotificationLinkState, NotificationLinkState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NotificationLinkState, NotificationLinkState>,
              NotificationLinkState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Subscribes to both tap paths exactly once, and feeds them to
/// [NotificationLink].
///
/// A provider rather than something in `initState` for the reason the reminder
/// bridge gives: it is `keepAlive`, so it registers once per app run no matter
/// how many times the screen that watches it is rebuilt or re-mounted. Watching
/// it from a widget that is only mounted while signed in is what keeps the whole
/// thing behind the session switch.

@ProviderFor(notificationLinkBridge)
final notificationLinkBridgeProvider = NotificationLinkBridgeProvider._();

/// Subscribes to both tap paths exactly once, and feeds them to
/// [NotificationLink].
///
/// A provider rather than something in `initState` for the reason the reminder
/// bridge gives: it is `keepAlive`, so it registers once per app run no matter
/// how many times the screen that watches it is rebuilt or re-mounted. Watching
/// it from a widget that is only mounted while signed in is what keeps the whole
/// thing behind the session switch.

final class NotificationLinkBridgeProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// Subscribes to both tap paths exactly once, and feeds them to
  /// [NotificationLink].
  ///
  /// A provider rather than something in `initState` for the reason the reminder
  /// bridge gives: it is `keepAlive`, so it registers once per app run no matter
  /// how many times the screen that watches it is rebuilt or re-mounted. Watching
  /// it from a widget that is only mounted while signed in is what keeps the whole
  /// thing behind the session switch.
  NotificationLinkBridgeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationLinkBridgeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationLinkBridgeHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return notificationLinkBridge(ref);
  }
}

String _$notificationLinkBridgeHash() =>
    r'c6f6ab6396e78d38f671adb894c63a53d09dd857';
