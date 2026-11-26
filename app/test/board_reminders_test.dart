import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/board_reminders.dart';
import 'package:taskradar/models/board_project.dart';

import 'support/fixtures.dart';

/// The F2 seam: a board goes in, the scheduler's input comes out.
///
/// Worth a test now rather than at F2 because it encodes a product rule that is
/// easy to get subtly wrong -- a leftover `remindAt` on a task that is no longer
/// blocked must not produce a notification, or the user gets reminded about
/// something they already finished.
void main() {
  test('a task with a date and no time is not a reminder', () {
    final board = BoardProject.listFromJson(boardJson());

    // `tsk_3` is blocked and dated, but has no `remindTime`: since the
    // today-history contract a date alone does not push.
    expect(remindersFromBoard(board), isEmpty);
  });

  test('only open tasks with a date and a time become reminders', () {
    final json = boardJson();
    final tasks =
        (json.first as Map<String, dynamic>)['tasks'] as List<dynamic>;
    for (final task in tasks.cast<Map<String, dynamic>>()) {
      // A done task keeps its date now, and must still not ring.
      task['remindAt'] = '2026-09-18T00:00:00.000Z';
      task['remindTime'] = '15:00';
    }
    final board = BoardProject.listFromJson(json);

    final reminders = remindersFromBoard(board);

    expect(reminders.map((r) => r.taskId), <String>['tsk_2', 'tsk_3']);
    final cable = reminders.last;
    expect(cable.taskId, 'tsk_3');
    expect(cable.taskTitle, 'Жду кабель');
    expect(cable.remindAt, '2026-09-18T00:00:00.000Z');
    expect(cable.remindTime, '15:00');
    expect(cable.projectName, 'TaskRadar');
  });

  test('an empty board produces no reminders', () {
    expect(remindersFromBoard(const <BoardProject>[]), isEmpty);
  });
}
