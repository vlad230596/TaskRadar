import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_status.dart';

part 'goal.freezed.dart';
part 'goal.g.dart';

/// Goals, contours and the goal references a task carries
/// (`design/goals-ideas-contract.md`).
///
/// Timestamps stay ISO strings, as everywhere in this client (see [Project]);
/// the few rules that need instants ([GoalView.windowEndsAt], a contour's
/// schedule) parse them in `domain/goals.dart`.

/// When a contour is in force: weekdays (1 = Monday, as `DateTime.weekday`)
/// and one span of local wall-clock time, `from < to`, never across midnight.
@freezed
abstract class ContourSchedule with _$ContourSchedule {
  const factory ContourSchedule({
    required List<int> days,
    required String from,
    required String to,
  }) = _ContourSchedule;

  factory ContourSchedule.fromJson(Map<String, dynamic> json) =>
      _$ContourScheduleFromJson(json);
}

/// A set of goal slots in force at certain times -- «Работа», «Личное».
@freezed
abstract class Contour with _$Contour {
  // ignore: invalid_annotation_target -- freezed forwards it to the class.
  @JsonSerializable(explicitToJson: true)
  const factory Contour({
    required String id,
    required String name,
    @Default(2) int slots,
    @Default(7) int windowDays,
    ContourSchedule? schedule,

    /// Gapped float, `double` for the reason given on `Task.position`.
    required double position,
    String? createdAt,
    String? updatedAt,
  }) = _Contour;

  factory Contour.fromJson(Map<String, dynamic> json) =>
      _$ContourFromJson(json);
}

/// The owner's manual choice of contour, exactly as the server stores it:
/// `contourId` null means "by schedule"; `until` null with a contour means
/// "until switched again".
@freezed
abstract class ActiveContourChoice with _$ActiveContourChoice {
  const factory ActiveContourChoice({String? contourId, String? until}) =
      _ActiveContourChoice;

  factory ActiveContourChoice.fromJson(Map<String, dynamic> json) =>
      _$ActiveContourChoiceFromJson(json);
}

/// `GET /contours`: every contour in order, and the manual choice.
@freezed
abstract class ContourList with _$ContourList {
  // ignore: invalid_annotation_target -- freezed forwards it to the class.
  @JsonSerializable(explicitToJson: true)
  const factory ContourList({
    required List<Contour> contours,
    @Default(ActiveContourChoice()) ActiveContourChoice active,
  }) = _ContourList;

  factory ContourList.fromJson(Map<String, dynamic> json) =>
      _$ContourListFromJson(json);
}

/// What a task carries about each goal it serves -- the source of the crown.
/// Achieved goals are never here (the server leaves them out).
@freezed
abstract class TaskGoalRef with _$TaskGoalRef {
  const factory TaskGoalRef({
    required String id,
    required String title,
    required String contourId,
  }) = _TaskGoalRef;

  factory TaskGoalRef.fromJson(Map<String, dynamic> json) =>
      _$TaskGoalRefFromJson(json);
}

/// One task of a goal, in the goal's own order.
@freezed
abstract class GoalTask with _$GoalTask {
  const factory GoalTask({
    required String id,
    required String title,
    required TaskStatus status,
    required String projectId,
    required String projectName,
    String? focusedAt,
    String? focusContourId,
  }) = _GoalTask;

  factory GoalTask.fromJson(Map<String, dynamic> json) =>
      _$GoalTaskFromJson(json);
}

/// An idea kept next to a goal.
@freezed
abstract class GoalIdea with _$GoalIdea {
  const factory GoalIdea({
    required String id,
    required String title,
    required String projectId,
    required String projectName,
  }) = _GoalIdea;

  factory GoalIdea.fromJson(Map<String, dynamic> json) =>
      _$GoalIdeaFromJson(json);
}

@freezed
abstract class GoalProgress with _$GoalProgress {
  const factory GoalProgress({@Default(0) int done, @Default(0) int total}) =
      _GoalProgress;

  factory GoalProgress.fromJson(Map<String, dynamic> json) =>
      _$GoalProgressFromJson(json);
}

/// Where a goal is. Derived by the server from its timestamps.
enum GoalState { slot, bench, achieved }

/// A goal as the API shows it -- `GoalView` in the contract.
@freezed
abstract class GoalView with _$GoalView {
  // ignore: invalid_annotation_target -- freezed forwards it to the class.
  @JsonSerializable(explicitToJson: true)
  const factory GoalView({
    required String id,
    required String contourId,
    required String title,
    String? why,
    @JsonKey(unknownEnumValue: GoalState.bench) required GoalState state,
    String? slottedAt,

    /// The window that applies (the goal's own, else its contour's).
    @Default(7) int windowDays,

    /// The goal's own window, or null for its contour's.
    int? ownWindowDays,
    String? windowEndsAt,
    @Default(false) bool windowExpired,
    String? achievedAt,
    required double position,
    required String createdAt,
    @Default(<GoalTask>[]) List<GoalTask> tasks,
    GoalTask? nextStep,
    @Default(<GoalIdea>[]) List<GoalIdea> ideas,
    @Default(GoalProgress()) GoalProgress progress,
  }) = _GoalView;

  const GoalView._();

  factory GoalView.fromJson(Map<String, dynamic> json) =>
      _$GoalViewFromJson(json);

  bool get inSlot => state == GoalState.slot;
  bool get onBench => state == GoalState.bench;
  bool get achieved => state == GoalState.achieved;

  /// No pending task left, but some are blocked: «всё заблокировано».
  bool get allBlocked =>
      nextStep == null &&
      tasks.any((task) => task.status == TaskStatus.blocked);

  /// 1-based number of the next step among the goal's tasks, or null.
  int? get stepNumber {
    final step = nextStep;
    if (step == null) return null;
    final index = tasks.indexWhere((task) => task.id == step.id);
    return index < 0 ? null : index + 1;
  }
}
