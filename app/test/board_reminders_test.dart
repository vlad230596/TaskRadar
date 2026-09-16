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
  test('only blocked tasks with a date become reminders', () {
    final board = BoardProject.listFromJson(boardJson());

    final reminders = remindersFromBoard(board);

    expect(reminders, hasLength(1));
    expect(reminders.single.taskId, 'tsk_3');
    expect(reminders.single.taskTitle, 'Жду кабель');
    expect(reminders.single.remindAt, '2026-09-18T00:00:00.000Z');
    expect(reminders.single.projectName, 'TaskRadar');
  });

  test('an empty board produces no reminders', () {
    expect(remindersFromBoard(const <BoardProject>[]), isEmpty);
  });
}
