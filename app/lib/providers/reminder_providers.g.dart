// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod wiring for the reminder machinery.
///
/// The shape to notice: [reminderSync] *watches* [reminderTargets] and
/// [reminderSettings]. Nobody calls "reschedule" after changing either of them
/// -- changing them **is** the reschedule. That is the property F4 needs: the
/// board provider will replace the targets after every `GET /board` and the
/// queue follows, with no second place that has to remember to fire.
///
/// Everything here is `keepAlive: true` for the same reason as
/// `dependencies.dart`: these own platform resources and a background sync must
/// not depend on some screen still being on-stage.

@ProviderFor(notificationGateway)
final notificationGatewayProvider = NotificationGatewayProvider._();

/// Riverpod wiring for the reminder machinery.
///
/// The shape to notice: [reminderSync] *watches* [reminderTargets] and
/// [reminderSettings]. Nobody calls "reschedule" after changing either of them
/// -- changing them **is** the reschedule. That is the property F4 needs: the
/// board provider will replace the targets after every `GET /board` and the
/// queue follows, with no second place that has to remember to fire.
///
/// Everything here is `keepAlive: true` for the same reason as
/// `dependencies.dart`: these own platform resources and a background sync must
/// not depend on some screen still being on-stage.

final class NotificationGatewayProvider
    extends
        $FunctionalProvider<
          NotificationGateway,
          NotificationGateway,
          NotificationGateway
        >
    with $Provider<NotificationGateway> {
  /// Riverpod wiring for the reminder machinery.
  ///
  /// The shape to notice: [reminderSync] *watches* [reminderTargets] and
  /// [reminderSettings]. Nobody calls "reschedule" after changing either of them
  /// -- changing them **is** the reschedule. That is the property F4 needs: the
  /// board provider will replace the targets after every `GET /board` and the
  /// queue follows, with no second place that has to remember to fire.
  ///
  /// Everything here is `keepAlive: true` for the same reason as
  /// `dependencies.dart`: these own platform resources and a background sync must
  /// not depend on some screen still being on-stage.
  NotificationGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationGatewayHash();

  @$internal
  @override
  $ProviderElement<NotificationGateway> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationGateway create(Ref ref) {
    return notificationGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationGateway>(value),
    );
  }
}

String _$notificationGatewayHash() =>
    r'718fab634b3febce6e723b540e1e168c263cea20';

/// The device's timezone, resolved once. See [NotificationTimeZone].

@ProviderFor(notificationTimeZone)
final notificationTimeZoneProvider = NotificationTimeZoneProvider._();

/// The device's timezone, resolved once. See [NotificationTimeZone].

final class NotificationTimeZoneProvider
    extends
        $FunctionalProvider<
          AsyncValue<NotificationTimeZone>,
          NotificationTimeZone,
          FutureOr<NotificationTimeZone>
        >
    with
        $FutureModifier<NotificationTimeZone>,
        $FutureProvider<NotificationTimeZone> {
  /// The device's timezone, resolved once. See [NotificationTimeZone].
  NotificationTimeZoneProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationTimeZoneProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationTimeZoneHash();

  @$internal
  @override
  $FutureProviderElement<NotificationTimeZone> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<NotificationTimeZone> create(Ref ref) {
    return notificationTimeZone(ref);
  }
}

String _$notificationTimeZoneHash() =>
    r'709e210b9d7ca0a0bc336618ce7f06e7f6688415';

/// The hour reminders fire at.
///
/// In memory only for F1. F4 adds the settings screen and persists it; when it
/// does, the only change here is where `build()` reads its initial value from --
/// every consumer already re-syncs on change.

@ProviderFor(ReminderSettings)
final reminderSettingsProvider = ReminderSettingsProvider._();

/// The hour reminders fire at.
///
/// In memory only for F1. F4 adds the settings screen and persists it; when it
/// does, the only change here is where `build()` reads its initial value from --
/// every consumer already re-syncs on change.
final class ReminderSettingsProvider
    extends $NotifierProvider<ReminderSettings, ReminderTime> {
  /// The hour reminders fire at.
  ///
  /// In memory only for F1. F4 adds the settings screen and persists it; when it
  /// does, the only change here is where `build()` reads its initial value from --
  /// every consumer already re-syncs on change.
  ReminderSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderSettingsHash();

  @$internal
  @override
  ReminderSettings create() => ReminderSettings();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReminderTime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReminderTime>(value),
    );
  }
}

String _$reminderSettingsHash() => r'78161f9695c32ed28e204b7ae8da67662a1e6047';

/// The hour reminders fire at.
///
/// In memory only for F1. F4 adds the settings screen and persists it; when it
/// does, the only change here is where `build()` reads its initial value from --
/// every consumer already re-syncs on change.

abstract class _$ReminderSettings extends $Notifier<ReminderTime> {
  ReminderTime build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ReminderTime, ReminderTime>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReminderTime, ReminderTime>,
              ReminderTime,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The set of reminders that *should* be armed right now.
///
/// The seam between F1 and the rest of the plan. F1's bench screen writes
/// synthetic rows here; F2/F4 will write `remindersFromBoard(board)` after each
/// refresh. Nothing downstream can tell the difference.

@ProviderFor(ReminderTargets)
final reminderTargetsProvider = ReminderTargetsProvider._();

/// The set of reminders that *should* be armed right now.
///
/// The seam between F1 and the rest of the plan. F1's bench screen writes
/// synthetic rows here; F2/F4 will write `remindersFromBoard(board)` after each
/// refresh. Nothing downstream can tell the difference.
final class ReminderTargetsProvider
    extends $NotifierProvider<ReminderTargets, List<TaskReminder>> {
  /// The set of reminders that *should* be armed right now.
  ///
  /// The seam between F1 and the rest of the plan. F1's bench screen writes
  /// synthetic rows here; F2/F4 will write `remindersFromBoard(board)` after each
  /// refresh. Nothing downstream can tell the difference.
  ReminderTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderTargetsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderTargetsHash();

  @$internal
  @override
  ReminderTargets create() => ReminderTargets();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<TaskReminder> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<TaskReminder>>(value),
    );
  }
}

String _$reminderTargetsHash() => r'7b0d12a2c175df087cb26f022cfca871eba338ce';

/// The set of reminders that *should* be armed right now.
///
/// The seam between F1 and the rest of the plan. F1's bench screen writes
/// synthetic rows here; F2/F4 will write `remindersFromBoard(board)` after each
/// refresh. Nothing downstream can tell the difference.

abstract class _$ReminderTargets extends $Notifier<List<TaskReminder>> {
  List<TaskReminder> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<TaskReminder>, List<TaskReminder>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<TaskReminder>, List<TaskReminder>>,
              List<TaskReminder>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The scheduler, once the plugin is initialised and the timezone is known.

@ProviderFor(reminderScheduler)
final reminderSchedulerProvider = ReminderSchedulerProvider._();

/// The scheduler, once the plugin is initialised and the timezone is known.

final class ReminderSchedulerProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReminderScheduler>,
          ReminderScheduler,
          FutureOr<ReminderScheduler>
        >
    with
        $FutureModifier<ReminderScheduler>,
        $FutureProvider<ReminderScheduler> {
  /// The scheduler, once the plugin is initialised and the timezone is known.
  ReminderSchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderSchedulerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderSchedulerHash();

  @$internal
  @override
  $FutureProviderElement<ReminderScheduler> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReminderScheduler> create(Ref ref) {
    return reminderScheduler(ref);
  }
}

String _$reminderSchedulerHash() => r'422ee94dec1cfb5cce27d6e8f296b3e07f47a73b';

/// Runs a resync whenever the targets or the configured hour change, and holds
/// the report of the last one.

@ProviderFor(ReminderSync)
final reminderSyncProvider = ReminderSyncProvider._();

/// Runs a resync whenever the targets or the configured hour change, and holds
/// the report of the last one.
final class ReminderSyncProvider
    extends $AsyncNotifierProvider<ReminderSync, ReminderSyncReport> {
  /// Runs a resync whenever the targets or the configured hour change, and holds
  /// the report of the last one.
  ReminderSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderSyncHash();

  @$internal
  @override
  ReminderSync create() => ReminderSync();
}

String _$reminderSyncHash() => r'2f453f87b85d03dcdb087b0b112615537d84c4e2';

/// Runs a resync whenever the targets or the configured hour change, and holds
/// the report of the last one.

abstract class _$ReminderSync extends $AsyncNotifier<ReminderSyncReport> {
  FutureOr<ReminderSyncReport> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ReminderSyncReport>, ReminderSyncReport>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReminderSyncReport>, ReminderSyncReport>,
              AsyncValue<ReminderSyncReport>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// What the OS has queued, read fresh.
///
/// Separate from [reminderSync] because the bench needs to re-read it without
/// triggering a resync -- "is it still there an hour later?" is a different
/// question from "arm it again".

@ProviderFor(pendingNotifications)
final pendingNotificationsProvider = PendingNotificationsProvider._();

/// What the OS has queued, read fresh.
///
/// Separate from [reminderSync] because the bench needs to re-read it without
/// triggering a resync -- "is it still there an hour later?" is a different
/// question from "arm it again".

final class PendingNotificationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PendingNotification>>,
          List<PendingNotification>,
          FutureOr<List<PendingNotification>>
        >
    with
        $FutureModifier<List<PendingNotification>>,
        $FutureProvider<List<PendingNotification>> {
  /// What the OS has queued, read fresh.
  ///
  /// Separate from [reminderSync] because the bench needs to re-read it without
  /// triggering a resync -- "is it still there an hour later?" is a different
  /// question from "arm it again".
  PendingNotificationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingNotificationsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingNotificationsHash();

  @$internal
  @override
  $FutureProviderElement<List<PendingNotification>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<PendingNotification>> create(Ref ref) {
    return pendingNotifications(ref);
  }
}

String _$pendingNotificationsHash() =>
    r'ff65c3d1f1bead5300128926852eef82189b8abc';

/// Current permission state, without prompting.

@ProviderFor(NotificationPermissions)
final notificationPermissionsProvider = NotificationPermissionsProvider._();

/// Current permission state, without prompting.
final class NotificationPermissionsProvider
    extends
        $AsyncNotifierProvider<
          NotificationPermissions,
          NotificationPermissionState
        > {
  /// Current permission state, without prompting.
  NotificationPermissionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationPermissionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationPermissionsHash();

  @$internal
  @override
  NotificationPermissions create() => NotificationPermissions();
}

String _$notificationPermissionsHash() =>
    r'0c92ecd092328766ee1310489f9afad0d20ca6a8';

/// Current permission state, without prompting.

abstract class _$NotificationPermissions
    extends $AsyncNotifier<NotificationPermissionState> {
  FutureOr<NotificationPermissionState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<NotificationPermissionState>,
              NotificationPermissionState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<NotificationPermissionState>,
                NotificationPermissionState
              >,
              AsyncValue<NotificationPermissionState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
