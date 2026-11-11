import '../models/checklist_item.dart';
import '../models/task_attachment.dart';
import '../models/task_location.dart';

/// The task fields of the task editor (`design/task-editor-spec.md` §10) as
/// they go over the wire, in one place.
///
/// Reading a task is `Task.fromJson` (generated, tolerant of missing keys).
/// Everything that *writes* `checklist` / `location` -- `ProjectApi`'s create
/// and PATCH bodies, an outbox entry's body and `expected`, the overlay that
/// draws an unsent edit -- goes through these functions, so a change of the
/// contract (a renamed key, `[]` vs `null`) is a change here and nowhere else.
abstract final class TaskWire {
  /// The key of the checklist in a task body.
  static const String checklistKey = 'checklist';

  /// The key of the place reminder in a task body.
  static const String locationKey = 'location';

  /// `[{ id, text, done }]`, or null for none. An empty list is sent as null:
  /// the server stores `[]` as null, and `expected` compares what is stored.
  static List<Map<String, Object?>>? checklist(List<ChecklistItem>? items) {
    if (items == null || items.isEmpty) return null;
    return <Map<String, Object?>>[
      for (final item in items)
        <String, Object?>{'id': item.id, 'text': item.text, 'done': item.done},
    ];
  }

  /// `{ lat, lng, radius, label? }`, or null for none.
  static Map<String, Object?>? location(TaskLocation? value) {
    if (value == null) return null;
    return <String, Object?>{
      'lat': value.lat,
      'lng': value.lng,
      'radius': value.radius,
      if (value.label != null) 'label': value.label,
    };
  }

  /// Back from a body (or a server row): null, or a list of item maps.
  static List<ChecklistItem>? checklistFrom(Object? json) {
    if (json is! List || json.isEmpty) return null;
    return List<ChecklistItem>.unmodifiable(
      json.map(
        (dynamic e) =>
            ChecklistItem.fromJson(Map<String, dynamic>.from(e as Map)),
      ),
    );
  }

  static TaskLocation? locationFrom(Object? json) {
    if (json is! Map) return null;
    return TaskLocation.fromJson(Map<String, dynamic>.from(json));
  }

  /// One attachment of a task row or of an upload's answer.
  static TaskAttachment attachmentFrom(Object? json) =>
      TaskAttachment.fromJson(Map<String, dynamic>.from(json! as Map));
}
