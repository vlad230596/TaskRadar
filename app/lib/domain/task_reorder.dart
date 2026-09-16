import 'package:flutter/foundation.dart';

import '../models/task.dart';

/// Turns a drag on a `ReorderableListView` into the request
/// `PATCH /tasks/:id/position` wants.
///
/// Pure, and deliberately so: the two things that can go wrong here -- the
/// index convention and the neighbour arithmetic -- are both off-by-one bugs
/// that a widget test cannot see (the list still looks reordered; only the
/// *persisted* order is wrong, and only sometimes). As plain functions they are
/// covered by a table of cases instead.
///
/// Port of the `handleDragEnd` logic in
/// `frontend/src/components/TaskList.tsx`, with the dnd-kit index convention
/// swapped for Flutter's.
@immutable
class TaskMove {
  const TaskMove({
    required this.taskId,
    required this.beforeTaskId,
    required this.afterTaskId,
    required this.reordered,
    required this.targetIndex,
  });

  /// The task being moved.
  final String taskId;

  /// The id of the task that will sit **above** [taskId], or null when it is
  /// moving to the very top.
  ///
  /// "Before" is the server's word and it means *earlier in the list*, i.e. a
  /// smaller `position` -- see `computePositionBetween(before, after)` in
  /// `backend/src/domain/position.ts`, which returns a value strictly between
  /// the two and treats a null as "no bound on that side".
  final String? beforeTaskId;

  /// The id of the task that will sit **below** [taskId], or null when it is
  /// moving to the very bottom.
  final String? afterTaskId;

  /// The list in its new order, for the optimistic frame.
  ///
  /// The rows still carry their **old** `position` values -- the server assigns
  /// the new one. That is safe only because nothing in this client sorts by
  /// `position`; see the note on [Task.position].
  final List<Task> reordered;

  /// Where [taskId] ended up in [reordered]. Exposed for tests and for a
  /// scroll-into-view that F4 may want.
  final int targetIndex;
}

/// Normalises `ReorderableListView.onReorder`'s index pair.
///
/// ## The convention, and why it needs a name
///
/// `onReorder(oldIndex, newIndex)` reports `newIndex` as an insertion point in
/// the list **with the dragged item still in it**. Dragging the first of three
/// rows to the bottom therefore reports `(0, 3)` -- an index one past the end of
/// the list it is describing. Every reorder handler in Flutter starts with the
/// same `if (newIndex > oldIndex) newIndex -= 1;` for that reason, and every one
/// that forgets it puts the row in the wrong place when dragging *downwards*
/// only, which is easy to miss by hand.
///
/// Returns the index the row should occupy in the list once it has been removed
/// from its old slot.
int normalizeReorderTarget(int oldIndex, int newIndex) =>
    newIndex > oldIndex ? newIndex - 1 : newIndex;

/// Plans a move, or returns null when there is nothing to do.
///
/// Null covers three cases that must not become a request:
///
/// - the drag ended where it started (the target index equals the old one).
///   `ReorderableListView` reports this as `(i, i)` or `(i, i + 1)`, and sending
///   it would be a pointless write -- worse, a repeated no-op drag on the same
///   row is the cheapest way to burn through the float gap between two
///   neighbours and force the server into a full rebalance;
/// - indices that are out of range for [tasks] (a stale callback firing after
///   the list changed under it);
/// - a list with fewer than two rows, where no order exists to change.
///
/// The neighbours are read from the list **after** the row has been pulled out
/// of it, which is what guarantees neither of them is the moved task itself --
/// the server rejects that with a 400 ("A task cannot be positioned relative to
/// itself"), and computing the neighbours from the *original* indices is how you
/// would hand it one.
TaskMove? planTaskMove(List<Task> tasks, int oldIndex, int newIndex) {
  if (tasks.length < 2) return null;
  if (oldIndex < 0 || oldIndex >= tasks.length) return null;

  final target = normalizeReorderTarget(oldIndex, newIndex);
  if (target < 0 || target >= tasks.length) return null;
  if (target == oldIndex) return null;

  final reordered = List<Task>.of(tasks);
  final moved = reordered.removeAt(oldIndex);
  reordered.insert(target, moved);

  return TaskMove(
    taskId: moved.id,
    beforeTaskId: target == 0 ? null : reordered[target - 1].id,
    afterTaskId: target == reordered.length - 1
        ? null
        : reordered[target + 1].id,
    reordered: List<Task>.unmodifiable(reordered),
    targetIndex: target,
  );
}
