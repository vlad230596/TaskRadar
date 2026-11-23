// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Contours and goals (`design/goals-ideas-contract.md`).
///
/// ## Reads through the cache, writes online only
///
/// Both lists are read like the work set: network first, the local copy when
/// the network is slow or gone ([readThroughCache]). Writes have no outbox in
/// this iteration -- each one is a request whose answer (a whole [GoalView],
/// or a contour) replaces the row in the list; a failure throws to the button
/// that pressed it (`widgets/mutation_feedback.dart`).
///
/// ## Everything degrades to "no goals"
///
/// The contours and the goals are extras on top of the board and the set: a
/// server from before them, or a read that fails with no copy, must leave the
/// app exactly as it was. So the derived providers below answer "unknown"
/// (null, empty) rather than an error, and every screen treats unknown as
/// "draw nothing about goals".

@ProviderFor(goalsApi)
final goalsApiProvider = GoalsApiProvider._();

/// Contours and goals (`design/goals-ideas-contract.md`).
///
/// ## Reads through the cache, writes online only
///
/// Both lists are read like the work set: network first, the local copy when
/// the network is slow or gone ([readThroughCache]). Writes have no outbox in
/// this iteration -- each one is a request whose answer (a whole [GoalView],
/// or a contour) replaces the row in the list; a failure throws to the button
/// that pressed it (`widgets/mutation_feedback.dart`).
///
/// ## Everything degrades to "no goals"
///
/// The contours and the goals are extras on top of the board and the set: a
/// server from before them, or a read that fails with no copy, must leave the
/// app exactly as it was. So the derived providers below answer "unknown"
/// (null, empty) rather than an error, and every screen treats unknown as
/// "draw nothing about goals".

final class GoalsApiProvider
    extends $FunctionalProvider<GoalsApi, GoalsApi, GoalsApi>
    with $Provider<GoalsApi> {
  /// Contours and goals (`design/goals-ideas-contract.md`).
  ///
  /// ## Reads through the cache, writes online only
  ///
  /// Both lists are read like the work set: network first, the local copy when
  /// the network is slow or gone ([readThroughCache]). Writes have no outbox in
  /// this iteration -- each one is a request whose answer (a whole [GoalView],
  /// or a contour) replaces the row in the list; a failure throws to the button
  /// that pressed it (`widgets/mutation_feedback.dart`).
  ///
  /// ## Everything degrades to "no goals"
  ///
  /// The contours and the goals are extras on top of the board and the set: a
  /// server from before them, or a read that fails with no copy, must leave the
  /// app exactly as it was. So the derived providers below answer "unknown"
  /// (null, empty) rather than an error, and every screen treats unknown as
  /// "draw nothing about goals".
  GoalsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'goalsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$goalsApiHash();

  @$internal
  @override
  $ProviderElement<GoalsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoalsApi create(Ref ref) {
    return goalsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoalsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoalsApi>(value),
    );
  }
}

String _$goalsApiHash() => r'c2de559d962e212acfaa5e5b7c607c3721730d1a';

/// `GET /contours`: the contours in order and the manual choice.

@ProviderFor(Contours)
final contoursProvider = ContoursProvider._();

/// `GET /contours`: the contours in order and the manual choice.
final class ContoursProvider
    extends $AsyncNotifierProvider<Contours, ContourList> {
  /// `GET /contours`: the contours in order and the manual choice.
  ContoursProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'contoursProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contoursHash();

  @$internal
  @override
  Contours create() => Contours();
}

String _$contoursHash() => r'fd30fe8a1a0e8aa86de7873f4900eab3e44f81e6';

/// `GET /contours`: the contours in order and the manual choice.

abstract class _$Contours extends $AsyncNotifier<ContourList> {
  FutureOr<ContourList> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ContourList>, ContourList>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ContourList>, ContourList>,
              AsyncValue<ContourList>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The contours in order, or empty while unknown.

@ProviderFor(contourList)
final contourListProvider = ContourListProvider._();

/// The contours in order, or empty while unknown.

final class ContourListProvider
    extends $FunctionalProvider<List<Contour>, List<Contour>, List<Contour>>
    with $Provider<List<Contour>> {
  /// The contours in order, or empty while unknown.
  ContourListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contourListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contourListHash();

  @$internal
  @override
  $ProviderElement<List<Contour>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Contour> create(Ref ref) {
    return contourList(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Contour> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Contour>>(value),
    );
  }
}

String _$contourListHash() => r'a5081773304b8c9924d6b79d3cd82fc38f06c134';

/// The active contour, resolved on this device ([resolveActiveContour]), or
/// null while the contours are unknown -- which every screen reads as "no
/// goals, one working set", the app as it was before contours.
///
/// Re-resolves itself at the next moment the answer can change (a schedule's
/// edge or the manual choice's `until`); no timer when nothing can change.

@ProviderFor(activeContour)
final activeContourProvider = ActiveContourProvider._();

/// The active contour, resolved on this device ([resolveActiveContour]), or
/// null while the contours are unknown -- which every screen reads as "no
/// goals, one working set", the app as it was before contours.
///
/// Re-resolves itself at the next moment the answer can change (a schedule's
/// edge or the manual choice's `until`); no timer when nothing can change.

final class ActiveContourProvider
    extends $FunctionalProvider<Contour?, Contour?, Contour?>
    with $Provider<Contour?> {
  /// The active contour, resolved on this device ([resolveActiveContour]), or
  /// null while the contours are unknown -- which every screen reads as "no
  /// goals, one working set", the app as it was before contours.
  ///
  /// Re-resolves itself at the next moment the answer can change (a schedule's
  /// edge or the manual choice's `until`); no timer when nothing can change.
  ActiveContourProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeContourProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeContourHash();

  @$internal
  @override
  $ProviderElement<Contour?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Contour? create(Ref ref) {
    return activeContour(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Contour? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Contour?>(value),
    );
  }
}

String _$activeContourHash() => r'82228763a21cdc6a13b852b115629170c6140261';

/// The active contour's id, or null while unknown.

@ProviderFor(activeContourId)
final activeContourIdProvider = ActiveContourIdProvider._();

/// The active contour's id, or null while unknown.

final class ActiveContourIdProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The active contour's id, or null while unknown.
  ActiveContourIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeContourIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeContourIdHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return activeContourId(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$activeContourIdHash() => r'bc68baf1e428049fce17eaa1ab1fc1b3394c5945';

/// The default contour (first by position) -- where a task in the set with no
/// contour belongs. Null while unknown.

@ProviderFor(defaultContourId)
final defaultContourIdProvider = DefaultContourIdProvider._();

/// The default contour (first by position) -- where a task in the set with no
/// contour belongs. Null while unknown.

final class DefaultContourIdProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The default contour (first by position) -- where a task in the set with no
  /// contour belongs. Null while unknown.
  DefaultContourIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'defaultContourIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$defaultContourIdHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return defaultContourId(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$defaultContourIdHash() => r'6033538d391733cda36cb0d9a46e578092ebd272';

/// Whether the active contour is a manual choice in force.

@ProviderFor(activeContourIsManual)
final activeContourIsManualProvider = ActiveContourIsManualProvider._();

/// Whether the active contour is a manual choice in force.

final class ActiveContourIsManualProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the active contour is a manual choice in force.
  ActiveContourIsManualProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeContourIsManualProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeContourIsManualHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return activeContourIsManual(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$activeContourIsManualHash() =>
    r'0ee6b5b20181c9641cbae871440870a46dc0112b';

/// Goals in slots and on the bench, in contour order then position.

@ProviderFor(Goals)
final goalsProvider = GoalsProvider._();

/// Goals in slots and on the bench, in contour order then position.
final class GoalsProvider
    extends $AsyncNotifierProvider<Goals, List<GoalView>> {
  /// Goals in slots and on the bench, in contour order then position.
  GoalsProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'goalsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$goalsHash();

  @$internal
  @override
  Goals create() => Goals();
}

String _$goalsHash() => r'6f6b2415f0d9381f4b1a3d4ec1ba89a2121e1718';

/// Goals in slots and on the bench, in contour order then position.

abstract class _$Goals extends $AsyncNotifier<List<GoalView>> {
  FutureOr<List<GoalView>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<GoalView>>, List<GoalView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<GoalView>>, List<GoalView>>,
              AsyncValue<List<GoalView>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The goals list, or empty while unknown (or unavailable).

@ProviderFor(goalList)
final goalListProvider = GoalListProvider._();

/// The goals list, or empty while unknown (or unavailable).

final class GoalListProvider
    extends $FunctionalProvider<List<GoalView>, List<GoalView>, List<GoalView>>
    with $Provider<List<GoalView>> {
  /// The goals list, or empty while unknown (or unavailable).
  GoalListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'goalListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$goalListHash();

  @$internal
  @override
  $ProviderElement<List<GoalView>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<GoalView> create(Ref ref) {
    return goalList(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<GoalView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<GoalView>>(value),
    );
  }
}

String _$goalListHash() => r'10187392508da91ea913ec93f97946097447a5f9';

/// Which (unachieved) goals each task serves, built from the goals list --
/// so a crown follows a link the moment it is made, without re-reading the
/// board. Null while the goals are unknown: callers then fall back to the
/// task's own `goals` as the server last sent them.

@ProviderFor(taskGoalIndex)
final taskGoalIndexProvider = TaskGoalIndexProvider._();

/// Which (unachieved) goals each task serves, built from the goals list --
/// so a crown follows a link the moment it is made, without re-reading the
/// board. Null while the goals are unknown: callers then fall back to the
/// task's own `goals` as the server last sent them.

final class TaskGoalIndexProvider
    extends
        $FunctionalProvider<
          Map<String, List<TaskGoalRef>>?,
          Map<String, List<TaskGoalRef>>?,
          Map<String, List<TaskGoalRef>>?
        >
    with $Provider<Map<String, List<TaskGoalRef>>?> {
  /// Which (unachieved) goals each task serves, built from the goals list --
  /// so a crown follows a link the moment it is made, without re-reading the
  /// board. Null while the goals are unknown: callers then fall back to the
  /// task's own `goals` as the server last sent them.
  TaskGoalIndexProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'taskGoalIndexProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$taskGoalIndexHash();

  @$internal
  @override
  $ProviderElement<Map<String, List<TaskGoalRef>>?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, List<TaskGoalRef>>? create(Ref ref) {
    return taskGoalIndex(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, List<TaskGoalRef>>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, List<TaskGoalRef>>?>(
        value,
      ),
    );
  }
}

String _$taskGoalIndexHash() => r'036d18f839f99afec1c00ff205cf8c973c3f49ed';

/// Achieved goals, newest first -- the history screen's «Достигнутые цели».

@ProviderFor(achievedGoals)
final achievedGoalsProvider = AchievedGoalsProvider._();

/// Achieved goals, newest first -- the history screen's «Достигнутые цели».

final class AchievedGoalsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<GoalView>>,
          List<GoalView>,
          FutureOr<List<GoalView>>
        >
    with $FutureModifier<List<GoalView>>, $FutureProvider<List<GoalView>> {
  /// Achieved goals, newest first -- the history screen's «Достигнутые цели».
  AchievedGoalsProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutomaticRetry,
        name: r'achievedGoalsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$achievedGoalsHash();

  @$internal
  @override
  $FutureProviderElement<List<GoalView>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<GoalView>> create(Ref ref) {
    return achievedGoals(ref);
  }
}

String _$achievedGoalsHash() => r'f8ef2302b9b3ab0a28518900a363ac3299bd23d6';

/// One task, fetched by id -- a goal's step opened from somewhere that is not
/// a list.

@ProviderFor(taskById)
final taskByIdProvider = TaskByIdFamily._();

/// One task, fetched by id -- a goal's step opened from somewhere that is not
/// a list.

final class TaskByIdProvider
    extends $FunctionalProvider<AsyncValue<Task>, Task, FutureOr<Task>>
    with $FutureModifier<Task>, $FutureProvider<Task> {
  /// One task, fetched by id -- a goal's step opened from somewhere that is not
  /// a list.
  TaskByIdProvider._({
    required TaskByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'taskByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$taskByIdHash();

  @override
  String toString() {
    return r'taskByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Task> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Task> create(Ref ref) {
    final argument = this.argument as String;
    return taskById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TaskByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$taskByIdHash() => r'3bc8f30934077f97812a4b5154c3e854c61e8fc3';

/// One task, fetched by id -- a goal's step opened from somewhere that is not
/// a list.

final class TaskByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Task>, String> {
  TaskByIdFamily._()
    : super(
        retry: null,
        name: r'taskByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One task, fetched by id -- a goal's step opened from somewhere that is not
  /// a list.

  TaskByIdProvider call(String id) =>
      TaskByIdProvider._(argument: id, from: this);

  @override
  String toString() => r'taskByIdProvider';
}
