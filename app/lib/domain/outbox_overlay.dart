import 'package:flutter/foundation.dart';

import '../api/task_wire.dart';
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
  TaskWire.checklistKey,
  TaskWire.locationKey,
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
  TaskWire.checklistKey: TaskWire.checklist(task.checklist),
  TaskWire.locationKey: TaskWire.location(task.location),
};

/// The same for a task in the server's JSON (a conflict's `task`).
Map<String, Object?> jsonWireValues(Map<String, Object?> json) =>
    <String, Object?>{
      for (final field in outboxTaskFields)
        field: switch (field) {
          'remindAt' => _calendarDate(json['remindAt'] as String?),
          // `[]` and null are one value, as the server stores them.
          TaskWire.checklistKey => TaskWire.checklist(
            TaskWire.checklistFrom(json[field]),
          ),
          TaskWire.locationKey => TaskWire.location(
            TaskWire.locationFrom(json[field]),
          ),
          _ => json[field],
        },
    };

String? _calendarDate(String? value) =>
    value == null || value.length < 10 ? value : value.substring(0, 10);

/// [rows] as they will be once the outbox has been sent: waiting edits
/// applied, waiting creates appended, waiting moves taken out of the project
/// they leave and appended to the one they go to.
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
  // In order: a move draws its row in the target, and an edit made after the
  // move (an entry of the target) lands on that row.
  final waiting = entries
      .where(
        (entry) =>
            entry.isWaiting &&
            (entry.projectId == projectId ||
                entry.landsInProjectId == projectId),
      )
      .toList(growable: false);
  if (waiting.isEmpty) return rows;

  final result = <Task>[...rows];
  for (final entry in waiting) {
    switch (entry.kind) {
      case OutboxKind.editTask:
        final index = result.indexWhere((row) => row.id == entry.taskId);
        if (index >= 0) {
          result[index] = applyTaskPatch(result[index], entry.body);
        }
      case OutboxKind.createTask:
        result.add(_pendingRow(entry, result));
      case OutboxKind.moveTask:
        // Gone from the project it left, and appended to the one it went
        // to -- unless that list already has it: re-read after the server
        // took the move, a moment before the entry stops waiting.
        final moved = entry.row;
        if (entry.targetProjectId != projectId) {
          result.removeWhere((row) => row.id == entry.taskId);
        } else if (moved != null &&
            !result.any((row) => row.id == entry.taskId)) {
          result.add(_movedRow(moved, projectId, result));
        }
      case OutboxKind.deleteAttachment:
        // The picture is gone from the row at once; the pictures still
        // waiting to go up are not in the row at all -- see
        // [pendingAttachments].
        final index = result.indexWhere((row) => row.id == entry.taskId);
        if (index >= 0) {
          final row = result[index];
          result[index] = row.copyWith(
            attachments: List.unmodifiable(
              row.attachments.where((a) => a.id != entry.attachmentId),
            ),
          );
        }
      case OutboxKind.uploadAttachment:
        break;
    }
  }
  return List<Task>.unmodifiable(result);
}

/// A moved task as the target project will have it: last, no category (the
/// server drops it, categories are per project), and not current -- which
/// task is current is the server's call, as for an unsent create.
Task _movedRow(Map<String, Object?> json, String projectId, List<Task> rows) {
  return Task.fromJson(Map<String, dynamic>.from(json)).copyWith(
    projectId: projectId,
    categoryId: null,
    position: rows.isEmpty ? 1000 : rows.last.position + 1000,
    isCurrent: false,
  );
}

/// [task] with a `PATCH /tasks/:id` [body] applied the way the server would
/// apply it -- for an unsent edit in the overlay, and for the optimistic row
/// of `ProjectTasks.update`.
Task applyTaskPatch(Task task, Map<String, Object?> body) {
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
  if (body.containsKey(TaskWire.checklistKey)) {
    next = next.copyWith(
      checklist: TaskWire.checklistFrom(body[TaskWire.checklistKey]),
    );
  }
  if (body.containsKey(TaskWire.locationKey)) {
    next = next.copyWith(
      location: TaskWire.locationFrom(body[TaskWire.locationKey]),
    );
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
    checklist: TaskWire.checklistFrom(body[TaskWire.checklistKey]),
    location: TaskWire.locationFrom(body[TaskWire.locationKey]),
    createdAt: at,
    updatedAt: at,
    isCurrent: false,
  );
}

// --- pictures waiting to go up ----------------------------------------------

/// Where a picture in the outbox is.
enum PendingAttachmentState {
  /// Waiting for a network, or for the create of its task (the clock).
  waiting,

  /// The server said no (too big, wrong type, 30 already) -- the red dot:
  /// «Повторить» or «Убрать».
  refused,
}

/// A picture of a task that the server does not have yet: drawn in the
/// editor's strip from its local copy ([localPath]) next to the task's
/// `Task.attachments`, and counted in the row's picture badge.
@immutable
class PendingAttachment {
  const PendingAttachment({
    required this.entry,
    required this.state,
    this.progress,
  });

  /// The outbox entry behind it -- for `AttachmentQueue.retry` / `remove`.
  final OutboxEntry entry;
  final PendingAttachmentState state;

  /// 0..1 while its bytes are going up; null otherwise.
  final double? progress;

  /// `local:upload:<key>`: the id the strip keys it by, and what
  /// `attachmentBytesProvider` reads the local copy with.
  String get id => entry.pendingAttachmentId;
  String get uploadKey => entry.key;
  String? get localPath => entry.localPath;
  String get mime => entry.mime ?? 'image/jpeg';
  String? get message => entry.message;
  bool get isUploading => progress != null;

  PendingAttachment withProgress(double? value) =>
      PendingAttachment(entry: entry, state: state, progress: value);

  @override
  bool operator ==(Object other) =>
      other is PendingAttachment &&
      other.entry.key == entry.key &&
      other.state == state &&
      other.progress == progress &&
      other.entry.message == entry.message;

  @override
  int get hashCode => Object.hash(entry.key, state, progress, entry.message);

  @override
  String toString() => 'PendingAttachment($id, ${state.name}, $progress)';
}

const String _localCreatePrefix = 'local:outbox:';

/// The task id an entry applies to *now*: a `local:outbox:<key>` of a create
/// that has been sent becomes the id the server gave it.
String? resolvedTaskId(OutboxEntry entry, Iterable<OutboxEntry> entries) {
  final id = entry.taskId;
  if (id == null || !id.startsWith(_localCreatePrefix)) return id;
  final key = id.substring(_localCreatePrefix.length);
  for (final other in entries) {
    if (other.kind == OutboxKind.createTask && other.key == key) {
      return other.state == OutboxState.sent ? (other.taskId ?? id) : id;
    }
  }
  return id;
}

/// The pictures of [taskIdOrLocal] still in the outbox, oldest first --
/// waiting and refused. [taskIdOrLocal] may be the task's id or the
/// `local:outbox:<createKey>` of its unsent create; a picture queued against
/// the local id is found by the real one once the create is sent, and the
/// other way round.
List<PendingAttachment> pendingAttachments(
  Iterable<OutboxEntry> entries,
  String taskIdOrLocal,
) {
  final all = entries.toList(growable: false);
  final wanted = <String>{taskIdOrLocal};
  // The two names of one task: the local id of a sent create, and its id.
  for (final entry in all) {
    if (entry.kind != OutboxKind.createTask) continue;
    final serverId = entry.taskId;
    if (entry.localTaskId == taskIdOrLocal && serverId != null) {
      wanted.add(serverId);
    } else if (serverId == taskIdOrLocal) {
      wanted.add(entry.localTaskId);
    }
  }
  return List<PendingAttachment>.unmodifiable(<PendingAttachment>[
    for (final entry in all)
      if (entry.kind == OutboxKind.uploadAttachment &&
          (entry.isWaiting || entry.state == OutboxState.refused) &&
          (wanted.contains(entry.taskId) ||
              wanted.contains(resolvedTaskId(entry, all))))
        PendingAttachment(
          entry: entry,
          state: entry.isWaiting
              ? PendingAttachmentState.waiting
              : PendingAttachmentState.refused,
        ),
  ]);
}

/// How many pictures are still in the outbox per task id (resolved, see
/// [resolvedTaskId]; an unsent create's under its `local:outbox:<key>`), for
/// the row's badge: `task.attachments.length + counts[task.id]`.
Map<String, int> pendingAttachmentCounts(Iterable<OutboxEntry> entries) {
  final all = entries.toList(growable: false);
  final counts = <String, int>{};
  for (final entry in all) {
    if (entry.kind != OutboxKind.uploadAttachment) continue;
    if (!entry.isWaiting && entry.state != OutboxState.refused) continue;
    final id = resolvedTaskId(entry, all);
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}
