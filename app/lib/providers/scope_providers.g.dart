// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scope_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Scopes (F7): the list of spaces, which one the board is showing, and the
/// filter that turns the second into the first.
///
/// ## The one decision this file is built around
///
/// **The board is fetched whole and filtered here, on the client.** The server
/// can filter it (`GET /board?scopeId=`) and this deliberately does not ask it
/// to, for three reasons, in order of how badly each one bites:
///
/// 1. **Reminders.** The local alarm queue is armed from the board
///    ([boardReminderBridge]). A server-filtered board would arm alarms for the
///    scope currently on screen and silently drop every other scope's -- so
///    switching to "Работа" in the morning would quietly disarm the reminder
///    about the cable for the dacha. The one feature the native client exists
///    for would fail in a way nobody notices until a date passes.
/// 2. **Switching scopes must be instant**, including with no signal. A whole
///    board is a few dozen rows; it is already in memory and already in the
///    snapshot.
/// 3. **One snapshot.** A per-scope cache would need a file per scope and a
///    rule for what to show while the fresh one for the newly selected scope is
///    still loading.
///
/// The cost is one wire format carrying projects the screen will not draw,
/// which at 10-15 projects is nothing.
///
/// ## Why the selection is stored as an id and resolved against the list
///
/// The stored value is a string from a previous run, and the scope it names can
/// be gone -- deleted on another device, or this database restored from a
/// backup. Every read therefore resolves it ([activeScope]) and falls back to
/// the first scope rather than trusting it, which makes "the selected scope was
/// deleted" an ordinary state instead of an empty board with no explanation.
/// `GET /scopes`, in server (position) order.
///
/// `keepAlive`, like the board: the switcher is on the app's home screen and
/// the list is read by everything that creates or moves a project, so letting
/// it dispose between screens would mean re-fetching it on every navigation.
///
/// Framework retries are off for the same reason as on the board -- see
/// [noAutomaticRetry].

@ProviderFor(Scopes)
final scopesProvider = ScopesProvider._();

/// Scopes (F7): the list of spaces, which one the board is showing, and the
/// filter that turns the second into the first.
///
/// ## The one decision this file is built around
///
/// **The board is fetched whole and filtered here, on the client.** The server
/// can filter it (`GET /board?scopeId=`) and this deliberately does not ask it
/// to, for three reasons, in order of how badly each one bites:
///
/// 1. **Reminders.** The local alarm queue is armed from the board
///    ([boardReminderBridge]). A server-filtered board would arm alarms for the
///    scope currently on screen and silently drop every other scope's -- so
///    switching to "Работа" in the morning would quietly disarm the reminder
///    about the cable for the dacha. The one feature the native client exists
///    for would fail in a way nobody notices until a date passes.
/// 2. **Switching scopes must be instant**, including with no signal. A whole
///    board is a few dozen rows; it is already in memory and already in the
///    snapshot.
/// 3. **One snapshot.** A per-scope cache would need a file per scope and a
///    rule for what to show while the fresh one for the newly selected scope is
///    still loading.
///
/// The cost is one wire format carrying projects the screen will not draw,
/// which at 10-15 projects is nothing.
///
/// ## Why the selection is stored as an id and resolved against the list
///
/// The stored value is a string from a previous run, and the scope it names can
/// be gone -- deleted on another device, or this database restored from a
/// backup. Every read therefore resolves it ([activeScope]) and falls back to
/// the first scope rather than trusting it, which makes "the selected scope was
/// deleted" an ordinary state instead of an empty board with no explanation.
/// `GET /scopes`, in server (position) order.
///
/// `keepAlive`, like the board: the switcher is on the app's home screen and
/// the list is read by everything that creates or moves a project, so letting
/// it dispose between screens would mean re-fetching it on every navigation.
///
/// Framework retries are off for the same reason as on the board -- see
/// [noAutomaticRetry].
final class ScopesProvider extends $AsyncNotifierProvider<Scopes, List<Scope>> {
  /// Scopes (F7): the list of spaces, which one the board is showing, and the
  /// filter that turns the second into the first.
  ///
  /// ## The one decision this file is built around
  ///
  /// **The board is fetched whole and filtered here, on the client.** The server
  /// can filter it (`GET /board?scopeId=`) and this deliberately does not ask it
  /// to, for three reasons, in order of how badly each one bites:
  ///
  /// 1. **Reminders.** The local alarm queue is armed from the board
  ///    ([boardReminderBridge]). A server-filtered board would arm alarms for the
  ///    scope currently on screen and silently drop every other scope's -- so
  ///    switching to "Работа" in the morning would quietly disarm the reminder
  ///    about the cable for the dacha. The one feature the native client exists
  ///    for would fail in a way nobody notices until a date passes.
  /// 2. **Switching scopes must be instant**, including with no signal. A whole
  ///    board is a few dozen rows; it is already in memory and already in the
  ///    snapshot.
  /// 3. **One snapshot.** A per-scope cache would need a file per scope and a
  ///    rule for what to show while the fresh one for the newly selected scope is
  ///    still loading.
  ///
  /// The cost is one wire format carrying projects the screen will not draw,
  /// which at 10-15 projects is nothing.
  ///
  /// ## Why the selection is stored as an id and resolved against the list
  ///
  /// The stored value is a string from a previous run, and the scope it names can
  /// be gone -- deleted on another device, or this database restored from a
  /// backup. Every read therefore resolves it ([activeScope]) and falls back to
  /// the first scope rather than trusting it, which makes "the selected scope was
  /// deleted" an ordinary state instead of an empty board with no explanation.
  /// `GET /scopes`, in server (position) order.
  ///
  /// `keepAlive`, like the board: the switcher is on the app's home screen and
  /// the list is read by everything that creates or moves a project, so letting
  /// it dispose between screens would mean re-fetching it on every navigation.
  ///
  /// Framework retries are off for the same reason as on the board -- see
  /// [noAutomaticRetry].
  ScopesProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'scopesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scopesHash();

  @$internal
  @override
  Scopes create() => Scopes();
}

String _$scopesHash() => r'4823788260b13a3c44e940bcc69a21e2832c97a1';

/// Scopes (F7): the list of spaces, which one the board is showing, and the
/// filter that turns the second into the first.
///
/// ## The one decision this file is built around
///
/// **The board is fetched whole and filtered here, on the client.** The server
/// can filter it (`GET /board?scopeId=`) and this deliberately does not ask it
/// to, for three reasons, in order of how badly each one bites:
///
/// 1. **Reminders.** The local alarm queue is armed from the board
///    ([boardReminderBridge]). A server-filtered board would arm alarms for the
///    scope currently on screen and silently drop every other scope's -- so
///    switching to "Работа" in the morning would quietly disarm the reminder
///    about the cable for the dacha. The one feature the native client exists
///    for would fail in a way nobody notices until a date passes.
/// 2. **Switching scopes must be instant**, including with no signal. A whole
///    board is a few dozen rows; it is already in memory and already in the
///    snapshot.
/// 3. **One snapshot.** A per-scope cache would need a file per scope and a
///    rule for what to show while the fresh one for the newly selected scope is
///    still loading.
///
/// The cost is one wire format carrying projects the screen will not draw,
/// which at 10-15 projects is nothing.
///
/// ## Why the selection is stored as an id and resolved against the list
///
/// The stored value is a string from a previous run, and the scope it names can
/// be gone -- deleted on another device, or this database restored from a
/// backup. Every read therefore resolves it ([activeScope]) and falls back to
/// the first scope rather than trusting it, which makes "the selected scope was
/// deleted" an ordinary state instead of an empty board with no explanation.
/// `GET /scopes`, in server (position) order.
///
/// `keepAlive`, like the board: the switcher is on the app's home screen and
/// the list is read by everything that creates or moves a project, so letting
/// it dispose between screens would mean re-fetching it on every navigation.
///
/// Framework retries are off for the same reason as on the board -- see
/// [noAutomaticRetry].

abstract class _$Scopes extends $AsyncNotifier<List<Scope>> {
  FutureOr<List<Scope>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Scope>>, List<Scope>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Scope>>, List<Scope>>,
              AsyncValue<List<Scope>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Which scope the board is showing, as stored on disk (F7).
///
/// The raw id, resolved by [activeScope]. Null means "nothing was ever chosen",
/// which is the ordinary state on a fresh install and reads as "the first
/// scope".

@ProviderFor(SelectedScopeId)
final selectedScopeIdProvider = SelectedScopeIdProvider._();

/// Which scope the board is showing, as stored on disk (F7).
///
/// The raw id, resolved by [activeScope]. Null means "nothing was ever chosen",
/// which is the ordinary state on a fresh install and reads as "the first
/// scope".
final class SelectedScopeIdProvider
    extends $AsyncNotifierProvider<SelectedScopeId, String?> {
  /// Which scope the board is showing, as stored on disk (F7).
  ///
  /// The raw id, resolved by [activeScope]. Null means "nothing was ever chosen",
  /// which is the ordinary state on a fresh install and reads as "the first
  /// scope".
  SelectedScopeIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedScopeIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedScopeIdHash();

  @$internal
  @override
  SelectedScopeId create() => SelectedScopeId();
}

String _$selectedScopeIdHash() => r'0a5ac6df0317f86bd5fa8ea6d7251770685acbc4';

/// Which scope the board is showing, as stored on disk (F7).
///
/// The raw id, resolved by [activeScope]. Null means "nothing was ever chosen",
/// which is the ordinary state on a fresh install and reads as "the first
/// scope".

abstract class _$SelectedScopeId extends $AsyncNotifier<String?> {
  FutureOr<String?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<String?>, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<String?>, String?>,
              AsyncValue<String?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The scope the board is actually showing, or null while the list is still
/// loading (or if there are somehow none).
///
/// Resolution order, and each step is load-bearing:
///
/// 1. the stored id, **if it still names a scope that exists**;
/// 2. otherwise the first scope in server order -- which is also what the
///    backend uses as the default for a project created without one, so the
///    client and the server agree on what "the default scope" means;
/// 3. null only when there are no scopes at all, which the migration makes
///    impossible but which a test can produce.

@ProviderFor(activeScope)
final activeScopeProvider = ActiveScopeProvider._();

/// The scope the board is actually showing, or null while the list is still
/// loading (or if there are somehow none).
///
/// Resolution order, and each step is load-bearing:
///
/// 1. the stored id, **if it still names a scope that exists**;
/// 2. otherwise the first scope in server order -- which is also what the
///    backend uses as the default for a project created without one, so the
///    client and the server agree on what "the default scope" means;
/// 3. null only when there are no scopes at all, which the migration makes
///    impossible but which a test can produce.

final class ActiveScopeProvider
    extends $FunctionalProvider<Scope?, Scope?, Scope?>
    with $Provider<Scope?> {
  /// The scope the board is actually showing, or null while the list is still
  /// loading (or if there are somehow none).
  ///
  /// Resolution order, and each step is load-bearing:
  ///
  /// 1. the stored id, **if it still names a scope that exists**;
  /// 2. otherwise the first scope in server order -- which is also what the
  ///    backend uses as the default for a project created without one, so the
  ///    client and the server agree on what "the default scope" means;
  /// 3. null only when there are no scopes at all, which the migration makes
  ///    impossible but which a test can produce.
  ActiveScopeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeScopeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeScopeHash();

  @$internal
  @override
  $ProviderElement<Scope?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Scope? create(Ref ref) {
    return activeScope(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Scope? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Scope?>(value),
    );
  }
}

String _$activeScopeHash() => r'00c81df52ac982193a8b306feb00a81f650a30fc';

/// True when the switcher is worth drawing at all.
///
/// One scope is what every existing installation has after the migration, and a
/// switcher with a single option is furniture: it costs a row of screen on the
/// home screen to offer a choice that does not exist. So the whole feature
/// stays invisible until a second scope is created -- which is also what makes
/// F7 free for someone who never wanted it.

@ProviderFor(hasMultipleScopes)
final hasMultipleScopesProvider = HasMultipleScopesProvider._();

/// True when the switcher is worth drawing at all.
///
/// One scope is what every existing installation has after the migration, and a
/// switcher with a single option is furniture: it costs a row of screen on the
/// home screen to offer a choice that does not exist. So the whole feature
/// stays invisible until a second scope is created -- which is also what makes
/// F7 free for someone who never wanted it.

final class HasMultipleScopesProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// True when the switcher is worth drawing at all.
  ///
  /// One scope is what every existing installation has after the migration, and a
  /// switcher with a single option is furniture: it costs a row of screen on the
  /// home screen to offer a choice that does not exist. So the whole feature
  /// stays invisible until a second scope is created -- which is also what makes
  /// F7 free for someone who never wanted it.
  HasMultipleScopesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hasMultipleScopesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hasMultipleScopesHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return hasMultipleScopes(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$hasMultipleScopesHash() => r'e106282968b564511ee4de2fde61ecbea8f4a96a';

/// How many **active** projects sit in one scope, or null while the board has
/// not loaded.
///
/// Read from the board that is already in memory rather than from a count
/// endpoint that does not exist: the client holds every project anyway (see the
/// note at the top of this file), so this is a filter over data already
/// fetched. Null rather than 0 while the board is unknown -- "no projects" and
/// "we do not know yet" must not look the same next to a delete button.

@ProviderFor(projectCountInScope)
final projectCountInScopeProvider = ProjectCountInScopeFamily._();

/// How many **active** projects sit in one scope, or null while the board has
/// not loaded.
///
/// Read from the board that is already in memory rather than from a count
/// endpoint that does not exist: the client holds every project anyway (see the
/// note at the top of this file), so this is a filter over data already
/// fetched. Null rather than 0 while the board is unknown -- "no projects" and
/// "we do not know yet" must not look the same next to a delete button.

final class ProjectCountInScopeProvider
    extends $FunctionalProvider<int?, int?, int?>
    with $Provider<int?> {
  /// How many **active** projects sit in one scope, or null while the board has
  /// not loaded.
  ///
  /// Read from the board that is already in memory rather than from a count
  /// endpoint that does not exist: the client holds every project anyway (see the
  /// note at the top of this file), so this is a filter over data already
  /// fetched. Null rather than 0 while the board is unknown -- "no projects" and
  /// "we do not know yet" must not look the same next to a delete button.
  ProjectCountInScopeProvider._({
    required ProjectCountInScopeFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectCountInScopeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectCountInScopeHash();

  @override
  String toString() {
    return r'projectCountInScopeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<int?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int? create(Ref ref) {
    final argument = this.argument as String;
    return projectCountInScope(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectCountInScopeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectCountInScopeHash() =>
    r'e8da0ab1022550aca1c247b013b5de638d33c8d1';

/// How many **active** projects sit in one scope, or null while the board has
/// not loaded.
///
/// Read from the board that is already in memory rather than from a count
/// endpoint that does not exist: the client holds every project anyway (see the
/// note at the top of this file), so this is a filter over data already
/// fetched. Null rather than 0 while the board is unknown -- "no projects" and
/// "we do not know yet" must not look the same next to a delete button.

final class ProjectCountInScopeFamily extends $Family
    with $FunctionalFamilyOverride<int?, String> {
  ProjectCountInScopeFamily._()
    : super(
        retry: null,
        name: r'projectCountInScopeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// How many **active** projects sit in one scope, or null while the board has
  /// not loaded.
  ///
  /// Read from the board that is already in memory rather than from a count
  /// endpoint that does not exist: the client holds every project anyway (see the
  /// note at the top of this file), so this is a filter over data already
  /// fetched. Null rather than 0 while the board is unknown -- "no projects" and
  /// "we do not know yet" must not look the same next to a delete button.

  ProjectCountInScopeProvider call(String scopeId) =>
      ProjectCountInScopeProvider._(argument: scopeId, from: this);

  @override
  String toString() => r'projectCountInScopeProvider';
}
