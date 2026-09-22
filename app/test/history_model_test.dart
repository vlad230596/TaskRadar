import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/history_snapshot.dart';
import 'package:taskradar/models/history_task_event.dart';
import 'package:taskradar/models/task_status.dart';

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

  group('HistorySnapshot.fromJson', () {
    test('разбирает ответ роута целиком', () {
      final snapshot = HistorySnapshot.fromJson(fixtures.sampleWeek());

      expect(snapshot.range, HistoryRange.week);
      expect(snapshot.closedTotal, 9);
      expect(snapshot.closedByDay, hasLength(7));
      expect(snapshot.closedByDay.last.date, fixtures.dayKey(0));
      expect(snapshot.projects.first.name, 'Дом');
      expect(snapshot.projects.first.opened, 6);
      expect(snapshot.stale.first.title, contains('вентилятор'));
      expect(snapshot.stale.first.status, TaskStatus.blocked);
      expect(snapshot.isEmpty, isFalse);
    });

    test('пустой ответ — это пустой ответ, а не нули', () {
      final snapshot = HistorySnapshot.fromJson(fixtures.emptyWeek());

      expect(snapshot.closedTotal, 0);
      // Семь дней с нулями всё равно приходят: ось рисуется, данных на ней нет.
      expect(snapshot.closedByDay, hasLength(7));
      expect(snapshot.isEmpty, isTrue);
    });

    test('неизвестный диапазон не роняет разбор', () {
      final snapshot = HistorySnapshot.fromJson(<String, dynamic>{
        ...fixtures.sampleWeek(),
        'range': '90d',
      });

      expect(snapshot.range, HistoryRange.month);
    });

    test('миллисекунды приходят числом любой формы', () {
      final raw = fixtures.staleJson(
        id: 't1',
        title: 'x',
        projectName: 'Дом',
        ageDays: 2,
        pendingDays: 2,
      );
      raw['ageMs'] = 172800000.0;

      expect(StaleTask.fromJson(raw).ageMs, 172800000);
    });

    test('общая шкала полосок — возраст самой старой задачи', () {
      final snapshot = HistorySnapshot.fromJson(fixtures.sampleWeek());

      expect(snapshot.oldestAgeMs, 8 * Duration.millisecondsPerDay);
    });
  });

  group('StaleTask.inWorkMs', () {
    test('считается от focusedAt и не вылезает за время в очереди', () {
      final task = StaleTask.fromJson(
        fixtures.staleJson(
          id: 't7',
          title: 'Потестить диктовку',
          projectName: 'TaskRadar',
          ageDays: 5,
          pendingDays: 5,
          focusedDaysAgo: 2,
        ),
      );

      expect(
        task.inWorkMs(now: now),
        closeTo(2 * Duration.millisecondsPerDay, 1000),
      );
    });

    test('задача вне набора не была в работе', () {
      final task = StaleTask.fromJson(
        fixtures.staleJson(
          id: 't2',
          title: 'Купить лампочки',
          projectName: 'Дом',
          ageDays: 5,
          pendingDays: 5,
        ),
      );

      expect(task.inWorkMs(now: now), 0);
    });

    test('заход в набор не может быть длиннее очереди', () {
      // Задачу взяли в работу, потом она ушла в блокер: времени в очереди у неё
      // день, а в наборе она числится третьи сутки. Синий сегмент не имеет
      // права быть длиннее серого, из которого он вырезан.
      final task = StaleTask.fromJson(
        fixtures.staleJson(
          id: 't4',
          title: 'Вентилятор',
          projectName: 'Дом',
          status: TaskStatus.blocked,
          ageDays: 4,
          pendingDays: 1,
          blockedDays: 3,
          focusedDaysAgo: 3,
        ),
      );

      expect(task.inWorkMs(now: now), 1 * Duration.millisecondsPerDay);
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
