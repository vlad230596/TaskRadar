import 'package:flutter/foundation.dart';

import '../models/task.dart';
import '../models/task_category.dart';

/// One group of the project screen's open tasks: a category and its rows, or
/// the tasks that have none.
@immutable
class TaskGroup {
  const TaskGroup({
    required this.category,
    required this.tasks,
    required this.indices,
  });

  /// Null for "без категории".
  final TaskCategory? category;

  /// In server order.
  final List<Task> tasks;

  /// The full-list index of each of [tasks], for [mapSectionReorder]: a group
  /// is a slice of the one list the server orders, so a drag inside it is a
  /// move in that list.
  final List<int> indices;
}

/// Splits the open tasks into their categories' groups.
///
/// [open] and [openIndices] are `TaskSections.open` and its indices. The
/// groups come in the categories' order, each holding only the tasks that are
/// in it; categories with no open task are left out -- an empty heading is a
/// line that says nothing. The tasks without a category come last, and so do
/// those whose category this client does not know (deleted on another device,
/// or the list not loaded yet): they are drawn rather than lost.
///
/// With no categories at all, one group with a null category -- the list as it
/// was before categories existed.
List<TaskGroup> groupOpenTasks(
  List<Task> open,
  List<int> openIndices,
  List<TaskCategory> categories,
) {
  final known = <String>{for (final category in categories) category.id};
  final byCategory = <String?, List<int>>{};
  for (var i = 0; i < open.length; i++) {
    final id = open[i].categoryId;
    byCategory
        .putIfAbsent(known.contains(id) ? id : null, () => <int>[])
        .add(i);
  }

  TaskGroup group(TaskCategory? category, List<int> at) => TaskGroup(
    category: category,
    tasks: List<Task>.unmodifiable(<Task>[for (final i in at) open[i]]),
    indices: List<int>.unmodifiable(<int>[for (final i in at) openIndices[i]]),
  );

  return List<TaskGroup>.unmodifiable(<TaskGroup>[
    for (final category in categories)
      if (byCategory[category.id] case final at?) group(category, at),
    if (byCategory[null] case final at?) group(null, at),
  ]);
}
