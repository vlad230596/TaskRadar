import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/project_summary.dart';
import 'package:taskradar/models/board_project.dart';

import 'support/fixtures.dart';

/// The four rules a project card states, one test group each.
///
/// These are the numbers a person reads at 09:00 and then acts on for the rest
/// of the day, so being quietly off by one here is worse than a visible bug.
void main() {
  /// "Today" for every test below. Fixed, so the due/not-due boundary does not
  /// move with the wall clock.
  final today = DateTime(2026, 9, 18);

  BoardProject project(List<Map<String, dynamic>> tasks) =>
      BoardProject.fromJson(
        boardProjectJson(id: 'prj_1', name: 'Проект', tasks: tasks),
      );

  ProjectSummary summarise(List<Map<String, dynamic>> tasks) =>
      ProjectSummary.of(project(tasks), now: today);

  group('the counter', () {
    test('counts done against the whole list', () {
      final summary = summarise([
        taskJson(id: 't1', status: 'done'),
        taskJson(id: 't2', status: 'done'),
        taskJson(id: 't3', status: 'pending', isCurrent: true),
        taskJson(id: 't4', status: 'pending'),
      ]);

      expect(summary.doneCount, 2);
      expect(summary.totalCount, 4);
      expect(summary.progress, 0.5);
    });

    test('a blocked task is unfinished, not done', () {
      // Folding `blocked` into "done" would make a stuck project look finished,
      // which is the exact opposite of what the board is for.
      final summary = summarise([
        taskJson(id: 't1', status: 'done'),
        taskJson(id: 't2', status: 'blocked', remindAt: '2026-09-30T00:00:00.000Z'),
      ]);

      expect(summary.doneCount, 1);
      expect(summary.totalCount, 2);
    });

    test('an empty project is 0 / 0 and 0% done, not 100%', () {
      final summary = summarise(const <Map<String, dynamic>>[]);

      expect(summary.doneCount, 0);
      expect(summary.totalCount, 0);
      expect(summary.progress, 0);
    });
  });

  group('the current task', () {
    test('is the one the server flagged, not one we re-derive', () {
      // The flag is deliberately trusted even when it disagrees with what a
      // local "first not done and not blocked" rule would pick: the rule lives
      // in backend/src/domain/isCurrent.ts and a second implementation here is
      // a second thing to keep in sync. If the two ever disagree, the server is
      // right by definition.
      final summary = summarise([
        taskJson(id: 't1', status: 'pending', position: 1000),
        taskJson(id: 't2', status: 'pending', position: 2000, isCurrent: true),
      ]);

      expect(summary.currentTask?.id, 't2');
      expect(summary.emptiness, ProjectEmptiness.hasCurrentTask);
    });

    test('an empty project says so', () {
      expect(
        summarise(const <Map<String, dynamic>>[]).emptiness,
        ProjectEmptiness.noTasks,
      );
    });

    test('a finished project says so', () {
      final summary = summarise([
        taskJson(id: 't1', status: 'done'),
        taskJson(id: 't2', status: 'done'),
      ]);

      expect(summary.currentTask, isNull);
      expect(summary.emptiness, ProjectEmptiness.allDone);
    });

    test('a fully blocked project is not the same as a finished one', () {
      final summary = summarise([
        taskJson(id: 't1', status: 'done'),
        taskJson(id: 't2', status: 'blocked', remindAt: '2026-10-01T00:00:00.000Z'),
      ]);

      expect(summary.currentTask, isNull);
      expect(summary.emptiness, ProjectEmptiness.allBlocked);
    });
  });

  group('the blocker', () {
    test('a project with no blocked task has none', () {
      final summary = summarise([taskJson(id: 't1', isCurrent: true)]);

      expect(summary.hasBlocker, isFalse);
      expect(summary.blockedCount, 0);
      expect(summary.nextReminderAt, isNull);
    });

    test('a blocked task with no date is still a blocker', () {
      final summary = summarise([taskJson(id: 't1', status: 'blocked')]);

      expect(summary.hasBlocker, isTrue);
      expect(summary.nextReminderAt, isNull);
      expect(summary.hasDueReminder, isFalse);
    });

    test('the badge date is the earliest of them', () {
      final summary = summarise([
        taskJson(id: 't1', status: 'blocked', remindAt: '2026-10-05T00:00:00.000Z'),
        taskJson(id: 't2', status: 'blocked', remindAt: '2026-09-25T00:00:00.000Z'),
        taskJson(id: 't3', status: 'blocked'),
      ]);

      expect(summary.blockedCount, 3);
      expect(summary.nextReminderAt, '2026-09-25');
    });
  });

  group('the due reminder', () {
    test('today counts as due', () {
      final summary = summarise([
        taskJson(id: 't1', status: 'blocked', remindAt: '2026-09-18T00:00:00.000Z'),
      ]);

      expect(summary.hasDueReminder, isTrue);
      expect(summary.dueReminders.single.id, 't1');
    });

    test('tomorrow does not', () {
      final summary = summarise([
        taskJson(id: 't1', status: 'blocked', remindAt: '2026-09-19T00:00:00.000Z'),
      ]);

      expect(summary.hasBlocker, isTrue);
      expect(summary.hasDueReminder, isFalse);
      expect(summary.nextReminderAt, '2026-09-19');
    });

    test('a leftover date on a task that is no longer blocked is ignored', () {
      // Same rule as `remindersFromBoard`: the date only means something while
      // the task is actually waiting on something. Badging a finished task
      // would be a reminder to do something already done.
      final summary = summarise([
        taskJson(id: 't1', status: 'done', remindAt: '2026-09-01T00:00:00.000Z'),
        taskJson(
          id: 't2',
          status: 'pending',
          isCurrent: true,
          remindAt: '2026-09-01T00:00:00.000Z',
        ),
      ]);

      expect(summary.hasBlocker, isFalse);
      expect(summary.hasDueReminder, isFalse);
      expect(summary.nextReminderAt, isNull);
    });

    test('an unreadable date is neither due nor the badge date', () {
      final summary = summarise([
        taskJson(id: 't1', status: 'blocked', remindAt: 'не-дата'),
      ]);

      expect(summary.hasBlocker, isTrue);
      expect(summary.hasDueReminder, isFalse);
      expect(summary.nextReminderAt, isNull);
    });

    test('when anything is due, the earliest date is the earliest due one', () {
      // The card relies on this to avoid a second traversal -- worth pinning
      // rather than leaving as a comment.
      final summary = summarise([
        taskJson(id: 'future', status: 'blocked', remindAt: '2026-09-30T00:00:00.000Z'),
        taskJson(id: 'due', status: 'blocked', remindAt: '2026-09-10T00:00:00.000Z'),
      ]);

      expect(summary.hasDueReminder, isTrue);
      expect(summary.nextReminderAt, '2026-09-10');
    });
  });

  test('the reference board fixture summarises the way the card will draw it', () {
    final board = BoardProject.listFromJson(boardJson());

    final first = ProjectSummary.of(board.first, now: today);
    expect(first.doneCount, 1);
    expect(first.totalCount, 3);
    expect(first.currentTask?.title, 'Каркас Flutter');
    expect(first.blockedCount, 1);
    expect(first.nextReminderAt, '2026-09-18');
    expect(first.hasDueReminder, isTrue, reason: '"today" is 2026-09-18 here');

    final second = ProjectSummary.of(board.last, now: today);
    expect(second.totalCount, 0);
    expect(second.emptiness, ProjectEmptiness.noTasks);
  });
}
