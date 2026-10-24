import '../models/task.dart';
import '../models/task_status.dart';
import '../storage/outbox_store.dart';

/// The fields an outbox edit can carry, i.e. the ones `PATCH /tasks/:id`
/// can check against `expected`.
const List<String> outboxTaskFields = <String>[
  'title',
  'description',
  'categoryId',
  'status',
  'remindAt',
  'remindTime',
];

/// [task]'s values in the shape `PATCH` sends and `expected` compares:
/// the status by name, the reminder as its `YYYY-MM-DD` calendar date.
Map<String, Object?> taskWireValues(Task task) => <String, Object?>{
  'title': task.title,
  'description': task.description,
  'categoryId': task.categoryId,
  'status': task.status.name,
  'remindAt': _calendarDate(task.remindAt),
  'remindTime': task.remindTime,
};

/// The same for a task in the server's JSON (a conflict's `task`).
Map<String, Object?> jsonWireValues(Map<String, Object?> json) =>
    <String, Object?>{
      for (final field in outboxTaskFields)
        field: field == 'remindAt'
            ? _calendarDate(json['remindAt'] as String?)
            : json[field],
    };

String? _calendarDate(String? value) =>
    value == null || value.length < 10 ? value : value.substring(0, 10);

/// [rows] as they will be once the outbox has been sent: waiting edits
/// applied, waiting creates appended.
///
/// ## Why an overlay and not a write into the list
///
/// The list is the server's answer (or yesterday's copy of it) and is replaced
/// whole by every re-read. A change written into it would vanish at the next
/// refresh while still being unsent, and the user would watch their edit
/// undo itself. Drawn on top instead, it stays until the entry stops waiting
/// -- which is exactly when the server's list starts containing it.
///
/// Skipped and refused entries are not drawn: the server's value is the one
/// in force, and the history screen is where the difference is shown.
List<Task> overlayOutbox(
  List<Task> rows,
  Iterable<OutboxEntry> entries,
  String projectId,
) {
  final waiting = entries
      .where((entry) => entry.isWaiting && entry.projectId == projectId)
      .toList(growable: false);
  if (waiting.isEmpty) return rows;

  final result = <Task>[...rows];
  for (final entry in waiting) {
    switch (entry.kind) {
      case OutboxKind.editTask:
        final index = result.indexWhere((row) => row.id == entry.taskId);
        if (index >= 0) result[index] = _applyEdit(result[index], entry.body);
      case OutboxKind.createTask:
        result.add(_pendingRow(entry, result));
    }
  }
  return List<Task>.unmodifiable(result);
}

Task _applyEdit(Task task, Map<String, Object?> body) {
  var next = task;
  if (body.containsKey('title')) {
    next = next.copyWith(title: body['title']! as String);
  }
  if (body.containsKey('description')) {
    next = next.copyWith(description: body['description'] as String?);
  }
  if (body.containsKey('categoryId')) {
    next = next.copyWith(categoryId: body['categoryId'] as String?);
  }
  if (body.containsKey('status')) {
    final status = TaskStatus.values.byName(body['status']! as String);
    // A task that is not open cannot be the current one -- the same
    // weakening `ProjectTasks.setStatus` makes optimistically.
    next = next.copyWith(
      status: status,
      isCurrent: next.isCurrent && status == TaskStatus.pending,
    );
  }
  if (body.containsKey('remindAt')) {
    final date = body['remindAt'] as String?;
    next = next.copyWith(
      remindAt: date,
      remindTime: date == null ? null : next.remindTime,
    );
  }
  if (body.containsKey('remindTime')) {
    next = next.copyWith(remindTime: body['remindTime'] as String?);
  }
  return next;
}

Task _pendingRow(OutboxEntry entry, List<Task> rows) {
  final body = entry.body;
  final at = entry.createdAt.toUtc().toIso8601String();
  final status = body['status'] as String?;
  return Task(
    id: entry.localTaskId,
    projectId: entry.projectId,
    title: body['title']! as String,
    description: body['description'] as String?,
    status: status == null
        ? TaskStatus.pending
        : TaskStatus.values.byName(status),
    position: rows.isEmpty ? 1000 : rows.last.position + 1000,
    remindAt: body['remindAt'] as String?,
    remindTime: body['remindTime'] as String?,
    categoryId: body['categoryId'] as String?,
    createdAt: at,
    updatedAt: at,
    isCurrent: false,
  );
}
