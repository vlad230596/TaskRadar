import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/history_task_event.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/models/today_history.dart';

import 'support/fake_backend.dart';
import 'support/fake_history_backend.dart';

/// Разбор ответов истории и проигрывание журнала задачи (F13).
///
/// Здесь проверяется контракт, а не виджеты: если сервер перестанет присылать
/// `byStatus` или начнёт писать миллисекунды дробными, это должно падать тут, а
/// не выглядеть на экране как задача, которая ничего нигде не провела.
void main() {
  final DateTime now = DateTime(2026, 9, 22, 14, 30);
  late FakeHistoryBackend fixtures;

  setUp(() {
    fixtures = FakeHistoryBackend(FakeBackend(), now: now);
  });

  group('ответы «Сделано», «Недели», пересмотра', () {
    test('страница «Сделано» и курсор следующей', () {
      final page = DonePage.fromJson(<String, dynamic>{
        'items': fixtures.sampleDone(),
        'nextBefore': fixtures.iso(4),
      });
      expect(page.items, hasLength(5));
      expect(page.items.first.task.projectName, 'TaskRadar');
      expect(page.items.first.task.task.status, TaskStatus.done);
      expect(page.nextBefore, fixtures.iso(4));
    });

    test('недели, запись пересмотра в неделе', () {
      final weeks = HistoryWeek.listFromJson(<String, dynamic>{
        'weeks': fixtures.sampleWeeks(),
      });
      expect(weeks, hasLength(12));
      expect(weeks.first.start, fixtures.mondayKey(0));
      expect(weeks[1].review?.closedCount, 23);
      expect(weeks[1].review?.achievedGoals.single.title, 'Релиз 0.15');
      expect(weeks[2].review, isNull);
    });

    test('черновик пересмотра: все разделы и месяц', () {
      final draft = ReviewDraft.fromJson(fixtures.draftJson(monthly: true));
      expect(draft.done, hasLength(3));
      expect(draft.intended.first.reasons, <IntendedReason>[
        IntendedReason.workingSet,
      ]);
      expect(draft.goals.single.windowExpired, isTrue);
      expect(draft.rhythm.single.project.rhythm?.silentWeeks, 3);
      expect(draft.month?.closed, 64);
      expect(ReviewDraft.fromJson(fixtures.draftJson()).month, isNull);
    });
  });

  group('replayTaskLife', () {
    List<TaskEvent> journal(String taskId) =>
        TaskEvent.listFromJson(fixtures.sampleJournal(taskId));

    test('раскладывает журнал по фазам', () {
      final life = replayTaskLife(
        createdAt: fixtures.iso(8),
        status: TaskStatus.blocked,
        focusedAt: null,
        events: journal('t4'),
        now: now,
      );

      expect(
        life[TaskLifePhase.queued],
        closeTo(4 * Duration.millisecondsPerDay, 1000),
      );
      expect(
        life[TaskLifePhase.working],
        closeTo(1 * Duration.millisecondsPerDay, 1000),
      );
      expect(
        life[TaskLifePhase.blocked],
        closeTo(3 * Duration.millisecondsPerDay, 1000),
      );
      expect(life[TaskLifePhase.done], 0);
      expect(life.phase, TaskLifePhase.blocked);
      expect(
        life.totalMs,
        closeTo(8 * Duration.millisecondsPerDay, 1000),
      );
    });

    test('текущая фаза началась с последнего перехода, а не с создания', () {
      final life = replayTaskLife(
        createdAt: fixtures.iso(8),
        status: TaskStatus.blocked,
        focusedAt: null,
        events: journal('t4'),
        now: now,
      );

      expect(
        life.since.difference(now).inDays.abs(),
        3,
        reason: 'блокер поставили три дня назад',
      );
    });

    test('пустой журнал отдаёт всю жизнь нынешнему статусу', () {
      final life = replayTaskLife(
        createdAt: fixtures.iso(6),
        status: TaskStatus.pending,
        focusedAt: null,
        events: const <TaskEvent>[],
        now: now,
      );

      expect(
        life[TaskLifePhase.queued],
        closeTo(6 * Duration.millisecondsPerDay, 1000),
      );
      expect(life.totalMs, life[TaskLifePhase.queued]);
      expect(life.phase, TaskLifePhase.queued);
    });

    test('задача без журнала, но в наборе, считается работающей', () {
      final life = replayTaskLife(
        createdAt: fixtures.iso(2),
        status: TaskStatus.pending,
        focusedAt: fixtures.iso(1),
        events: const <TaskEvent>[],
        now: now,
      );

      expect(life.phase, TaskLifePhase.working);
      expect(life[TaskLifePhase.queued], 0);
    });

    test('взятие блокера в работу не сбрасывает «ждёт с»', () {
      final events = TaskEvent.listFromJson(<dynamic>[
        fixtures.eventJson(
          taskId: 't1',
          kind: 'created',
          daysAgo: 10,
          toStatus: TaskStatus.pending,
        ),
        fixtures.eventJson(
          taskId: 't1',
          kind: 'status',
          daysAgo: 6,
          fromStatus: TaskStatus.pending,
          toStatus: TaskStatus.blocked,
        ),
        fixtures.eventJson(taskId: 't1', kind: 'focused', daysAgo: 2),
      ]);

      final life = replayTaskLife(
        createdAt: fixtures.iso(10),
        status: TaskStatus.blocked,
        focusedAt: fixtures.iso(2),
        events: events,
        now: now,
      );

      expect(life.phase, TaskLifePhase.blocked);
      expect(life[TaskLifePhase.working], 0);
      expect(life.since.difference(now).inDays.abs(), 6);
    });

    test('сумма фаз равна возрасту задачи', () {
      final life = replayTaskLife(
        createdAt: fixtures.iso(8),
        status: TaskStatus.blocked,
        focusedAt: null,
        events: journal('t4'),
        now: now,
      );

      var sum = 0;
      for (final phase in TaskLifePhase.values) {
        sum += life[phase];
      }
      expect(sum, life.totalMs);
    });
  });

  group('TaskEvent.listFromJson', () {
    test('пропускает событие неизвестного вида, а не падает', () {
      final events = TaskEvent.listFromJson(<dynamic>[
        fixtures.eventJson(
          taskId: 't1',
          kind: 'created',
          daysAgo: 3,
          toStatus: TaskStatus.pending,
        ),
        fixtures.eventJson(taskId: 't1', kind: 'renamed', daysAgo: 2),
      ]);

      expect(events, hasLength(1));
      expect(events.single.kind, TaskEventKind.created);
    });

    test('сохраняет порядок сервера', () {
      final events = TaskEvent.listFromJson(fixtures.sampleJournal('t4'));

      expect(
        events.map((e) => e.kind).toList(),
        <TaskEventKind>[
          TaskEventKind.created,
          TaskEventKind.focused,
          TaskEventKind.unfocused,
          TaskEventKind.status,
        ],
      );
    });
  });
}
