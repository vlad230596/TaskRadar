import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/task_reorder.dart';
import 'package:taskradar/models/task.dart';

import 'support/fixtures.dart';

/// Every drag, turned into the neighbour pair the server wants.
///
/// This is the file that has to be right, because nothing downstream can tell
/// when it is not: an off-by-one puts the row in the correct place *on screen*
/// (the optimistic list is computed from the same indices) and in the wrong
/// place in the database, which shows up on the next refresh as a list that
/// "randomly" reorders itself.
void main() {
  /// Four tasks, a..d, in position order.
  List<Task> rows([int count = 4]) => <Task>[
    for (var i = 0; i < count; i++)
      Task.fromJson(
        taskJson(
          id: String.fromCharCode('a'.codeUnitAt(0) + i),
          title: 'Задача ${i + 1}',
          position: (i + 1) * 1000,
        ),
      ),
  ];

  List<String> idsOf(List<Task> tasks) => tasks.map((task) => task.id).toList();

  group('normalizeReorderTarget', () {
    // ReorderableListView reports `newIndex` as an insertion point in the list
    // *including* the dragged row, so a downward drag is always one too high.
    test('a downward drag loses one', () {
      expect(normalizeReorderTarget(0, 3), 2);
      expect(normalizeReorderTarget(1, 4), 3);
    });

    test('an upward drag is already correct', () {
      expect(normalizeReorderTarget(3, 0), 0);
      expect(normalizeReorderTarget(2, 1), 1);
    });

    test('a drop in place normalises to the original index', () {
      // Both of the pairs Flutter emits for "nothing moved".
      expect(normalizeReorderTarget(2, 2), 2);
      expect(normalizeReorderTarget(2, 3), 2);
    });
  });

  group('planTaskMove', () {
    test('into the middle names both neighbours', () {
      // a b c d -> move a between b and c.
      final move = planTaskMove(rows(), 0, 2)!;

      expect(move.taskId, 'a');
      expect(move.beforeTaskId, 'b');
      expect(move.afterTaskId, 'c');
      expect(idsOf(move.reordered), <String>['b', 'a', 'c', 'd']);
      expect(move.targetIndex, 1);
    });

    test('to the very top has no "before"', () {
      final move = planTaskMove(rows(), 2, 0)!;

      // Null, not the id of the row that used to be first: null is how the
      // protocol says "no neighbour on that side", and the server turns it into
      // `firstPosition - GAP`.
      expect(move.beforeTaskId, isNull);
      expect(move.afterTaskId, 'a');
      expect(idsOf(move.reordered), <String>['c', 'a', 'b', 'd']);
    });

    test('to the very bottom has no "after"', () {
      final move = planTaskMove(rows(), 0, 4)!;

      expect(move.beforeTaskId, 'd');
      expect(move.afterTaskId, isNull);
      expect(idsOf(move.reordered), <String>['b', 'c', 'd', 'a']);
    });

    test('one step down swaps with the row below', () {
      final move = planTaskMove(rows(), 1, 3)!;

      expect(move.taskId, 'b');
      expect(move.beforeTaskId, 'c');
      expect(move.afterTaskId, 'd');
      expect(idsOf(move.reordered), <String>['a', 'c', 'b', 'd']);
    });

    test('one step up swaps with the row above', () {
      final move = planTaskMove(rows(), 2, 1)!;

      expect(move.taskId, 'c');
      expect(move.beforeTaskId, 'a');
      expect(move.afterTaskId, 'b');
      expect(idsOf(move.reordered), <String>['a', 'c', 'b', 'd']);
    });

    test('neither neighbour is ever the moved task itself', () {
      // The server rejects that with a 400, and computing the neighbours from
      // the *original* indices instead of the post-removal ones is precisely how
      // a client hands it one.
      for (var from = 0; from < 4; from++) {
        for (var to = 0; to <= 4; to++) {
          final move = planTaskMove(rows(), from, to);
          if (move == null) continue;

          expect(move.beforeTaskId, isNot(move.taskId), reason: '$from -> $to');
          expect(move.afterTaskId, isNot(move.taskId), reason: '$from -> $to');
        }
      }
    });

    group('no request at all', () {
      test('dropped where it started', () {
        // Not merely harmless: repeating a no-op move would keep bisecting the
        // gap between the same two neighbours and is the cheapest way to force
        // the server into a full rebalance for nothing.
        expect(planTaskMove(rows(), 2, 2), isNull);
        expect(planTaskMove(rows(), 2, 3), isNull);
        expect(planTaskMove(rows(), 0, 0), isNull);
        expect(planTaskMove(rows(), 0, 1), isNull);
      });

      test('a list too short to have an order', () {
        expect(planTaskMove(rows(1), 0, 1), isNull);
        expect(planTaskMove(const <Task>[], 0, 0), isNull);
      });

      test('indices that are out of range', () {
        // A callback firing after the list changed under it -- e.g. a refresh
        // landing mid-drag.
        expect(planTaskMove(rows(), 9, 0), isNull);
        expect(planTaskMove(rows(), -1, 0), isNull);
        expect(planTaskMove(rows(), 0, 99), isNull);
      });
    });

    test('the optimistic list keeps the old positions, unsorted', () {
      // The rows in `reordered` still carry the positions the server gave them
      // before the move, so the list is deliberately *not* in position order for
      // one frame. That is only safe because nothing re-sorts by position; this
      // test exists so that if someone ever does, it fails here.
      final move = planTaskMove(rows(), 0, 4)!;

      expect(move.reordered.map((task) => task.position), <double>[
        2000,
        3000,
        4000,
        1000,
      ]);
    });

    test('the source list is not mutated', () {
      final original = rows();
      planTaskMove(original, 0, 4);

      expect(idsOf(original), <String>['a', 'b', 'c', 'd']);
    });
  });
}
