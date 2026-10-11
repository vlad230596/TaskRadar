import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/task_groups.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_category.dart';
import 'package:taskradar/models/task_status.dart';

Task _task(String id, {String? categoryId}) => Task(
  id: id,
  projectId: 'p',
  title: id,
  description: null,
  status: TaskStatus.pending,
  position: 0,
  remindAt: null,
  categoryId: categoryId,
  createdAt: '2026-10-01T00:00:00.000Z',
  updatedAt: '2026-10-01T00:00:00.000Z',
  isCurrent: false,
);

TaskCategory _category(String id) => TaskCategory(
  id: id,
  projectId: 'p',
  name: id,
  position: 0,
  createdAt: '2026-10-01T00:00:00.000Z',
  updatedAt: '2026-10-01T00:00:00.000Z',
);

void main() {
  test('without categories: one group, the list as it was', () {
    final open = <Task>[_task('a'), _task('b')];
    final groups = groupOpenTasks(open, <int>[1, 3], const <TaskCategory>[]);

    expect(groups, hasLength(1));
    expect(groups.single.category, isNull);
    expect(groups.single.tasks.map((t) => t.id), <String>['a', 'b']);
    expect(groups.single.indices, <int>[1, 3]);
  });

  test("groups follow the categories' order, ungrouped last", () {
    final open = <Task>[
      _task('a'),
      _task('b', categoryId: 'second'),
      _task('c', categoryId: 'first'),
      _task('d', categoryId: 'second'),
    ];
    final groups = groupOpenTasks(
      open,
      <int>[0, 2, 3, 5],
      <TaskCategory>[
        _category('first'),
        _category('second'),
        _category('empty'),
      ],
    );

    expect(groups.map((g) => g.category?.id), <String?>[
      'first',
      'second',
      null,
    ]);
    expect(groups[1].tasks.map((t) => t.id), <String>['b', 'd']);
    // Full-list indices, for the reorder.
    expect(groups[1].indices, <int>[2, 5]);
    expect(groups[2].indices, <int>[0]);
  });

  test('a category this client does not know falls in with the ungrouped', () {
    final open = <Task>[_task('a', categoryId: 'gone'), _task('b')];
    final groups = groupOpenTasks(
      open,
      <int>[0, 1],
      <TaskCategory>[_category('kept')],
    );

    expect(groups, hasLength(1));
    expect(groups.single.category, isNull);
    expect(groups.single.tasks.map((t) => t.id), <String>['a', 'b']);
  });
}
