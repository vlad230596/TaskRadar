import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_location.freezed.dart';
part 'task_location.g.dart';

/// A place reminder (`Task.location`, `design/task-editor-spec.md` §7): fire
/// when the phone enters the circle.
///
/// The server keeps it as four columns, all or none, and sends it as this
/// object or `null` -- so on the client it is one value, and "no place" is a
/// null `Task.location`, never a half-filled object.
@freezed
abstract class TaskLocation with _$TaskLocation {
  // ignore: invalid_annotation_target -- freezed forwards it to the class.
  @JsonSerializable(includeIfNull: false)
  const factory TaskLocation({
    /// -90..90.
    required double lat,

    /// -180..180.
    required double lng,

    /// Metres, [minRadius]..[maxRadius].
    @Default(TaskLocation.defaultRadius) int radius,

    /// ≤ 80 characters; the picker defaults it to «Место». Optional on the
    /// wire, and left out of it when null.
    String? label,
  }) = _TaskLocation;

  const TaskLocation._();

  factory TaskLocation.fromJson(Map<String, dynamic> json) =>
      _$TaskLocationFromJson(json);

  static const int minRadius = 100;
  static const int maxRadius = 1000;
  static const int defaultRadius = 200;
}
